import 'dart:async';

import 'package:starflow/core/logging/app_logger.dart';

/// Emits at most one warning for each continuous period with queued work.
class QueueWaitDiagnostics {
  QueueWaitDiagnostics({
    required this.category,
    required this.message,
    required this.warningThreshold,
    required this.pendingCount,
    required this.oldestEnqueuedAt,
    required this.snapshotFields,
  });

  final String category;
  final String message;
  final Duration warningThreshold;
  final int Function() pendingCount;
  final DateTime? Function() oldestEnqueuedAt;
  final Map<String, Object?> Function() snapshotFields;

  Timer? _timer;
  bool _reportedForCurrentQueue = false;
  bool _paused = false;
  DateTime? _windowStartedAt;

  void update() {
    if (_paused) {
      return;
    }
    final count = pendingCount();
    final oldest = oldestEnqueuedAt();
    if (count <= 0 || oldest == null) {
      _timer?.cancel();
      _timer = null;
      _reportedForCurrentQueue = false;
      _windowStartedAt = null;
      return;
    }
    if (_reportedForCurrentQueue || _timer != null) {
      return;
    }

    final effectiveOldest = _effectiveOldest(oldest);
    final elapsed = DateTime.now().difference(effectiveOldest);
    final remaining = warningThreshold - elapsed;
    _timer = Timer(remaining > Duration.zero ? remaining : Duration.zero, () {
      _timer = null;
      final currentOldest = oldestEnqueuedAt();
      final currentCount = pendingCount();
      if (currentCount <= 0 || currentOldest == null) {
        update();
        return;
      }
      final currentWait = DateTime.now().difference(currentOldest);
      final effectiveCurrentWait = DateTime.now().difference(
        _effectiveOldest(currentOldest),
      );
      if (effectiveCurrentWait < warningThreshold) {
        update();
        return;
      }
      _reportedForCurrentQueue = true;
      appLogWarning(
        category,
        message,
        fields: <String, Object?>{
          ...snapshotFields(),
          'pendingCount': currentCount,
          'oldestWaitMs': currentWait.inMilliseconds,
          'currentWaitWindowMs': effectiveCurrentWait.inMilliseconds,
          'warningThresholdMs': warningThreshold.inMilliseconds,
        },
      );
    });
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  void resume({bool resetWaitWindow = true}) {
    _paused = false;
    if (resetWaitWindow) {
      _windowStartedAt = DateTime.now();
      _reportedForCurrentQueue = false;
    }
    update();
  }

  DateTime _effectiveOldest(DateTime oldest) {
    final windowStartedAt = _windowStartedAt;
    if (windowStartedAt != null && windowStartedAt.isAfter(oldest)) {
      return windowStartedAt;
    }
    return oldest;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _paused = true;
  }
}
