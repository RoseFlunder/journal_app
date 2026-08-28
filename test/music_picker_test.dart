import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/page_music.dart';
import 'package:journal_app/services/audio_playback.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/ui/features/music/view_models/music_picker_view_model.dart';
import 'package:journal_app/ui/features/music/views/music_picker_sheet.dart';

void main() {
  const track = PageMusicTrack(
    provider: 'jamendo',
    trackId: '42',
    title: 'Soft Rain',
    artist: 'Bloom Artist',
    streamUrl: 'https://audio.example/42.mp3',
    trackPageUrl: 'https://jamendo.example/42',
    licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    duration: Duration(minutes: 2, seconds: 5),
  );

  testWidgets('searches, previews, and returns a selected track', (
    tester,
  ) async {
    final catalog = _PickerCatalog(track);
    final playback = _PickerPlayback();
    MusicPickerResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showModalBottomSheet<MusicPickerResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MusicPickerSheet(
                    viewModel: MusicPickerViewModel(
                      catalog: catalog,
                      playback: playback,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Soft Rain'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('music-search-field')),
      'quiet piano',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(catalog.queries, contains('quiet piano'));

    await tester.tap(find.byTooltip('Preview Soft Rain'));
    await tester.pump();
    expect(playback.loadedUrls, [track.streamUrl]);
    expect(playback.playCalls, 1);

    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(result?.track?.trackId, '42');
    expect(playback.disposed, isTrue);
  });

  testWidgets('shows setup guidance when catalog is disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicPickerSheet(
            viewModel: MusicPickerViewModel(
              catalog: DisabledMusicCatalogRepository(),
              playback: _disabledFactory(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('JAMENDO_CLIENT_ID'), findsOneWidget);
  });
}

AudioPlaybackService _disabledFactory() => const DisabledAudioPlaybackService();

class _PickerCatalog implements MusicCatalogRepository {
  _PickerCatalog(this.track);
  final PageMusicTrack track;
  final List<String> queries = [];
  @override
  bool get isConfigured => true;
  @override
  Future<PageMusicTrack> resolveTrack(String trackId) async => track;
  @override
  Future<List<PageMusicTrack>> searchTracks({
    String query = '',
    int offset = 0,
    int limit = 20,
  }) async {
    queries.add(query);
    return [track];
  }
}

class _PickerPlayback implements AudioPlaybackService {
  final _states = StreamController<AudioPlaybackSnapshot>.broadcast();
  final loadedUrls = <String>[];
  int playCalls = 0;
  bool disposed = false;
  @override
  Stream<AudioPlaybackSnapshot> get states => _states.stream;
  @override
  Future<void> load(String url) async => loadedUrls.add(url);
  @override
  Future<void> pause() async =>
      _states.add(const AudioPlaybackSnapshot(AudioPlaybackStatus.paused));
  @override
  Future<void> play() async {
    playCalls++;
    _states.add(const AudioPlaybackSnapshot(AudioPlaybackStatus.playing));
  }

  @override
  Future<void> setLoopOne() async {}
  @override
  Future<void> stopAndReset() async {}
  @override
  Future<void> dispose() async {
    disposed = true;
    await _states.close();
  }
}
