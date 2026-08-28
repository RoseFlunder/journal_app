import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'sync_models.dart';

/// Platform-neutral account information. The stable [id] is the Google
/// subject/account identifier and is never used as a Drive file name.
class CloudAccount {
  const CloudAccount({required this.id, required this.email, this.name});

  final String id;
  final String email;
  final String? name;
}

enum CloudAuthPhase {
  disabled,
  signedOut,
  authorizing,
  signedIn,
  authorizationRequired,
  failed,
}

class CloudAuthState {
  const CloudAuthState({
    required this.phase,
    this.account,
    this.error,
  });

  const CloudAuthState.disabled() : this(phase: CloudAuthPhase.disabled);

  const CloudAuthState.signedOut() : this(phase: CloudAuthPhase.signedOut);

  final CloudAuthPhase phase;
  final CloudAccount? account;
  final Object? error;
}

/// Authentication and Drive authorization boundary. Implementations own
/// platform SDKs and token storage; callers never receive SDK account types.
abstract interface class CloudAccountGateway {
  CloudAuthState get state;

  Stream<CloudAuthState> get states;

  Future<CloudAccount?> restoreSession();

  /// Authenticates the Google account without requesting Drive access.
  Future<CloudAccount> authenticate();

  /// Checks Drive authorization without showing UI.
  Future<bool> hasDriveAuthorization();

  /// Requests Drive authorization from an explicit user action.
  Future<void> requestDriveAuthorization();

  Future<String?> accessToken();

  Future<void> signOut();

  Future<void> dispose();
}

/// Default implementation used when Google credentials are not configured.
class DisabledCloudAccountGateway implements CloudAccountGateway {
  DisabledCloudAccountGateway() : _states = StreamController.broadcast();

  final StreamController<CloudAuthState> _states;

  @override
  CloudAuthState get state => const CloudAuthState.disabled();

  @override
  Stream<CloudAuthState> get states => _states.stream;

  @override
  Future<CloudAccount?> restoreSession() async => null;

  @override
  Future<CloudAccount> authenticate() =>
      Future<CloudAccount>.error(const CloudUnavailableException());

  @override
  Future<bool> hasDriveAuthorization() async => false;

  @override
  Future<void> requestDriveAuthorization() =>
      Future<void>.error(const CloudUnavailableException());

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> dispose() => _states.close();
}

class CloudUnavailableException implements Exception {
  const CloudUnavailableException();

  @override
  String toString() => 'Google synchronization is not configured.';
}

/// Drive operation without Google SDK types. The gateway uses only app-owned
/// files in Drive's hidden application data space.
abstract interface class DriveSyncGateway {
  Future<List<DriveSyncRecord>> listRecords();

  Future<DriveSyncRecord> createRecord({
    required String name,
    required String mimeType,
    required Map<String, String> properties,
    required List<int> bytes,
  });

  Future<DriveSyncRecord> updateRecord({
    required String fileId,
    required String mimeType,
    required List<int> bytes,
  });

  Future<Uint8List> downloadRecord(String fileId);

  Future<void> deleteRecord(String fileId);

  Future<void> dispose();
}

/// No-op gateway paired with [DisabledCloudAccountGateway].
class DisabledDriveSyncGateway implements DriveSyncGateway {
  const DisabledDriveSyncGateway();

  @override
  Future<List<DriveSyncRecord>> listRecords() async => const [];

  @override
  Future<DriveSyncRecord> createRecord({
    required String name,
    required String mimeType,
    required Map<String, String> properties,
    required List<int> bytes,
  }) =>
      Future<DriveSyncRecord>.error(const CloudUnavailableException());

  @override
  Future<DriveSyncRecord> updateRecord({
    required String fileId,
    required String mimeType,
    required List<int> bytes,
  }) =>
      Future<DriveSyncRecord>.error(const CloudUnavailableException());

  @override
  Future<Uint8List> downloadRecord(String fileId) =>
      Future<Uint8List>.error(const CloudUnavailableException());

  @override
  Future<void> deleteRecord(String fileId) async {}

  @override
  Future<void> dispose() async {}
}

/// In-memory Drive implementation for deterministic coordinator tests.
class InMemoryDriveSyncGateway implements DriveSyncGateway {
  final Map<String, _MemoryRecord> _records = <String, _MemoryRecord>{};
  int _nextId = 0;

