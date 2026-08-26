import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/lifecycle/app_runtime_recovery_boundary.dart';
import 'package:starflow/features/home/application/home_feed_load_scheduler.dart';
import 'package:starflow/features/metadata/application/metadata_prefetch_concurrency_limiter.dart';

void main() {
  testWidgets(
    'runtime boundary pauses lifecycle work and softens memory pressure',
    (tester) async {
      var memoryCleanupCount = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appMemoryPressureCleanupProvider.overrideWithValue(() async {
              memoryCleanupCount += 1;
            }),
          ],
          child: const AppRuntimeRecoveryBoundary(
            child: MaterialApp(home: SizedBox()),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppRuntimeRecoveryBoundary)),
      );
      final homeScheduler = container.read(homeFeedLoadSchedulerProvider);
      final metadataLimiter =
          container.read(metadataPrefetchConcurrencyLimiterProvider);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(homeScheduler.isPaused, isTrue);
      expect(metadataLimiter.isPausedForForeground, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(
        kAppResumeBackgroundQuietPeriod - const Duration(milliseconds: 1),
      );
      expect(homeScheduler.isPaused, isTrue);
      expect(metadataLimiter.isPausedForForeground, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(homeScheduler.isPaused, isFalse);
      expect(metadataLimiter.isPausedForForeground, isFalse);

      tester.binding.handleMemoryPressure();
      await tester.pump();
      expect(memoryCleanupCount, 1);
      expect(homeScheduler.isPaused, isTrue);
      expect(metadataLimiter.isPausedForForeground, isTrue);

      await tester.pump(kMemoryPressureBackgroundQuietPeriod);
      expect(homeScheduler.isPaused, isFalse);
      expect(metadataLimiter.isPausedForForeground, isFalse);
    },
  );
}
