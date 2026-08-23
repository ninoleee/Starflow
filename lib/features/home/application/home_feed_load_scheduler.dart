import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
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
    this.backgroundBatchDelay = const Duration(milliseconds: 350),
    this.resultApplySpacing = const Duration(milliseconds: 20),
    this.idleResetDelay = const Duration(seconds: 3),
  });

  final Duration backgroundBatchDelay;
  final Duration resultApplySpacing;
  final Duration idleResetDelay;
  final Queue<void Function()> _pendingLoads = Queue<void Function()>();
  final Queue<void Function()> _pendingApplies = Queue<void Function()>();

  int _activeLoads = 0;
  int _maxConcurrency = kHomeFeedMaxConcurrencyDefault;
  int _initialBatchSize = kHomeFeedInitialBatchSizeDefault;
  int _remainingStartsInBatch = kHomeFeedInitialBatchSizeDefault;
  bool _cycleStarted = false;
  bool _applyActive = false;
  Timer? _batchTimer;
  Timer? _idleResetTimer;

  int get activeLoadCount => _activeLoads;
  int get pendingLoadCount => _pendingLoads.length;
  int get pendingApplyCount => _pendingApplies.length;

  Future<T> runLoad<T>({
    required String moduleId,
    required int maxConcurrency,
    required int initialBatchSize,
    required Future<T> Function() task,
  }) {
    _updateLimits(
      maxConcurrency: maxConcurrency,
      initialBatchSize: initialBatchSize,
    );
    _idleResetTimer?.cancel();
    _idleResetTimer = null;
    if (!_cycleStarted) {
      _cycleStarted = true;
      _remainingStartsInBatch = _initialBatchSize;
      appLogInfo(
        'home.scheduler',
        'Home module load cycle started',
        fields: <String, Object?>{
          'maxConcurrency': _maxConcurrency,
          'initialBatchSize': _initialBatchSize,
          'backgroundBatchDelayMs': backgroundBatchDelay.inMilliseconds,
        },
      );
    }

    final completer = Completer<T>();
    _pendingLoads.add(() {
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
    });
    _drainLoads();
    return completer.future;
  }

  Future<T> runSerializedApply<T>({
    required String moduleId,
    required Future<T> Function() task,
  }) {
    final completer = Completer<T>();
    _pendingApplies.add(() async {
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
    });
    _drainApplies();
    return completer.future;
  }

  void updateLimits({
    required int maxConcurrency,
    required int initialBatchSize,
  }) {
    _updateLimits(
      maxConcurrency: maxConcurrency,
      initialBatchSize: initialBatchSize,
    );
    _drainLoads();
  }

  void dispose() {
    _batchTimer?.cancel();
    _idleResetTimer?.cancel();
  }

  void _updateLimits({
    required int maxConcurrency,
    required int initialBatchSize,
  }) {
    _maxConcurrency = clampHomeFeedMaxConcurrency(maxConcurrency);
    final normalizedBatchSize = clampHomeFeedInitialBatchSize(initialBatchSize);
    if (_initialBatchSize != normalizedBatchSize) {
      _initialBatchSize = normalizedBatchSize;
      if (!_cycleStarted) {
        _remainingStartsInBatch = normalizedBatchSize;
      }
    }
  }

  void _drainLoads() {
    if (_batchTimer != null) {
      return;
    }
    while (_activeLoads < _maxConcurrency &&
        _pendingLoads.isNotEmpty &&
        _remainingStartsInBatch > 0) {
      _remainingStartsInBatch -= 1;
      _pendingLoads.removeFirst()();
    }
    if (_pendingLoads.isNotEmpty && _remainingStartsInBatch == 0) {
      _batchTimer = Timer(backgroundBatchDelay, () {
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
  }

  void _drainApplies() {
    if (_applyActive || _pendingApplies.isEmpty) {
      return;
    }
    _applyActive = true;
    _pendingApplies.removeFirst()();
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
