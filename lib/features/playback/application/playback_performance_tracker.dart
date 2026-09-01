import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

class PlaybackPerformanceSummary {
  const PlaybackPerformanceSummary({
    required this.sessionDurationMs,
    required this.firstFrameMs,
    required this.bufferingCount,
    required this.bufferingDurationMs,
    required this.recoveryCount,
    required this.averageNetworkBytesPerSecond,
    required this.minimumNetworkBytesPerSecond,
    required this.maximumNetworkBytesPerSecond,
    required this.sourceBitrate,
    required this.bandwidthToBitrateRatio,
  });

  final int sessionDurationMs;
  final int firstFrameMs;
  final int bufferingCount;
  final int bufferingDurationMs;
  final int recoveryCount;
  final int averageNetworkBytesPerSecond;
  final int minimumNetworkBytesPerSecond;
  final int maximumNetworkBytesPerSecond;
  final int sourceBitrate;
  final double? bandwidthToBitrateRatio;
}

class PlaybackHostBandwidthCache {
  PlaybackHostBandwidthCache({
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, ({int bytesPerSecond, DateTime recordedAt})> _entries = {};

  int? resolve(PlaybackTarget target) {
    final key = _hostKey(target);
    final entry = key.isEmpty ? null : _entries[key];
    if (entry == null) {
      return null;
    }
    if (_clock().difference(entry.recordedAt) > ttl) {
      _entries.remove(key);
      return null;
    }
    return entry.bytesPerSecond;
  }

  void record(PlaybackTarget target, int bytesPerSecond) {
    final key = _hostKey(target);
    if (key.isEmpty || bytesPerSecond <= 0) {
      return;
    }
    final previous = _entries[key];
    final smoothedBytesPerSecond =
        previous == null || _clock().difference(previous.recordedAt) > ttl
            ? bytesPerSecond
            : ((previous.bytesPerSecond * 3) + bytesPerSecond) ~/ 4;
    _entries[key] = (
      bytesPerSecond: smoothedBytesPerSecond,
      recordedAt: _clock(),
    );
  }

  String _hostKey(PlaybackTarget target) {
    final url = isLoopbackPlaybackRelayUrl(target.streamUrl)
        ? target.actualAddress
        : target.streamUrl;
    final uri = Uri.tryParse(url.trim());
    return uri?.host.trim().toLowerCase() ?? '';
  }
}

class PlaybackPerformanceTracker {
  PlaybackPerformanceTracker({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _startedAt;
  DateTime? _firstFrameAt;
  DateTime? _bufferingStartedAt;
  Duration _bufferingDuration = Duration.zero;
  int _bufferingCount = 0;
  int _recoveryCount = 0;
  int _networkSampleCount = 0;
  int _networkBytesPerSecondSum = 0;
  int _minimumNetworkBytesPerSecond = 0;
  int _maximumNetworkBytesPerSecond = 0;
  int _sourceBitrate = 0;

  bool get isActive => _startedAt != null;

  void begin({required int sourceBitrate}) {
    _startedAt = _clock();
    _firstFrameAt = null;
    _bufferingStartedAt = null;
    _bufferingDuration = Duration.zero;
    _bufferingCount = 0;
    _recoveryCount = 0;
    _networkSampleCount = 0;
    _networkBytesPerSecondSum = 0;
    _minimumNetworkBytesPerSecond = 0;
    _maximumNetworkBytesPerSecond = 0;
    _sourceBitrate = sourceBitrate.clamp(0, 1 << 62);
  }

  int markFirstFrame() {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return 0;
    }
    if (_firstFrameAt != null) {
      return -1;
    }
    _firstFrameAt = _clock();
    return _firstFrameAt!
        .difference(startedAt)
        .inMilliseconds
        .clamp(0, 1 << 31);
  }

  void onBufferingChanged(bool buffering) {
    if (!isActive) {
      return;
    }
    final now = _clock();
    if (buffering) {
      if (_bufferingStartedAt == null) {
        _bufferingStartedAt = now;
        _bufferingCount += 1;
      }
      return;
    }
    _closeBufferingWindow(now);
  }

  void recordNetworkBytesPerSecond(int bytesPerSecond) {
    if (!isActive || bytesPerSecond <= 0) {
      return;
    }
    _networkSampleCount += 1;
    _networkBytesPerSecondSum += bytesPerSecond;
    if (_minimumNetworkBytesPerSecond == 0 ||
        bytesPerSecond < _minimumNetworkBytesPerSecond) {
      _minimumNetworkBytesPerSecond = bytesPerSecond;
    }
    if (bytesPerSecond > _maximumNetworkBytesPerSecond) {
      _maximumNetworkBytesPerSecond = bytesPerSecond;
    }
  }

  void recordRecovery() {
    if (isActive) {
      _recoveryCount += 1;
    }
  }

  PlaybackPerformanceSummary? finish() {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return null;
    }
    final now = _clock();
    _closeBufferingWindow(now);
    _startedAt = null;
    final averageBytesPerSecond = _networkSampleCount > 0
        ? _networkBytesPerSecondSum ~/ _networkSampleCount
        : 0;
    final ratio = _sourceBitrate > 0 && averageBytesPerSecond > 0
        ? (averageBytesPerSecond * 8) / _sourceBitrate
        : null;
    return PlaybackPerformanceSummary(
      sessionDurationMs:
          now.difference(startedAt).inMilliseconds.clamp(0, 1 << 31),
      firstFrameMs: _firstFrameAt == null
          ? 0
          : _firstFrameAt!
              .difference(startedAt)
              .inMilliseconds
              .clamp(0, 1 << 31),
      bufferingCount: _bufferingCount,
      bufferingDurationMs: _bufferingDuration.inMilliseconds,
      recoveryCount: _recoveryCount,
      averageNetworkBytesPerSecond: averageBytesPerSecond,
      minimumNetworkBytesPerSecond: _minimumNetworkBytesPerSecond,
      maximumNetworkBytesPerSecond: _maximumNetworkBytesPerSecond,
      sourceBitrate: _sourceBitrate,
      bandwidthToBitrateRatio: ratio,
    );
  }

  void _closeBufferingWindow(DateTime now) {
    final startedAt = _bufferingStartedAt;
    if (startedAt == null) {
      return;
    }
    _bufferingDuration += now.difference(startedAt);
    _bufferingStartedAt = null;
  }
}
