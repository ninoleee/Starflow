import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/metadata/application/metadata_prefetch_concurrency_limiter.dart';

void main() {
  test('metadata prefetch limiter shares one maximum across queued tasks',
      () async {
    final limiter = MetadataPrefetchConcurrencyLimiter();
    final gates = List<Completer<void>>.generate(
      5,
      (_) => Completer<void>(),
    );
    var started = 0;
    var active = 0;
    var peakActive = 0;

    final tasks = List<Future<void>>.generate(5, (index) {
      return limiter.run<void>(
        maxConcurrency: 2,
        task: () async {
          started += 1;
          active += 1;
          if (active > peakActive) {
            peakActive = active;
          }
          await gates[index].future;
          active -= 1;
        },
      );
    });

    await Future<void>.delayed(Duration.zero);
    expect(started, 2);
    expect(limiter.activeCount, 2);
    expect(limiter.pendingCount, 3);

    gates[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, 3);
    expect(peakActive, 2);

    for (final gate in gates) {
      if (!gate.isCompleted) {
        gate.complete();
      }
      await Future<void>.delayed(Duration.zero);
    }
    await Future.wait(tasks);

    expect(peakActive, 2);
    expect(limiter.activeCount, 0);
    expect(limiter.pendingCount, 0);
  });

  test('lowering the maximum stops new tasks until active work drains',
      () async {
    final limiter = MetadataPrefetchConcurrencyLimiter();
    final gates = List<Completer<void>>.generate(
      4,
      (_) => Completer<void>(),
    );
    var started = 0;

    final tasks = <Future<void>>[
      for (var index = 0; index < 3; index += 1)
        limiter.run<void>(
          maxConcurrency: 3,
          task: () async {
            started += 1;
            await gates[index].future;
          },
        ),
    ];
    tasks.add(
      limiter.run<void>(
        maxConcurrency: 1,
        task: () async {
          started += 1;
          await gates[3].future;
        },
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(started, 3);

    gates[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, 3);
    gates[1].complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, 3);
    gates[2].complete();
    await Future<void>.delayed(Duration.zero);
    expect(started, 4);

    gates[3].complete();
    await Future.wait(tasks);
    expect(limiter.activeCount, 0);
  });

  test('releases work after the initial group in delayed background batches',
      () async {
    final limiter = MetadataPrefetchConcurrencyLimiter(
      backgroundBatchDelay: const Duration(milliseconds: 40),
      idleResetDelay: const Duration(seconds: 1),
    );
    addTearDown(limiter.dispose);
    var started = 0;

    final tasks = List<Future<void>>.generate(8, (_) {
      return limiter.run<void>(
        maxConcurrency: 2,
        initialBatchSize: 6,
        task: () async {
          started += 1;
        },
      );
    });

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(started, 6);
    expect(limiter.isBackgroundBatchDelayed, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 55));
    await Future.wait(tasks);
    expect(started, 8);
    expect(limiter.activeCount, 0);
    expect(limiter.pendingCount, 0);
  });

  test('restores the full initial group after a continuous idle period',
      () async {
    final limiter = MetadataPrefetchConcurrencyLimiter(
      backgroundBatchDelay: const Duration(milliseconds: 40),
      idleResetDelay: const Duration(milliseconds: 20),
    );
    addTearDown(limiter.dispose);
    var started = 0;

    await Future.wait(
      List<Future<void>>.generate(
        6,
        (_) => limiter.run<void>(
          maxConcurrency: 2,
          initialBatchSize: 6,
          task: () async {
            started += 1;
          },
        ),
      ),
    );
    expect(started, 6);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    await limiter.run<void>(
      maxConcurrency: 2,
      initialBatchSize: 6,
      task: () async {
        started += 1;
      },
    );
    expect(started, 7);
    expect(limiter.isBackgroundBatchDelayed, isFalse);
  });

  test('foreground lease keeps queued work paused until the quiet period',
      () async {
    final limiter = MetadataPrefetchConcurrencyLimiter();
    addTearDown(limiter.dispose);
    final lease = limiter.beginForegroundWork(reason: 'detail.startup');
    var started = false;

    final task = limiter.run<void>(
      maxConcurrency: 1,
      task: () async {
        started = true;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(started, isFalse);
    expect(limiter.pendingCount, 1);
    expect(limiter.isPausedForForeground, isTrue);

    lease.release(resumeDelay: const Duration(milliseconds: 25));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(started, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 25));
    await task;
    expect(started, isTrue);
    expect(limiter.isPausedForForeground, isFalse);
  });

  test('foreground interaction extends the quiet period without losing work',
      () async {
    final limiter = MetadataPrefetchConcurrencyLimiter();
    addTearDown(limiter.dispose);
    var started = false;

    limiter.deferForForegroundInteraction(
      reason: 'library.scroll',
      resumeDelay: const Duration(milliseconds: 30),
    );
    final task = limiter.run<void>(
      maxConcurrency: 1,
      task: () async {
        started = true;
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    limiter.deferForForegroundInteraction(
      reason: 'library.scroll',
      resumeDelay: const Duration(milliseconds: 30),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(started, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await task;
    expect(started, isTrue);
  });

  test('requested maintenance bypasses quiet delay but shares the same slot',
      () async {
    final limiter = MetadataPrefetchConcurrencyLimiter();
    addTearDown(limiter.dispose);
    final lease = limiter.beginForegroundWork(reason: 'library.loading');
    var prefetchStarted = false;
    var maintenanceStarted = false;

    final prefetch = limiter.run<void>(
      maxConcurrency: 1,
      task: () async {
        prefetchStarted = true;
      },
    );
    final maintenance = limiter.runMaintenance<void>(
      maxConcurrency: 1,
      task: () async {
        maintenanceStarted = true;
      },
    );
    await maintenance;

    expect(maintenanceStarted, isTrue);
    expect(prefetchStarted, isFalse);
    lease.release(resumeDelay: Duration.zero);
    await prefetch;
    expect(prefetchStarted, isTrue);
  });
}
