import 'package:starflow/core/platform/playback_system_session.dart';

typedef PlaybackSessionProgress = ({
  Duration position,
  Duration duration,
  bool playing,
  bool buffering,
  double speed,
  bool hasEpisodeQueue,
  bool hasPrevious,
  bool hasNext,
});

/// Serializes the platform bridge and invalidates queued work on detach.
/// Metadata stays lazy so suppressed position ticks allocate no artwork lists.
class PlaybackPlatformSessionOwner {
  PlaybackPlatformSessionOwner({
    required this.supported,
    required Future<void> Function(PlaybackRemoteCommandListener) attach,
    required Future<void> Function() detach,
    required Future<void> Function(bool) setActive,
    required Future<void> Function(PlaybackSystemSessionState) update,
    DateTime Function()? clock,
  })  : _attach = attach,
        _detach = detach,
        _setActive = setActive,
        _update = update,
        _clock = clock ?? DateTime.now;

  final bool supported;
  final Future<void> Function(PlaybackRemoteCommandListener) _attach;
  final Future<void> Function() _detach;
  final Future<void> Function(bool) _setActive;
  final Future<void> Function(PlaybackSystemSessionState) _update;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _bound = false;
  PlaybackSessionProgress? _lastProgress;
  DateTime? _lastPublishedAt;

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((_) {});
    return next;
  }

  Future<void> bind(PlaybackRemoteCommandListener listener) {
    if (!supported) return Future<void>.value();
    final generation = _generation;
    return _enqueue(() async {
      if (generation != _generation || _bound) return;
      await _attach((command) async {
        if (generation == _generation && _bound) await listener(command);
      });
      if (generation == _generation) _bound = true;
    });
  }

  Future<void> deactivate() {
    if (!supported) return Future<void>.value();
    final generation = _generation;
    return _enqueue(() async {
      if (generation == _generation) await _setActive(false);
    });
  }

  Future<void> publish({
    required PlaybackSessionProgress progress,
    required bool isForeground,
    required bool force,
    required PlaybackSystemSessionState Function() buildState,
  }) {
    if (!supported) return Future<void>.value();
    final last = _lastProgress;
    final now = _clock();
    if (!shouldPublishPlaybackSystemSessionUpdate(
      force: force,
      isForeground: isForeground,
      positionChanged:
          (progress.position - (last?.position ?? Duration.zero)).inSeconds !=
              0,
      hasNonPositionChange:
          progress.duration != (last?.duration ?? Duration.zero) ||
              progress.playing != (last?.playing ?? false) ||
              progress.buffering != (last?.buffering ?? false) ||
              progress.speed != (last?.speed ?? 1.0) ||
              progress.hasEpisodeQueue != (last?.hasEpisodeQueue ?? false) ||
              progress.hasPrevious != (last?.hasPrevious ?? false) ||
              progress.hasNext != (last?.hasNext ?? false),
      lastPublishedAt: _lastPublishedAt,
      now: now,
    )) {
      return Future<void>.value();
    }
    final state = buildState();
    _lastProgress = progress;
    _lastPublishedAt = now;
    final generation = _generation;
    return _enqueue(() async {
      if (generation != _generation) return;
      await _setActive(true);
      if (generation != _generation) return;
      await _update(state);
    });
  }

  Future<void> detach() {
    _generation++;
    _bound = false;
    _lastProgress = null;
    _lastPublishedAt = null;
    if (!supported) return Future<void>.value();
    return _enqueue(() async {
      try {
        await _setActive(false);
      } finally {
        await _detach();
      }
    });
  }
}
