// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStatePerformance on _PlayerPageState {
  void _beginMpvPerformanceSession(PlaybackTarget target) {
    _mpvPerformanceTracker = PlaybackPerformanceTracker()
      ..begin(sourceBitrate: target.bitrate ?? 0)
      ..onBufferingChanged(true);
  }

  void _recordMpvPreflightBandwidth(int? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond <= 0) {
      return;
    }
    _mpvPerformanceTracker?.recordNetworkBytesPerSecond(bytesPerSecond);
  }

  void _markMpvFirstFrame() {
    final tracker = _mpvPerformanceTracker;
    if (tracker == null) {
      return;
    }
    tracker.onBufferingChanged(false);
    final firstFrameMs = tracker.markFirstFrame();
    if (firstFrameMs < 0) {
      return;
    }
    appLogInfo(
      'playback.performance',
      'Playback first frame rendered',
      fields: <String, Object?>{
        'engine': 'mpv',
        'firstFrameMs': firstFrameMs,
      },
    );
  }

  void _startMpvPerformanceSampling(Player player, PlaybackTarget target) {
    _stopMpvPerformanceSampling();
    _mpvPerformanceSampleTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_sampleMpvPerformance(player, target)),
    );
  }

  void _stopMpvPerformanceSampling() {
    _mpvPerformanceSampleTimer?.cancel();
    _mpvPerformanceSampleTimer = null;
    _mpvPerformanceSampleInProgress = false;
  }

  Future<void> _sampleMpvPerformance(
    Player player,
    PlaybackTarget target,
  ) async {
    if (_mpvPerformanceSampleInProgress ||
        _player != player ||
        _mpvPerformanceTracker == null) {
      return;
    }
    _mpvPerformanceSampleInProgress = true;
    try {
      final cacheSpeed = await _readMpvIntProperty(player, 'cache-speed');
      if (cacheSpeed == null || cacheSpeed <= 0) {
        return;
      }
      _mpvPerformanceTracker?.recordNetworkBytesPerSecond(cacheSpeed);
      _PlayerPageState._hostBandwidthCache.record(target, cacheSpeed);
    } finally {
      _mpvPerformanceSampleInProgress = false;
    }
  }

  Future<void> _finishMpvPerformanceSession({
    required String reason,
    Player? player,
  }) async {
    final tracker = _mpvPerformanceTracker;
    if (tracker == null) {
      return;
    }
    _mpvPerformanceTracker = null;
    _stopMpvPerformanceSampling();

    final target = _resolvedTarget ?? widget.target;
    final properties = await Future.wait<Object?>([
      _readMpvIntProperty(player, 'cache-speed'),
      _readMpvStringProperty(player, 'hwdec-current'),
      _readMpvStringProperty(player, 'video-codec'),
      _readMpvIntProperty(player, 'decoder-frame-drop-count'),
      _readMpvIntProperty(player, 'frame-drop-count'),
    ]);
    final cacheSpeed = properties[0] as int?;
    if (cacheSpeed != null && cacheSpeed > 0) {
      tracker.recordNetworkBytesPerSecond(cacheSpeed);
      _PlayerPageState._hostBandwidthCache.record(target, cacheSpeed);
    }
    final hardwareDecoder = properties[1] as String?;
    final videoDecoder = properties[2] as String?;
    final droppedDecoderFrames = properties[3] as int? ?? 0;
    final droppedOutputFrames = properties[4] as int? ?? 0;
    final summary = tracker.finish();
    if (summary == null) {
      return;
    }
    final budget = _resolveMpvBufferBudget(target);
    appLogInfo(
      'playback.performance',
      'Playback session completed',
      fields: <String, Object?>{
        'engine': 'mpv',
        'reason': reason,
        'sessionMs': summary.sessionDurationMs,
        'firstFrameMs': summary.firstFrameMs,
        'targetResolutionMs': _playbackTargetResolutionMs,
        'startupToFirstFrameMs':
            _playbackTargetResolutionMs + summary.firstFrameMs,
        'bufferingCount': summary.bufferingCount,
        'bufferingMs': summary.bufferingDurationMs,
        'recoveries': summary.recoveryCount,
        'avgBytesPerSecond': summary.averageNetworkBytesPerSecond,
        'minBytesPerSecond': summary.minimumNetworkBytesPerSecond,
        'maxBytesPerSecond': summary.maximumNetworkBytesPerSecond,
        'sourceBitrate': summary.sourceBitrate,
        'bandwidthRatio':
            summary.bandwidthToBitrateRatio?.toStringAsFixed(2) ?? '',
        'hardwareDecoder': hardwareDecoder ?? '',
        'videoDecoder': videoDecoder ?? '',
        'droppedFrames': droppedDecoderFrames + droppedOutputFrames,
        'forwardBufferBytes': budget.forwardBytes,
        'backBufferBytes': budget.backBytes,
        'memoryClassMb': _androidMemoryClassMb ?? 0,
        'memoryCapApplied': budget.memoryCapApplied,
      },
    );
  }

  Future<String?> _readMpvStringProperty(Player? player, String name) async {
    final native = player?.platform;
    if (native == null) {
      return null;
    }
    try {
      final value = await (native as dynamic)
          .getProperty(name)
          .timeout(const Duration(milliseconds: 250));
      if (value == null) {
        return null;
      }
      final normalized = '$value'.trim();
      return normalized.isEmpty || normalized == 'null' ? null : normalized;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _readMpvIntProperty(Player? player, String name) async {
    final raw = await _readMpvStringProperty(player, name);
    if (raw == null) {
      return null;
    }
    return num.tryParse(raw)?.round();
  }
}
