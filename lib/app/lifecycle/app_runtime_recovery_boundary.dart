import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/home/application/home_feed_load_scheduler.dart';
import 'package:starflow/features/library/application/media_refresh_coordinator.dart';
import 'package:starflow/features/metadata/application/metadata_prefetch_concurrency_limiter.dart';

const Duration kAppResumeBackgroundQuietPeriod = Duration(milliseconds: 400);
const Duration kMemoryPressureBackgroundQuietPeriod = Duration(seconds: 2);

typedef AppMemoryPressureCleanup = Future<void> Function();

final appMemoryPressureCleanupProvider = Provider<AppMemoryPressureCleanup>(
  (ref) => ref.read(mediaRefreshCoordinatorProvider).cancelBackgroundTasks,
);

/// Coordinates only global background admission around lifecycle transitions.
/// Active work is never cancelled here; low-memory cleanup remains a separate
/// best-effort path for media-library background tasks.
class AppRuntimeRecoveryBoundary extends ConsumerStatefulWidget {
  const AppRuntimeRecoveryBoundary({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppRuntimeRecoveryBoundary> createState() =>
      _AppRuntimeRecoveryBoundaryState();
}

class _AppRuntimeRecoveryBoundaryState
    extends ConsumerState<AppRuntimeRecoveryBoundary>
    with WidgetsBindingObserver {
  HomeFeedSchedulerPauseLease? _lifecycleHomeLease;
  MetadataPrefetchPauseLease? _lifecycleMetadataLease;
  HomeFeedSchedulerPauseLease? _memoryHomeLease;
  MetadataPrefetchPauseLease? _memoryMetadataLease;
  Timer? _resumeTimer;
  Timer? _memoryQuietTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    _memoryQuietTimer?.cancel();
    _releaseLifecyclePauses();
    _releaseMemoryPauses();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleResume();
      return;
    }
    _pauseForLifecycle(state);
  }

  @override
  void didHaveMemoryPressure() {
    appLogWarning(
      'app.memory-pressure',
      'Runtime memory pressure received; background work was softened',
      fields: const <String, Object?>{
        'flutterImageCacheClearedByFramework': true,
        'persistentCacheCleared': false,
        'activeRequestsCancelled': false,
      },
    );
    _memoryHomeLease ??= ref
        .read(homeFeedLoadSchedulerProvider)
        .beginPause(reason: 'memory-pressure');
    _memoryMetadataLease ??= ref
        .read(metadataPrefetchConcurrencyLimiterProvider)
        .beginGlobalPause(reason: 'memory-pressure');
    _memoryQuietTimer?.cancel();
    _memoryQuietTimer = Timer(
      kMemoryPressureBackgroundQuietPeriod,
      _releaseMemoryPauses,
    );
    unawaited(
      ref.read(appMemoryPressureCleanupProvider)().catchError(
        (Object error, StackTrace stackTrace) {
          appLogWarning(
            'app.memory-pressure',
            'Memory pressure background cleanup failed',
            error: error,
            stackTrace: stackTrace,
          );
        },
      ),
    );
  }

  void _pauseForLifecycle(AppLifecycleState state) {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _lifecycleHomeLease ??= ref
        .read(homeFeedLoadSchedulerProvider)
        .beginPause(reason: 'app-${state.name}');
    _lifecycleMetadataLease ??= ref
        .read(metadataPrefetchConcurrencyLimiterProvider)
        .beginGlobalPause(reason: 'app-${state.name}');
    appLogInfo(
      'app.lifecycle',
      'Background admission paused for app lifecycle',
      fields: <String, Object?>{'state': state.name},
    );
  }

  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    if (_lifecycleHomeLease == null && _lifecycleMetadataLease == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      _resumeTimer = Timer(kAppResumeBackgroundQuietPeriod, () {
        _resumeTimer = null;
        if (!mounted ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
          return;
        }
        _releaseLifecyclePauses();
        appLogInfo(
          'app.lifecycle',
          'Background admission resumed after app lifecycle quiet period',
          fields: <String, Object?>{
            'quietPeriodMs': kAppResumeBackgroundQuietPeriod.inMilliseconds,
          },
        );
      });
    });
  }

  void _releaseLifecyclePauses() {
    _lifecycleHomeLease?.release();
    _lifecycleHomeLease = null;
    _lifecycleMetadataLease?.release();
    _lifecycleMetadataLease = null;
  }

  void _releaseMemoryPauses() {
    _memoryQuietTimer?.cancel();
    _memoryQuietTimer = null;
    _memoryHomeLease?.release();
    _memoryHomeLease = null;
    _memoryMetadataLease?.release();
    _memoryMetadataLease = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
