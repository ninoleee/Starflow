/// Native demuxer state, deliberately separate from cache-buffering-state
/// (which only describes the short startup/rebuffer pause cushion).
class MpvMemoryCacheSample {
  const MpvMemoryCacheSample({
    required this.idle,
    required this.eof,
    required this.underrun,
    required this.forwardBytes,
    required this.seconds,
    required this.end,
    required this.reader,
  });

  final bool? idle;
  final bool? eof;
  final bool? underrun;
  final int? forwardBytes;
  final double? seconds;
  final double? end;
  final double? reader;

  bool get valid =>
      idle != null &&
      eof != null &&
      underrun == false &&
      (forwardBytes ?? 0) > 0 &&
      seconds != null &&
      seconds!.isFinite &&
      seconds! > 0 &&
      end != null &&
      end!.isFinite &&
      reader != null &&
      reader!.isFinite &&
      end! > reader!;
}

class MpvRefillThreshold {
  const MpvRefillThreshold(this.seconds, this.bytes);
  final double seconds;
  final int bytes;
}

class MpvMemoryPriorityPolicy {
  MpvMemoryCacheSample? _stopped;
  bool _established = false;
  MpvRefillThreshold? refill;

  void reset() {
    _stopped = null;
    _established = false;
    refill = null;
  }

  bool sample(MpvMemoryCacheSample sample, {required bool active}) {
    if (!active || !sample.valid || sample.idle != true) {
      reset();
      return false;
    }
    final previous = _stopped;
    _stopped = sample;
    // Idle also occurs before the reader starts. Require a stable cache end
    // and an advancing reader before granting the relay its short lease.
    if (previous == null ||
        (sample.end! - previous.end!).abs() > 0.001 ||
        sample.eof != previous.eof) {
      _established = false;
      refill = null;
      return false;
    }
    if (!_established && sample.reader! <= previous.reader!) return false;
    if (!_established && sample.eof == false) {
      refill = MpvRefillThreshold(
        previous.seconds! * 0.75,
        (previous.forwardBytes! * 0.75).floor(),
      );
    }
    _established = true;
    // EOF is a completed read, not a refill high water to learn from.
    return true;
  }
}
