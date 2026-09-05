// The dependency fields stay private while constructor names remain clear at
// composition sites.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../models/page_music.dart';
import '../../../../services/audio_playback.dart';
import 'page_music_controller.dart';
import '../../../../services/repositories.dart';

/// Owns catalog search and preview state for the music picker view.
class MusicPickerViewModel extends ChangeNotifier {
  MusicPickerViewModel({
    required MusicCatalogRepository catalog,
    required PageMusicController playback,
    this.current,
  }) : _catalog = catalog,
       _playback = playback {
    _playback.addListener(_notify);
  }

  final MusicCatalogRepository _catalog;
  final PageMusicController _playback;
  final PageMusicTrack? current;

  Timer? _debounce;
  List<PageMusicTrack> _tracks = const <PageMusicTrack>[];
  String _query = '';
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _requestGeneration = 0;
  bool didPreview = false;
  bool _disposed = false;
  Future<void>? _closeFuture;

  bool get isConfigured => _catalog.isConfigured;
  List<PageMusicTrack> get tracks => List.unmodifiable(_tracks);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error ?? (didPreview ? _playback.error : null);
  String? get previewTrackId => _playback.track?.trackId;
  AudioPlaybackStatus get previewStatus => _playback.status;

  bool isPreviewing(PageMusicTrack track) => previewTrackId == track.trackId;

  bool isPlaying(PageMusicTrack track) =>
      isPreviewing(track) && previewStatus == AudioPlaybackStatus.playing;

  bool isLoading(PageMusicTrack track) =>
      isPreviewing(track) && _playback.isLoading;

  /// Starts the initial catalog request after the sheet is mounted.
  Future<void> load() async {
    if (_disposed) return;

    await search();
  }

  void setQuery(String value) {
    if (_disposed) return;
    _query = value;
    // Invalidate an in-flight request immediately. Waiting for the debounce
    // would allow an old pagination response to be appended to this query.
    _requestGeneration++;
    _tracks = const <PageMusicTrack>[];
    // Show the same loading state during the debounce and request so the
    // cleared result area never looks like a completed empty search.
    _loading = true;
    _loadingMore = false;
    _error = null;
    _notify();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(search());
    });
  }

  Future<void> search({bool append = false}) async {
    if (_disposed) return;
    if (!append) _debounce?.cancel();
    final generation = ++_requestGeneration;
    final query = _query;
    final offset = append ? _tracks.length : 0;
    if (!isConfigured) {
      _loading = false;
      _loadingMore = false;
      _error = 'Set JAMENDO_CLIENT_ID to enable the music catalog.';
      _notify();
      return;
    }
    if (append) {
      _loadingMore = true;
    } else {
      _loading = true;
      _error = null;
    }
    _notify();
    try {
      final tracks = await _catalog
          .searchTracks(query: query, offset: offset, limit: 20)
          .timeout(const Duration(seconds: 20));
      if (_disposed || generation != _requestGeneration) return;
      _tracks = append ? [..._tracks, ...tracks] : tracks;
      _loading = false;
      _loadingMore = false;
      _notify();
    } catch (error) {
      if (_disposed || generation != _requestGeneration) return;
      _loading = false;
      _loadingMore = false;
      _error = error.toString();
      _notify();
    }
  }

  Future<void> togglePreview(PageMusicTrack track) async {
    if (_disposed || isLoading(track)) return;
    didPreview = true;
    if (isPreviewing(track)) {
      await _playback.toggle();
    } else {
      await _playback.setActivePage(_playback.pageId, track, preview: true);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Releases picker listeners without stopping the shared page player.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _disposed = true;
    _debounce?.cancel();
    _requestGeneration++;
    _playback.removeListener(_notify);
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
