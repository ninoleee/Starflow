import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_auto_skip_policy.dart';
import 'package:starflow/features/playback/application/playback_intro_start_guard.dart';

void main() {
  const intro = PlaybackStartPosition(
    position: Duration(seconds: 90),
    introPosition: Duration(seconds: 90),
  );
  late PlaybackIntroStartGuard guard;
  late List<String> calls;
  late List<Object> failures;
  late bool current;
  late bool shouldResume;
  Completer<void>? seekCompletion;

  PlaybackIntroStartGuard create([PlaybackStartPosition start = intro]) =>
      PlaybackIntroStartGuard(
        start: start,
        seekToStart: () async {
          calls.add('seek-zero');
          await seekCompletion?.future;
        },
        resume: () async => calls.add('play'),
        shouldResume: () => shouldResume,
        isCurrent: () => current,
        onFailure: (error, _) => failures.add(error),
      );

  setUp(() {
    calls = [];
    failures = [];
    current = true;
    shouldResume = false;
    seekCompletion = null;
    guard = create();
  });

  tearDown(() => guard.dispose());

  test('unknown duration defers validation without blocking readiness',
      () async {
    guard.observeDuration(Duration.zero);
    guard.observeDuration(const Duration(seconds: -1));
    await guard.settle();
    expect(guard.effectiveStart, same(intro));
    expect(guard.isCorrecting, isFalse);
    expect(guard.readinessRevision, 0);
    expect(calls, isEmpty);
  });

  test('valid intro is unchanged but later shorter duration is checked',
      () async {
    guard.observeDuration(const Duration(minutes: 5));
    expect(guard.effectiveStart, same(intro));
    guard.observeDuration(const Duration(seconds: 60));
    await guard.settle();
    expect(guard.effectiveStart.position, Duration.zero);
    expect(calls, ['seek-zero']);
  });

  for (final seconds in [60, 90]) {
    test('intro at or beyond $seconds seconds is rejected before seek ends',
        () async {
      seekCompletion = Completer<void>();
      guard.observeDuration(Duration(seconds: seconds));
      expect(guard.effectiveStart.position, Duration.zero);
      expect(guard.effectiveStart.isIntroSkip, isFalse);
      expect(guard.effectiveStart.isResume, isFalse);
      expect(guard.isCorrecting, isTrue);
      expect(guard.readinessRevision, 1);
      seekCompletion!.complete();
      await guard.settle();
      expect(guard.isCorrecting, isFalse);
      expect(guard.readinessRevision, 2);
      expect(calls, ['seek-zero']);
    });
  }

  test('duplicate durations and later growth cannot restore rejected intro',
      () async {
    seekCompletion = Completer<void>();
    guard.observeDuration(const Duration(seconds: 60));
    guard.observeDuration(const Duration(seconds: 60));
    seekCompletion!.complete();
    await guard.settle();
    guard.observeDuration(const Duration(minutes: 10));
    expect(guard.effectiveStart.position, Duration.zero);
    expect(calls, ['seek-zero']);
  });

  test('resume and explicit restart are not intro skips', () async {
    for (final start in [
      const PlaybackStartPosition(
        position: Duration(minutes: 5),
        isResume: true,
      ),
      const PlaybackStartPosition(position: Duration.zero),
    ]) {
      final other = create(start);
      other.observeDuration(const Duration(seconds: 30));
      await other.settle();
      expect(other.effectiveStart, same(start));
      expect(calls, isEmpty);
      other.dispose();
    }
  });

  test('completed or already-playing playback resumes after seek', () async {
    shouldResume = true;
    seekCompletion = Completer<void>();
    guard.observeDuration(const Duration(seconds: 60));
    shouldResume = false;
    seekCompletion!.complete();
    await guard.settle();
    expect(calls, ['seek-zero', 'play']);
  });

  test('play requested during correction resumes after seek', () async {
    seekCompletion = Completer<void>();
    guard.observeDuration(const Duration(seconds: 60));
    shouldResume = true;
    seekCompletion!.complete();
    await guard.settle();
    expect(calls, ['seek-zero', 'play']);
  });

  test('disposed listener cannot start a correction', () async {
    guard.dispose();
    guard.observeDuration(const Duration(seconds: 60));
    await guard.settle();
    expect(calls, isEmpty);
  });

  for (final dispose in [false, true]) {
    test('cancel or dispose while seeking prevents a late resume ($dispose)',
        () async {
      shouldResume = true;
      seekCompletion = Completer<void>();
      guard.observeDuration(const Duration(seconds: 60));
      if (dispose) {
        guard.dispose();
      } else {
        current = false;
      }
      seekCompletion!.complete();
      await guard.settle();
      expect(calls, ['seek-zero']);
    });
  }

  test('listener correction failure is captured until explicitly awaited',
      () async {
    seekCompletion = Completer<void>();
    guard.observeDuration(const Duration(seconds: 60));
    final error = StateError('seek failed');
    seekCompletion!.completeError(error);
    // Let the listener-triggered operation fail without an awaiting caller.
    await Future<void>.delayed(Duration.zero);
    expect(failures, [error]);
    expect(guard.isCorrecting, isFalse);
    expect(guard.effectiveStart.position, Duration.zero);
    await expectLater(guard.settle(), throwsA(same(error)));
  });

  test('late failure after dispose does not report into another startup',
      () async {
    seekCompletion = Completer<void>();
    guard.observeDuration(const Duration(seconds: 60));
    guard.dispose();
    final error = StateError('player disposed');
    seekCompletion!.completeError(error);
    await Future<void>.delayed(Duration.zero);
    expect(failures, isEmpty);
    await expectLater(guard.settle(), throwsA(same(error)));
  });

  test('resume failure is captured by the same startup failure path', () async {
    final error = StateError('resume failed');
    final other = PlaybackIntroStartGuard(
      start: intro,
      seekToStart: () async => calls.add('seek-zero'),
      resume: () => Future<void>.error(error),
      shouldResume: () => true,
      isCurrent: () => true,
      onFailure: (error, _) => failures.add(error),
    );
    other.observeDuration(const Duration(seconds: 60));
    await Future<void>.delayed(Duration.zero);
    expect(failures, [error]);
    expect(other.isCorrecting, isFalse);
    await expectLater(other.settle(), throwsA(same(error)));
    other.dispose();
  });
}
