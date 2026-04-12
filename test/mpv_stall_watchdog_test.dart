import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/mpv_stall_watchdog.dart';

void main() {
  group('MpvStallWatchdog', () {
    test('triggers soft then hard recovery when buffering stalls', () {
      final watchdog = MpvStallWatchdog(
        config: const MpvStallWatchdogConfig(
          minBufferingBeforeCheck: Duration(seconds: 1),
          softRecoverAfter: Duration(seconds: 3),
          hardRecoverAfter: Duration(seconds: 6),
          progressDeltaThreshold: Duration(milliseconds: 200),
        ),
      );
      final base = DateTime(2026, 4, 12, 12, 0, 0);

      final warmup = watchdog.evaluate(
        _snapshot(),
        now: base,
      );
      expect(warmup.level, MpvStallRecoveryLevel.none);
      expect(warmup.reason, 'warmup');

      final soft = watchdog.evaluate(
        _snapshot(),
        now: base.add(const Duration(seconds: 3)),
      );
      expect(soft.level, MpvStallRecoveryLevel.soft);
      expect(soft.triggered, isTrue);
      expect(soft.reason, 'stalled-soft-threshold');

      final hard = watchdog.evaluate(
        _snapshot(),
        now: base.add(const Duration(seconds: 6)),
      );
      expect(hard.level, MpvStallRecoveryLevel.hard);
      expect(hard.triggered, isTrue);
      expect(hard.reason, 'stalled-hard-threshold');
    });

    test('does not re-trigger until progress resumes', () {
      final watchdog = MpvStallWatchdog(
        config: const MpvStallWatchdogConfig(
          minBufferingBeforeCheck: Duration(seconds: 1),
          softRecoverAfter: Duration(seconds: 2),
          hardRecoverAfter: Duration(seconds: 5),
        ),
      );
      final base = DateTime(2026, 4, 12, 12, 0, 0);

      watchdog.evaluate(_snapshot(position: const Duration(seconds: 10)),
          now: base);
      final soft = watchdog.evaluate(
        _snapshot(position: const Duration(seconds: 10)),
        now: base.add(const Duration(seconds: 2)),
      );
      expect(soft.level, MpvStallRecoveryLevel.soft);
      expect(soft.triggered, isTrue);

      final softPersistent = watchdog.evaluate(
        _snapshot(position: const Duration(seconds: 10)),
        now: base.add(const Duration(seconds: 3)),
      );
      expect(softPersistent.level, MpvStallRecoveryLevel.soft);
      expect(softPersistent.triggered, isFalse);
      expect(softPersistent.reason, 'stalled-soft-persistent');

      final resumed = watchdog.evaluate(
        _snapshot(position: const Duration(seconds: 11)),
        now: base.add(const Duration(seconds: 4)),
      );
      expect(resumed.level, MpvStallRecoveryLevel.none);
      expect(resumed.reason, 'warmup');

      final softAgain = watchdog.evaluate(
        _snapshot(position: const Duration(seconds: 11)),
        now: base.add(const Duration(seconds: 6)),
      );
      expect(softAgain.level, MpvStallRecoveryLevel.soft);
      expect(softAgain.triggered, isTrue);
    });

    test('stops detection when buffering is inactive or paused', () {
      final watchdog = MpvStallWatchdog(
        config: const MpvStallWatchdogConfig(
          minBufferingBeforeCheck: Duration(seconds: 1),
          softRecoverAfter: Duration(seconds: 2),
          hardRecoverAfter: Duration(seconds: 4),
          requirePlaying: true,
        ),
      );
      final base = DateTime(2026, 4, 12, 12, 0, 0);

      final paused = watchdog.evaluate(
        _snapshot(playing: false, buffering: true),
        now: base,
      );
      expect(paused.level, MpvStallRecoveryLevel.none);
      expect(paused.reason, 'buffering-inactive');

      final notBuffering = watchdog.evaluate(
        _snapshot(playing: true, buffering: false),
        now: base.add(const Duration(seconds: 2)),
      );
      expect(notBuffering.level, MpvStallRecoveryLevel.none);
      expect(notBuffering.reason, 'buffering-inactive');
    });

    test('evaluateAndNotify invokes soft/hard callbacks once per trigger',
        () async {
      var softCalls = 0;
      var hardCalls = 0;
      final watchdog = MpvStallWatchdog(
        config: const MpvStallWatchdogConfig(
          minBufferingBeforeCheck: Duration(seconds: 1),
          softRecoverAfter: Duration(seconds: 2),
          hardRecoverAfter: Duration(seconds: 4),
        ),
        onSoftRecover: (_) {
          softCalls += 1;
        },
        onHardRecover: (_) {
          hardCalls += 1;
        },
      );
      final base = DateTime(2026, 4, 12, 12, 0, 0);

      await watchdog.evaluateAndNotify(_snapshot(), now: base);
      await watchdog.evaluateAndNotify(
        _snapshot(),
        now: base.add(const Duration(seconds: 2)),
      );
      await watchdog.evaluateAndNotify(
        _snapshot(),
        now: base.add(const Duration(seconds: 3)),
      );
      await watchdog.evaluateAndNotify(
        _snapshot(),
        now: base.add(const Duration(seconds: 4)),
      );
      await watchdog.evaluateAndNotify(
        _snapshot(),
        now: base.add(const Duration(seconds: 5)),
      );

      expect(softCalls, 1);
      expect(hardCalls, 1);
    });
  });
}

MpvPlaybackSnapshot _snapshot({
  Duration position = const Duration(seconds: 8),
  Duration duration = const Duration(minutes: 40),
  bool playing = true,
  bool buffering = true,
  double bufferingPercentage = 56.0,
}) {
  return MpvPlaybackSnapshot(
    position: position,
    duration: duration,
    playing: playing,
    buffering: buffering,
    bufferingPercentage: bufferingPercentage,
  );
}
