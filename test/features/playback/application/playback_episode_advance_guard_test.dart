import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_episode_advance_guard.dart';

void main() {
  late PlaybackEpisodeAdvanceGuard guard;

  setUp(() {
    guard = PlaybackEpisodeAdvanceGuard();
  });

  PlaybackEpisodeAdvanceRequest begin(String key, {bool automatic = true}) =>
      guard.begin(key: key, automatic: automatic)!;

  test('allows only one automatic resolution even for different keys', () {
    final request = begin('1->2');
    expect(guard.isActive, isTrue);
    expect(guard.isSwitching, isFalse);
    expect(guard.begin(key: '1->2', automatic: true), isNull);
    expect(guard.begin(key: '1->3', automatic: true), isNull);
    expect(guard.isCurrent(request), isTrue);
    expect(guard.finish(request), isTrue);
    expect(guard.isActive, isFalse);
  });

  test('cancellation during await rejects late result and allows retry',
      () async {
    final resolution = Completer<String>();
    final request = begin('1->2');
    final switches = <String>[];
    final operation = () async {
      try {
        final destination = await resolution.future;
        if (!guard.commit(request)) return;
        switches.add(destination);
      } finally {
        guard.finish(request);
      }
    }();

    expect(guard.invalidateAutomaticPending(), isTrue);
    expect(guard.isCurrent(request), isFalse);
    final retry = begin('1->2');
    resolution.complete('episode 2');
    await operation;

    expect(switches, isEmpty);
    expect(guard.isCurrent(retry), isTrue);
    expect(retry.generation, greaterThan(request.generation));
  });

  test('manual request supersedes automatic await and owns its finally',
      () async {
    final resolution = Completer<void>();
    final automatic = begin('1->2');
    var obsoleteFailureAccepted = true;
    final operation = () async {
      try {
        await resolution.future;
      } catch (_) {
        obsoleteFailureAccepted = guard.finish(automatic, failed: true);
      } finally {
        expect(guard.finish(automatic), isFalse);
      }
    }();

    final manual = begin('1->3', automatic: false);
    expect(guard.commit(automatic), isFalse);
    expect(guard.commit(manual), isTrue);
    resolution.completeError(StateError('late resolution error'));
    await operation;

    expect(obsoleteFailureAccepted, isFalse);
    expect(guard.isCurrent(manual), isTrue);
    expect(guard.isSwitching, isTrue);
    expect(guard.finish(manual), isTrue);
    expect(guard.begin(key: '1->2', automatic: true), isNotNull);
  });

  test('pending manual request rejects all supersession and cancellation', () {
    final manual = begin('1->2', automatic: false);
    expect(guard.begin(key: '1->3', automatic: false), isNull);
    expect(guard.begin(key: '1->3', automatic: true), isNull);
    expect(guard.invalidateAutomaticPending(), isFalse);
    expect(guard.isCurrent(manual), isTrue);
  });

  for (final automatic in [true, false]) {
    test('committed automatic=$automatic is locked until owner finishes', () {
      final request = begin('1->2', automatic: automatic);
      expect(guard.commit(request), isTrue);
      expect(guard.commit(request), isFalse);
      expect(guard.isSwitching, isTrue);
      expect(guard.invalidateAutomaticPending(), isFalse);
      expect(guard.reset(), isFalse);
      expect(guard.begin(key: '1->3', automatic: false), isNull);
      expect(guard.begin(key: '1->3', automatic: true), isNull);
      expect(guard.isCurrent(request), isTrue);
      expect(guard.finish(request), isTrue);
      expect(guard.isSwitching, isFalse);
      expect(guard.isActive, isFalse);
      expect(guard.begin(key: '1->3', automatic: false), isNotNull);
    });
  }

  test('automatic failures dedupe each key until reset, manual bypasses', () {
    guard.finish(begin('1->2'), failed: true);
    guard.finish(begin('2->3'), failed: true);
    expect(guard.begin(key: '1->2', automatic: true), isNull);
    expect(guard.begin(key: '2->3', automatic: true), isNull);
    final manual = begin('1->2', automatic: false);
    guard.finish(manual);
    expect(guard.begin(key: '1->2', automatic: true), isNull);
    guard.finish(begin('3->4'));
    expect(guard.reset(), isTrue);
    guard.finish(begin('1->2'));
    expect(guard.begin(key: '2->3', automatic: true), isNotNull);
  });

  test('manual failure and automatic success do not poison retries', () {
    guard.finish(begin('1->2', automatic: false), failed: true);
    guard.finish(begin('1->2'));
    expect(guard.begin(key: '1->2', automatic: true), isNotNull);
  });

  test('switch failure is deduped and releases committed ownership', () {
    final request = begin('1->2');
    guard.commit(request);
    expect(guard.finish(request, failed: true), isTrue);
    expect(guard.isSwitching, isFalse);
    expect(guard.begin(key: '1->2', automatic: true), isNull);
    expect(guard.begin(key: '1->2', automatic: false), isNotNull);
  });

  test('reset invalidates pending tokens without reusing generations', () {
    final old = begin('1->2', automatic: false);
    expect(guard.reset(), isTrue);
    expect(guard.isCurrent(old), isFalse);
    final current = begin('1->2');
    expect(current.generation, greaterThan(old.generation));
    expect(guard.commit(old), isFalse);
    expect(guard.finish(old, failed: true), isFalse);
    expect(guard.isCurrent(current), isTrue);
    guard.finish(current);
    expect(guard.begin(key: '1->2', automatic: true), isNotNull);
  });

  test('reset during await rejects late result without clearing new owner',
      () async {
    final resolution = Completer<void>();
    final old = begin('1->2');
    final operation = () async {
      try {
        await resolution.future;
        expect(guard.commit(old), isFalse);
      } finally {
        expect(guard.finish(old), isFalse);
      }
    }();
    guard.reset();
    final current = begin('1->2');
    resolution.complete();
    await operation;
    expect(guard.isCurrent(current), isTrue);
  });

  test('tokens from another guard cannot commit or finish an operation', () {
    final request = begin('1->2');
    final other =
        PlaybackEpisodeAdvanceGuard().begin(key: '1->2', automatic: true)!;
    expect(other.generation, request.generation);
    expect(guard.isCurrent(other), isFalse);
    expect(guard.commit(other), isFalse);
    expect(guard.finish(other, failed: true), isFalse);
    expect(guard.isCurrent(request), isTrue);
  });

  test('duplicate finish cannot clear or mark failure on a newer operation',
      () {
    final old = begin('1->2');
    guard.finish(old);
    final current = begin('1->2');
    expect(guard.finish(old, failed: true), isFalse);
    expect(guard.isCurrent(current), isTrue);
    guard.finish(current);
    expect(guard.begin(key: '1->2', automatic: true), isNotNull);
  });

  test('natural EOF remains valid unless caller signals intentional cancel',
      () async {
    Future<bool> resolveAtEof({required bool intentionalCancel}) async {
      final resolution = Completer<void>();
      final request = begin('1->2');
      final operation = () async {
        try {
          await resolution.future;
          return guard.commit(request);
        } finally {
          guard.finish(request);
        }
      }();
      // Both EOF and pause can report playing=false. Only pause invalidates.
      if (intentionalCancel) guard.invalidateAutomaticPending();
      resolution.complete();
      return operation;
    }

    expect(await resolveAtEof(intentionalCancel: false), isTrue);
    expect(await resolveAtEof(intentionalCancel: true), isFalse);
  });

  test('rejected reset preserves failure dedupe as well as switch ownership',
      () {
    guard.finish(begin('1->2'), failed: true);
    final switching = begin('1->3');
    guard.commit(switching);
    expect(guard.reset(), isFalse);
    guard.finish(switching);
    expect(guard.begin(key: '1->2', automatic: true), isNull);
    expect(guard.reset(), isTrue);
    expect(guard.begin(key: '1->2', automatic: true), isNotNull);
  });
}
