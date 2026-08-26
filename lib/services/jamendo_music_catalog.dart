import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/page_music.dart';
import 'repositories.dart';

class MusicCatalogException implements Exception {
  const MusicCatalogException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Read-only Jamendo catalog adapter. It never downloads or persists audio.
class JamendoMusicCatalogRepository implements MusicCatalogRepository {
  JamendoMusicCatalogRepository({required String clientId, http.Client? client})
    : // The public parameter intentionally omits the private-field prefix.
      // ignore: prefer_initializing_formals
      _clientId = clientId,
      _client = client ?? http.Client();

  final String _clientId;
  final http.Client _client;

  @override
  bool get isConfigured => _clientId.trim().isNotEmpty;

  @override
  Future<List<PageMusicTrack>> searchTracks({
    String query = '',
    int offset = 0,
    int limit = 20,
  }) async {
    _requireConfiguration();
    final parameters = <String, String>{
      'client_id': _clientId,
      'format': 'json',
      'limit': limit.clamp(1, 200).toString(),
      'offset': offset.clamp(0, 1000000).toString(),
      'include': 'licenses',
      'audioformat': 'mp32',
      'type': 'single albumtrack',
      'vocalinstrumental': 'instrumental',
      'groupby': 'artist_id',
    };
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      parameters
        ..['featured'] = '1'
        ..['fuzzytags'] = 'relaxation lounge ambient acoustic';
    } else {
      parameters['search'] = trimmed;
    }
    return _fetch(Uri.https('api.jamendo.com', '/v3.0/tracks/', parameters));
  }

  @override
  Future<PageMusicTrack> resolveTrack(String trackId) async {
    _requireConfiguration();
    final tracks = await _fetch(
      Uri.https('api.jamendo.com', '/v3.0/tracks/', {
        'client_id': _clientId,
        'format': 'json',
        'id': trackId,
        'limit': '1',
        'include': 'licenses',
        'audioformat': 'mp32',
      }),
    );
    if (tracks.isEmpty) {
      throw const MusicCatalogException('This track is no longer available.');
    }
    return tracks.first;
  }

  Future<List<PageMusicTrack>> _fetch(Uri uri) async {
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw MusicCatalogException(
        'Jamendo request failed (${response.statusCode}).',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const MusicCatalogException('Jamendo returned invalid data.');
    }
    if (decoded is! Map) {
      throw const MusicCatalogException('Jamendo returned invalid data.');
    }
    final body = Map<String, dynamic>.from(decoded);
    final headers = body['headers'];
    if (headers is Map && headers['status'] == 'failed') {
      throw MusicCatalogException(
        headers['error_message'] as String? ?? 'Jamendo request failed.',
      );
    }
    final results = body['results'];
    if (results is! List) {
      throw const MusicCatalogException('Jamendo returned invalid track data.');
    }
    return results
        .whereType<Map<Object?, Object?>>()
        .map((raw) => _trackFromJson(Map<String, dynamic>.from(raw)))
        .where(
          (track) => track.trackId.isNotEmpty && track.streamUrl.isNotEmpty,
        )
        .toList(growable: false);
  }

  PageMusicTrack _trackFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final shareUrl =
        json['shareurl'] as String? ??
        (id.isEmpty ? '' : 'https://www.jamendo.com/track/$id');
    return PageMusicTrack(
      provider: 'jamendo',
      trackId: id,
      title: json['name'] as String? ?? 'Unknown track',
      artist: json['artist_name'] as String? ?? 'Unknown artist',
      artworkUrl:
          json['image'] as String? ?? json['album_image'] as String? ?? '',
      streamUrl: json['audio'] as String? ?? '',
      trackPageUrl: shareUrl,
      licenseUrl:
          json['license_ccurl'] as String? ??
          (json['license'] is Map
              ? (json['license'] as Map)['ccurl'] as String? ?? ''
              : ''),
      duration: Duration(
        seconds: int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      ),
    );
  }

  void _requireConfiguration() {
    if (!isConfigured) {
      throw const MusicCatalogException(
        'Set JAMENDO_CLIENT_ID to enable the music catalog.',
      );
    }
  }

  void dispose() => _client.close();
}
