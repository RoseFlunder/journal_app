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
       _playback = playback;

  final MusicCatalogRepository _catalog;
  final AudioPlaybackService _playback;
  final PageMusicTrack? current;
  late final StreamSubscription<AudioPlaybackSnapshot> _subscription =
      _playback.states.listen(_handlePlaybackState);
  Timer? _debounce;
  List<PageMusicTrack> _tracks = const <PageMusicTrack>[];
  String _query = '';
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _previewTrackId;
  AudioPlaybackStatus _previewStatus = AudioPlaybackStatus.idle;
  int _requestGeneration = 0;
  bool _disposed = false;

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
      isPreviewing(track) && _previewStatus == AudioPlaybackStatus.loading;

  /// Starts the initial catalog request after the sheet is mounted.
  Future<void> load() async {
    try {
      await _playback.setLoopOne();
    } catch (_) {}
    await search();
  }

  void setQuery(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(search());
    });
  }

  Future<void> search({bool append = false}) async {
    final generation = ++_requestGeneration;
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
        query: _query,
        offset: append ? _tracks.length : 0,
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
    if (isLoading(track)) return;
    if (isPlaying(track)) {
      await _playback.pause();
      return;
    }
    try {
      if (!isPreviewing(track)) {
        await _playback.stopAndReset();
        if (_disposed) return;
        _previewTrackId = track.trackId;
        _previewStatus = AudioPlaybackStatus.loading;
        _notify();
        await _playback.load(track.streamUrl);
      }
      await _playback.play();
    } catch (error) {
      if (_disposed) return;
      _previewStatus = AudioPlaybackStatus.error;
      _error = 'Could not preview ${track.title}: $error';
      _notify();
    }
  }

  void _handlePlaybackState(AudioPlaybackSnapshot state) {
    if (_disposed) return;
    _previewStatus = state.status;
    if (state.status == AudioPlaybackStatus.error) {
      _error = state.message ?? 'Could not preview this track.';
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_subscription.cancel());
    unawaited(_playback.dispose());
    super.dispose();
  }
}

