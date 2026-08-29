import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/scheduling/queue_wait_diagnostics.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final homeFeedLoadSchedulerProvider = Provider<HomeFeedLoadScheduler>((ref) {
  final scheduler = HomeFeedLoadScheduler();
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

/// Limits cold-start Home fan-out separately from metadata prefetches.
///
/// The first visible modules are allowed through immediately. Remaining work
/// starts in small delayed batches, while result/cache application is always
/// serialized so several network completions cannot rebuild Home together.
class HomeFeedLoadScheduler {
  HomeFeedLoadScheduler({
    Duration backgroundBatchDelay = const Duration(
      milliseconds: kHomeFeedBatchDelayMsDefault,
    ),
    this.resultApplySpacing = const Duration(milliseconds: 20),
    this.idleResetDelay = const Duration(seconds: 3),
    this.waitWarningThreshold = const Duration(seconds: 5),
  }) : _backgroundBatchDelay = backgroundBatchDelay {
    _waitDiagnostics = QueueWaitDiagnostics(
      category: 'home.scheduler',
      message: 'Home scheduler work remained queued',
      warningThreshold: waitWarningThreshold,
      pendingCount: () => _pendingLoads.length + _pendingApplies.length,
      oldestEnqueuedAt: _oldestPendingAt,
      snapshotFields: () => <String, Object?>{
        'activeLoadCount': _activeLoads,
        'pendingLoadCount': _pendingLoads.length,
        'pendingApplyCount': _pendingApplies.length,
        'applyActive': _applyActive,
        'pauseHoldCount': _pauseHoldCount,
        'batchDelayed': _batchTimer != null,
        'maxConcurrency': _maxConcurrency,
      },
    );
  }

  Duration _backgroundBatchDelay;
  final Duration resultApplySpacing;
  final Duration idleResetDelay;
  final Duration waitWarningThreshold;
  final Queue<_QueuedHomeWork> _pendingLoads = Queue<_QueuedHomeWork>();
  final Queue<_QueuedHomeWork> _pendingApplies = Queue<_QueuedHomeWork>();
  late final QueueWaitDiagnostics _waitDiagnostics;

  int _activeLoads = 0;
  int _maxConcurrency = kTaskMaxConcurrencyDefault;
  int _initialBatchSize = kHomeFeedInitialBatchSizeDefault;
  int _remainingStartsInBatch = kHomeFeedInitialBatchSizeDefault;
  bool _cycleStarted = false;
  bool _applyActive = false;
  Timer? _batchTimer;
  Timer? _idleResetTimer;
  int _pauseHoldCount = 0;

  int get activeLoadCount => _activeLoads;
  int get pendingLoadCount => _pendingLoads.length;
  int get pendingApplyCount => _pendingApplies.length;
  bool get isPaused => _pauseHoldCount > 0;

  HomeFeedSchedulerPauseLease beginPause({required String reason}) {
    _pauseHoldCount += 1;
    if (_pauseHoldCount == 1) {
      _waitDiagnostics.pause();
      appLogTrace(
        'home.scheduler',
        'Home module scheduler paused',
        fields: <String, Object?>{
          'reason': reason,
          'activeCount': _activeLoads,
          'pendingCount': _pendingLoads.length,
        },
      );
    }
    return HomeFeedSchedulerPauseLease._(() => _endPause(reason));
  }

  Future<T> runLoad<T>({
    required String moduleId,
    required int maxConcurrency,
    required int initialBatchSize,
    Duration? backgroundBatchDelay,
    required Future<T> Function() task,
  }) {
    _updateLimits(
      maxConcurrency: maxConcurrency,
      initialBatchSize: initialBatchSize,
      backgroundBatchDelay: backgroundBatchDelay,
    );
    _idleResetTimer?.cancel();
    _idleResetTimer = null;
    if (!_cycleStarted) {
      _cycleStarted = true;
      _remainingStartsInBatch = _initialBatchSize;
      appLogTrace(
        'home.scheduler',
        'Home module load cycle started',
        fields: <String, Object?>{
          'maxConcurrency': _maxConcurrency,
          'initialBatchSize': _initialBatchSize,
          'backgroundBatchDelayMs': _backgroundBatchDelay.inMilliseconds,
        },
      );
    }

    final completer = Completer<T>();
    _pendingLoads.add(_QueuedHomeWork(() {
      _activeLoads += 1;
      appLogTrace(
        'home.scheduler',
        'Home module load admitted',
        fields: <String, Object?>{
          'moduleId': moduleId,
          'activeCount': _activeLoads,
          'pendingCount': _pendingLoads.length,
          'maxConcurrency': _maxConcurrency,
        },
      );
      Future<T>.sync(task)
          .then(completer.complete, onError: completer.completeError)
          .whenComplete(() {
        _activeLoads -= 1;
        _drainLoads();
      });
    }));
    _waitDiagnostics.update();
    _drainLoads();
    return completer.future;
  }

  Future<T> runSerializedApply<T>({
    required String moduleId,
    required Future<T> Function() task,
  }) {
    final completer = Completer<T>();
    _pendingApplies.add(_QueuedHomeWork(() async {
      final stopwatch = Stopwatch()..start();
      try {
        completer.complete(await task());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        stopwatch.stop();
        appLogTrace(
          'home.scheduler',
          'Home module result applied serially',
          fields: <String, Object?>{
            'moduleId': moduleId,
            'durationMs': stopwatch.elapsedMilliseconds,
            'pendingApplyCount': _pendingApplies.length,
          },
        );
        if (resultApplySpacing > Duration.zero) {
          await Future<void>.delayed(resultApplySpacing);
        } else {
          await Future<void>.delayed(Duration.zero);
        }
        _applyActive = false;
        _drainApplies();
      }
    }));
    _waitDiagnostics.update();
    _drainApplies();
    return completer.future;
  }

  void updateLimits({
    required int maxConcurrency,
    required int initialBatchSize,
    Duration? backgroundBatchDelay,
  }) {
    _updateLimits(
      maxConcurrency: maxConcurrency,
      initialBatchSize: initialBatchSize,
      backgroundBatchDelay: backgroundBatchDelay,
    );
    _drainLoads();
  }

  /// Releases only scheduler-owned delays after the user explicitly returns
  /// Home. Running work and its concurrency accounting stay intact.
  void recoverAfterUserNavigation() {
    _batchTimer?.cancel();
    _batchTimer = null;
    _idleResetTimer?.cancel();
    _idleResetTimer = null;

    if (_pendingLoads.isEmpty && _activeLoads == 0) {
      _cycleStarted = false;
      _remainingStartsInBatch = _initialBatchSize;
    } else {
      _cycleStarted = true;
      _remainingStartsInBatch = _maxConcurrency;
    }

    appLogTrace(
      'home.scheduler',
      'Home module scheduler soft recovery requested',
      fields: <String, Object?>{
        'activeCount': _activeLoads,
        'pendingCount': _pendingLoads.length,
        'maxConcurrency': _maxConcurrency,
      },
    );
    _drainLoads();
    _drainApplies();
  }

  void dispose() {
    _batchTimer?.cancel();
    _idleResetTimer?.cancel();
    _waitDiagnostics.dispose();
  }

  void _updateLimits({
    required int maxConcurrency,
    required int initialBatchSize,
    Duration? backgroundBatchDelay,
  }) {
    _maxConcurrency = clampTaskMaxConcurrency(maxConcurrency);
    final normalizedBatchSize = clampHomeFeedInitialBatchSize(initialBatchSize);
    if (_initialBatchSize != normalizedBatchSize) {
      _initialBatchSize = normalizedBatchSize;
      if (!_cycleStarted) {
        _remainingStartsInBatch = normalizedBatchSize;
      }
    }
    if (backgroundBatchDelay != null) {
      _backgroundBatchDelay = backgroundBatchDelay.isNegative
          ? Duration.zero
          : backgroundBatchDelay;
    }
  }

  void _drainLoads() {
    if (isPaused || _batchTimer != null) {
      _waitDiagnostics.update();
      return;
    }
    while (_activeLoads < _maxConcurrency &&
        _pendingLoads.isNotEmpty &&
        _remainingStartsInBatch > 0) {
      _remainingStartsInBatch -= 1;
      _pendingLoads.removeFirst().start();
    }
    if (_pendingLoads.isNotEmpty && _remainingStartsInBatch == 0) {
      _batchTimer = Timer(_backgroundBatchDelay, () {
        _batchTimer = null;
        _remainingStartsInBatch = _maxConcurrency;
        appLogTrace(
          'home.scheduler',
          'Home background module batch released',
          fields: <String, Object?>{
            'batchSize': _remainingStartsInBatch,
            'activeCount': _activeLoads,
            'pendingCount': _pendingLoads.length,
          },
        );
        _drainLoads();
      });
      return;
    }
    if (_pendingLoads.isEmpty && _activeLoads == 0 && _cycleStarted) {
      _scheduleIdleReset();
    }
    _waitDiagnostics.update();
  }

  void _drainApplies() {
    if (isPaused || _applyActive || _pendingApplies.isEmpty) {
      _waitDiagnostics.update();
      return;
    }
    _applyActive = true;
    _pendingApplies.removeFirst().start();
    _waitDiagnostics.update();
  }

  void _endPause(String reason) {
    if (_pauseHoldCount == 0) {
      return;
    }
    _pauseHoldCount -= 1;
    if (_pauseHoldCount > 0) {
      return;
    }
    appLogTrace(
      'home.scheduler',
      'Home module scheduler resumed',
      fields: <String, Object?>{
        'reason': reason,
        'activeCount': _activeLoads,
        'pendingCount': _pendingLoads.length,
      },
    );
    _waitDiagnostics.resume();
    _drainLoads();
    _drainApplies();
  }

  DateTime? _oldestPendingAt() {
    final loadAt =
        _pendingLoads.isEmpty ? null : _pendingLoads.first.enqueuedAt;
    final applyAt =
        _pendingApplies.isEmpty ? null : _pendingApplies.first.enqueuedAt;
    if (loadAt == null) {
      return applyAt;
    }
    if (applyAt == null) {
      return loadAt;
    }
    return loadAt.isBefore(applyAt) ? loadAt : applyAt;
  }

  void _scheduleIdleReset() {
    if (_idleResetTimer != null) {
      return;
    }
    _idleResetTimer = Timer(idleResetDelay, () {
      _idleResetTimer = null;
      if (_activeLoads != 0 || _pendingLoads.isNotEmpty) {
        return;
      }
      _cycleStarted = false;
      _remainingStartsInBatch = _initialBatchSize;
      appLogTrace(
        'home.scheduler',
        'Home module load scheduler became idle',
      );
    });
  }
}

class HomeFeedSchedulerPauseLease {
  HomeFeedSchedulerPauseLease._(this._releaseCallback);

  final void Function() _releaseCallback;
  bool _released = false;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _releaseCallback();
  }
}

class _QueuedHomeWork {
  _QueuedHomeWork(this.start) : enqueuedAt = DateTime.now();

  final void Function() start;
  final DateTime enqueuedAt;
}
