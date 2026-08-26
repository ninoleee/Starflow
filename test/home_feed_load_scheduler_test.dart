import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/home/application/home_feed_load_scheduler.dart';

void main() {
  test('home scheduler delays work after the configured first batch', () async {
    final scheduler = HomeFeedLoadScheduler(
      backgroundBatchDelay: const Duration(milliseconds: 40),
      resultApplySpacing: Duration.zero,
      idleResetDelay: const Duration(milliseconds: 20),
    );
    addTearDown(scheduler.dispose);
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    final starts = <String>[];

    final first = scheduler.runLoad<void>(
      moduleId: 'first',
      maxConcurrency: 2,
      initialBatchSize: 1,
      task: () async {
        starts.add('first');
        await firstGate.future;
      },
    );
    final second = scheduler.runLoad<void>(
      moduleId: 'second',
      maxConcurrency: 2,
      initialBatchSize: 1,
      task: () async {
        starts.add('second');
        await secondGate.future;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(starts, <String>['first']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(starts, <String>['first', 'second']);

    firstGate.complete();
    secondGate.complete();
    await Future.wait(<Future<void>>[first, second]);
  });

  test('home scheduler serializes result application', () async {
    final scheduler = HomeFeedLoadScheduler(
      backgroundBatchDelay: Duration.zero,
      resultApplySpacing: const Duration(milliseconds: 5),
    );
    addTearDown(scheduler.dispose);
    var active = 0;
    var maxActive = 0;
    final order = <String>[];

    Future<String> apply(String id) {
      return scheduler.runSerializedApply<String>(
        moduleId: id,
        task: () async {
          active += 1;
          if (active > maxActive) {
            maxActive = active;
          }
          order.add(id);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active -= 1;
          return id;
        },
      );
    }

    final results = await Future.wait(<Future<String>>[
      apply('one'),
      apply('two'),
      apply('three'),
    ]);

    expect(results, <String>['one', 'two', 'three']);
    expect(order, <String>['one', 'two', 'three']);
    expect(maxActive, 1);
  });

  test('per-load continuation delay updates the active scheduler policy',
      () async {
    final scheduler = HomeFeedLoadScheduler(
      backgroundBatchDelay: const Duration(seconds: 1),
    );
    addTearDown(scheduler.dispose);
    final starts = <String>[];

    final tasks = List<Future<void>>.generate(3, (index) {
      return scheduler.runLoad<void>(
        moduleId: 'module-$index',
        maxConcurrency: 2,
        initialBatchSize: 1,
        backgroundBatchDelay: Duration.zero,
        task: () async {
          starts.add('module-$index');
        },
      );
    });

    await Future.wait(tasks);
    expect(starts, hasLength(3));
  });

  test('navigation recovery releases batch delay without resetting active work',
      () async {
    final scheduler = HomeFeedLoadScheduler(
      backgroundBatchDelay: const Duration(seconds: 1),
    );
    addTearDown(scheduler.dispose);
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    final starts = <String>[];

    final first = scheduler.runLoad<void>(
      moduleId: 'first',
      maxConcurrency: 2,
      initialBatchSize: 1,
      task: () async {
        starts.add('first');
        await firstGate.future;
      },
    );
    final second = scheduler.runLoad<void>(
      moduleId: 'second',
      maxConcurrency: 2,
      initialBatchSize: 1,
      task: () async {
        starts.add('second');
        await secondGate.future;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(starts, <String>['first']);
    expect(scheduler.activeLoadCount, 1);

    scheduler.recoverAfterUserNavigation();
    await Future<void>.delayed(Duration.zero);
    expect(starts, <String>['first', 'second']);
    expect(scheduler.activeLoadCount, 2);

    firstGate.complete();
    secondGate.complete();
    await Future.wait(<Future<void>>[first, second]);
  });

  test('pause lease holds new loads until every pause is released', () async {
    final scheduler =
        HomeFeedLoadScheduler(backgroundBatchDelay: Duration.zero);
    addTearDown(scheduler.dispose);
    final lifecycleLease = scheduler.beginPause(reason: 'app-paused');
    final memoryLease = scheduler.beginPause(reason: 'memory-pressure');
    var started = false;

    final task = scheduler.runLoad<void>(
      moduleId: 'paused-module',
      maxConcurrency: 1,
      initialBatchSize: 1,
      task: () async {
        started = true;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(started, isFalse);

    lifecycleLease.release();
    await Future<void>.delayed(Duration.zero);
    expect(started, isFalse);

    memoryLease.release();
    await task;
    expect(started, isTrue);
  });
}
