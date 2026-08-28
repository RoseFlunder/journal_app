import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';

import 'cloud_auth_config.dart';
import 'cloud_gateway.dart';

/// Google Identity Services implementation for Flutter Web. The web SDK
/// requires its own rendered sign-in button; [authenticate] is therefore intended
/// for mobile/desktop and the authentication event stream is authoritative on
/// Web.
class PlatformCloudAccountGateway implements CloudAccountGateway {
  factory PlatformCloudAccountGateway({
    GoogleCloudConfig config = const GoogleCloudConfig(),
  }) =>
      PlatformCloudAccountGateway._(config);

  PlatformCloudAccountGateway._(this._config)
      : _events = StreamController<CloudAuthState>.broadcast();

  final GoogleCloudConfig _config;
  final StreamController<CloudAuthState> _events;
  GoogleSignInAccount? _user;
  String? _token;
  CloudAuthState _state = const CloudAuthState.signedOut();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  bool _initialized = false;

  @override
  CloudAuthState get state => _state;

  @override
  Stream<CloudAuthState> get states => _events.stream;

  @override
  Future<CloudAccount?> restoreSession() async {
    await _initialize();
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (attempt != null) await attempt;
    return _user == null ? null : _toAccount(_user!);
  }

  @override
  Future<CloudAccount> authenticate() =>
      Future<CloudAccount>.error(const CloudAuthorizationException(
        CloudAuthErrorCode.providerUnavailable,
      ));

  @override
  Future<bool> hasDriveAuthorization() async {
    await _initialize();
    final user = _user;
    if (user == null) return false;
    try {
      final authorization = await user.authorizationClient.authorizationForScopes(
        [googleDriveAppDataScope],
      );
      _token = authorization?.accessToken;
      return _token != null && _token!.isNotEmpty;
    } on GoogleSignInException catch (error) {
      throw _mapGoogleException(error);
    }
  }

  @override
  Future<void> requestDriveAuthorization() async {
    await _initialize();
    final user = _user;
    if (user == null) throw const CloudAuthorizationException();
    late final GoogleSignInClientAuthorization authorization;
    try {
      authorization = await user.authorizationClient.authorizeScopes(
        [googleDriveAppDataScope],
      );
    } on GoogleSignInException catch (error) {
      throw _mapGoogleException(error);
    }
    _token = authorization.accessToken;
    _setState(CloudAuthState(phase: CloudAuthPhase.signedIn, account: _toAccount(user)));
  }

  @override
  Future<String?> accessToken() async {
    await _initialize();
    final user = _user;
    if (user == null) return null;
    final authorization = await _authorizationForScopes(
      user,
      [googleDriveAppDataScope],
    );
    _token = authorization?.accessToken;
    return _token;
  }

  Future<GoogleSignInClientAuthorization?> _authorizationForScopes(
    GoogleSignInAccount user,
    List<String> scopes,
  ) async {
    try {
      return await user.authorizationClient.authorizationForScopes(scopes);
    } on GoogleSignInException catch (error) {
      throw _mapGoogleException(error);
    }
  }

  @override
  Future<void> signOut() async {
    await _initialize();
    await GoogleSignIn.instance.signOut();
    _user = null;
    _token = null;
    _setState(const CloudAuthState.signedOut());
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _events.close();
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    if (_config.webClientId == null) {
      throw const CloudAuthorizationException(CloudAuthErrorCode.configuration);
    }
    await GoogleSignIn.instance.initialize(clientId: _config.webClientId);
    _subscription = GoogleSignIn.instance.authenticationEvents.listen(
      (event) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn(:final user):
            _user = user;
            _setState(
              CloudAuthState(phase: CloudAuthPhase.signedIn, account: _toAccount(user)),
            );
          case GoogleSignInAuthenticationEventSignOut():
            _user = null;
            _token = null;
            _setState(const CloudAuthState.signedOut());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _setState(CloudAuthState(phase: CloudAuthPhase.failed, error: error));
      },
    );
    _initialized = true;
  }

  void _setState(CloudAuthState next) {
    _state = next;
    if (!_events.isClosed) _events.add(next);
  }

  static CloudAccount _toAccount(GoogleSignInAccount user) => CloudAccount(
        id: user.id,
        email: user.email,
        name: user.displayName,
      );

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
