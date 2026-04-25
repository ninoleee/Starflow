// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStateStartupMpvOpen on _PlayerPageState {
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
        if (_isLikelyRemotePlaybackTarget(resolvedTarget)) {
          final backoff = Duration(milliseconds: 650 * attempt);
          await Future<void>.delayed(backoff);
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
    _attachOpeningEmbeddedPlayback(player, videoController);
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
      unawaited(_handleRuntimeMpvError(player, resolvedTarget, normalized));
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
      startupError = Completer<String>();
      await _awaitMpvPrePlayReady(
        player,
        target: resolvedTarget,
        videoController: videoController,
        timeout: _remainingMpvOpenTimeout(deadline),
        startupError: startupError!.future,
      );
      await player.play().timeout(_remainingMpvOpenTimeout(deadline));
      await _awaitStrictPlaybackReady(
        player,
        target: resolvedTarget,
        timeout: _remainingMpvOpenTimeout(deadline),
        startupError: startupError!.future,
        stageLabel: 'open-attempt',
        progressBaseline: player.state.position,
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
      _detachOpeningEmbeddedPlayback(player, videoController);
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

  Future<void> _awaitStrictPlaybackReady(
    Player player, {
    required PlaybackTarget target,
    required Duration timeout,
    required String stageLabel,
    Duration? progressBaseline,
    Future<String>? startupError,
  }) async {
    final deadline = DateTime.now().add(timeout);
    final readyCompleter = Completer<void>();
    final subscriptions = <StreamSubscription<dynamic>>[];
    DateTime? readyCandidateSince;
    final startupFailureFuture = startupError?.then<void>((message) {
      throw _PlayerOpenException(message);
    });
    final baseline = progressBaseline ?? player.state.position;
    final watchdog = MpvStallWatchdog(
      config: _resolveMpvStallWatchdogConfig(target, startupPhase: true),
    );
    final readyConfirmWindow = _resolveStrictReadyConfirmWindow(target);

    void evaluateReady() {
      if (readyCompleter.isCompleted) {
        return;
      }
      if (_isStrictPlaybackReady(
        player,
        target: target,
        progressBaseline: baseline,
      )) {
        readyCandidateSince ??= DateTime.now();
        if (DateTime.now().difference(readyCandidateSince!) <
            readyConfirmWindow) {
          return;
        }
        readyCompleter.complete();
        return;
      }
      readyCandidateSince = null;
    }

    subscriptions.addAll([
      player.stream.position.listen((_) => evaluateReady()),
      player.stream.duration.listen((_) => evaluateReady()),
      player.stream.width.listen((_) => evaluateReady()),
      player.stream.height.listen((_) => evaluateReady()),
      player.stream.playing.listen((_) => evaluateReady()),
      player.stream.buffering.listen((_) => evaluateReady()),
    ]);
    evaluateReady();

    try {
      while (!readyCompleter.isCompleted) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw TimeoutException('播放器打开后长时间没有开始播放');
        }
        final tick = remaining > const Duration(seconds: 1)
            ? const Duration(seconds: 1)
            : remaining;
        final waiters = <Future<void>>[
          readyCompleter.future,
          Future<void>.delayed(tick),
        ];
        if (startupFailureFuture != null) {
          waiters.add(startupFailureFuture);
        }
        await Future.any(waiters);
        if (readyCompleter.isCompleted) {
          break;
        }
        evaluateReady();
        if (readyCompleter.isCompleted) {
          break;
        }
        final decision = watchdog.evaluate(
          MpvPlaybackSnapshot.fromPlayer(player),
        );
        if (!decision.triggered) {
          continue;
        }
        _traceWindowsMpv(
          'windows-mpv.startup.stall-detected',
          fields: {
            'stage': stageLabel,
            'level': decision.level.name,
            'positionMs': decision.position.inMilliseconds,
            'bufferingForMs': decision.bufferingFor.inMilliseconds,
            'stagnantForMs': decision.stagnantFor.inMilliseconds,
            'bufferingPercentage': decision.bufferingPercentage,
            'reason': decision.reason,
          },
        );
        if (!_mpvStallAutoRecoveryEnabled) {
          continue;
        }
        if (decision.level == MpvStallRecoveryLevel.soft) {
          await _attemptSoftMpvStallRecovery(
            player,
            decision,
            stageLabel: '$stageLabel-soft',
          );
          evaluateReady();
          continue;
        }
        throw TimeoutException('播放器启动后持续缓冲且进度未前进，已自动重试');
      }
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  bool _isStrictPlaybackReady(
    Player player, {
    required PlaybackTarget target,
    required Duration progressBaseline,
  }) {
    final state = player.state;
    final isRemote = _isLikelyRemotePlaybackTarget(target);
    final positionDelta = state.position - progressBaseline;
    final hasProgress = positionDelta >=
        (isRemote
            ? const Duration(milliseconds: 450)
            : const Duration(milliseconds: 250));
    final hasMetadata = _hasStrictPlaybackMetadata(player);
    if (isRemote) {
      final hasWarmPlaybackProgress =
          positionDelta >= const Duration(milliseconds: 900);
      return state.playing &&
          hasProgress &&
          (hasMetadata || (!state.buffering && hasWarmPlaybackProgress));
    }
    return state.playing && hasProgress && (hasMetadata || !state.buffering);
  }

  Duration _resolveStrictReadyConfirmWindow(PlaybackTarget target) {
    if (isLikelyQuarkPlaybackTarget(target)) {
      return const Duration(milliseconds: 900);
    }
    if (_isLikelyRemotePlaybackTarget(target)) {
      return const Duration(milliseconds: 750);
    }
    return const Duration(milliseconds: 300);
  }

  bool _shouldRequireMpvFirstFrame(PlaybackTarget target) {
    if ((target.width ?? 0) > 0 || (target.height ?? 0) > 0) {
      return true;
    }
    if (target.videoCodec.trim().isNotEmpty) {
      return true;
    }
    switch (target.container.trim().toLowerCase()) {
      case 'mp3':
      case 'aac':
      case 'm4a':
      case 'flac':
      case 'wav':
      case 'ogg':
      case 'opus':
      case 'wma':
      case 'alac':
        return false;
      default:
        return true;
    }
  }

  Future<void> _awaitMpvPrePlayReady(
    Player player, {
    required PlaybackTarget target,
    required Duration timeout,
    VideoController? videoController,
    Future<String>? startupError,
  }) async {
    if (!_shouldRequireMpvFirstFrame(target)) {
      return;
    }
    final waiters = <Future<void>>[_awaitMpvVisualMetadataReady(player)];
    if (videoController != null) {
      waiters.add(_awaitMpvFirstFrameReady(videoController));
    }
    final readinessFuture = Future.wait<void>(waiters);
    if (startupError == null) {
      await readinessFuture.timeout(timeout);
      return;
    }
    await Future.any<void>([
      readinessFuture,
      startupError.then<void>((message) {
        throw _PlayerOpenException(message);
      }),
    ]).timeout(timeout);
  }

  Future<void> _awaitMpvFirstFrameReady(
    VideoController videoController,
  ) async {
    await videoController.waitUntilFirstFrameRendered;
  }

  Future<void> _awaitMpvVisualMetadataReady(Player player) async {
    if (_hasMpvVisualMetadataReady(player)) {
      return;
    }
    final completer = Completer<void>();
    final subscriptions = <StreamSubscription<dynamic>>[];

    void evaluate() {
      if (completer.isCompleted) {
        return;
      }
      if (_hasMpvVisualMetadataReady(player)) {
        completer.complete();
      }
    }

    subscriptions.addAll([
      player.stream.width.listen((_) => evaluate()),
      player.stream.height.listen((_) => evaluate()),
    ]);
    evaluate();

    try {
      await completer.future;
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  bool _hasStrictPlaybackMetadata(Player player) {
    final state = player.state;
    final width = state.width ?? 0;
    final height = state.height ?? 0;
    return state.duration > Duration.zero || (width > 0 && height > 0);
  }

  void _attachOpeningEmbeddedPlayback(
    Player player,
    VideoController videoController,
  ) {
    if (!mounted) {
      return;
    }
    final nextPosition = player.state.position;
    final nextDuration = player.state.duration;
    final unchanged = identical(_player, player) &&
        identical(_videoController, videoController) &&
        !_isReady &&
        _error == null &&
        _latestPosition == nextPosition &&
        _latestDuration == nextDuration;
    if (unchanged) {
      return;
    }
    if (mounted) {
      setState(() {
        _player = player;
        _videoController = videoController;
        _isReady = false;
        _error = null;
        _latestPosition = nextPosition;
        _latestDuration = nextDuration;
      });
    }
  }

  void _detachOpeningEmbeddedPlayback(
    Player player,
    VideoController videoController,
  ) {
    if (!mounted) {
      return;
    }
    if (!identical(_player, player) || !identical(_videoController, videoController)) {
      return;
    }
    setState(() {
      _player = null;
      _videoController = null;
      _isReady = false;
      _error = null;
      _latestPosition = Duration.zero;
      _latestDuration = Duration.zero;
    });
  }

  bool _hasMpvVisualMetadataReady(Player player) {
    final state = player.state;
    final width = state.width ?? 0;
    final height = state.height ?? 0;
    return width > 0 && height > 0;
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
      player.open(media, play: false),
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
}
