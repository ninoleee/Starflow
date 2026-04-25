// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStateStartupMpvTuning on _PlayerPageState {
  String _resolveMpvHardwareDecodeMode() {
    switch (_playbackDecodeMode) {
      case PlaybackDecodeMode.auto:
        return 'auto-safe';
      case PlaybackDecodeMode.hardwarePreferred:
        return 'auto';
      case PlaybackDecodeMode.softwarePreferred:
        return 'no';
    }
  }

  Future<void> _setMpvOption(Player player, String name, String value) async {
    if (kIsWeb) {
      return;
    }
    final native = player.platform;
    if (native == null) {
      return;
    }
    try {
      await (native as dynamic).setProperty(name, value);
    } catch (_) {
      // Keep playback available even if a tuning hint is unsupported.
    }
  }

  Future<void> _applyMpvVisualQualityPreset(
    Player player,
    PlaybackMpvQualityPreset preset,
  ) async {
    switch (preset) {
      case PlaybackMpvQualityPreset.qualityFirst:
        await _setMpvOption(player, 'deband', 'yes');
        await _setMpvOption(player, 'scale', 'ewa_lanczossharp');
        await _setMpvOption(player, 'cscale', 'ewa_lanczossoft');
        await _setMpvOption(player, 'dscale', 'mitchell');
        await _setMpvOption(player, 'sigmoid-upscaling', 'yes');
        await _setMpvOption(player, 'correct-downscaling', 'yes');
        await _setMpvOption(player, 'interpolation', 'no');
        break;
      case PlaybackMpvQualityPreset.balanced:
        await _setMpvOption(player, 'deband', 'yes');
        await _setMpvOption(player, 'scale', 'spline36');
        await _setMpvOption(player, 'cscale', 'bilinear');
        await _setMpvOption(player, 'dscale', 'mitchell');
        await _setMpvOption(player, 'sigmoid-upscaling', 'no');
        await _setMpvOption(player, 'correct-downscaling', 'yes');
        await _setMpvOption(player, 'interpolation', 'no');
        break;
      case PlaybackMpvQualityPreset.performanceFirst:
        await _setMpvOption(player, 'deband', 'no');
        await _setMpvOption(player, 'scale', 'bilinear');
        await _setMpvOption(player, 'cscale', 'bilinear');
        await _setMpvOption(player, 'dscale', 'bilinear');
        await _setMpvOption(player, 'sigmoid-upscaling', 'no');
        await _setMpvOption(player, 'correct-downscaling', 'no');
        await _setMpvOption(player, 'interpolation', 'no');
        break;
    }
  }

  bool get _isTelevisionPlaybackDevice =>
      _providerContainer.read(isTelevisionProvider).value ?? false;

  void _traceQuarkPlaybackStartup(
    String stage, {
    required PlaybackTarget target,
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (target.sourceKind != MediaSourceKind.quark) {
      return;
    }
    playbackTrace(
      stage,
      fields: <String, Object?>{
        'title': target.title.trim().isEmpty ? 'Starflow' : target.title.trim(),
        'sourceKind': target.sourceKind.name,
        'container': target.container,
        ...fields,
      },
      error: error,
      stackTrace: stackTrace,
    );
  }

  int _resolveMpvBufferSizeBytes(PlaybackTarget target) {
    if (isLikelyQuarkPlaybackTarget(target)) {
      return _shouldUseAggressiveMpvTuning(target)
          ? _PlayerPageState._kAggressiveQuarkMpvBufferSizeBytes
          : _PlayerPageState._kQuarkMpvBufferSizeBytes;
    }
    if (_shouldUseAggressiveMpvTuning(target)) {
      return _PlayerPageState._kAggressiveMpvBufferSizeBytes;
    }
    if (_isTelevisionPlaybackDevice && _isLikelyRemotePlaybackTarget(target)) {
      return _PlayerPageState._kHeavyMpvBufferSizeBytes;
    }
    if (_isHeavyPlaybackTarget(target)) {
      return _PlayerPageState._kHeavyMpvBufferSizeBytes;
    }
    if (_isLikelyRemotePlaybackTarget(target)) {
      return _PlayerPageState._kNetworkMpvBufferSizeBytes;
    }
    return _PlayerPageState._kDefaultMpvBufferSizeBytes;
  }

  bool _isLikelyRemotePlaybackTarget(PlaybackTarget target) {
    return isLikelyRemotePlaybackTargetTransport(target);
  }

  bool _isHeavyPlaybackTarget(PlaybackTarget target) {
    return isHeavyPlaybackTargetMetadata(target);
  }

  bool _shouldUseAggressiveMpvTuning(PlaybackTarget target) {
    if (!_aggressivePlaybackTuningEnabled) {
      return false;
    }
    return _isHeavyPlaybackTarget(target) ||
        _isLikelyRemotePlaybackTarget(target);
  }

  PlaybackMpvQualityPreset _resolveEffectiveMpvQualityPreset(
    PlaybackTarget target,
  ) {
    final requestedPreset = _playbackMpvQualityPreset;
    if (!_autoDowngradePlaybackQualityEnabled) {
      return requestedPreset;
    }
    return resolveEffectivePlaybackMpvQualityPreset(
      requestedPreset: requestedPreset,
      target: target,
      isWindowsPlatform:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
      isTelevision: _isTelevisionPlaybackDevice,
      isFullscreen: _isEmbeddedMpvFullscreen,
      aggressiveTuningEnabled: _aggressivePlaybackTuningEnabled,
      decodeMode: _playbackDecodeMode,
      remotePlaybackOverride: _isLikelyRemotePlaybackTarget(target),
      highRiskContainerOverride:
          isHighRiskRemotePlaybackContainer(target) ||
          _remotePreflightIndicatesRangeRisk,
      startupProbeMegabitsPerSecond: _startupProbeMegabitsPerSecond,
    );
  }

  Future<void> _syncEmbeddedMpvFullscreen(bool isFullscreen) async {
    if (_isEmbeddedMpvFullscreen == isFullscreen) {
      return;
    }
    if (mounted) {
      setState(() {
        _isEmbeddedMpvFullscreen = isFullscreen;
      });
    } else {
      _isEmbeddedMpvFullscreen = isFullscreen;
    }
    final player = _player;
    if (player == null) {
      return;
    }
    await _applyMpvPerformanceTuning(player, _resolvedTarget ?? widget.target);
  }

  Future<void> _applyMpvPerformanceTuning(
    Player player,
    PlaybackTarget target,
  ) async {
    if (kIsWeb) {
      return;
    }

    final remotePlayback = _isLikelyRemotePlaybackTarget(target);
    final heavyPlayback = _isHeavyPlaybackTarget(target);
    final aggressiveTuning = _shouldUseAggressiveMpvTuning(target);
    final leanPlayback = _preferLeanPlaybackRendering;
    final requestedQualityPreset = _playbackMpvQualityPreset;
    final qualityPreset = _resolveEffectiveMpvQualityPreset(target);
    final bufferSizeBytes = _resolveMpvBufferSizeBytes(target);
    final highRiskContainer = isHighRiskRemotePlaybackContainer(target) ||
        _remotePreflightIndicatesRangeRisk;
    final remoteProfile = resolveMpvRemotePlaybackTuningProfile(
      target: target,
      aggressiveTuning: aggressiveTuning,
      heavyPlayback: heavyPlayback,
      startupProbeMegabitsPerSecond: _startupProbeMegabitsPerSecond,
      highRiskContainerOverride: highRiskContainer,
    );
    final backBufferBytes = _resolveMpvBackBufferSizeBytes(
      target,
      bufferSizeBytes: bufferSizeBytes,
    );

    await _setMpvOption(player, 'demuxer-thread', 'yes');
    await _setMpvOption(
      player,
      'demuxer-max-bytes',
      bufferSizeBytes.toString(),
    );
    await _setMpvOption(
      player,
      'demuxer-max-back-bytes',
      backBufferBytes.toString(),
    );
    await _setMpvOption(player, 'audio-display', 'no');
    await _applyMpvVisualQualityPreset(player, qualityPreset);

    if (_isTelevisionPlaybackDevice) {
      await _setMpvOption(player, 'osd-bar', 'no');
    }

    if (remotePlayback && remoteProfile != null) {
      await _setMpvOption(
        player,
        'network-timeout',
        remoteProfile.networkTimeoutSeconds,
      );
      await _setMpvOption(player, 'cache', 'yes');
      await _setMpvOption(player, 'cache-on-disk', remoteProfile.cacheOnDisk);
      if (remoteProfile.cacheSecs.isNotEmpty) {
        await _setMpvOption(player, 'cache-secs', remoteProfile.cacheSecs);
      }
      await _setMpvOption(
        player,
        'demuxer-readahead-secs',
        remoteProfile.demuxerReadaheadSecs,
      );
      await _setMpvOption(
        player,
        'demuxer-hysteresis-secs',
        remoteProfile.demuxerHysteresisSecs,
      );
      await _setMpvOption(
        player,
        'cache-pause-wait',
        remoteProfile.cachePauseWait,
      );
      await _setMpvOption(
        player,
        'cache-pause-initial',
        remoteProfile.cachePauseInitial,
      );
    }

    await _setMpvOption(
      player,
      'vd-lavc-dr',
      (leanPlayback ||
              aggressiveTuning ||
              heavyPlayback ||
              qualityPreset == PlaybackMpvQualityPreset.performanceFirst)
          ? 'yes'
          : 'no',
    );

    final shouldSkipLoopFilter =
        _playbackDecodeMode == PlaybackDecodeMode.softwarePreferred &&
            (aggressiveTuning ||
                heavyPlayback ||
                qualityPreset == PlaybackMpvQualityPreset.performanceFirst);
    await _setMpvOption(
      player,
      'vd-lavc-skiploopfilter',
      shouldSkipLoopFilter ? 'nonref' : 'none',
    );
    _traceWindowsMpv(
      'windows-mpv.tuning.summary',
      fields: {
        'remotePlayback': remotePlayback,
        'heavyPlayback': heavyPlayback,
        'aggressiveTuning': aggressiveTuning,
        'leanPlayback': leanPlayback,
        'qualityPresetRequested': requestedQualityPreset.name,
        'qualityPresetApplied': qualityPreset.name,
        'bufferSizeBytes': bufferSizeBytes,
        'backBufferBytes': backBufferBytes,
        'quarkTuning': isLikelyQuarkPlaybackTarget(target),
        'startupProbeMbps':
            _startupProbeMegabitsPerSecond?.toStringAsFixed(2) ?? '',
        'rangeRisk': _remotePreflightIndicatesRangeRisk,
        'remoteProfile': remoteProfile == null
            ? ''
            : remoteProfile.lowLatency
                ? 'low-latency'
                : 'buffered',
        'skipLoopFilter': shouldSkipLoopFilter ? 'nonref' : 'none',
      },
    );
  }

  int _resolveMpvBackBufferSizeBytes(
    PlaybackTarget target, {
    required int bufferSizeBytes,
  }) {
    final maxBackBufferBytes = isLikelyQuarkPlaybackTarget(target)
        ? _PlayerPageState._kMaxQuarkMpvBackBufferSizeBytes
        : _PlayerPageState._kMaxMpvBackBufferSizeBytes;
    var backBufferBytes = bufferSizeBytes ~/ 4;
    if (backBufferBytes < _PlayerPageState._kMinMpvBackBufferSizeBytes) {
      backBufferBytes = _PlayerPageState._kMinMpvBackBufferSizeBytes;
    } else if (backBufferBytes > maxBackBufferBytes) {
      backBufferBytes = maxBackBufferBytes;
    }
    return backBufferBytes;
  }

  bool get _remotePreflightIndicatesRangeRisk {
    final preflight = _lastRemotePreflight;
    return preflight != null &&
        preflight.attempted &&
        !preflight.supportsByteRange;
  }
}
