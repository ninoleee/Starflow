import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/application/empty_library_auto_rebuild_scheduler.dart';

void main() {
  group('EmptyLibraryAutoRebuildScheduler', () {
    test('deduplicates concurrent tasks by scope key', () async {
      final scheduler = EmptyLibraryAutoRebuildScheduler();
      final firstTaskCompleter = Completer<void>();
      var runCount = 0;

      final firstScheduled = scheduler.schedule(
        scopeKey: 'nas-main::anime',
        task: () async {
          runCount += 1;
          await firstTaskCompleter.future;
        },
      );
      final secondScheduled = scheduler.schedule(
        scopeKey: 'nas-main::anime',
        task: () async {
          runCount += 1;
        },
      );

      expect(firstScheduled, isTrue);
      expect(secondScheduled, isFalse);
      expect(runCount, 0);

      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(runCount, 1);

      firstTaskCompleter.complete();
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final thirdScheduled = scheduler.schedule(
        scopeKey: 'nas-main::anime',
        task: () async {
          runCount += 1;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(thirdScheduled, isFalse);
      expect(runCount, 1);
    });

    test('swallows task errors and releases scope lock', () async {
      final scheduler = EmptyLibraryAutoRebuildScheduler();
      var runCount = 0;

      final firstScheduled = scheduler.schedule(
        scopeKey: 'nas-main::all',
        task: () async {
          runCount += 1;
          throw StateError('expected');
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final secondScheduled = scheduler.schedule(
        scopeKey: 'nas-main::all',
        task: () async {
          runCount += 1;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(firstScheduled, isTrue);
      expect(secondScheduled, isTrue);
      expect(runCount, 2);
    });

    test('allows scheduling again after scope is marked healthy', () async {
      final scheduler = EmptyLibraryAutoRebuildScheduler();
      var runCount = 0;

      final firstScheduled = scheduler.schedule(
        scopeKey: 'nas-main::all',
        task: () async {
          runCount += 1;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final secondScheduled = scheduler.schedule(
        scopeKey: 'nas-main::all',
        task: () async {
          runCount += 1;
        },
      );
      scheduler.markScopeHealthy('nas-main::all');
      final thirdScheduled = scheduler.schedule(
        scopeKey: 'nas-main::all',
        task: () async {
          runCount += 1;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(firstScheduled, isTrue);
      expect(secondScheduled, isFalse);
      expect(thirdScheduled, isTrue);
      expect(runCount, 2);
    });
  });
}
