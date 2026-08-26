import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journal_app/services/jamendo_music_catalog.dart';

void main() {
  group('JamendoMusicCatalogRepository', () {
    test(
      'searches featured instrumental music and parses attribution',
      () async {
        late Uri requested;
        final client = MockClient((request) async {
          requested = request.url;
          return http.Response('''
          {
            "headers": {"status": "success"},
            "results": [{
              "id": "42",
              "name": "Soft Rain",
              "artist_name": "Bloom Artist",
              "image": "https://img.example/42.jpg",
              "audio": "https://audio.example/42.mp3",
              "shareurl": "https://jamendo.example/track/42",
              "license_ccurl": "https://creativecommons.org/licenses/by/4.0/",
              "duration": "125"
            }]
          }
        ''', 200);
        });
        final repository = JamendoMusicCatalogRepository(
          clientId: 'client',
          client: client,
        );

        final tracks = await repository.searchTracks();

        expect(requested.host, 'api.jamendo.com');
        expect(requested.queryParameters['featured'], '1');
        expect(requested.queryParameters['vocalinstrumental'], 'instrumental');
        expect(tracks.single.trackId, '42');
        expect(tracks.single.title, 'Soft Rain');
        expect(tracks.single.artist, 'Bloom Artist');
        expect(tracks.single.duration, const Duration(seconds: 125));
        expect(tracks.single.licenseUrl, contains('creativecommons.org'));
        repository.dispose();
      },
    );

    test('encodes text search, offset, and limit', () async {
      late Uri requested;
      final repository = JamendoMusicCatalogRepository(
        clientId: 'client',
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            '{"headers":{"status":"success"},"results":[]}',
            200,
          );
        }),
      );

      await repository.searchTracks(
        query: 'quiet piano',
        offset: 20,
        limit: 20,
      );

      expect(requested.queryParameters['search'], 'quiet piano');
      expect(requested.queryParameters['offset'], '20');
      expect(requested.queryParameters['featured'], isNull);
      repository.dispose();
    });

    test('surfaces API, HTTP, and malformed response failures', () async {
      Future<void> expectFailure(http.Response response, String message) async {
        final repository = JamendoMusicCatalogRepository(
          clientId: 'client',
          client: MockClient((_) async => response),
        );
        await expectLater(
          repository.searchTracks(),
          throwsA(
            isA<MusicCatalogException>().having(
              (error) => error.message,
              'message',
              contains(message),
            ),
          ),
        );
        repository.dispose();
      }

      await expectFailure(http.Response('unavailable', 503), '503');
      await expectFailure(http.Response('not-json', 200), 'invalid data');
      await expectFailure(
        http.Response(
          '{"headers":{"status":"failed","error_message":"Suspended"},"results":[]}',
          200,
        ),
        'Suspended',
      );
    });
  });
}
