import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/app/app_dependencies.dart';
import 'package:journal_app/main.dart';
import 'package:journal_app/models/page_music.dart';
import 'package:journal_app/services/audio_playback.dart';

import 'support/hive_test_environment.dart';

import 'package:journal_app/services/repositories.dart';

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late TestHiveEnvironment store;

  const track = PageMusicTrack(
    provider: 'jamendo',
    trackId: '42',
    title: 'Soft Rain',
    artist: 'Bloom Artist',
    streamUrl: 'https://audio.example/42.mp3',
    trackPageUrl: 'https://jamendo.example/42',
    licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
  );

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('page_music_widget_test');
    Hive.init(temp.path);
  });

  tearDownAll(() async {
    await Hive.close();
    temp.deleteSync(recursive: true);
  });

  testWidgets('page music autoplays and resets on navigation', (tester) async {
    store = TestHiveEnvironment();
    await store.init();
    final entry = await store.addEntry(title: 'Music page');
    await store.updateEntry(entry.id, (entry) => entry.music = track);
    final playback = _WidgetPlayback();

    await tester.pumpWidget(
      JournalApp(
        dependencies: AppDependencies(
          repositories: store.repositories,
          musicCatalog: const _WidgetCatalog(track),
          audioPlaybackFactory: () => playback,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music page'));
    await tester.pumpAndSettle();

    expect(find.text('Soft Rain'), findsOneWidget);
    expect(playback.loadedUrls, [track.streamUrl]);
    expect(playback.playCalls, 1);
    expect(find.byTooltip('Pause page music'), findsOneWidget);

    // Reopening while the looping play future is pending must remain possible.
    final stopsBeforePicker = playback.stopCalls;
    await tester.tap(find.byTooltip('Change page music'));
    await tester.pumpAndSettle();
    expect(find.text('Choose page music'), findsOneWidget);
    expect(playback.stopCalls, stopsBeforePicker);
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(playback.playCalls, 1);
    await tester.tap(find.byTooltip('Change page music'));
    await tester.pumpAndSettle();
    expect(find.text('Choose page music'), findsOneWidget);
    await tester.tap(find.byTooltip('Close music picker'));
    await tester.pumpAndSettle();
    expect(playback.stopCalls, stopsBeforePicker);

    await tester.tap(find.byTooltip('Pause page music'));
    await tester.pump();
    expect(playback.playCalls, 1);

    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(playback.stopCalls, greaterThanOrEqualTo(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _WidgetCatalog implements MusicCatalogRepository {
  const _WidgetCatalog(this.track);
  final PageMusicTrack track;
  @override
  bool get isConfigured => true;
  @override
  Future<PageMusicTrack> resolveTrack(String trackId) async => track;
  @override
  Future<List<PageMusicTrack>> searchTracks({
    String query = '',
    int offset = 0,
    int limit = 20,
  }) async => [track];
}

class _WidgetPlayback implements AudioPlaybackService {
  Completer<void>? _playing;
  final _states = StreamController<AudioPlaybackSnapshot>.broadcast();
  final loadedUrls = <String>[];
  int playCalls = 0;
  int stopCalls = 0;
  @override
  Stream<AudioPlaybackSnapshot> get states => _states.stream;
  @override
  Future<void> load(String url) async => loadedUrls.add(url);
  @override
  Future<void> pause() async {
    if (_playing != null && !_playing!.isCompleted) _playing!.complete();
    _states.add(const AudioPlaybackSnapshot(AudioPlaybackStatus.paused));
  }

  @override
  Future<void> play() async {
    playCalls++;
    _states.add(const AudioPlaybackSnapshot(AudioPlaybackStatus.playing));
    _playing = Completer<void>();
    await _playing!.future;
  }

  @override
  Future<void> setLoopOne() async {}
  @override
  Future<void> stopAndReset() async {
    if (_playing != null && !_playing!.isCompleted) _playing!.complete();
    stopCalls++;
    _states.add(const AudioPlaybackSnapshot(AudioPlaybackStatus.idle));
  }

  @override
  Future<void> dispose() async => _states.close();
}
