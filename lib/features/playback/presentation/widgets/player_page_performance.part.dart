// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStatePerformance on _PlayerPageState {
  void _beginMpvPerformanceSession(PlaybackTarget target) {
    _mpvHealthLogGate = MpvHealthLogGate();
    _mpvLastDroppedFrames = 0;
    _mpvPerformanceTracker = PlaybackPerformanceTracker()
      ..begin(sourceBitrate: target.bitrate ?? 0)
      ..onBufferingChanged(true);
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
    _mpvPerformanceSampleGeneration++;
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
    final generation = _mpvPerformanceSampleGeneration;
    final tracker = _mpvPerformanceTracker;
    try {
      final cacheSpeed = await _readMpvIntProperty(player, 'cache-speed');
      if (_player != player ||
          generation != _mpvPerformanceSampleGeneration ||
          tracker != _mpvPerformanceTracker) {
        return;
      }
      if (cacheSpeed != null && cacheSpeed > 0) {
        tracker?.recordNetworkBytesPerSecond(cacheSpeed);
        _PlayerPageState._hostBandwidthCache.record(target, cacheSpeed);
      }
      if (appLogger.isRecording(AppLogLevel.info)) {
        final decoderDrops =
            await _readMpvIntProperty(player, 'decoder-frame-drop-count');
        final outputDrops =
            await _readMpvIntProperty(player, 'frame-drop-count');
        if (_player != player || generation != _mpvPerformanceSampleGeneration) {
          return;
        }
        final drops = (decoderDrops ?? 0) + (outputDrops ?? 0);
        if (drops > _mpvLastDroppedFrames) {
          unawaited(_logMpvPlaybackHealth(player, 'dropped-frames'));
        }
        _mpvLastDroppedFrames = drops;
      }
    } finally {
      if (generation == _mpvPerformanceSampleGeneration) {
        _mpvPerformanceSampleInProgress = false;
      }
    }
  }

  Future<void> _logMpvPlaybackHealth(Player player, String reason) async {
    if (!appLogger.isRecording(AppLogLevel.info) ||
        _player != player ||
        !_mpvHealthLogGate.admit(DateTime.now())) {
      return;
    }
    final tracker = _mpvPerformanceTracker;
    final properties = await readMpvHealthProperties(
      readProperty: (name) => _readMpvStringProperty(player, name),
    );
    if (!mounted || _player != player || tracker != _mpvPerformanceTracker) {
      return;
    }
    appLogInfo('playback.health', 'Playback health snapshot', fields: {
      'engine': 'mpv',
      'reason': reason,
      'positionMs': player.state.position.inMilliseconds,
      'buffering': player.state.buffering,
      'speed': player.state.rate,
      ...properties,
    });
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
    final includeDiagnostics = appLogger.isRecording(AppLogLevel.info);
    final properties = await readMpvShutdownProperties(
      readProperty: (name) => _readMpvStringProperty(player, name),
      includeDiagnostics: includeDiagnostics,
    );
    int? intProperty(String name) =>
        num.tryParse(properties[name] ?? '')?.round();
    final cacheSpeed = intProperty('cache-speed');
    if (cacheSpeed != null && cacheSpeed > 0) {
      tracker.recordNetworkBytesPerSecond(cacheSpeed);
      _PlayerPageState._hostBandwidthCache.record(target, cacheSpeed);
    }
    final summary = tracker.finish();
    if (summary == null || !includeDiagnostics) {
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
        'hardwareDecoder': properties['hwdec-current'] ?? '',
        'videoDecoder': properties['video-codec'] ?? '',
        'audioDecoder': properties['audio-codec-name'] ?? '',
        'audioOutput': properties['current-ao'] ?? '',
        'audioSampleFormat': properties['audio-params/format'] ?? '',
        'audioInputChannels': properties['audio-params/channel-count'] ?? '',
        'audioOutputSampleRate':
            properties['audio-out-params/samplerate'] ?? '',
        'audioOutputChannels':
            properties['audio-out-params/channel-count'] ?? '',
        'avSyncSeconds': properties['avsync'] ?? '',
        'droppedFrames': (intProperty('decoder-frame-drop-count') ?? 0) +
            (intProperty('frame-drop-count') ?? 0),
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
