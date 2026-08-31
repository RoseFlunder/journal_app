import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/page_music.dart';
import 'package:journal_app/services/audio_playback.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/ui/features/music/view_models/page_music_controller.dart';

void main() {
  const track = PageMusicTrack(
    provider: 'jamendo',
    trackId: 'one',
    title: 'One',
    artist: 'Artist',
    streamUrl: 'https://audio.example/one.mp3',
    trackPageUrl: 'https://jamendo.example/one',
    licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
  );

  test(
    'autoplays selected page music and resets when active page changes',
    () async {
      final playback = _FakePlayback();
      final controller = PageMusicController(
        catalog: const _FakeCatalog(track),
        playback: playback,
        persistResolvedTrack: (_, _) async {},
      );

      await controller.setActivePage('page-one', track);
      expect(playback.loadedUrls, [track.streamUrl]);
      expect(playback.playCalls, 1);

      await controller.toggle();
      expect(playback.pauseCalls, 1);

      await controller.setActivePage('page-two', null);
      expect(playback.stopCalls, greaterThanOrEqualTo(2));
      expect(controller.track, isNull);
      controller.dispose();
    },
  );

  test('pause toggles without reloading and loop mode is configured', () async {
    final playback = _FakePlayback();
    final controller = PageMusicController(
      catalog: const _FakeCatalog(track),
      playback: playback,
      persistResolvedTrack: (_, _) async {},
    );
    await Future<void>.delayed(Duration.zero);
    await controller.setActivePage('page', track);
    playback.emit(AudioPlaybackStatus.playing);
    await controller.toggle();

    expect(playback.loopCalls, 1);
    expect(playback.loadedUrls, hasLength(1));
    expect(playback.pauseCalls, 1);
    controller.dispose();
  });

  test('restart reloads and autoplays the selected track from the beginning',
      () async {
    final playback = _FakePlayback();
    final controller = PageMusicController(
      catalog: const _FakeCatalog(track),
      playback: playback,
      persistResolvedTrack: (_, _) async {},
    );

    await controller.setActivePage('page', track);
    await controller.setActivePage('page', track, restart: true);

    expect(playback.loadedUrls, [track.streamUrl, track.streamUrl]);
    expect(playback.playCalls, 2);
    expect(playback.stopCalls, greaterThanOrEqualTo(2));
    controller.dispose();
  });

  test('refreshes a failed stream URL and persists the replacement', () async {
    final playback = _FakePlayback(failFirstLoad: true);
    const refreshed = PageMusicTrack(
      provider: 'jamendo',
      trackId: 'one',
      title: 'One',
      artist: 'Artist',
      streamUrl: 'https://audio.example/refreshed.mp3',
      trackPageUrl: 'https://jamendo.example/one',
      licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    );
    PageMusicTrack? persisted;
    final controller = PageMusicController(
      catalog: const _FakeCatalog(refreshed),
      playback: playback,
      persistResolvedTrack: (_, value) async => persisted = value,
    );
    await controller.setActivePage('page', track);

    await controller.toggle();

    expect(playback.loadedUrls, [track.streamUrl, refreshed.streamUrl]);
    expect(persisted?.streamUrl, refreshed.streamUrl);
    expect(controller.error, isNull);
    controller.dispose();
  });

}

class _FakeCatalog implements MusicCatalogRepository {
  const _FakeCatalog(this.track);
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

class _FakePlayback implements AudioPlaybackService {
  _FakePlayback({this.failFirstLoad = false});
  final bool failFirstLoad;
  final _states = StreamController<AudioPlaybackSnapshot>.broadcast();
  final List<String> loadedUrls = [];
  int loopCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;

  void emit(AudioPlaybackStatus status) =>
      _states.add(AudioPlaybackSnapshot(status));

  @override
  Stream<AudioPlaybackSnapshot> get states => _states.stream;
  @override
  Future<void> load(String url) async {
    loadedUrls.add(url);
    if (failFirstLoad && loadedUrls.length == 1) throw Exception('expired');
  }

  @override
  Future<void> pause() async => pauseCalls++;
  @override
  Future<void> play() async {
    playCalls++;
    emit(AudioPlaybackStatus.playing);
  }

  @override
  Future<void> setLoopOne() async => loopCalls++;
  @override
  Future<void> stopAndReset() async => stopCalls++;
  @override
  Future<void> dispose() async => _states.close();
}
