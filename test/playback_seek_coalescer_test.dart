import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_seek_coalescer.dart';

void main() {
  for (final seconds in [2, 5, 10]) {
    testWidgets(
        'long press ${seconds}s accumulates targets and bounds seek count',
        (tester) async {
      final targets = <Duration>[];
      final coalescer = PlaybackSeekCoalescer(seek: (target) async {
        targets.add(target);
      });
      for (var tick = 0; tick < seconds * 20; tick++) {
        coalescer.add(const Duration(seconds: 10),
            position: Duration.zero, duration: const Duration(hours: 2));
        await tester.pump(const Duration(milliseconds: 50));
      }
      coalescer.flush();
      await tester.pump();
      expect(targets.first, const Duration(seconds: 10));
      expect(targets.last, Duration(seconds: seconds * 200));
      expect(targets.length, lessThanOrEqualTo(seconds * 4 + 2));
      coalescer.cancel();
    });
  }

  testWidgets(
      'in-flight seek keeps only latest target and flush survives completion',
      (tester) async {
    final targets = <Duration>[];
    final pending = <Completer<void>>[];
    final coalescer = PlaybackSeekCoalescer(seek: (target) {
      targets.add(target);
      final completer = Completer<void>();
      pending.add(completer);
      return completer.future;
    });
    for (var index = 0; index < 5; index++) {
      coalescer.add(const Duration(seconds: 10),
          position: Duration.zero, duration: const Duration(minutes: 2));
    }
    coalescer.flush();
    expect(targets.length, 1);
    pending.first.complete();
    await tester.pump();
    expect(targets, [const Duration(seconds: 10), const Duration(seconds: 50)]);
    coalescer.cancel();
    pending.last.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(targets.length, 2);
  });

  testWidgets(
      'cancel drops pending input and clamps the next session independently',
      (tester) async {
    final targets = <Duration>[];
    final coalescer =
        PlaybackSeekCoalescer(seek: (value) async => targets.add(value));
    coalescer.add(const Duration(seconds: 10),
        position: Duration.zero, duration: const Duration(seconds: 15));
    coalescer.add(const Duration(seconds: 10),
        position: Duration.zero, duration: const Duration(seconds: 15));
    coalescer.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(targets, [const Duration(seconds: 10)]);
    coalescer.add(const Duration(seconds: -10),
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 2));
    await tester.pump();
    expect(targets.last, Duration.zero);
    coalescer.cancel();
  });
}
