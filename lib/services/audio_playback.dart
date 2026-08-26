import 'dart:async';

import 'package:just_audio/just_audio.dart';

enum AudioPlaybackStatus { idle, loading, playing, paused, error }

class AudioPlaybackSnapshot {
  const AudioPlaybackSnapshot(this.status, {this.message});

  final AudioPlaybackStatus status;
  final String? message;
}

abstract interface class AudioPlaybackService {
  Stream<AudioPlaybackSnapshot> get states;

  Future<void> load(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> stopAndReset();
  Future<void> setLoopOne();
  Future<void> dispose();
}

class JustAudioPlaybackService implements AudioPlaybackService {
  JustAudioPlaybackService({AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    _subscription = _player.playerStateStream.listen(
      _handleState,
      onError: (Object error, StackTrace stackTrace) {
        _states.add(
          AudioPlaybackSnapshot(
            AudioPlaybackStatus.error,
            message: error.toString(),
          ),
        );
      },
    );
  }

  final AudioPlayer _player;
  final StreamController<AudioPlaybackSnapshot> _states =
      StreamController<AudioPlaybackSnapshot>.broadcast();
  late final StreamSubscription<PlayerState> _subscription;

  @override
  Stream<AudioPlaybackSnapshot> get states => _states.stream;

  void _handleState(PlayerState state) {
    final status = switch (state.processingState) {
      ProcessingState.loading ||
      ProcessingState.buffering => AudioPlaybackStatus.loading,
      ProcessingState.idle => AudioPlaybackStatus.idle,
      _ =>
        state.playing
            ? AudioPlaybackStatus.playing
            : AudioPlaybackStatus.paused,
    };
    _states.add(AudioPlaybackSnapshot(status));
  }

  @override
  Future<void> load(String url) async {
    _states.add(const AudioPlaybackSnapshot(AudioPlaybackStatus.loading));
    await _player.setUrl(url);
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> setLoopOne() => _player.setLoopMode(LoopMode.one);

  @override
  Future<void> stopAndReset() async {
    await _player.stop();
    await _player.seek(Duration.zero);
    _states.add(const AudioPlaybackSnapshot(AudioPlaybackStatus.idle));
  }

  @override
  Future<void> dispose() async {
    await _subscription.cancel();
    await _player.dispose();
    await _states.close();
  }
}

class DisabledAudioPlaybackService implements AudioPlaybackService {
  const DisabledAudioPlaybackService();

  @override
  Stream<AudioPlaybackSnapshot> get states => const Stream.empty();

  Never _unsupported() =>
      throw StateError('Audio playback is not configured for this app.');

  @override
  Future<void> load(String url) async => _unsupported();
  @override
  Future<void> pause() async => _unsupported();
  @override
  Future<void> play() async => _unsupported();
  @override
  Future<void> setLoopOne() async => _unsupported();
  @override
  Future<void> stopAndReset() async {}
  @override
  Future<void> dispose() async {}
}

typedef AudioPlaybackFactory = AudioPlaybackService Function();
