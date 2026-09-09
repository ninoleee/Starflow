import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_reliability_policy.dart';
import 'package:starflow/features/playback/application/mpv_buffer_progress.dart';

void main() {
  test('generated Dart and Kotlin policy match the single source', () async {
    final result = await Process.run('dart', [
      'tool/generate_playback_policy.dart',
      '--check',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('HTTP classification and refresh eligibility remain separate', () {
    for (final code in [408, 425, 429, 500, 503, 599]) {
      expect(classifyPlaybackHttpStatus(code),
          PlaybackFailureKind.transientNetwork);
      expect(isPlaybackAddressRefreshable(code), false);
    }
    for (final code in [401, 403, 404, 410]) {
      expect(classifyPlaybackHttpStatus(code), PlaybackFailureKind.permanent);
      expect(isPlaybackAddressRefreshable(code), true);
    }
    expect(classifyPlaybackHttpStatus(null), PlaybackFailureKind.unknown);
    expect(isPlaybackAddressRefreshable(416), false);
  });

  test('state precedence suppresses loading after failure and completion', () {
    for (var mask = 0; mask < 64; mask++) {
      final phase = resolvePlaybackPhase(
        ready: mask & 1 != 0,
        playing: mask & 2 != 0,
        buffering: mask & 4 != 0,
        recovering: mask & 8 != 0,
        ended: mask & 16 != 0,
        failed: mask & 32 != 0,
      );
      if (mask & 32 != 0) {
        expect(phase, PlaybackPhase.failed);
      } else if (mask & 16 != 0) {
        expect(phase, PlaybackPhase.ended);
      } else if (mask & 8 != 0) {
        expect(phase, PlaybackPhase.recovering);
      } else if (mask & 1 == 0) {
        expect(phase, PlaybackPhase.preparing);
      } else if (mask & 4 != 0) {
        expect(phase, PlaybackPhase.buffering);
      } else {
        expect(phase,
            mask & 2 != 0 ? PlaybackPhase.playing : PlaybackPhase.paused);
      }
      expect(
          phase.showsLoading,
          [
            PlaybackPhase.preparing,
            PlaybackPhase.buffering,
            PlaybackPhase.recovering
          ].contains(phase));
    }
  });

  test('automatic rebuild budget only resets explicitly', () {
    final budget = PlaybackRecoveryBudget();
    expect(budget.take(), true);
    expect(budget.take(), true);
    expect(budget.take(), false);
    expect(budget.attempts, 2);
    budget.reset();
    expect(budget.take(), true);
  });

  test('buffer progress accumulates and does not count oscillation', () {
    final progress = PlaybackBufferProgress();
    expect(
        progress.observe(
            buffer: const Duration(milliseconds: 500), percentage: 0),
        false);
    expect(progress.observe(buffer: const Duration(seconds: 1), percentage: 1),
        true);
    expect(progress.observe(buffer: Duration.zero, percentage: 0), false);
    expect(progress.observe(buffer: const Duration(seconds: 1), percentage: 1),
        false);
    progress.reset();
    expect(progress.observe(buffer: const Duration(seconds: 1), percentage: 1),
        true);
  });
}
