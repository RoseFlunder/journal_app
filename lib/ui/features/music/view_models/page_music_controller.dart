import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../models/page_music.dart';
import '../../../../services/audio_playback.dart';
import '../../../../services/repositories.dart';

class PageMusicController extends ChangeNotifier {
  PageMusicController({
    required MusicCatalogRepository catalog,
    required AudioPlaybackService playback,
    required Future<void> Function(String pageId, PageMusicTrack track)
    persistResolvedTrack,
  }) : // Keep dependency names public and readable at composition sites.
       // ignore: prefer_initializing_formals
       _catalog = catalog,
       // ignore: prefer_initializing_formals
       _playback = playback,
       // ignore: prefer_initializing_formals
       _persistResolvedTrack = persistResolvedTrack {
    _subscription = _playback.states.listen(_handlePlaybackState);
    unawaited(_playback.setLoopOne().catchError((_) {}));
  }

  final MusicCatalogRepository _catalog;
  final AudioPlaybackService _playback;
  final Future<void> Function(String pageId, PageMusicTrack track)
  _persistResolvedTrack;
  late final StreamSubscription<AudioPlaybackSnapshot> _subscription;

  String? _pageId;
  PageMusicTrack? _track;
  String? _loadedUrl;
  AudioPlaybackStatus _status = AudioPlaybackStatus.idle;
  String? _error;
  int _selectionGeneration = 0;
  bool _disposed = false;
  Future<void> _operations = Future.value();
  bool _previewing = false;

  String? get pageId => _pageId;
  PageMusicTrack? get track => _track;
  AudioPlaybackStatus get status => _status;
  String? get error => _error;
  bool get isPlaying => _status == AudioPlaybackStatus.playing;
  bool get isLoading => _status == AudioPlaybackStatus.loading;

  Future<void> setActivePage(
    String? pageId,
    PageMusicTrack? track, {
    bool restart = false,
    bool autoplay = true,
    bool preview = false,
    bool resume = false,
  }) async {
    if (_disposed) return;
    final pageChanged = _pageId != pageId;
    final trackChanged =
        _track?.trackId != track?.trackId ||
        _track?.streamUrl != track?.streamUrl;
    final selectionChanged = pageChanged || trackChanged;
    final shouldPlay = pageId != null && track != null;
    final generation = selectionChanged || restart
        ? ++_selectionGeneration
        : _selectionGeneration;
    _pageId = pageId;
    _track = track;
    _previewing = preview;
    _error = null;
    _notify();
    await _enqueue(() async {
      if (_disposed || generation != _selectionGeneration) return;
      if (selectionChanged || restart) await _stopSilently();
      if (_disposed || generation != _selectionGeneration) return;
      if (shouldPlay &&
          autoplay &&
          (selectionChanged || restart || (resume && !isPlaying))) {
        await _playCurrentSelection();
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> toggle() async {
    final track = _track;
    final pageId = _pageId;
    if (track == null || pageId == null || isLoading) return;
    if (isPlaying) {
      await _enqueue(_playback.pause);
      return;
    }
    await _enqueue(_playCurrentSelection);
  }

  Future<void> _playCurrentSelection() async {
    final track = _track;
    final pageId = _pageId;
    if (track == null || pageId == null || isLoading) return;
    final generation = _selectionGeneration;
    _error = null;
    _status = AudioPlaybackStatus.loading;
    _notify();
    try {
      if (!await _loadAndPlay(track, pageId, generation)) return;
    } catch (_) {
      if (!_isCurrentSelection(pageId, track, generation)) return;
      try {
        final refreshed = await _catalog.resolveTrack(track.trackId);
        if (!_isCurrentSelection(pageId, track, generation)) return;
        _track = refreshed;
        if (!_previewing) await _persistResolvedTrack(pageId, refreshed);
        if (!_isCurrentSelection(pageId, refreshed, generation)) return;
        if (!await _loadAndPlay(refreshed, pageId, generation)) return;
      } catch (error) {
        if (!_isCurrentSelection(pageId, _track, generation)) return;
        _loadedUrl = null;
        _setError(_friendlyError(error));
      }
    }
  }

  Future<bool> _loadAndPlay(
    PageMusicTrack track,
    String pageId,
    int generation,
  ) async {
    if (track.streamUrl.isEmpty) {
      throw StateError('This track has no playable stream.');
    }
    if (_loadedUrl != track.streamUrl) {
      await _playback.load(track.streamUrl);
      if (!_isCurrentSelection(pageId, track, generation)) return false;
      _loadedUrl = track.streamUrl;
    }
    if (!_isCurrentSelection(pageId, track, generation)) return false;
    // just_audio's play future lasts until playback ends (forever for a loop).
    // Source changes must remain available while that future is pending.
    unawaited(
      _playback.play().catchError((Object error) {
        if (_isCurrentSelection(pageId, track, generation)) {
          _setError(_friendlyError(error));
        }
      }),
    );
    return true;
  }

  bool _isCurrentSelection(
    String pageId,
    PageMusicTrack? track,
    int generation,
  ) {
    return !_disposed &&
        generation == _selectionGeneration &&
        _pageId == pageId &&
        _track?.trackId == track?.trackId &&
        _track?.streamUrl == track?.streamUrl;
  }

  Future<void> stopAndReset() async {
    _selectionGeneration++;
    await _enqueue(_stopSilently);
    _notify();
  }

  Future<void> _stopSilently() async {
    try {
      await _playback.stopAndReset();
    } catch (_) {
      // Stopping during navigation/disposal is best-effort.
    }
    _loadedUrl = null;
    _status = AudioPlaybackStatus.idle;
  }

  void _handlePlaybackState(AudioPlaybackSnapshot state) {
    if (_disposed) return;
    _status = state.status;
    if (state.status == AudioPlaybackStatus.error) {
      _error = state.message ?? 'Could not play this track.';
    }
    _notify();
  }

  void _setError(String message) {
    _status = AudioPlaybackStatus.error;
    _error = message;
    _notify();
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) return message.substring(11);
    return message.isEmpty ? 'Could not play this track.' : message;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    _selectionGeneration++;
    unawaited(_enqueue(_playback.dispose));
    super.dispose();
  }
}