  @override
  Future<List<DriveSyncRecord>> listRecords() async =>
      _records.values.map((record) => record.metadata).toList(growable: false);

  @override
  Future<DriveSyncRecord> createRecord({
    required String name,
    required String mimeType,
    required Map<String, String> properties,
    required List<int> bytes,
  }) async {
    final id = 'memory-${_nextId++}';
    final record = _MemoryRecord(
      metadata: DriveSyncRecord(
        fileId: id,
        name: name,
        mimeType: mimeType,
        properties: Map<String, String>.unmodifiable(properties),
        modifiedAt: DateTime.now().toUtc(),
        size: bytes.length,
      ),
      bytes: Uint8List.fromList(bytes),
    );
    _records[id] = record;
    return record.metadata;
  }

  @override
  Future<DriveSyncRecord> updateRecord({
    required String fileId,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final existing = _records[fileId];
    if (existing == null) throw StateError('Unknown Drive record $fileId');
    final metadata = DriveSyncRecord(
      fileId: fileId,
      name: existing.metadata.name,
      mimeType: mimeType,
      properties: existing.metadata.properties,
      modifiedAt: DateTime.now().toUtc(),
      size: bytes.length,
    );
    _records[fileId] = _MemoryRecord(
      metadata: metadata,
      bytes: Uint8List.fromList(bytes),
    );
    return metadata;
  }

  @override
  Future<Uint8List> downloadRecord(String fileId) async {
    final record = _records[fileId];
    if (record == null) throw StateError('Unknown Drive record $fileId');
    return Uint8List.fromList(record.bytes);
  }

  @override
  Future<void> deleteRecord(String fileId) async {
    _records.remove(fileId);
  }

  @override
  Future<void> dispose() async {}
}

class _MemoryRecord {
  const _MemoryRecord({required this.metadata, required this.bytes});

  final DriveSyncRecord metadata;
  final Uint8List bytes;
}

/// Minimal REST Drive v3 adapter. It deliberately uses a bearer-token
/// callback so access-token refresh remains owned by the platform account
/// gateway.
class HttpDriveSyncGateway implements DriveSyncGateway {
  factory HttpDriveSyncGateway({
    required Future<String?> Function() accessToken,
    http.Client? client,
  }) =>
      HttpDriveSyncGateway._(accessToken, client ?? http.Client());

  HttpDriveSyncGateway._(this._accessToken, this._client);

  static final _filesUri = Uri.parse('https://www.googleapis.com/drive/v3/files');
  static final _uploadUri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files');
  static const _appDataScope = 'appDataFolder';

  final Future<String?> Function() _accessToken;
  final http.Client _client;

