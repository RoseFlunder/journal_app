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

  String? get pageId => _pageId;
  PageMusicTrack? get track => _track;
  AudioPlaybackStatus get status => _status;
  String? get error => _error;
  bool get isPlaying => _status == AudioPlaybackStatus.playing;
  bool get isLoading => _status == AudioPlaybackStatus.loading;

  Future<void> setActivePage(String? pageId, PageMusicTrack? track) async {
    final pageChanged = _pageId != pageId;
    final trackChanged =
        _track?.trackId != track?.trackId ||
        _track?.streamUrl != track?.streamUrl;
    final selectionChanged = pageChanged || trackChanged;
    if (selectionChanged) {
      _selectionGeneration++;
      await _stopSilently();
    }
    _pageId = pageId;
    _track = track;
    _error = null;
    _notify();
    if (selectionChanged && pageId != null && track != null) {
      await _playCurrentSelection();
    }
  }

  Future<void> toggle() async {
    final track = _track;
    final pageId = _pageId;
    if (track == null || pageId == null || isLoading) return;
    if (isPlaying) {
      await _playback.pause();
      return;
    }
    await _playCurrentSelection();
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
        await _persistResolvedTrack(pageId, refreshed);
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
      _loadedUrl = track.streamUrl;
    }
    if (!_isCurrentSelection(pageId, track, generation)) return false;
    await _playback.play();
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
    await _stopSilently();
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
    unawaited(_playback.dispose());
    super.dispose();
  }
}
