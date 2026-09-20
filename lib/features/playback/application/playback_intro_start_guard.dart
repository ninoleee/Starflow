import 'dart:async';

import 'playback_auto_skip_policy.dart';

/// Validates an open-time intro before startup readiness can be confirmed.
class PlaybackIntroStartGuard {
  PlaybackIntroStartGuard({
    required PlaybackStartPosition start,
    required this.seekToStart,
    required this.resume,
    required this.shouldResume,
    required this.isCurrent,
    required this.onFailure,
  }) : _effectiveStart = start;

  final Future<void> Function() seekToStart;
  final Future<void> Function() resume;
  final bool Function() shouldResume;
  final bool Function() isCurrent;
  final void Function(Object error, StackTrace stackTrace) onFailure;

  PlaybackStartPosition _effectiveStart;
  Future<void>? _correction;
  Object? _error;
  StackTrace? _stackTrace;
  bool _disposed = false;
  bool _isCorrecting = false;
  int _readinessRevision = 0;

  PlaybackStartPosition get effectiveStart => _effectiveStart;
  bool get isCorrecting => _isCorrecting;

  /// A readiness candidate and its progress baseline expire on either edge.
  int get readinessRevision => _readinessRevision;
  bool get _active => !_disposed && isCurrent();

  void observeDuration(Duration duration) {
    if (!_active ||
        !_effectiveStart.isIntroSkip ||
        duration <= Duration.zero ||
        _effectiveStart.position < duration) {
      return;
    }
    // Clear the intro synchronously so neither duplicate duration events nor
    // a later open/finalize fallback can restore the rejected position.
    _effectiveStart = const PlaybackStartPosition(position: Duration.zero);
    _isCorrecting = true;
    _readinessRevision++;
    _correction = _correct();
  }

  Future<void> _correct() async {
    try {
      if (!_active) return;
      final resumeAfterSeek = shouldResume();
      await seekToStart();
      if (!_active) return;
      if (resumeAfterSeek || shouldResume()) await resume();
    } catch (error, stackTrace) {
      _error = error;
      _stackTrace = stackTrace;
      if (_active) onFailure(error, stackTrace);
    } finally {
      _isCorrecting = false;
      _readinessRevision++;
    }
  }

  /// Listener-triggered correction errors are observed here, never detached.
  Future<void> settle() async {
    await _correction;
    if (_error != null) Error.throwWithStackTrace(_error!, _stackTrace!);
  }

  void dispose() {
    _disposed = true;
  }
}
