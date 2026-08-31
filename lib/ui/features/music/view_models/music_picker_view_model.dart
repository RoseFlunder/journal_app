// The dependency fields stay private while constructor names remain clear at
// composition sites.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../models/page_music.dart';
import '../../../../services/audio_playback.dart';
import '../../../../services/repositories.dart';

/// Owns catalog search and preview state for the music picker view.
class MusicPickerViewModel extends ChangeNotifier {
  MusicPickerViewModel({
    required MusicCatalogRepository catalog,
    required AudioPlaybackService playback,
    this.current,
  }) : _catalog = catalog,
       _playback = playback {
    _subscription = _playback.states.listen(_handlePlaybackState);
  }

  final MusicCatalogRepository _catalog;
  final AudioPlaybackService _playback;
  final PageMusicTrack? current;
  late final StreamSubscription<AudioPlaybackSnapshot> _subscription;
  Timer? _debounce;
  List<PageMusicTrack> _tracks = const <PageMusicTrack>[];
  String _query = '';
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _previewTrackId;
  AudioPlaybackStatus _previewStatus = AudioPlaybackStatus.idle;
  int _requestGeneration = 0;
  int _previewGeneration = 0;
  bool _previewOperationActive = false;
  bool _disposed = false;
  Future<void>? _closeFuture;

  bool get isConfigured => _catalog.isConfigured;
  List<PageMusicTrack> get tracks => List.unmodifiable(_tracks);
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  String? get previewTrackId => _previewTrackId;
  AudioPlaybackStatus get previewStatus => _previewStatus;

  bool isPreviewing(PageMusicTrack track) =>
      _previewTrackId == track.trackId;

  bool isPlaying(PageMusicTrack track) =>
      isPreviewing(track) && _previewStatus == AudioPlaybackStatus.playing;

  bool isLoading(PageMusicTrack track) =>
      isPreviewing(track) &&
      (_previewStatus == AudioPlaybackStatus.loading ||
          _previewOperationActive);

  /// Starts the initial catalog request after the sheet is mounted.
  Future<void> load() async {
    if (_disposed) return;
    try {
      await _playback.setLoopOne();
    } catch (_) {}
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
      final tracks = await _catalog.searchTracks(
        query: query,
        offset: offset,
        limit: 20,
      );
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
    if (_disposed) return;
    if (isLoading(track)) return;
    if (isPlaying(track)) {
      await _playback.pause();
      return;
    }
    final generation = ++_previewGeneration;
    final mustLoad = !isPreviewing(track) ||
        _previewStatus == AudioPlaybackStatus.error;
    _previewOperationActive = true;
    _previewTrackId = track.trackId;
    _previewStatus = AudioPlaybackStatus.loading;
    _notify();
    try {
      await _playback.stopAndReset();
      if (!_isCurrentPreview(generation)) return;
      if (mustLoad) await _playback.load(track.streamUrl);
      if (!_isCurrentPreview(generation)) return;
      _previewStatus = AudioPlaybackStatus.loading;
      _previewOperationActive = false;
      _notify();
      await _playback.play();
    } catch (error) {
      if (!_isCurrentPreview(generation)) return;
      _previewOperationActive = false;
      _previewStatus = AudioPlaybackStatus.error;
      _error = 'Could not preview ${track.title}: $error';
      _notify();
    }
  }

  bool _isCurrentPreview(int generation) =>
      !_disposed && generation == _previewGeneration;

  void _handlePlaybackState(AudioPlaybackSnapshot state) {
    if (_disposed) return;
    // stopAndReset emits idle before the replacement source is loaded. Keep
    // the row busy for that handover instead of briefly enabling a second
    // preview request.
    if (_previewOperationActive && state.status == AudioPlaybackStatus.idle) {
      return;
    }
    _previewStatus = state.status;
    if (state.status == AudioPlaybackStatus.error) {
      _error = state.message ?? 'Could not preview this track.';
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Stops the preview and releases its player. The operation is idempotent
  /// so the presenter and widget teardown can safely converge on one close.
  Future<void> close() {
    return _closeFuture ??= _closePreview();
  }

  Future<void> _closePreview() async {
    _disposed = true;
    _debounce?.cancel();
    _requestGeneration++;
    _previewGeneration++;
    Object? failure;
    // Cancellation is best-effort; some platform stream implementations keep
    // their cancellation future open while the player is being torn down.
    unawaited(_subscription.cancel());
    try {
      await _playback.stopAndReset();
    } catch (error) {
      failure ??= error;
    }
    try {
      await _playback.dispose();
    } catch (error) {
      failure ??= error;
    }
    if (failure != null) throw failure;
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
