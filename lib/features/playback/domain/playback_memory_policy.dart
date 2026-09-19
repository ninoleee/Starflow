import 'package:starflow/features/playback/application/playback_policy_values.dart';

bool playbackMemoryCompleted(
    {required int positionMs,
    required int durationMs,
    required double progress}) {
  if (durationMs <= 0) {
    return progress >=
        PlaybackPolicyValues.memoryUnknownCompletedPermille / 1000;
  }
  return progress >= PlaybackPolicyValues.memoryCompletedPermille / 1000 ||
      durationMs - positionMs <=
          PlaybackPolicyValues.memoryCompletedRemainingMs;
}
