import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/page_music.dart';
import 'package:journal_app/services/audio_playback.dart';
import 'package:journal_app/services/repositories.dart';
import 'package:journal_app/ui/features/music/view_models/music_picker_view_model.dart';
import 'package:journal_app/ui/features/music/view_models/page_music_controller.dart';
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
    final viewModel = MusicPickerViewModel(
      catalog: catalog,
      playback: _controller(playback),
    );
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
                  builder: (_) => MusicPickerSheet(viewModel: viewModel),
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
    await viewModel.close();
    viewModel.dispose();
    expect(playback.stopCalls, 2);
    expect(playback.disposed, isFalse);
  });

  test('discards stale search responses after the query changes', () async {
    final catalog = _SequencedCatalog();
    final playback = _PickerPlayback();
    final viewModel = MusicPickerViewModel(
      catalog: catalog,
      playback: _controller(playback),
    );

    viewModel.setQuery('first');
    final firstSearch = viewModel.search();
    viewModel.setQuery('second');
    final secondSearch = viewModel.search();
    catalog.responses[0].complete(const <PageMusicTrack>[]);
    catalog.responses[1].complete(<PageMusicTrack>[_track('second')]);
    await Future.wait([firstSearch, secondSearch]);

    expect(viewModel.tracks.single.title, 'second');
    await viewModel.close();
    viewModel.dispose();
  });

  testWidgets('first opening stays loading until the catalog responds', (
    tester,
  ) async {
    final catalog = _SequencedCatalog();
    final viewModel = MusicPickerViewModel(
      catalog: catalog,
      playback: _controller(_PickerPlayback()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MusicPickerSheet(viewModel: viewModel)),
      ),
    );
    expect(find.text('Loading music…'), findsOneWidget);
    expect(find.text('No instrumental tracks found.'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Loading music…'), findsOneWidget);
    catalog.responses.single.complete([track]);
    await tester.pumpAndSettle();
    expect(find.text('Soft Rain'), findsOneWidget);
    await viewModel.close();
    viewModel.dispose();
  });

  testWidgets('failed initial search can retry without reopening', (
    tester,
  ) async {
    final catalog = _SequencedCatalog();
    final viewModel = MusicPickerViewModel(
      catalog: catalog,
      playback: _controller(_PickerPlayback()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MusicPickerSheet(viewModel: viewModel)),
      ),
    );
    catalog.responses.single.completeError(Exception('Offline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Loading music…'), findsOneWidget);
    catalog.responses.last.complete([track]);
    await tester.pumpAndSettle();
    expect(find.text('Soft Rain'), findsOneWidget);
    await viewModel.close();
    viewModel.dispose();
  });

  testWidgets('retains picker state when an ancestor rebuilds', (tester) async {
    final catalog = _PickerCatalog(track);
    final playback = _PickerPlayback();
    final viewModel = MusicPickerViewModel(
      catalog: catalog,
      playback: _controller(playback),
    );
    VoidCallback? rebuild;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = () => setState(() {});
          return MaterialApp(
            home: Scaffold(body: MusicPickerSheet(viewModel: viewModel)),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('music-search-field')),
      'first keyword',
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    rebuild!();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('music-search-field')),
      'second keyword',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(
      catalog.queries,
      containsAll(<String>['first keyword', 'second keyword']),
    );
    expect(find.text('Soft Rain'), findsOneWidget);
    await viewModel.close();
    viewModel.dispose();
  });

  testWidgets('shows setup guidance when catalog is disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicPickerSheet(
            viewModel: MusicPickerViewModel(
              catalog: DisabledMusicCatalogRepository(),
              playback: _controller(_disabledFactory()),
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

class _SequencedCatalog implements MusicCatalogRepository {
  final responses = <Completer<List<PageMusicTrack>>>[];

  @override
  bool get isConfigured => true;

  @override
  Future<PageMusicTrack> resolveTrack(String trackId) async => _track(trackId);

  @override
  Future<List<PageMusicTrack>> searchTracks({
    String query = '',
    int offset = 0,
    int limit = 20,
  }) {
    final response = Completer<List<PageMusicTrack>>();
    responses.add(response);
    return response.future;
  }
}

PageMusicTrack _track(String id) => PageMusicTrack(
  provider: 'jamendo',
  trackId: id,
  title: id,
  artist: 'Artist',
  streamUrl: 'https://audio.example/$id.mp3',
  trackPageUrl: 'https://jamendo.example/$id',
  licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
);

class _PickerPlayback implements AudioPlaybackService {
  final _states = StreamController<AudioPlaybackSnapshot>.broadcast();
  final loadedUrls = <String>[];
  int playCalls = 0;
  int stopCalls = 0;
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
  Future<void> stopAndReset() async => stopCalls++;
  @override
  Future<void> dispose() async {
    disposed = true;
    await _states.close();
  }
}

PageMusicController _controller(AudioPlaybackService playback) {
  final controller = PageMusicController(
    catalog: const DisabledMusicCatalogRepository(),
    playback: playback,
    persistResolvedTrack: (_, _) async {},
  );
  unawaited(controller.setActivePage('page', null));
  addTearDown(controller.dispose);
  return controller;
}
