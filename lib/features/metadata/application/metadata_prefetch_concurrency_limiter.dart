import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final metadataPrefetchConcurrencyLimiterProvider =
    Provider<MetadataPrefetchConcurrencyLimiter>((ref) {
  final limiter = MetadataPrefetchConcurrencyLimiter();
  ref.onDispose(limiter.dispose);
  return limiter;
});

/// Shares concurrency and burst budgets across Hero, rating, and metadata
/// prefetches. The first group is allowed through immediately; remaining work
/// is released in small background batches so it cannot monopolize a weak TV.
class MetadataPrefetchConcurrencyLimiter {
  MetadataPrefetchConcurrencyLimiter({
    Duration backgroundBatchDelay = const Duration(
      milliseconds: kMetadataPrefetchBatchDelayMsDefault,
    ),
    this.idleResetDelay = const Duration(seconds: 3),
  }) : _backgroundBatchDelay = backgroundBatchDelay;

  Duration _backgroundBatchDelay;
  final Duration idleResetDelay;
  final Queue<void Function()> _pending = Queue<void Function()>();
  final Queue<void Function()> _maintenancePending = Queue<void Function()>();
  int _activeCount = 0;
  int _maxConcurrency = kMetadataPrefetchMaxConcurrencyDefault;
  int _initialBatchSize = kMetadataPrefetchInitialBatchSizeDefault;
  int _remainingStartsInBatch = kMetadataPrefetchInitialBatchSizeDefault;
  bool _activityStarted = false;
  Timer? _backgroundBatchTimer;
  Timer? _idleResetTimer;
  Timer? _foregroundQuietTimer;
  int _foregroundHoldCount = 0;

  int get activeCount => _activeCount;
  int get pendingCount => _pending.length + _maintenancePending.length;
  bool get isBackgroundBatchDelayed => _backgroundBatchTimer != null;
  bool get isPausedForForeground =>
      _foregroundHoldCount > 0 || _foregroundQuietTimer != null;

  /// Stops new background prefetch work while an interactive foreground task
  /// is running. Already-started work is allowed to finish so callers do not
  /// lose results or leave provider futures unresolved.
  MetadataPrefetchForegroundLease beginForegroundWork({
    required String reason,
    Duration resumeDelay = const Duration(
      milliseconds: kMetadataPrefetchForegroundResumeDelayMsDefault,
    ),
  }) {
    final wasPaused = isPausedForForeground;
    _foregroundQuietTimer?.cancel();
    _foregroundQuietTimer = null;
    _foregroundHoldCount += 1;
    if (!wasPaused) {
      _logForegroundPause(reason);
    }
    return MetadataPrefetchForegroundLease._(
      resumeDelay,
      (resumeDelay) => _endForegroundWork(
        reason: reason,
        resumeDelay: resumeDelay,
      ),
    );
  }

  /// Extends the foreground quiet window for scrolling, focus navigation, and
  /// page transitions without requiring a long-lived task lease.
  void deferForForegroundInteraction({
    required String reason,
    Duration resumeDelay = const Duration(
      milliseconds: kMetadataPrefetchForegroundResumeDelayMsDefault,
    ),
  }) {
    final wasPaused = isPausedForForeground;
    _scheduleForegroundResume(resumeDelay);
    if (!wasPaused) {
      _logForegroundPause(reason);
    }
  }

  Future<T> run<T>({
    required int maxConcurrency,
    int initialBatchSize = kMetadataPrefetchInitialBatchSizeDefault,
    Duration? backgroundBatchDelay,
    required Future<T> Function() task,
  }) {
    updateLimits(
      maxConcurrency: maxConcurrency,
      initialBatchSize: initialBatchSize,
      backgroundBatchDelay: backgroundBatchDelay,
    );
    _idleResetTimer?.cancel();
    _idleResetTimer = null;
    if (!_activityStarted) {
      _activityStarted = true;
      _remainingStartsInBatch = _initialBatchSize;
      appLogTrace(
        'metadata.prefetch-scheduler',
        'Initial metadata prefetch batch started',
        fields: <String, Object?>{
          'initialBatchSize': _initialBatchSize,
          'maxConcurrency': _maxConcurrency,
        },
      );
    }
    final completer = Completer<T>();
    _pending.add(() {
      _activeCount += 1;
      Future<T>.sync(task)
          .then(
        completer.complete,
        onError: completer.completeError,
      )
          .whenComplete(() {
        _activeCount -= 1;
        _drain();
      });
    });
    _drain();
    return completer.future;
  }

  /// Runs an explicitly requested index/refresh operation within the same
  /// global concurrency budget. Maintenance work bypasses interaction quiet
  /// delays so a page waiting for its own refresh cannot deadlock.
  Future<T> runMaintenance<T>({
    required int maxConcurrency,
    required Future<T> Function() task,
  }) {
    updateMaxConcurrency(maxConcurrency);
    final completer = Completer<T>();
    _maintenancePending.add(() {
      _activeCount += 1;
      Future<T>.sync(task)
          .then(
        completer.complete,
        onError: completer.completeError,
      )
          .whenComplete(() {
        _activeCount -= 1;
        _drain();
      });
    });
    _drain();
    return completer.future;
  }

  void updateMaxConcurrency(int maxConcurrency) {
    _maxConcurrency = clampMetadataPrefetchMaxConcurrency(maxConcurrency);
    _drain();
  }

