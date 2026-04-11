// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStateStartupMpv on _PlayerPageState {
  Future<void> _initialize() async {
    await ActivePlaybackCleanupCoordinator.cleanupAll(
      reason: 'player-page-initialize',
      exceptToken: _activePlaybackCleanupToken,
    );
    await _waitForPendingPlayerShutdowns(reason: 'player-page-initialize');
    _traceWindowsMpv(
      'windows-mpv.initialize.begin',
      fields: {
        'canPlay': widget.target.canPlay,
        'needsResolution': widget.target.needsResolution,
        'decodeMode': _playbackDecodeMode.name,
        'qualityPresetRequested': _playbackMpvQualityPreset.name,
        'qualityAutoDowngrade': _autoDowngradePlaybackQualityEnabled,
        'leanUi': _leanPlaybackUiEnabled,
        'aggressiveTuning': _aggressivePlaybackTuningEnabled,
      },
    );
    if (!widget.target.canPlay) {
      _traceWindowsMpv('windows-mpv.initialize.no-playable-source');
      setState(() {
        _error = '没有可播放的流地址';
      });
      return;
    }

    try {
      final coordinator = PlaybackStartupCoordinator(
        read: ref.read,
        targetResolver: PlaybackTargetResolver(read: ref.read),
        engineRouter: const PlaybackEngineRouter(),
      );
      final outcome = await coordinator.start(
        initialTarget: widget.target,
        isTelevision: ref.read(isTelevisionProvider).value ?? false,
        isWeb: kIsWeb,
      );
      final resolvedTarget = outcome.resolvedTarget;
      _traceWindowsMpv(
        'windows-mpv.initialize.target-resolved',
        fields: {
          'urlScheme':
              Uri.tryParse(resolvedTarget.streamUrl.trim())?.scheme ?? '',
          'sourceName': resolvedTarget.sourceName,
          'resolution': resolvedTarget.resolutionLabel,
          'format': resolvedTarget.formatLabel,
          'videoCodec': resolvedTarget.videoCodec,
          'audioCodec': resolvedTarget.audioCodec,
          'bitrate': resolvedTarget.bitrate ?? 0,
          'headers': resolvedTarget.headers.length,
        },
      );
      final startupPreparation = outcome.startupPreparation;
      final resumeEntry = startupPreparation.resumeEntry;
      final skipPreference = startupPreparation.skipPreference;
      if (mounted) {
        setState(() {
          _resolvedTarget = resolvedTarget;
          _seriesSkipPreference = skipPreference;
        });
      }
      final executor = PlaybackStartupExecutor(
        launchSystemPlayer: _launchWithSystemPlayer,
        launchNativeContainer: _launchWithNativeContainer,
        launchPerformanceFallback: _tryLaunchWithPerformanceFallback,
      );
      final shouldOpen = await executor.execute(
        outcome.routeAction,
        resolvedTarget,
      );
      if (!shouldOpen) {
        return;
      }
      if (_startupProbeEnabled) {
        unawaited(_runStartupProbe(resolvedTarget));
      } else if (_startupProbe.estimatedSpeedBytesPerSecond != null) {
        setState(() {
          _startupProbe = const _StartupProbeResult();
        });
      }
      final settings = outcome.settings;
      final timeoutSeconds = settings.playbackOpenTimeoutSeconds.clamp(1, 600);
      _traceWindowsMpv(
        'windows-mpv.initialize.open-start',
        fields: {
          'timeoutSeconds': timeoutSeconds,
          'bufferSizeBytes': _resolveMpvBufferSizeBytes(resolvedTarget),
          'hwdec': _resolveMpvHardwareDecodeMode(),
        },
      );
      final playback = await _openEmbeddedPlayback(
        resolvedTarget,
        Duration(seconds: timeoutSeconds),
      );

      if (!mounted) {
        await playback.errorSubscription.cancel();
        await playback.player.dispose();
        return;
      }

      _playerErrorSubscription = playback.errorSubscription;
      _playerPlayingSubscription = playback.player.stream.playing.listen((
        playing,
      ) {
        _traceWindowsMpv(
          'windows-mpv.player.playing',
          fields: {'playing': playing},
        );
        _updateTvPlaybackState(playing: playing);
        unawaited(_syncBackgroundPlayback(enabled: playing));
        unawaited(_syncPlaybackSystemSession(force: true));
        if (_isTelevisionPlaybackDevice) {
          if (!playing) {
            _showTvPlaybackChrome(autoHide: false);
          } else if (_tvPlaybackChromeVisible) {
            _scheduleTvPlaybackChromeHide();
          }
        }
        if (!playing) {
          unawaited(_persistPlaybackProgress(force: true));
        }
      });
      _playerDurationSubscription = playback.player.stream.duration.listen((
        duration,
      ) {
        _latestDuration = duration;
        _updateTvPlaybackState(duration: duration);
        unawaited(_syncPlaybackSystemSession());
      });
      _playerPositionSubscription = playback.player.stream.position.listen((
        position,
      ) {
        _latestPosition = position;
        _updateTvPlaybackState(position: position);
        _maybeApplyAutoSkip(playback.player, position);
        unawaited(_persistPlaybackProgress());
        unawaited(_syncPlaybackSystemSession());
      });
      _bindWindowsMpvTraceStreams(playback.player);
      setState(() {
        _player = playback.player;
        _videoController = playback.videoController;
        _isReady = true;
        _error = null;
        _latestPosition = playback.player.state.position;
        _latestDuration = playback.player.state.duration;
      });
      await _syncSubtitleDelayState(playback.player);
      await _restorePlaybackProgress(playback.player, resumeEntry);
      _syncSkipFlagsWithCurrentPosition();
      _traceWindowsMpv(
        'windows-mpv.initialize.ready',
        fields: {
          'durationMs': playback.player.state.duration.inMilliseconds,
          'width': playback.player.state.width ?? 0,
          'height': playback.player.state.height ?? 0,
          'buffering': playback.player.state.buffering,
        },
      );
      unawaited(_syncBackgroundPlayback(enabled: true));
      unawaited(_syncPlaybackSystemSession(force: true));
    } catch (error, stackTrace) {
      _traceWindowsMpv(
        'windows-mpv.initialize.failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _buildPlaybackErrorMessage(error);
      });
      unawaited(_syncBackgroundPlayback(enabled: false));
      unawaited(_teardownPlaybackSystemSession());
    }
  }

  Future<_OpenedPlayback> _openWithRetry(
    PlaybackTarget resolvedTarget, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;

    for (var attempt = 1;
        attempt <= _PlayerPageState._maxPlaybackAttempts;
        attempt++) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }

      try {
        _traceWindowsMpv(
          'windows-mpv.open.attempt',
          fields: {
            'attempt': attempt,
            'remainingMs': remaining.inMilliseconds,
          },
        );
        final opened = await _openSingleAttempt(
          resolvedTarget,
          timeout: remaining,
        );
        _traceWindowsMpv(
          'windows-mpv.open.attempt-success',
          fields: {'attempt': attempt},
        );
        return opened;
      } catch (error, stackTrace) {
        lastError = error;
        _traceWindowsMpv(
          'windows-mpv.open.attempt-failed',
          fields: {'attempt': attempt},
          error: error,
          stackTrace: stackTrace,
        );
        if (attempt >= _PlayerPageState._maxPlaybackAttempts) {
          break;
        }
      }
    }

    if (deadline.difference(DateTime.now()) <= Duration.zero) {
      throw TimeoutException('超过最大等待时间，已停止尝试播放');
    }
    throw lastError ?? const _PlayerOpenException('播放打开失败');
  }

  Future<_OpenedPlayback> _openSingleAttempt(
    PlaybackTarget resolvedTarget, {
    required Duration timeout,
  }) async {
    final bufferSizeBytes = _resolveMpvBufferSizeBytes(resolvedTarget);
    final hardwareDecodeMode = _resolveMpvHardwareDecodeMode();
    final player = Player(
      configuration: PlayerConfiguration(
        title: 'Starflow',
        logLevel: MPVLogLevel.error,
        bufferSize: bufferSizeBytes,
      ),
    );
    final videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        hwdec: hardwareDecodeMode,
        enableHardwareAcceleration:
            _playbackDecodeMode != PlaybackDecodeMode.softwarePreferred,
      ),
    );
    _traceWindowsMpv(
      'windows-mpv.open.create-player',
      fields: {
        'timeoutMs': timeout.inMilliseconds,
        'bufferSizeBytes': bufferSizeBytes,
        'hwdec': hardwareDecodeMode,
        'hardwareAcceleration':
            _playbackDecodeMode != PlaybackDecodeMode.softwarePreferred,
      },
    );
    Completer<String>? startupError;
    var awaitingStartup = false;
    late final StreamSubscription<String> errorSubscription;
    errorSubscription = player.stream.error.listen((message) {
      final normalized = message.trim();
      if (normalized.isEmpty) {
        return;
      }
      _traceWindowsMpv(
        'windows-mpv.player.error',
        fields: {
          'startup': awaitingStartup,
          'message': normalized,
        },
      );
      final pendingStartupError = startupError;
      if (awaitingStartup &&
          pendingStartupError != null &&
          !pendingStartupError.isCompleted) {
        pendingStartupError.complete(normalized);
        return;
      }
      if (!mounted || _player != player) {
        return;
      }
      setState(() {
        _error = normalized;
      });
    });

    try {
      await _applyMpvPerformanceTuning(player, resolvedTarget);
      _traceWindowsMpv('windows-mpv.open.tuning-applied');
      final deadline = DateTime.now().add(timeout);
      Completer<String> beginStartupWait() {
        final completer = Completer<String>();
        startupError = completer;
        awaitingStartup = true;
        return completer;
      }

      await _openResolvedTargetWithMpv(
        player,
        resolvedTarget,
        deadline: deadline,
        beginStartupWait: beginStartupWait,
      );
      awaitingStartup = false;
      startupError = null;
      _traceWindowsMpv(
        'windows-mpv.open.ready',
        fields: {
          'positionMs': player.state.position.inMilliseconds,
          'durationMs': player.state.duration.inMilliseconds,
          'width': player.state.width ?? 0,
          'height': player.state.height ?? 0,
          'buffering': player.state.buffering,
        },
      );
      return _OpenedPlayback(
        player: player,
        videoController: videoController,
        errorSubscription: errorSubscription,
      );
    } catch (error, stackTrace) {
      _traceWindowsMpv(
        'windows-mpv.open.failed',
        error: error,
        stackTrace: stackTrace,
      );
      await errorSubscription.cancel();
      await player.dispose();
      rethrow;
    }
  }

  Future<_OpenedPlayback> _openEmbeddedPlayback(
    PlaybackTarget resolvedTarget,
    Duration timeout,
  ) async {
    final playback = await _openWithRetry(
      resolvedTarget,
      timeout: timeout,
    );
    await _applyStartupPlaybackPreferences(playback.player);
    await _applyStartupExternalSubtitle(playback.player, resolvedTarget);
    return playback;
  }

  Future<void> _launchWithSystemPlayer(PlaybackTarget target) async {
    final result =
        await ref.read(systemPlaybackLauncherProvider).launch(target);
    if (!result.launched) {
      throw _PlayerOpenException(
        result.message.isEmpty ? '系统播放器启动失败' : result.message,
      );
    }

    if (!mounted) {
      return;
    }
    context.pop();
  }

  Future<void> _launchWithNativeContainer(PlaybackTarget target) async {
    final result = await ref.read(nativePlaybackLauncherProvider).launch(
          target,
          decodeMode: _playbackDecodeMode,
        );
    if (!result.launched) {
      throw _PlayerOpenException(
        result.message.isEmpty ? '原生播放器启动失败' : result.message,
      );
    }

    if (!mounted) {
      return;
    }
    context.pop();
  }

  Future<bool> _tryLaunchWithPerformanceFallback(
    PlaybackTarget target,
  ) async {
    final nativeResult = await ref.read(nativePlaybackLauncherProvider).launch(
          target,
          decodeMode: _playbackDecodeMode,
        );
    if (nativeResult.launched) {
      if (mounted) {
        context.pop();
      }
      return true;
    }

    final result =
        await ref.read(systemPlaybackLauncherProvider).launch(target);
    if (!result.launched) {
      return false;
    }
    if (!mounted) {
      return true;
    }
    context.pop();
    return true;
  }

  String _resolveMpvHardwareDecodeMode() {
    switch (_playbackDecodeMode) {
      case PlaybackDecodeMode.auto:
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
          return 'auto-safe';
        }
        return _prefersAggressiveHardwareDecoding ? 'auto' : 'auto-safe';
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

  Future<void> _openResolvedTargetWithMpv(
    Player player,
    PlaybackTarget target, {
    required DateTime deadline,
    required Completer<String> Function() beginStartupWait,
  }) async {
    final regularMedia = _buildRegularMpvMedia(target);
    if (!target.isIsoLike) {
      _traceWindowsMpv(
        'windows-mpv.open.dispatch',
        fields: {
          'urlScheme': Uri.tryParse(target.streamUrl)?.scheme ?? '',
          'openMode': 'direct',
        },
      );
      await _awaitMpvMediaOpen(
        player,
        regularMedia,
        timeout: _remainingMpvOpenTimeout(deadline),
        startupError: beginStartupWait(),
      );
      return;
    }

    final isoPlans = _buildMpvIsoOpenPlans(target);
    _traceWindowsMpv(
      'windows-mpv.iso.plan',
      fields: {
        'candidateCount': isoPlans.length,
        'discKinds':
            _inferMpvIsoDiscKinds(target).map((kind) => kind.name).join(','),
        'hasHeaders': target.headers.isNotEmpty,
      },
    );
    if (isoPlans.isEmpty) {
      _traceWindowsMpv(
        'windows-mpv.iso.skip-device-mode',
        fields: {
          'urlScheme': Uri.tryParse(target.streamUrl)?.scheme ?? '',
        },
      );
      await _awaitMpvMediaOpen(
        player,
        regularMedia,
        timeout: _remainingMpvOpenTimeout(deadline),
        startupError: beginStartupWait(),
      );
      return;
    }

    Object? lastError;
    for (final plan in isoPlans) {
      try {
        await _applyMpvIsoOpenPlan(player, target, plan);
        _traceWindowsMpv(
          'windows-mpv.open.dispatch',
          fields: {
            'urlScheme': Uri.tryParse(target.streamUrl)?.scheme ??
                Uri.tryParse(plan.deviceSource)?.scheme ??
                '',
            'openMode': 'iso',
            'discKind': plan.discKind.name,
            'deviceProperty': plan.deviceProperty,
            'deviceSourceKind': _describeMpvIsoDeviceSource(plan.deviceSource),
          },
        );
        await _awaitMpvMediaOpen(
          player,
          Media(plan.mediaUri),
          timeout: _remainingMpvOpenTimeout(deadline),
          startupError: beginStartupWait(),
        );
        return;
      } catch (error, stackTrace) {
        lastError = error;
        _traceWindowsMpv(
          'windows-mpv.iso.open-attempt-failed',
          fields: {
            'discKind': plan.discKind.name,
            'deviceProperty': plan.deviceProperty,
            'deviceSourceKind': _describeMpvIsoDeviceSource(plan.deviceSource),
          },
          error: error,
          stackTrace: stackTrace,
        );
        try {
          await player.stop();
        } catch (_) {
          // Ignore stop failures and allow the next ISO fallback to continue.
        }
      }
    }

    _traceWindowsMpv(
      'windows-mpv.iso.fallback-direct',
      fields: {
        'urlScheme': Uri.tryParse(target.streamUrl)?.scheme ?? '',
      },
    );
    try {
      await _resetMpvIsoOpenState(player);
      await _awaitMpvMediaOpen(
        player,
        regularMedia,
        timeout: _remainingMpvOpenTimeout(deadline),
        startupError: beginStartupWait(),
      );
      return;
    } catch (error, stackTrace) {
      if (lastError != null) {
        _traceWindowsMpv(
          'windows-mpv.iso.fallback-direct-failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<void> _awaitMpvMediaOpen(
    Player player,
    Media media, {
    required Duration timeout,
    required Completer<String> startupError,
  }) async {
    await Future.any<void>([
      player.open(media, play: true),
      startupError.future.then<void>((message) {
        throw _PlayerOpenException(message);
      }),
    ]).timeout(timeout);
  }

  Media _buildRegularMpvMedia(PlaybackTarget target) {
    final resource = target.streamUrl.trim().isNotEmpty
        ? target.streamUrl.trim()
        : target.actualAddress.trim();
    final resolvedResource = buildStarflowWebProxyUrl(
      resource,
      headers: target.headers,
    );
    return Media(
      resolvedResource,
      httpHeaders: kIsWeb || target.headers.isEmpty ? null : target.headers,
    );
  }

  Duration _remainingMpvOpenTimeout(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('超过最大等待时间，已停止尝试播放');
    }
    return remaining;
  }

  List<_MpvIsoOpenPlan> _buildMpvIsoOpenPlans(PlaybackTarget target) {
    final deviceSources = <String>[];
    final seen = <String>{};

    void addDeviceSource(String raw) {
      final normalized = _normalizeMpvIsoDeviceSource(raw);
      if (normalized.isEmpty) {
        return;
      }
      final dedupeKey = normalized.toLowerCase();
      if (!seen.add(dedupeKey)) {
        return;
      }
      deviceSources.add(normalized);
    }

    final actualAddress = _normalizeMpvIsoDeviceSource(target.actualAddress);
    final streamUrl = _normalizeMpvIsoDeviceSource(target.streamUrl);
    if (_isLikelyLocalMpvIsoDeviceSource(actualAddress)) {
      addDeviceSource(actualAddress);
    }
    if (_isLikelyLocalMpvIsoDeviceSource(streamUrl)) {
      addDeviceSource(streamUrl);
    }

    final discKinds = _inferMpvIsoDiscKinds(target);
    return [
      for (final deviceSource in deviceSources)
        for (final discKind in discKinds)
          _MpvIsoOpenPlan(
            discKind: discKind,
            deviceSource: deviceSource,
          ),
    ];
  }

  List<_MpvIsoDiscKind> _inferMpvIsoDiscKinds(PlaybackTarget target) {
    final hint = [
      target.container,
      target.streamUrl,
      target.actualAddress,
      target.title,
      target.sourceName,
    ].join(' ').toLowerCase();
    final looksLikeBluray = hint.contains('bluray') ||
        hint.contains('blu-ray') ||
        hint.contains('bdmv') ||
        hint.contains('bdrom');
    final looksLikeDvd = hint.contains('dvd') ||
        hint.contains('video_ts') ||
        hint.contains('vts_');
    if (looksLikeDvd && !looksLikeBluray) {
      return const [_MpvIsoDiscKind.dvd, _MpvIsoDiscKind.bluray];
    }
    return const [_MpvIsoDiscKind.bluray, _MpvIsoDiscKind.dvd];
  }

  String _normalizeMpvIsoDeviceSource(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (_looksLikeWindowsAbsolutePath(trimmed) || _looksLikeUncPath(trimmed)) {
      return trimmed;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      try {
        return uri.toFilePath(
          windows: defaultTargetPlatform == TargetPlatform.windows,
        );
      } catch (_) {
        return trimmed;
      }
    }
    if (uri != null && uri.hasScheme) {
      return uri.toString();
    }
    return trimmed;
  }

  bool _isLikelyLocalMpvIsoDeviceSource(String value) {
    return isLikelyLocalMpvIsoDeviceSource(
      value,
      windowsPlatform: defaultTargetPlatform == TargetPlatform.windows,
      posixPlatform: defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS,
    );
  }

  bool _isLikelyRemoteMpvIsoDeviceSource(String value) {
    final uri = Uri.tryParse(value.trim());
    final scheme = uri?.scheme.toLowerCase() ?? '';
    return switch (scheme) {
      'http' || 'https' || 'rtsp' || 'rtmp' || 'ftp' || 'ftps' => true,
      _ => false,
    };
  }

  bool _looksLikeWindowsAbsolutePath(String value) {
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
  }

  bool _looksLikeUncPath(String value) {
    return value.startsWith(r'\\') || value.startsWith('//');
  }

  Future<void> _applyMpvIsoOpenPlan(
    Player player,
    PlaybackTarget target,
    _MpvIsoOpenPlan plan,
  ) async {
    await _setMpvOption(player, plan.deviceProperty, plan.deviceSource);
    await _setMpvOption(player, plan.otherDeviceProperty, '');
    final headerFields = _isLikelyRemoteMpvIsoDeviceSource(plan.deviceSource)
        ? _encodeMpvHttpHeaderFields(target.headers)
        : '';
    await _setMpvOption(player, 'http-header-fields', headerFields);
  }

  Future<void> _resetMpvIsoOpenState(Player player) async {
    await _setMpvOption(player, 'dvd-device', '');
    await _setMpvOption(player, 'bluray-device', '');
    await _setMpvOption(player, 'http-header-fields', '');
  }

  String _encodeMpvHttpHeaderFields(Map<String, String> headers) {
    return headers.entries
        .where(
          (entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        )
        .map(
          (entry) =>
              '${_escapeMpvListValue(entry.key.trim())}: ${_escapeMpvListValue(entry.value.trim().replaceAll(RegExp(r'[\r\n]+'), ' '))}',
        )
        .join(',');
  }

  String _escapeMpvListValue(String value) {
    return value.replaceAll('\\', r'\\').replaceAll(',', r'\,');
  }

  String _describeMpvIsoDeviceSource(String value) {
    final trimmed = value.trim();
    if (_looksLikeWindowsAbsolutePath(trimmed)) {
      return 'windows-path';
    }
    if (_looksLikeUncPath(trimmed)) {
      return 'unc-path';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      return uri.scheme.toLowerCase();
    }
    if (trimmed.startsWith('/')) {
      return 'posix-path';
    }
    return 'plain-path';
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
      ref.read(isTelevisionProvider).value ?? false;

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
    if (_aggressivePlaybackTuningEnabled) {
      return true;
    }
    if (!_isHeavyPlaybackTarget(target)) {
      return false;
    }
    return _isTelevisionPlaybackDevice ||
        _playbackDecodeMode == PlaybackDecodeMode.softwarePreferred;
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
    );
  }

  Future<void> _syncEmbeddedMpvFullscreen(bool isFullscreen) async {
    if (_isEmbeddedMpvFullscreen == isFullscreen) {
      return;
    }
    _isEmbeddedMpvFullscreen = isFullscreen;
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
    final remoteProfile = resolveMpvRemotePlaybackTuningProfile(
      target: target,
      aggressiveTuning: aggressiveTuning,
      heavyPlayback: heavyPlayback,
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
}
