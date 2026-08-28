import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:url_launcher/url_launcher.dart';

import 'cloud_auth_config.dart';
import 'cloud_gateway.dart';

/// Android uses the official Google Sign-In SDK. Windows uses Google's
/// installed-app authorization-code flow with PKCE and a loopback callback.
class PlatformCloudAccountGateway implements CloudAccountGateway {
  factory PlatformCloudAccountGateway({
    GoogleCloudConfig config = const GoogleCloudConfig(),
    FlutterSecureStorage? secureStorage,
  }) =>
      PlatformCloudAccountGateway._(
        config,
        secureStorage ?? const FlutterSecureStorage(),
      );

  PlatformCloudAccountGateway._(this._config, this._secureStorage)
      : _events = StreamController<CloudAuthState>.broadcast();

  static const _credentialsKey = 'cozy_bloom.google.oauth.credentials';
  static const _accountKey = 'cozy_bloom.google.account';
  static final _userinfoUri = Uri.parse(
    'https://openidconnect.googleapis.com/v1/userinfo',
  );
  static final _authorizationUri = Uri.parse(
    'https://accounts.google.com/o/oauth2/v2/auth',
  );
  static final _tokenUri = Uri.parse('https://oauth2.googleapis.com/token');

  final GoogleCloudConfig _config;
  final FlutterSecureStorage _secureStorage;
  final StreamController<CloudAuthState> _events;
  CloudAuthState _state = const CloudAuthState.signedOut();
  GoogleSignInAccount? _googleUser;
  oauth2.Client? _windowsClient;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  bool _initialized = false;

  bool get _isWindows => Platform.isWindows;

  @override
  CloudAuthState get state => _state;

  @override
  Stream<CloudAuthState> get states => _events.stream;

  @override
  Future<CloudAccount?> restoreSession() async {
    if (_isWindows) return _restoreWindows();
    await _initializeGoogle();
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (attempt != null) await attempt;
    final user = _googleUser;
    return user == null ? null : _toAccount(user);
  }