  void updateLimits({
    required int maxConcurrency,
    required int initialBatchSize,
    Duration? backgroundBatchDelay,
  }) {
    _maxConcurrency = clampMetadataPrefetchMaxConcurrency(maxConcurrency);
    final normalizedBatchSize =
        clampMetadataPrefetchInitialBatchSize(initialBatchSize);
    if (_initialBatchSize != normalizedBatchSize) {
      _initialBatchSize = normalizedBatchSize;
      if (!_activityStarted) {
        _remainingStartsInBatch = normalizedBatchSize;
      }
    }
    if (backgroundBatchDelay != null) {
      _backgroundBatchDelay = backgroundBatchDelay.isNegative
          ? Duration.zero
          : backgroundBatchDelay;
    }
    _drain();
  }

  void dispose() {
    _backgroundBatchTimer?.cancel();
    _backgroundBatchTimer = null;
    _idleResetTimer?.cancel();
    _idleResetTimer = null;
    _foregroundQuietTimer?.cancel();
    _foregroundQuietTimer = null;
  }

  void _drain() {
    while (_activeCount < _maxConcurrency && _maintenancePending.isNotEmpty) {
      _maintenancePending.removeFirst()();
    }
    if (isPausedForForeground || _backgroundBatchTimer != null) {
      return;
    }
    while (_activeCount < _maxConcurrency &&
        _pending.isNotEmpty &&
        _remainingStartsInBatch > 0) {
      _remainingStartsInBatch -= 1;
      _pending.removeFirst()();
    }
    if (_pending.isNotEmpty && _remainingStartsInBatch == 0) {
      _scheduleBackgroundBatch();
      return;
    }
    if (_pending.isEmpty &&
        _maintenancePending.isEmpty &&
        _activeCount == 0 &&
        _activityStarted) {
      _scheduleIdleReset();
    }
  }

  void _endForegroundWork({
    required String reason,
    required Duration resumeDelay,
  }) {
    if (_foregroundHoldCount == 0) {
      return;
    }
    _foregroundHoldCount -= 1;
    if (_foregroundHoldCount > 0) {
      return;
    }
    _scheduleForegroundResume(resumeDelay, reason: reason);
  }

  void _scheduleForegroundResume(
    Duration resumeDelay, {
    String reason = 'foreground-interaction',
  }) {
    _foregroundQuietTimer?.cancel();
    _foregroundQuietTimer = null;
    if (resumeDelay <= Duration.zero) {
      if (_foregroundHoldCount == 0) {
        _logForegroundResume(reason);
        _drain();
      }
      return;
    }
    _foregroundQuietTimer = Timer(resumeDelay, () {
      _foregroundQuietTimer = null;
      if (_foregroundHoldCount > 0) {
        return;
      }
      _logForegroundResume(reason);
      _drain();
    });
  }

  void _logForegroundPause(String reason) {
    appLogTrace(
      'metadata.prefetch-scheduler',
      'Metadata prefetch paused for foreground work',
      fields: <String, Object?>{
        'reason': reason,
        'activeCount': _activeCount,
        'pendingCount': _pending.length,
      },
    );
  }

  void _logForegroundResume(String reason) {
    appLogTrace(
      'metadata.prefetch-scheduler',
      'Metadata prefetch resumed after foreground quiet period',
      fields: <String, Object?>{
        'reason': reason,
        'activeCount': _activeCount,
        'pendingCount': _pending.length,
      },
    );
  }

  void _scheduleBackgroundBatch() {
    if (_backgroundBatchTimer != null) {
      return;
    }
    final nextBatchSize = (_maxConcurrency * 2).clamp(2, 4);
    appLogTrace(
      'metadata.prefetch-scheduler',
      'Metadata prefetch continuation delayed',
      fields: <String, Object?>{
        'delayMs': _backgroundBatchDelay.inMilliseconds,
        'nextBatchSize': nextBatchSize,
        'pendingCount': _pending.length,
      },
    );
    _backgroundBatchTimer = Timer(_backgroundBatchDelay, () {
      _backgroundBatchTimer = null;
      _remainingStartsInBatch = nextBatchSize;
      _drain();
    });
  }

  void _scheduleIdleReset() {
    if (_idleResetTimer != null) {
      return;
    }
    _idleResetTimer = Timer(idleResetDelay, () {
      _idleResetTimer = null;
      if (_pending.isNotEmpty ||
          _maintenancePending.isNotEmpty ||
          _activeCount != 0) {
        return;
      }
      _activityStarted = false;
      _remainingStartsInBatch = _initialBatchSize;
      appLogTrace(
        'metadata.prefetch-scheduler',
        'Metadata prefetch scheduler became idle',
        fields: <String, Object?>{
          'nextInitialBatchSize': _initialBatchSize,
        },
      );
    });
  }
}

class MetadataPrefetchForegroundLease {
  MetadataPrefetchForegroundLease._(
    this._defaultResumeDelay,
    this._releaseCallback,
  );

  final Duration _defaultResumeDelay;
  final void Function(Duration resumeDelay) _releaseCallback;
  bool _released = false;

  void release({Duration? resumeDelay}) {
    if (_released) {
      return;
    }
    _released = true;
    _releaseCallback(resumeDelay ?? _defaultResumeDelay);
  }
}
