import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_auto_skip_policy.dart';

void main() {
  group('resolvePlaybackStartPosition', () {
    test('keeps the resume point for a manual entry', () {
      final start = resolvePlaybackStartPosition(
        allowResume: true,
        resumePosition: const Duration(minutes: 12),
        automaticNext: false,
        skipEnabled: true,
        introDuration: const Duration(seconds: 90),
      );

      expect(start.position, const Duration(minutes: 12));
      expect(start.isResume, isTrue);
      expect(start.isIntroSkip, isFalse);
    });

    test('keeps a resume point that falls inside the intro', () {
      final start = resolvePlaybackStartPosition(
        allowResume: true,
        resumePosition: const Duration(seconds: 40),
        automaticNext: false,
        skipEnabled: true,
        introDuration: const Duration(seconds: 90),
      );

      expect(start.position, const Duration(seconds: 40));
      expect(start.isResume, isTrue);
    });

    test('starts an explicit restart from zero', () {
      final start = resolvePlaybackStartPosition(
        allowResume: false,
        resumePosition: const Duration(minutes: 12),
        automaticNext: false,
        skipEnabled: true,
        introDuration: const Duration(seconds: 90),
      );

      expect(start.position, Duration.zero);
      expect(start.isResume, isFalse);
      expect(start.isIntroSkip, isFalse);
    });

    test('applies the intro rule when there is no resume point', () {
      final start = resolvePlaybackStartPosition(
        allowResume: true,
        resumePosition: Duration.zero,
        automaticNext: false,
        skipEnabled: true,
        introDuration: const Duration(seconds: 90),
      );

      expect(start.position, const Duration(seconds: 90));
      expect(start.isIntroSkip, isTrue);
      expect(start.isResume, isFalse);
    });

    test('ignores stale resume history for an auto-advanced episode', () {
      final start = resolvePlaybackStartPosition(
        allowResume: true,
        resumePosition: const Duration(minutes: 12),
        automaticNext: true,
        skipEnabled: true,
        introDuration: const Duration(seconds: 90),
      );

      expect(start.position, const Duration(seconds: 90));
      expect(start.isIntroSkip, isTrue);
      expect(start.isResume, isFalse);
    });

    test('starts an auto-advanced episode at zero without a skip rule', () {
      final start = resolvePlaybackStartPosition(
        allowResume: true,
        resumePosition: const Duration(minutes: 12),
        automaticNext: true,
        skipEnabled: false,
        introDuration: const Duration(seconds: 90),
      );

      expect(start.position, Duration.zero);
      expect(start.isIntroSkip, isFalse);
    });
  });

  group('resolvePlaybackEndBoundary', () {
    test('uses the outro skip point when the rule applies', () {
      final boundary = resolvePlaybackEndBoundary(
        duration: const Duration(minutes: 45),
        skipEnabled: true,
        outroDuration: const Duration(seconds: 90),
      );

      expect(boundary, const Duration(minutes: 43, seconds: 30));
    });

    test('falls back to the natural end when the rule is off', () {
      final boundary = resolvePlaybackEndBoundary(
        duration: const Duration(minutes: 45),
        skipEnabled: false,
        outroDuration: const Duration(seconds: 90),
      );

      expect(boundary, const Duration(minutes: 45));
    });

    test('falls back to the natural end for an outro longer than the file', () {
      final boundary = resolvePlaybackEndBoundary(
        duration: const Duration(minutes: 1),
        skipEnabled: true,
        outroDuration: const Duration(minutes: 5),
      );

      expect(boundary, const Duration(minutes: 1));
    });
  });

  group('shouldPrepareNextEpisode', () {
    const boundary = Duration(minutes: 43, seconds: 30);

    test('stays idle earlier than the lead window', () {
      expect(
        shouldPrepareNextEpisode(
          position: const Duration(minutes: 42, seconds: 59),
          boundary: boundary,
        ),
        isFalse,
      );
    });

    test('prepares inside the last 30 seconds before the boundary', () {
      expect(
        shouldPrepareNextEpisode(
          position: const Duration(minutes: 43),
          boundary: boundary,
        ),
        isTrue,
      );
    });

    test('stops at the boundary itself', () {
      expect(
        shouldPrepareNextEpisode(position: boundary, boundary: boundary),
        isFalse,
      );
    });

    test('prepares from zero for a boundary inside the lead window', () {
      expect(
        shouldPrepareNextEpisode(
          position: Duration.zero,
          boundary: const Duration(seconds: 20),
        ),
        isTrue,
      );
    });

    test('never prepares without a known boundary', () {
      expect(
        shouldPrepareNextEpisode(
          position: const Duration(minutes: 1),
          boundary: Duration.zero,
        ),
        isFalse,
      );
    });
  });
}
