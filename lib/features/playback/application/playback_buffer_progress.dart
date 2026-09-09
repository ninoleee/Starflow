import 'playback_policy_values.dart';

/// High-water marks avoid treating oscillation or tiny per-sample changes as
/// new buffering forever. Small advances accumulate until the next threshold.
class PlaybackBufferProgress {
  Duration _buffer = Duration.zero;
  double _percentage = 0;

  void reset() {
    _buffer = Duration.zero;
    _percentage = 0;
  }

  bool observe({required Duration buffer, required double percentage}) {
    var advanced = false;
    if (buffer - _buffer >=
        const Duration(milliseconds: PlaybackPolicyValues.bufferAdvanceMs)) {
      _buffer = buffer;
      advanced = true;
    }
    if (percentage.isFinite) {
      final normalized = percentage.clamp(0.0, 100.0);
      if (normalized - _percentage >=
          PlaybackPolicyValues.bufferAdvancePercent) {
        _percentage = normalized;
        advanced = true;
      }
    }
    return advanced;
  }
}
