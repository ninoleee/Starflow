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
}