  @override
  Future<CloudAccount> authenticate() async {
    if (_isWindows) return _signInWindows();
    await _initializeGoogle();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const CloudAuthorizationException(
        CloudAuthErrorCode.providerUnavailable,
      );
    }
    late final GoogleSignInAccount user;
    try {
      user = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      throw _mapGoogleException(error);
    }
    _googleUser = user;
    _setState(CloudAuthState(phase: CloudAuthPhase.signedIn, account: _toAccount(user)));
    return _toAccount(user);
  }

  @override
  Future<bool> hasDriveAuthorization() async {
    if (_isWindows) {
      final client = _windowsClient;
      if (client == null) return false;
      try {
        if (client.credentials.isExpired) await client.refreshCredentials();
        return client.credentials.scopes?.contains(googleDriveAppDataScope) ?? false;
      } on oauth2.AuthorizationException {
        throw const CloudAuthorizationException(CloudAuthErrorCode.expired);
      }
    }
    await _initializeGoogle();
    final user = _googleUser;
    if (user == null) return false;
    try {
      final authorization = await user.authorizationClient.authorizationForScopes(
        [googleDriveAppDataScope],
      );
      return authorization != null && authorization.accessToken.isNotEmpty;
    } on GoogleSignInException catch (error) {
      throw _mapGoogleException(error);
    }
  }

  @override
  Future<void> requestDriveAuthorization() async {
    if (_isWindows) {
      await _signInWindows();
      return;
    }
    await _initializeGoogle();
    final user = _googleUser;
    if (user == null) {
      throw const CloudAuthorizationException(CloudAuthErrorCode.authorizationRequired);
    }
    try {
      await user.authorizationClient.authorizeScopes([googleDriveAppDataScope]);
    } on GoogleSignInException catch (error) {
      throw _mapGoogleException(error);
    }
    _setState(CloudAuthState(phase: CloudAuthPhase.signedIn, account: _toAccount(user)));
  }

  @override
  Future<String?> accessToken() async {
    if (_isWindows) {
      final client = _windowsClient;
      if (client == null) return null;
      try {
        if (client.credentials.isExpired) await client.refreshCredentials();
        return client.credentials.accessToken;
      } on oauth2.ExpirationException {
        throw const CloudAuthorizationException();
      } on oauth2.AuthorizationException {
        throw const CloudAuthorizationException();
      }
    }
    await _initializeGoogle();
    final user = _googleUser;
    if (user == null) return null;
    try {
      final authorization = await user.authorizationClient.authorizationForScopes(
        [googleDriveAppDataScope],
      );
      return authorization?.accessToken;
    } on GoogleSignInException catch (error) {
      throw _mapGoogleException(error);
    }
  }

  @override
  Future<void> signOut() async {
    if (_isWindows) {
      _windowsClient?.close();
      _windowsClient = null;
      await _secureStorage.delete(key: _credentialsKey);
      await _secureStorage.delete(key: _accountKey);
    } else {
      await _initializeGoogle();
      await GoogleSignIn.instance.signOut();
      _googleUser = null;
    }
    _setState(const CloudAuthState.signedOut());
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _windowsClient?.close();
    await _events.close();
  }

  Future<void> _initializeGoogle() async {
    if (_initialized) return;
    if (_config.serverClientId == null) {
      throw const CloudAuthorizationException(CloudAuthErrorCode.configuration);
    }
    await GoogleSignIn.instance.initialize(
      serverClientId: _config.serverClientId,
    );
    _subscription = GoogleSignIn.instance.authenticationEvents.listen(
      (event) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn(:final user):
            _googleUser = user;
            _setState(
              CloudAuthState(phase: CloudAuthPhase.signedIn, account: _toAccount(user)),
            );
          case GoogleSignInAuthenticationEventSignOut():
            _googleUser = null;
            _setState(const CloudAuthState.signedOut());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _setState(CloudAuthState(phase: CloudAuthPhase.failed, error: error));
      },
    );
    _initialized = true;
  }

  Future<CloudAccount?> _restoreWindows() async {
    final serialized = await _secureStorage.read(key: _credentialsKey);
    final accountJson = await _secureStorage.read(key: _accountKey);
    if (serialized == null || accountJson == null) return null;
    CloudAccount? account;
    try {
      final credentials = oauth2.Credentials.fromJson(serialized);
      _windowsClient = _newOAuthClient(credentials);
      account = _accountFromJson(
        jsonDecode(accountJson) as Map<String, dynamic>,
      );
      if (_windowsClient!.credentials.isExpired) {
        await _windowsClient!.refreshCredentials();
      }
      _setState(CloudAuthState(phase: CloudAuthPhase.signedIn, account: account));
      return account;
    } on oauth2.AuthorizationException catch (error) {
      await _clearWindowsCredentials();
      if (account != null) {
        _setState(CloudAuthState(
          phase: CloudAuthPhase.authorizationRequired,
          account: account,
          error: const CloudAuthorizationException(CloudAuthErrorCode.expired),
        ));
        return account;
      }
      throw CloudAuthorizationException(CloudAuthErrorCode.expired, error.toString());
    } catch (_) {
      await _clearWindowsCredentials();
      return null;
    }
  }

  Future<CloudAccount> _signInWindows() async {
    final clientId = _config.desktopClientId;
    if (clientId == null) {
      throw const CloudAuthorizationException(CloudAuthErrorCode.configuration);
    }
    _setState(const CloudAuthState(phase: CloudAuthPhase.authorizing));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/oauth2redirect',
    );
    final grant = oauth2.AuthorizationCodeGrant(
      clientId,
      _authorizationUri,
      _tokenUri,
      basicAuth: false,
    );
    final authorizationUrl = grant.getAuthorizationUrl(
      redirect,
      scopes: googleDriveScopes,
      state: _randomState(),
    );
    // Append offline access and consent parameters without regenerating the
    // grant's one-shot authorization URL.
    final browserUrl = authorizationUrl.replace(
      queryParameters: <String, String>{
        ...authorizationUrl.queryParameters,
        'access_type': 'offline',
        'prompt': 'consent',
      },
    );
    try {
      if (!await launchUrl(browserUrl, mode: LaunchMode.externalApplication)) {
        throw const CloudAuthorizationException();
      }
      final request = await _waitForCallback(server, redirect.path);
      final response = request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write('<p>Cozy Bloom Journal is connected. You can close this tab.</p>');
      await response.close();
      late final oauth2.Client client;
      try {
        client = await grant.handleAuthorizationResponse(
          request.uri.queryParameters,
        );
      } on oauth2.AuthorizationException catch (error) {
        throw CloudAuthorizationException(
          error.error == 'access_denied'
              ? CloudAuthErrorCode.denied
              : CloudAuthErrorCode.authorizationRequired,
          error.description,
        );
      } on TimeoutException {
        throw const CloudAuthorizationException(CloudAuthErrorCode.timeout);
      }
      _windowsClient = client;
      final account = await _fetchWindowsAccount(client);
      await _saveWindowsSession(client.credentials, account);
      _setState(CloudAuthState(phase: CloudAuthPhase.signedIn, account: account));
      return account;
    } on TimeoutException {
      throw const CloudAuthorizationException(CloudAuthErrorCode.timeout);
    } finally {
      await server.close(force: true);
    }
  }

  oauth2.Client _newOAuthClient(oauth2.Credentials credentials) => oauth2.Client(
        credentials,
        identifier: _config.desktopClientId,
        basicAuth: false,
        onCredentialsRefreshed: (next) {
          unawaited(_secureStorage.write(key: _credentialsKey, value: next.toJson()));
        },
      );

  Future<CloudAccount> _fetchWindowsAccount(oauth2.Client client) async {
    final response = await client.get(_userinfoUri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudHttpException(response.statusCode, response.body);
    }
    return _accountFromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<HttpRequest> _waitForCallback(HttpServer server, String path) async {
    final callback = Completer<HttpRequest>();
    late final StreamSubscription<HttpRequest> subscription;
    final timeout = Timer(const Duration(minutes: 5), () {
      if (!callback.isCompleted) {
        callback.completeError(TimeoutException('OAuth callback timed out'));
      }
    });
    subscription = server.listen((incoming) {
      if (incoming.uri.path == path) {
        if (!callback.isCompleted) callback.complete(incoming);
        return;
      }
      // Browsers may request a favicon or another resource from the loopback
      // callback before redirecting with the authorization code.
      incoming.response
        ..statusCode = HttpStatus.notFound
        ..close();
    });
    try {
      return await callback.future;
    } finally {
      timeout.cancel();
      await subscription.cancel();
    }
  }

  Future<void> _saveWindowsSession(
    oauth2.Credentials credentials,
    CloudAccount account,
  ) async {
    await _secureStorage.write(key: _credentialsKey, value: credentials.toJson());
    await _secureStorage.write(
      key: _accountKey,
      value: jsonEncode(<String, dynamic>{
        'id': account.id,
        'email': account.email,
        'name': account.name,
      }),
    );
  }

  static CloudAccount _accountFromJson(Map<String, dynamic> json) => CloudAccount(
        id: json['sub'] as String? ?? json['id'] as String,
        email: json['email'] as String? ?? '',
        name: json['name'] as String?,
      );

  static CloudAccount _toAccount(GoogleSignInAccount user) => CloudAccount(
        id: user.id,
        email: user.email,
        name: user.displayName,
      );

  static String _randomState() => List<String>.generate(
        32,
        (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[Random.secure().nextInt(36)],
      ).join();

  void _setState(CloudAuthState next) {
    _state = next;
    if (!_events.isClosed) _events.add(next);
  }

  Future<void> _clearWindowsCredentials() async {
    _windowsClient?.close();
    _windowsClient = null;
    await _secureStorage.delete(key: _credentialsKey);
  }

  static CloudAuthorizationException _mapGoogleException(
    GoogleSignInException error,
  ) {
    final code = switch (error.code) {
      GoogleSignInExceptionCode.canceled => CloudAuthErrorCode.canceled,
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        CloudAuthErrorCode.configuration,
      GoogleSignInExceptionCode.uiUnavailable => CloudAuthErrorCode.providerUnavailable,
      _ => CloudAuthErrorCode.authorizationRequired,
    };
    return CloudAuthorizationException(code, error.description);
  }
}
