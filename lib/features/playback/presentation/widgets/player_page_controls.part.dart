// ignore_for_file: invalid_use_of_protected_member

part of '../player_page.dart';

extension _PlayerPageStateControls on _PlayerPageState {
  Future<void> _handleTvBack() async {
    if (!mounted) {
      return;
    }
    if (_error != null) {
      await _requestExitPlayer(reason: 'tv-error-exit');
      return;
    }
    if (_tvPlaybackChromeVisible) {
      _hideTvPlaybackChrome();
      return;
    }
    if (_tvExitDialogVisible) {
      return;
    }

    _tvExitDialogVisible = true;
    final shouldExit = await showDialog<bool>(
          barrierDismissible: false,
          context: context,
          builder: (dialogContext) {
            return PopScope(
              canPop: false,
              child: AlertDialog(
                title: const Text('退出播放'),
                content: const Text('确认退出当前播放吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('继续播放'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('退出'),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;
    _tvExitDialogVisible = false;

    if (!mounted || !shouldExit) {
      return;
    }
    await _requestExitPlayer(reason: 'tv-confirm-exit');
  }

  Future<void> _handleDesktopBack({
    required String reason,
  }) async {
    if (_useWindowManagedEmbeddedMpvFullscreen && _isEmbeddedMpvFullscreen) {
      await _setEmbeddedMpvFullscreen(
        false,
        reason: '$reason-exit-fullscreen',
      );
      return;
    }
    await _requestExitPlayer(reason: reason);
  }

  Future<void> _setEmbeddedMpvFullscreen(
    bool isFullscreen, {
    required String reason,
  }) async {
    if (_isEmbeddedMpvFullscreen == isFullscreen) {
      return;
    }
    _traceWindowsMpv(
      'windows-mpv.overlay.fullscreen-state-request',
      fields: {
        'reason': reason,
        'fullscreenBefore': _isEmbeddedMpvFullscreen,
        'fullscreenAfter': isFullscreen,
      },
    );
    if (_useWindowManagedEmbeddedMpvFullscreen) {
      if (isFullscreen) {
        await defaultEnterNativeFullscreen();
      } else {
        await defaultExitNativeFullscreen();
      }
    }
    await _syncEmbeddedMpvFullscreen(isFullscreen);
  }

  Future<void> _toggleEmbeddedMpvFullscreen() async {
    final fullscreenBefore = _isEmbeddedMpvFullscreen;
    await _setEmbeddedMpvFullscreen(
      !fullscreenBefore,
      reason: 'overlay-toggle',
    );
  }

  Future<void> _togglePlayback() async {
    final player = _player;
    if (!_isReady || player == null) {
      return;
    }
    _traceWindowsMpv(
      'windows-mpv.command.toggle-playback',
      fields: {'playingBefore': player.state.playing},
    );
    await player.playOrPause();
    if (_isTelevisionPlaybackDevice) {
      _showTvPlaybackChrome(autoHide: player.state.playing);
    }
  }

  Future<void> _setPlayWhenReady(bool playing) async {
    final player = _player;
    if (!_isReady || player == null) {
      return;
    }
    _traceWindowsMpv(
      'windows-mpv.command.set-play-when-ready',
      fields: {
        'requestedPlaying': playing,
        'playingBefore': player.state.playing,
      },
    );
    if (playing) {
      await player.play();
    } else {
      await player.pause();
    }
    if (_isTelevisionPlaybackDevice) {
      _showTvPlaybackChrome(autoHide: playing);
    }
    await _syncPlaybackSystemSession(force: true);
  }

  Future<void> _seekRelative(Duration delta) async {
    final player = _player;
    if (!_isReady || player == null) {
      return;
    }
    final current = player.state.position;
    final target = current + delta;
    _traceWindowsMpv(
      'windows-mpv.command.seek-relative',
      fields: {
        'fromMs': current.inMilliseconds,
        'deltaMs': delta.inMilliseconds,
        'toMs': target.inMilliseconds < 0 ? 0 : target.inMilliseconds,
      },
    );
    await player.seek(target < Duration.zero ? Duration.zero : target);
    if (_isTelevisionPlaybackDevice) {
      _showTvPlaybackChrome();
    }
  }

  Future<void> _seekTo(Duration position) async {
    final player = _player;
    if (!_isReady || player == null) {
      return;
    }
    _traceWindowsMpv(
      'windows-mpv.command.seek-to',
      fields: {
        'fromMs': player.state.position.inMilliseconds,
        'toMs': position.inMilliseconds < 0 ? 0 : position.inMilliseconds,
      },
    );
    await player.seek(position < Duration.zero ? Duration.zero : position);
    if (_isTelevisionPlaybackDevice) {
      _showTvPlaybackChrome();
    }
    await _syncPlaybackSystemSession(force: true);
  }

  void _showTvPlaybackChrome({bool autoHide = true}) {
    _tvPlaybackChromeHideTimer?.cancel();
    if (mounted && !_tvPlaybackChromeVisible) {
      setState(() {
        _tvPlaybackChromeVisible = true;
      });
    }
    if (autoHide) {
      _scheduleTvPlaybackChromeHide();
    }
  }

  void _scheduleTvPlaybackChromeHide() {
    _tvPlaybackChromeHideTimer?.cancel();
    _tvPlaybackChromeHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_tvPlaybackChromeVisible) {
        return;
      }
      setState(() {
        _tvPlaybackChromeVisible = false;
      });
    });
  }

  void _hideTvPlaybackChrome() {
    _tvPlaybackChromeHideTimer?.cancel();
    if (!mounted || !_tvPlaybackChromeVisible) {
      return;
    }
    setState(() {
      _tvPlaybackChromeVisible = false;
    });
  }

  Future<void> _openCurrentSubtitleSelector() async {
    final player = _player;
    if (player == null) {
      return;
    }
    await _selectSubtitleTrack(
      player,
      player.state.tracks.subtitle,
      player.state.track.subtitle,
    );
  }

  Future<void> _openCurrentAudioSelector() async {
    final player = _player;
    if (player == null) {
      return;
    }
    await _selectAudioTrack(
      player,
      player.state.tracks.audio,
      player.state.track.audio,
    );
  }

  Future<void> _enterPictureInPictureManually() async {
    if (!_pictureInPictureSupported || _isInPictureInPictureMode) {
      return;
    }
    _traceWindowsMpv('windows-mpv.command.enter-picture-in-picture');
    final size = _currentPictureInPictureAspectRatio();
    await AndroidPictureInPictureController.enter(
      aspectRatioWidth: size.width,
      aspectRatioHeight: size.height,
    );
  }

  Widget _buildVideoSurface(
    ThemeData theme, {
    required bool isTelevision,
    required AppSettings settings,
  }) {
    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '播放失败',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$_error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                if (!isTelevision) ...[
                  const SizedBox(height: 20),
                  StarflowButton(
                    label: '返回',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () {
                      unawaited(
                          _requestExitPlayer(reason: 'error-button-exit'));
                    },
                    variant: StarflowButtonVariant.secondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final player = _player;
    final videoController = _videoController;
    if (!_isReady || player == null || videoController == null) {
      return PlayerStartupOverlay(
        target: _resolvedTarget ?? widget.target,
        speedLabel: _startupProbe.speedLabel,
      );
    }

    final embeddedVideo = RepaintBoundary(
      child: _buildEmbeddedVideo(
        videoController,
        isTelevision: isTelevision,
        settings: settings,
      ),
    );

    return StreamBuilder<int?>(
      stream: player.stream.width,
      initialData: player.state.width,
      builder: (context, widthSnapshot) {
        return StreamBuilder<int?>(
          stream: player.stream.height,
          initialData: player.state.height,
          builder: (context, heightSnapshot) {
            final width = widthSnapshot.data ?? 0;
            final height = heightSnapshot.data ?? 0;
            final aspectRatio =
                width > 0 && height > 0 ? width / height : 16 / 9;
            final viewportSize = MediaQuery.sizeOf(context);
            final expandEmbeddedMpvSurfaceInPortrait =
                !isTelevision && viewportSize.height > viewportSize.width;
            return ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  expandEmbeddedMpvSurfaceInPortrait
                      ? Positioned.fill(child: embeddedVideo)
                      : Center(
                          child: AspectRatio(
                            aspectRatio: aspectRatio,
                            child: embeddedVideo,
                          ),
                        ),
                  if (!_isLeanPlaybackMode)
                    StreamBuilder<bool>(
                      stream: player.stream.buffering,
                      initialData: player.state.buffering,
                      builder: (context, bufferingSnapshot) {
                        final isBuffering = bufferingSnapshot.data ?? false;
                        if (!isBuffering) {
                          return const SizedBox.shrink();
                        }
                        return StreamBuilder<double>(
                          stream: player.stream.bufferingPercentage,
                          initialData: player.state.bufferingPercentage,
                          builder: (context, progressSnapshot) {
                            return IgnorePointer(
                              child: PlayerStartupOverlay(
                                target: _resolvedTarget ?? widget.target,
                                speedLabel: _startupProbe.speedLabel,
                                bufferingProgress: progressSnapshot.data,
                              ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmbeddedVideo(
    VideoController videoController, {
    required bool isTelevision,
    required AppSettings settings,
  }) {
    final useWindowManagedFullscreen =
        !isTelevision && _useWindowManagedEmbeddedMpvFullscreen;
    final video = Video(
      controller: videoController,
      controls: isTelevision || useWindowManagedFullscreen
          ? NoVideoControls
          : (state) {
              final isFullscreen = _isEmbeddedMpvFullscreen;
              return PlayerMpvControlsOverlay(
                isFullscreen: isFullscreen,
                player: videoController.player,
                target: _resolvedTarget ?? widget.target,
                showVolumeSlider: _showDesktopVolumeSliderForMpv,
                preferLightweightChrome: _leanPlaybackUiEnabled,
                traceEnabled: _shouldTraceWindowsMpv,
                onBack: () => _handleDesktopBack(reason: 'overlay-back'),
                onTogglePlayback: _togglePlayback,
                onSeekTo: _seekTo,
                onOpenSubtitle: _openCurrentSubtitleSelector,
                onOpenAudio: _openCurrentAudioSelector,
                onOpenOptions: () => _showPlaybackOptions(
                  isTelevision: false,
                  settings: settings,
                ),
                onToggleFullscreen: () async {
                  final fullscreenBefore = _isEmbeddedMpvFullscreen;
                  _traceWindowsMpv(
                    'windows-mpv.overlay.fullscreen-toggle-request',
                    fields: {'fullscreenBefore': fullscreenBefore},
                  );
                  await state.toggleFullscreen();
                  await _syncEmbeddedMpvFullscreen(!fullscreenBefore);
                },
                onShowPictureInPicture:
                    _pictureInPictureSupported && !_isInPictureInPictureMode
                        ? _enterPictureInPictureManually
                        : null,
                onShowAirPlay:
                    PlaybackSystemSessionController.supportsAirPlayPicker
                        ? _showAirPlayRoutePicker
                        : null,
              );
            },
      fill: Colors.black,
      fit: BoxFit.contain,
      subtitleViewConfiguration: _buildSubtitleViewConfiguration(
        settings,
        isTelevision: isTelevision,
      ),
    );
    if (!useWindowManagedFullscreen) {
      return video;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: video),
        Positioned.fill(
          child: PlayerMpvControlsOverlay(
            isFullscreen: _isEmbeddedMpvFullscreen,
            player: videoController.player,
            target: _resolvedTarget ?? widget.target,
            showVolumeSlider: _showDesktopVolumeSliderForMpv,
            preferLightweightChrome: _leanPlaybackUiEnabled,
            traceEnabled: _shouldTraceWindowsMpv,
            onBack: () => _handleDesktopBack(reason: 'overlay-back'),
            onTogglePlayback: _togglePlayback,
            onSeekTo: _seekTo,
            onOpenSubtitle: _openCurrentSubtitleSelector,
            onOpenAudio: _openCurrentAudioSelector,
            onOpenOptions: () => _showPlaybackOptions(
              isTelevision: false,
              settings: settings,
            ),
            onToggleFullscreen: _toggleEmbeddedMpvFullscreen,
            onShowPictureInPicture:
                _pictureInPictureSupported && !_isInPictureInPictureMode
                    ? _enterPictureInPictureManually
                    : null,
            onShowAirPlay:
                PlaybackSystemSessionController.supportsAirPlayPicker
                    ? _showAirPlayRoutePicker
                    : null,
          ),
        ),
      ],
    );
  }

  bool get _showDesktopVolumeSliderForMpv {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };
  }

  void _bindWindowsMpvTraceStreams(Player player) {
    if (!_shouldTraceWindowsMpv) {
      return;
    }
    _lastTracedVideoWidth = null;
    _lastTracedVideoHeight = null;
    _lastTracedBufferingState = null;
    _lastTracedBufferingBucket = null;
    _traceWindowsMpvVideoDimensions(
      width: player.state.width,
      height: player.state.height,
    );
    _traceWindowsMpvBufferingState(
      player.state.buffering,
      percentage: player.state.bufferingPercentage,
    );
    _playerWidthSubscription = player.stream.width.listen((width) {
      _traceWindowsMpvVideoDimensions(
        width: width,
        height: player.state.height,
      );
    });
    _playerHeightSubscription = player.stream.height.listen((height) {
      _traceWindowsMpvVideoDimensions(
        width: player.state.width,
        height: height,
      );
    });
    _playerBufferingSubscription = player.stream.buffering.listen((buffering) {
      _traceWindowsMpvBufferingState(
        buffering,
        percentage: player.state.bufferingPercentage,
      );
    });
    _playerBufferingPercentageSubscription =
        player.stream.bufferingPercentage.listen((percentage) {
      final bucket = _bufferingTraceBucket(percentage);
      if (bucket == null || bucket == _lastTracedBufferingBucket) {
        return;
      }
      _lastTracedBufferingBucket = bucket;
      _traceWindowsMpv(
        'windows-mpv.player.buffering-progress',
        fields: {
          'buffering': player.state.buffering,
          'percent': bucket,
        },
      );
      _updateTvPlaybackState(bufferingPercentage: percentage);
    });
  }

  void _traceWindowsMpvVideoDimensions({
    required int? width,
    required int? height,
  }) {
    if (!_shouldTraceWindowsMpv) {
      return;
    }
    if (_lastTracedVideoWidth == width && _lastTracedVideoHeight == height) {
      return;
    }
    _lastTracedVideoWidth = width;
    _lastTracedVideoHeight = height;
    _traceWindowsMpv(
      'windows-mpv.player.video-dimensions',
      fields: {
        'width': width ?? 0,
        'height': height ?? 0,
      },
    );
  }

  void _traceWindowsMpvBufferingState(
    bool buffering, {
    required double percentage,
  }) {
    if (!_shouldTraceWindowsMpv) {
      return;
    }
    if (_lastTracedBufferingState == buffering) {
      return;
    }
    _lastTracedBufferingState = buffering;
    if (!buffering) {
      _lastTracedBufferingBucket = null;
    }
    _traceWindowsMpv(
      'windows-mpv.player.buffering-state',
      fields: {
        'buffering': buffering,
        'percent': percentage.toStringAsFixed(1),
      },
    );
  }

  int? _bufferingTraceBucket(double percentage) {
    if (percentage <= 0) {
      return null;
    }
    final normalized = percentage.clamp(0.0, 100.0);
    return (normalized / 10).floor() * 10;
  }

  double _currentAspectRatio() {
    final player = _player;
    if (!_isReady || player == null) {
      return 16 / 9;
    }

    final width = player.state.width ?? 0;
    final height = player.state.height ?? 0;
    if (width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }

  SubtitleViewConfiguration _buildSubtitleViewConfiguration(
    AppSettings settings, {
    required bool isTelevision,
  }) {
    final simplifyForPerformance = settings.effectiveLeanPlaybackUiEnabled(
      isTelevision: isTelevision,
    );
    return SubtitleViewConfiguration(
      style: TextStyle(
        height: 1.35,
        fontSize: (simplifyForPerformance
                ? isTelevision
                    ? 26
                    : 28
                : 32) *
            settings.playbackSubtitleScale.textScale,
        color: Colors.white,
        fontWeight: FontWeight.w600,
        backgroundColor: simplifyForPerformance
            ? Colors.transparent
            : const Color(0xAA000000),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        simplifyForPerformance
            ? isTelevision
                ? 14
                : 18
            : 28,
      ),
    );
  }

  Future<void> _showPlaybackOptions({
    required bool isTelevision,
    required AppSettings settings,
  }) async {
    final player = _player;
    if (player == null || !mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return PlaybackOptionsDialog(
          player: player,
          target: _resolvedTarget ?? widget.target,
          isTelevision: isTelevision,
          defaultSubtitleScaleLabel: settings.playbackSubtitleScale.label,
          subtitleDelayLabel: formatSubtitleDelayLabel(
            _subtitleDelaySeconds,
            supported: _subtitleDelaySupported,
          ),
          seriesSkipLabel: formatSeriesSkipPreferenceLabel(
            _seriesSkipPreference,
            target: _resolvedTarget ?? widget.target,
          ),
          onSelectMpvQualityPreset: _selectPlaybackMpvQualityPreset,
          onSelectSpeed: (currentRate) =>
              _selectPlaybackSpeed(player, currentRate),
          onSelectSubtitle: (tracks, current) =>
              _selectSubtitleTrack(player, tracks, current),
          onSelectAudio: (tracks, current) =>
              _selectAudioTrack(player, tracks, current),
          onSetVolume: (value) => player.setVolume(value),
          onAdjustSubtitleDelay: () => _openSubtitleDelayDialog(player),
          onLoadExternalSubtitle: () => _loadExternalSubtitle(player),
          onSearchSubtitlesOnline: () => _showOnlineSubtitleSearch(
            player,
            _resolvedTarget ?? widget.target,
          ),
          onConfigureSeriesSkip: () => _configureSeriesSkipPreference(player),
        );
      },
    );
  }

  Future<void> _selectPlaybackMpvQualityPreset() async {
    final currentPreset = _playbackMpvQualityPreset;
    final selection = await showDialog<PlaybackMpvQualityPreset>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('MPV 画质策略'),
          children: [
            for (final preset in PlaybackMpvQualityPreset.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(preset),
                child: Text(
                  preset == currentPreset
                      ? '${preset.label}  当前'
                      : preset.label,
                ),
              ),
          ],
        );
      },
    );
    if (selection == null || selection == currentPreset) {
      return;
    }

    await ref
        .read(settingsControllerProvider.notifier)
        .setPlaybackMpvQualityPreset(selection);

    final player = _player;
    final target = _resolvedTarget ?? widget.target;
    if (player != null) {
      await _applyMpvPerformanceTuning(player, target);
    }
    _showMessage('MPV 画质策略已切换为 ${selection.label}');
  }

  Future<void> _selectPlaybackSpeed(Player player, double currentRate) async {
    final selection = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('播放速度'),
          children: [
            for (final rate in _PlayerPageState._kSpeedOptions)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(rate),
                child: Text(
                  rate == currentRate
                      ? '${formatPlaybackSpeed(rate)}  当前'
                      : formatPlaybackSpeed(rate),
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }

    await _runPlayerCommand(
      () => player.setRate(selection),
      failureMessage: '切换播放速度失败',
    );
  }

  Future<void> _selectSubtitleTrack(
    Player player,
    List<SubtitleTrack> tracks,
    SubtitleTrack current,
  ) async {
    final selection = await showDialog<SubtitleTrack>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('字幕选择'),
          children: [
            for (final track in tracks)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(track),
                child: Text(
                  track == current
                      ? '${formatPlaybackSubtitleTrackLabel(track)}  当前'
                      : formatPlaybackSubtitleTrackLabel(track),
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }

    await _runPlayerCommand(
      () => player.setSubtitleTrack(selection),
      failureMessage: '切换字幕失败',
    );
  }

  Future<void> _selectAudioTrack(
    Player player,
    List<AudioTrack> tracks,
    AudioTrack current,
  ) async {
    final selection = await showDialog<AudioTrack>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('音轨选择'),
          children: [
            for (final track in tracks)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(track),
                child: Text(
                  track == current
                      ? '${formatPlaybackAudioTrackLabel(track)}  当前'
                      : formatPlaybackAudioTrackLabel(track),
                ),
              ),
          ],
        );
      },
    );
    if (selection == null) {
      return;
    }

    await _runPlayerCommand(
      () => player.setAudioTrack(selection),
      failureMessage: '切换音轨失败',
    );
  }

  Future<void> _runPlayerCommand(
    Future<void> Function() action, {
    required String failureMessage,
  }) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failureMessage：$error')),
      );
    }
  }
}