  @override
  Future<List<DriveSyncRecord>> listRecords() async {
    final records = <DriveSyncRecord>[];
    String? pageToken;
    do {
      final query = <String, String>{
        'spaces': _appDataScope,
        'q': 'trashed = false',
        'pageSize': '1000',
        'fields':
            'nextPageToken,files(id,name,mimeType,appProperties,modifiedTime,size)',
      };
      if (pageToken != null) query['pageToken'] = pageToken;
      final response = await _send('GET', _filesUri.replace(queryParameters: query));
      final json = _decodeObject(response);
      final files = json['files'];
      if (files is List) {
        for (final raw in files.whereType<Map<Object?, Object?>>()) {
          final file = Map<String, dynamic>.from(raw);
          final properties = file['appProperties'];
          records.add(
            DriveSyncRecord(
              fileId: file['id'] as String,
              name: file['name'] as String? ?? '',
              mimeType: file['mimeType'] as String? ?? 'application/octet-stream',
              properties: properties is Map
                  ? <String, String>{
                      for (final entry in properties.entries)
                        if (entry.key is String && entry.value is String)
                          entry.key as String: entry.value as String,
                    }
                  : const <String, String>{},
              modifiedAt: DateTime.tryParse(file['modifiedTime'] as String? ?? ''),
              size: (file['size'] as num?)?.toInt(),
            ),
          );
        }
      }
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return records;
  }

  @override
  Future<DriveSyncRecord> createRecord({
    required String name,
    required String mimeType,
    required Map<String, String> properties,
    required List<int> bytes,
  }) async {
    final boundary = 'journal-${const Uuid().v4()}';
    final body = _multipartBody(
      boundary: boundary,
      metadata: <String, dynamic>{
        'name': name,
        'mimeType': mimeType,
        'parents': <String>[_appDataScope],
        'appProperties': properties,
      },
      mimeType: mimeType,
      bytes: bytes,
    );
    final response = await _send(
      'POST',
      _uploadUri.replace(queryParameters: const {'uploadType': 'multipart'}),
      headers: <String, String>{
        'content-type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );
    return _parseRecord(_decodeObject(response));
  }

  @override
  Future<DriveSyncRecord> updateRecord({
    required String fileId,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final response = await _send(
      'PATCH',
      _uploadUri.replace(
        path: '${_uploadUri.path}/$fileId',
        queryParameters: const {'uploadType': 'media'},
      ),
      headers: <String, String>{'content-type': mimeType},
      body: Uint8List.fromList(bytes),
    );
    return _parseRecord(_decodeObject(response));
  }

  @override
  Future<Uint8List> downloadRecord(String fileId) async {
    final response = await _send(
      'GET',
      _filesUri.replace(
        path: '${_filesUri.path}/$fileId',
        queryParameters: const {'alt': 'media'},
      ),
    );
    return Uint8List.fromList(response.bodyBytes);
  }

  @override
  Future<void> deleteRecord(String fileId) async {
    await _send(
      'DELETE',
      _filesUri.replace(path: '${_filesUri.path}/$fileId'),
    );
  }

  @override
  Future<void> dispose() async => _client.close();

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    Object? body,
  }) async {
    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      throw const CloudAuthorizationException();
    }
    final request = http.Request(method, uri)
      ..headers.addAll(<String, String>{
        'authorization': 'Bearer $token',
        ...headers,
      });
    if (body is Uint8List) {
      request.bodyBytes = body;
    } else if (body is List<int>) {
      request.bodyBytes = Uint8List.fromList(body);
    } else if (body is String) {
      request.body = body;
    }
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final materialized = await http.Response.fromStream(response);
    if (materialized.statusCode < 200 || materialized.statusCode >= 300) {
      throw CloudHttpException(materialized.statusCode, materialized.body);
    }
    return materialized;
  }

  static Map<String, dynamic> _decodeObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Drive returned invalid JSON');
    return Map<String, dynamic>.from(decoded);
  }

  static DriveSyncRecord _parseRecord(Map<String, dynamic> json) {
    final rawProperties = json['appProperties'];
    return DriveSyncRecord(
      fileId: json['id'] as String,
      name: json['name'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      properties: rawProperties is Map
          ? <String, String>{
              for (final entry in rawProperties.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const <String, String>{},
      modifiedAt: DateTime.tryParse(json['modifiedTime'] as String? ?? ''),
      size: (json['size'] as num?)?.toInt(),
    );
  }

  static Uint8List _multipartBody({
    required String boundary,
    required Map<String, dynamic> metadata,
    required String mimeType,
    required List<int> bytes,
  }) {
    final prefix = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '${jsonEncode(metadata)}\r\n'
      '--$boundary\r\n'
      'Content-Type: $mimeType\r\n\r\n',
    );
    final suffix = utf8.encode('\r\n--$boundary--\r\n');
    return Uint8List.fromList(<int>[...prefix, ...bytes, ...suffix]);
  }
}

enum CloudAuthErrorCode {
  authorizationRequired,
  canceled,
  configuration,
  denied,
  expired,
  providerUnavailable,
  timeout,
}

class CloudAuthorizationException implements Exception {
  const CloudAuthorizationException([
    this.code = CloudAuthErrorCode.authorizationRequired,
    this.details,
  ]);

  final CloudAuthErrorCode code;
  final String? details;

  String get userMessage => switch (code) {
        CloudAuthErrorCode.canceled => 'Google sign-in was canceled.',
        CloudAuthErrorCode.configuration =>
          'Google synchronization is not configured for this build.',
        CloudAuthErrorCode.denied =>
          'Google Drive access was declined. You can try again any time.',
        CloudAuthErrorCode.expired =>
          'Google Drive authorization expired. Please reconnect.',
        CloudAuthErrorCode.providerUnavailable =>
          'Google sign-in is unavailable on this device.',
        CloudAuthErrorCode.timeout =>
          'Google sign-in timed out. Please try again.',
        CloudAuthErrorCode.authorizationRequired =>
          'Google Drive authorization is required.',
      };

  @override
  String toString() => userMessage;
}

class CloudHttpException implements Exception {
  const CloudHttpException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'Drive request failed ($statusCode): $body';
}
