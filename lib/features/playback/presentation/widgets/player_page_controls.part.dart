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
    final shouldExit = await showStarflowActionDialog<bool>(
          context: context,
          title: '退出播放',
          message: '确认退出当前播放吗？',
          barrierDismissible: false,
          allowSystemDismiss: false,
          dialogWrapper: (dialog) => PlaybackMenuTheme(child: dialog),
          actions: const [
            StarflowDialogAction<bool>(
              label: '继续播放',
              value: false,
              icon: Icons.play_arrow_rounded,
              variant: StarflowButtonVariant.ghost,
              autofocus: true,
            ),
            StarflowDialogAction<bool>(
              label: '退出',
              value: true,
              icon: Icons.logout_rounded,
              variant: StarflowButtonVariant.secondary,
            ),
          ],
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
    if (_useWindowManagedEmbeddedMpvFullscreen) {
      if (isFullscreen) {
        await defaultEnterNativeFullscreen();
      } else {
        await defaultExitNativeFullscreen();
      }
    }
    await _syncEmbeddedMpvFullscreen(isFullscreen);
  }

  Future<void> _togglePlayback() async {
    _recoveryIntent.playback(!(_player?.state.playing ?? false));
    final player = _player;
    if (!_isReady || player == null) {
      return;
    }
    await player.playOrPause();
    if (_isTelevisionPlaybackDevice) {
      _showTvPlaybackChrome(autoHide: player.state.playing);
    }
  }

  Future<void> _setPlayWhenReady(bool playing) async {
    _recoveryIntent.playback(playing);
    final player = _player;
    if (!_isReady || player == null) {
      return;
    }
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
    final seekTarget = target < Duration.zero ? Duration.zero : target;
    await player.seek(seekTarget);
    if (_isTelevisionPlaybackDevice) {
      _showTvPlaybackChrome();
    }
  }

  Future<void> _seekTo(Duration position) async {
    final player = _player;
    if (!_isReady || player == null) {
      return;
    }
    final seekTarget = position < Duration.zero ? Duration.zero : position;
    await player.seek(seekTarget);
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
    if (autoHide && !_hasFocusedTvChromeControl) {
      _scheduleTvPlaybackChromeHide();
    }
  }

  void _scheduleTvPlaybackChromeHide() {
    _tvPlaybackChromeHideTimer?.cancel();
    _tvPlaybackChromeHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_tvPlaybackChromeVisible || _hasFocusedTvChromeControl) {
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

  Widget _buildVideoSurface(
    ThemeData theme, {
    required bool isTelevision,
    required AppSettings settings,
  }) {
    if (_error != null) {
      final errorBody = Center(
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
                        _requestExitPlayer(reason: 'error-button-exit'),
                      );
                    },
                    variant: StarflowButtonVariant.secondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      if (isTelevision) {
        return errorBody;
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          errorBody,
          _buildNonTvTransientTopChrome(
            settings: settings,
            showMoreButton: false,
          ),
        ],
      );
    }

    final player = _player;
    final videoController = _videoController;
    if (player == null || videoController == null) {
      final startupOverlay = PlayerStartupOverlay(
        target: _resolvedTarget ?? widget.target,
        networkSpeed: player == null
            ? null
            : MpvNetworkSpeedLabel(
                player: player,
                generation: _startupGeneration,
              ),
      );
      if (isTelevision) {
        return startupOverlay;
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          startupOverlay,
          _buildNonTvTransientTopChrome(
            settings: settings,
            showMoreButton: false,
          ),
        ],
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
            return ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PlayerEmbeddedSurface(
                    isTelevision: isTelevision,
                    aspectRatio: aspectRatio,
                    child: embeddedVideo,
                  ),
                  _buildEmbeddedMpvSurfaceOverlay(
                    player,
                    isTelevision: isTelevision,
                    videoWidth: width,
                    videoHeight: height,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmbeddedMpvSurfaceOverlay(
    Player player, {
    required bool isTelevision,
    required int videoWidth,
    required int videoHeight,
  }) {
    if (_isReady) {
      if (_isLeanPlaybackMode) {
        return const SizedBox.shrink();
      }
      return StreamBuilder<bool>(
        stream: player.stream.buffering,
        initialData: player.state.buffering,
        builder: (context, bufferingSnapshot) {
          final isBuffering = bufferingSnapshot.data ?? false;
          final phase = resolvePlaybackPhase(
            ready: _isReady,
            playing: player.state.playing,
            buffering: isBuffering,
            ended: player.state.completed,
            failed: _error != null,
          );
          if (!phase.showsLoading) {
            return const SizedBox.shrink();
          }
          return StreamBuilder<double>(
            stream: player.stream.bufferingPercentage,
            initialData: player.state.bufferingPercentage,
            builder: (context, progressSnapshot) {
              return IgnorePointer(
                child: PlayerStartupOverlay(
                  target: _resolvedTarget ?? widget.target,
                  networkSpeed: MpvNetworkSpeedLabel(
                    player: player,
                    generation: _startupGeneration,
                  ),
                  bufferingProgress: progressSnapshot.data,
                  showSpinner: isTelevision,
                ),
              );
            },
          );
        },
      );
    }

    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, playingSnapshot) {
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, positionSnapshot) {
            final hasVideoDimensions = videoWidth > 0 && videoHeight > 0;
            final isPlaying = playingSnapshot.data ?? player.state.playing;
            final position = positionSnapshot.data ?? player.state.position;
            final hasPlaybackProgress =
                position >= const Duration(milliseconds: 250);
            final playbackIsVisible =
                hasVideoDimensions && (isPlaying || hasPlaybackProgress);
            if (playbackIsVisible) {
              return const KeyedSubtree(
                key: ValueKey<String>('player:first-frame'),
                child: SizedBox.shrink(),
              );
            }
            return Positioned.fill(
              child: IgnorePointer(
                ignoring: !isTelevision,
                child: PlayerStartupOverlay(
                  target: _resolvedTarget ?? widget.target,
                  networkSpeed: MpvNetworkSpeedLabel(
                    player: player,
                    generation: _startupGeneration,
                  ),
                  showSpinner: isTelevision,
                ),
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
    final video = Video(
      controller: videoController,
      pauseUponEnteringBackgroundMode: !_backgroundPlaybackEnabled,
      controls: (state) {
        final controls = isTelevision
            ? const SizedBox.shrink()
            : _EmbeddedMpvFullscreenControlsBridge(
                onFullscreenChanged:
                    _handleObservedEmbeddedMpvFullscreenChanged,
                child: _buildAdaptiveEmbeddedVideoControls(
                  state,
                  settings: settings,
                ),
              );
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildMpvSubtitleOverlay(
              videoController.player,
              settings: settings,
            ),
            controls,
          ],
        );
      },
      fill: Colors.black,
      fit: _resolvedVideoBoxFit(),
      aspectRatio: _resolvedVideoAspectRatioOverride(),
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        visible: false,
      ),
    );
    return video;
  }

  Widget _buildMpvSubtitleOverlay(
    Player player, {
    required AppSettings settings,
  }) {
    final simplifyForPerformance = settings.effectiveLeanPlaybackUiEnabled(
      isTelevision: _isTelevisionPlaybackDevice,
    );
    final shadows = _buildSubtitleOutlineShadows(
      simplifyForPerformance: simplifyForPerformance,
    );
    return IgnorePointer(
      child: StreamBuilder<List<String>>(
        stream: player.stream.subtitle,
        initialData: player.state.subtitle,
        builder: (context, snapshot) {
          final subtitles = snapshot.data ?? const <String>[];
          final primary = subtitles.isNotEmpty ? subtitles[0].trim() : '';
          final secondary = subtitles.length > 1 ? subtitles[1].trim() : '';
          return Stack(
            fit: StackFit.expand,
            children: [
              if (primary.isNotEmpty && !_mpvBitmapSubtitle)
                _MpvPositionedSubtitleText(
                  text: primary,
                  positionPercent: _sessionPrimarySubtitlePosition,
                  fontSize: settings.playbackSubtitleScale,
                  shadows: shadows,
                ),
              if (_mpvDualSubtitleEnabled && secondary.isNotEmpty)
                _MpvPositionedSubtitleText(
                  text: secondary,
                  positionPercent: _sessionSecondarySubtitlePosition,
                  fontSize: settings.playbackSubtitleScale *
                      (_sessionSecondarySubtitleScale / 100),
                  shadows: shadows,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdaptiveEmbeddedVideoControls(
    VideoState state, {
    required AppSettings settings,
  }) {
    return PlayerAdaptiveControlsLayout(
      state: state,
      controlsKey:
          ValueKey('adaptive-controls-$_adaptiveGestureLevelsRevision'),
      materialThemeBuilder: (padding) =>
          _buildAdaptiveMaterialControlsThemeData(
        settings: settings,
        state: state,
        padding: padding,
      ),
      desktopThemeBuilder: (padding) => _buildAdaptiveDesktopControlsThemeData(
        settings: settings,
        state: state,
        padding: padding,
      ),
    );
  }

  MaterialVideoControlsThemeData _buildAdaptiveMaterialControlsThemeData({
    required AppSettings settings,
    required VideoState state,
    required EdgeInsets padding,
  }) {
    final materialTopButtonBar = _buildAdaptiveMaterialTopButtonBar(
      state,
      settings: settings,
    );
    final enableVerticalGestureControls = _supportsAdaptiveVerticalGestures;
    return MaterialVideoControlsThemeData(
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
      volumeGesture: enableVerticalGestureControls,
      brightnessGesture: enableVerticalGestureControls,
      seekGesture: _mpvSwipeToSeekEnabled,
      seekOnDoubleTap: _mpvDoubleTapToSeekEnabled,
      seekOnDoubleTapEnabledWhileControlsVisible: _mpvDoubleTapToSeekEnabled,
      speedUpOnLongPress: _mpvLongPressSpeedBoostEnabled,
      onVolumeChanged: enableVerticalGestureControls
          ? _handleAdaptiveVolumeGestureChanged
          : null,
      initialVolume: _adaptiveGestureVolume,
      onBrightnessChanged: enableVerticalGestureControls
          ? _handleAdaptiveBrightnessGestureChanged
          : null,
      initialBrightness: _adaptiveGestureBrightness,
      backdropColor: const Color(0x33000000),
      padding: EdgeInsets.zero,
      buttonBarHeight: playbackButtonBarHeight,
      primaryButtonBar: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: padding.left, right: padding.right),
            child: Row(children: _buildAdaptiveMaterialPrimaryButtonBar()),
          ),
        ),
      ],
      topButtonBar: materialTopButtonBar,
      topButtonBarMargin: padding.copyWith(bottom: 0),
      bottomButtonBarMargin: padding.copyWith(top: 0),
      seekBarMargin: padding.copyWith(top: 0) + playbackSeekBarMargin,
    );
  }

  MaterialDesktopVideoControlsThemeData _buildAdaptiveDesktopControlsThemeData({
    required AppSettings settings,
    required VideoState state,
    required EdgeInsets padding,
  }) {
    final desktopTopButtonBar = _buildAdaptiveDesktopTopButtonBar(
      state,
      settings: settings,
    );
    return MaterialDesktopVideoControlsThemeData(
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
      padding: EdgeInsets.zero,
      buttonBarHeight: playbackButtonBarHeight,
      topButtonBar: desktopTopButtonBar,
      topButtonBarMargin: padding.copyWith(bottom: 0),
      bottomButtonBarMargin: padding.copyWith(top: 0),
      bottomButtonBar: _buildAdaptiveDesktopBottomButtonBar(),
      seekBarMargin: EdgeInsets.only(left: padding.left, right: padding.right) +
          playbackSeekBarMargin,
    );
  }

  bool get _supportsAdaptiveVerticalGestures {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _bindAdaptiveGestureSystemLevels() async {
    if (!_supportsAdaptiveVerticalGestures) {
      return;
    }
    final brightness = await _readSystemBrightnessLevel();
    final volume = await _readSystemVolumeLevel();
    if (!mounted) {
      return;
    }
    final brightnessChanged = brightness != null &&
        (_adaptiveGestureBrightness - brightness).abs() >= 0.01;
    final volumeChanged =
        volume != null && (_adaptiveGestureVolume - volume).abs() >= 0.01;
    if (!brightnessChanged && !volumeChanged) {
      return;
    }
    setState(() {
      if (brightnessChanged) {
        _adaptiveGestureBrightness = brightness;
      }
      if (volumeChanged) {
        _adaptiveGestureVolume = volume;
      }
      _adaptiveGestureLevelsRevision++;
    });
  }

  Future<double?> _readSystemBrightnessLevel() async {
    try {
      final raw = await _PlayerPageState._platformChannel.invokeMethod<num>(
        'getSystemBrightnessLevel',
      );
      if (raw == null) {
        return null;
      }
      return raw.toDouble().clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  Future<double?> _readSystemVolumeLevel() async {
    try {
      final raw = await _PlayerPageState._platformChannel.invokeMethod<num>(
        'getSystemVolumeLevel',
      );
      if (raw == null) {
        return null;
      }
      return raw.toDouble().clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  Future<void> _setSystemBrightnessLevel(double value) async {
    try {
      await _PlayerPageState._platformChannel.invokeMethod<void>(
        'setSystemBrightnessLevel',
        {
          'value': value.clamp(0.0, 1.0),
        },
      );
    } catch (_) {
      // System-level gesture must not crash playback page.
    }
  }

  Future<void> _setSystemVolumeLevel(double value) async {
    try {
      await _PlayerPageState._platformChannel.invokeMethod<void>(
        'setSystemVolumeLevel',
        {
          'value': value.clamp(0.0, 1.0),
        },
      );
    } catch (_) {
      // System-level gesture must not crash playback page.
    }
  }

  void _handleAdaptiveVolumeGestureChanged(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if ((_adaptiveGestureVolume - clamped).abs() < 0.01) {
      return;
    }
    _adaptiveGestureVolume = clamped;
    unawaited(_setSystemVolumeLevel(clamped));
  }

  void _handleAdaptiveBrightnessGestureChanged(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if ((_adaptiveGestureBrightness - clamped).abs() < 0.01) {
      return;
    }
    _adaptiveGestureBrightness = clamped;
    unawaited(_setSystemBrightnessLevel(clamped));
  }

  List<Widget> _buildAdaptiveMaterialTopButtonBar(
    VideoState state, {
    required AppSettings settings,
  }) {
    return [
      Tooltip(
        message: '返回',
        child: MaterialCustomButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            unawaited(_handleAdaptiveControlsBack(state));
          },
        ),
      ),
      MpvNetworkSpeedLabel(
        player: state.widget.controller.player,
        generation: _startupGeneration,
      ),
      const Spacer(),
      if (_hasPlaybackEpisodeQueue)
        Tooltip(
          message: '选集',
          child: MaterialCustomButton(
            icon: const Icon(Icons.playlist_play_rounded),
            onPressed: () {
              unawaited(
                _openPlaybackEpisodePicker(isTelevision: false),
              );
            },
          ),
        ),
      Tooltip(
        message: '更多',
        child: MaterialCustomButton(
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: () {
            unawaited(
              _showPlaybackOptions(
                isTelevision: false,
              ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildAdaptiveDesktopTopButtonBar(
    VideoState state, {
    required AppSettings settings,
  }) {
    return [
      Tooltip(
        message: '返回',
        child: MaterialDesktopCustomButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            unawaited(_handleAdaptiveControlsBack(state));
          },
        ),
      ),
      MpvNetworkSpeedLabel(
        player: state.widget.controller.player,
        generation: _startupGeneration,
      ),
      const Spacer(),
      if (_hasPlaybackEpisodeQueue)
        Tooltip(
          message: '选集',
          child: MaterialDesktopCustomButton(
            icon: const Icon(Icons.playlist_play_rounded),
            onPressed: () {
              unawaited(
                _openPlaybackEpisodePicker(isTelevision: false),
              );
            },
          ),
        ),
      Tooltip(
        message: '更多',
        child: MaterialDesktopCustomButton(
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: () {
            unawaited(
              _showPlaybackOptions(
                isTelevision: false,
              ),
            );
          },
        ),
      ),
    ];
  }

  bool get _hasPlaybackEpisodeQueue {
    final queue = _episodeQueue;
    return queue != null && queue.entries.isNotEmpty && queue.hasCurrent;
  }

  Widget _buildEpisodeQueueControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    double iconSize = 26,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: iconSize,
        color: Colors.white,
        disabledColor: Colors.white.withValues(alpha: 0.30),
      ),
    );
  }

  List<Widget> _buildAdaptiveMaterialPrimaryButtonBar() {
    final queue = _episodeQueue;
    final showEpisodeControls = _hasPlaybackEpisodeQueue;
    return <Widget>[
      const Spacer(flex: 2),
      if (showEpisodeControls) ...[
        _buildEpisodeQueueControlButton(
          icon: Icons.skip_previous_rounded,
          tooltip: '上一集',
          onPressed: queue?.hasPrevious == true
              ? () {
                  unawaited(
                    _movePlaybackQueue(
                      forward: false,
                      reason: 'mobile-control-previous',
                    ),
                  );
                }
              : null,
          iconSize: 30,
        ),
        const Spacer(),
      ],
      const MaterialPlayOrPauseButton(iconSize: 48),
      if (showEpisodeControls) ...[
        const Spacer(),
        _buildEpisodeQueueControlButton(
          icon: Icons.skip_next_rounded,
          tooltip: '下一集',
          onPressed: queue?.hasNext == true
              ? () {
                  unawaited(
                    _movePlaybackQueue(
                      forward: true,
                      reason: 'mobile-control-next',
                    ),
                  );
                }
              : null,
          iconSize: 30,
        ),
      ],
      const Spacer(flex: 2),
    ];
  }

  List<Widget> _buildAdaptiveDesktopBottomButtonBar() {
    final queue = _episodeQueue;
    final showEpisodeControls = _hasPlaybackEpisodeQueue;
    return <Widget>[
      if (showEpisodeControls)
        _buildEpisodeQueueControlButton(
          icon: Icons.skip_previous_rounded,
          tooltip: '上一集',
          onPressed: queue?.hasPrevious == true
              ? () {
                  unawaited(
                    _movePlaybackQueue(
                      forward: false,
                      reason: 'desktop-control-previous',
                    ),
                  );
                }
              : null,
        ),
      const MaterialDesktopPlayOrPauseButton(),
      if (showEpisodeControls)
        _buildEpisodeQueueControlButton(
          icon: Icons.skip_next_rounded,
          tooltip: '下一集',
          onPressed: queue?.hasNext == true
              ? () {
                  unawaited(
                    _movePlaybackQueue(
                      forward: true,
                      reason: 'desktop-control-next',
                    ),
                  );
                }
              : null,
        ),
      const MaterialDesktopVolumeButton(),
      const MaterialDesktopPositionIndicator(),
      const Spacer(),
      const MaterialDesktopFullscreenButton(),
    ];
  }

  Widget _buildNonTvTransientTopChrome({
    required AppSettings settings,
    bool showMoreButton = true,
  }) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _adaptiveTopChromeController.pingActivity,
        child: PlayerAdaptiveTopChrome(
          controller: _adaptiveTopChromeController,
          onBack: () {
            unawaited(
              _handleDesktopBack(reason: 'transient-top-chrome-back'),
            );
          },
          onMore: showMoreButton
              ? () {
                  unawaited(
                    _showPlaybackOptions(
                      isTelevision: false,
                    ),
                  );
                }
              : null,
        ),
      ),
    );
  }

  Future<void> _handleAdaptiveControlsBack(VideoState state) async {
    if (_isEmbeddedMpvFullscreen) {
      state.toggleFullscreen();
      if (_useWindowManagedEmbeddedMpvFullscreen) {
        await _setEmbeddedMpvFullscreen(
          false,
          reason: 'adaptive-controls-back',
        );
      }
      return;
    }
    await _handleDesktopBack(reason: 'adaptive-controls-back');
  }

  void _handleObservedEmbeddedMpvFullscreenChanged(bool isFullscreen) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isEmbeddedMpvFullscreen == isFullscreen) {
        return;
      }
      unawaited(_syncEmbeddedMpvFullscreen(isFullscreen));
    });
  }

  void _bindMpvBufferingStreams(Player player) {
    _lastTracedBufferingState = null;
    _lastTracedBufferingBucket = null;
    _recordMpvBufferingState(player.state.buffering);
    _mpvPerformanceTracker?.onBufferingChanged(player.state.buffering);
    _mpvLifecycle.listen(player.stream.buffering, (buffering) {
      if (!identical(_player, player)) {
        return;
      }
      _mpvPerformanceTracker?.onBufferingChanged(buffering);
      if (buffering && player.state.playing) {
        unawaited(_logMpvPlaybackHealth(player, 'buffering'));
      }
      _recordMpvBufferingState(buffering);
    });
    _mpvLifecycle.listen(player.stream.bufferingPercentage, (percentage) {
      final bucket = _bufferingTraceBucket(percentage);
      if (bucket == null || bucket == _lastTracedBufferingBucket) {
        return;
      }
      _lastTracedBufferingBucket = bucket;
      if (_shouldUpdatePlaybackVisualState) {
        _updateTvPlaybackState(bufferingPercentage: percentage);
      }
    });
  }

  void _recordMpvBufferingState(bool buffering) {
    if (_lastTracedBufferingState == buffering) {
      return;
    }
    _lastTracedBufferingState = buffering;
    if (!buffering) {
      _lastTracedBufferingBucket = null;
    }
    if (!appLogger.isRecording(AppLogLevel.info)) return;
    final player = _player;
    appLogInfo('playback.reliability', 'Playback state', fields: {
      'engine': 'mpv',
      'policyVersion': PlaybackPolicyValues.version,
      'phase': resolvePlaybackPhase(
        ready: _isReady,
        playing: player?.state.playing ?? false,
        buffering: buffering,
        ended: player?.state.completed ?? false,
        failed: _error != null,
      ).name,
      'positionMs': player?.state.position.inMilliseconds ?? 0,
    });
  }

  int? _bufferingTraceBucket(double percentage) {
    if (percentage <= 0) {
      return null;
    }
    final normalized = percentage.clamp(0.0, 100.0);
    return (normalized / 10).floor() * 10;
  }

  double _currentAspectRatio() {
    final aspectRatioOverride = _resolvedVideoAspectRatioOverride();
    if (aspectRatioOverride != null && aspectRatioOverride > 0) {
      return aspectRatioOverride;
    }
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

  BoxFit _resolvedVideoBoxFit() {
    return BoxFit.contain;
  }

  double? _resolvedVideoAspectRatioOverride() {
    return null;
  }

  List<Shadow> _buildSubtitleOutlineShadows({
    required bool simplifyForPerformance,
  }) {
    const strongOutline = Color(0xE0000000);
    const softOutline = Color(0xB0000000);
    if (simplifyForPerformance) {
      return const [
        Shadow(color: strongOutline, offset: Offset(-1.2, 0), blurRadius: 0),
        Shadow(color: strongOutline, offset: Offset(1.2, 0), blurRadius: 0),
        Shadow(color: strongOutline, offset: Offset(0, -1.2), blurRadius: 0),
        Shadow(color: strongOutline, offset: Offset(0, 1.2), blurRadius: 0),
      ];
    }
    return const [
      Shadow(color: strongOutline, offset: Offset(-1.4, 0), blurRadius: 0),
      Shadow(color: strongOutline, offset: Offset(1.4, 0), blurRadius: 0),
      Shadow(color: strongOutline, offset: Offset(0, -1.4), blurRadius: 0),
      Shadow(color: strongOutline, offset: Offset(0, 1.4), blurRadius: 0),
      Shadow(color: softOutline, offset: Offset(-1.0, -1.0), blurRadius: 0),
      Shadow(color: softOutline, offset: Offset(1.0, -1.0), blurRadius: 0),
      Shadow(color: softOutline, offset: Offset(-1.0, 1.0), blurRadius: 0),
      Shadow(color: softOutline, offset: Offset(1.0, 1.0), blurRadius: 0),
    ];
  }

  Future<void> _showPlaybackOptions({
    required bool isTelevision,
  }) async {
    final player = _player;
    if (player == null || !mounted) {
      return;
    }

    await showPlaybackMenuDialog<void>(
      context: context,
      builder: (context) {
        final settings = _playbackSettings;
        return PlaybackOptionsDialog(
          player: player,
          target: _resolvedTarget ?? widget.target,
          isTelevision: isTelevision,
          subtitleDelayLabel: formatSubtitleDelayLabel(
            _subtitleDelaySeconds,
            supported: _subtitleDelaySupported,
          ),
          seriesSkipLabel: formatSeriesSkipPreferenceLabel(
            _seriesSkipPreference,
            target: _resolvedTarget ?? widget.target,
          ),
          onSelectSubtitle: (tracks, current) =>
              _selectSubtitleTrack(player, tracks, current),
          onSelectAudio: (tracks, current) =>
              _selectAudioTrack(player, tracks, current),
          onAdjustSubtitleDelay: () => _openSubtitleDelayDialog(player),
          onLoadExternalSubtitle: () => _loadExternalSubtitle(player),
          onSearchSubtitlesOnline: () => _showOnlineSubtitleSearch(
            player,
            _resolvedTarget ?? widget.target,
          ),
          onConfigureSeriesSkip: () => _configureSeriesSkipPreference(player),
          onSelectVersion:
              supportsPlaybackVariants(_resolvedTarget ?? widget.target)
              ? () async {
                  Navigator.of(context).pop();
                  await _selectPlaybackVersion(player, isTelevision);
                }
              : null,
          onSelectQuality: (quality) => _switchFntvPlaybackQuality(
            player,
            quality,
          ),
          runtimeSettings: PlaybackMpvRuntimeSettings(
            backgroundPlaybackEnabled: _backgroundPlaybackEnabled,
            doubleTapToSeekEnabled: settings.playbackMpvDoubleTapToSeekEnabled,
            swipeToSeekEnabled: settings.playbackMpvSwipeToSeekEnabled,
            longPressSpeedBoostEnabled:
                settings.playbackMpvLongPressSpeedBoostEnabled,
            stallAutoRecoveryEnabled:
                settings.playbackMpvStallAutoRecoveryEnabled,
            aggressiveTuningEnabled:
                settings.performanceAggressivePlaybackTuningEnabled,
            subtitleScale: settings.playbackSubtitleScale,
            primarySubtitlePosition: _sessionPrimarySubtitlePosition,
            secondarySubtitlePosition: _sessionSecondarySubtitlePosition,
            secondarySubtitleScale: _sessionSecondarySubtitleScale,
          ),
          onApplyRuntimeSettings: (next) =>
              _applyMpvRuntimeSettings(player, next),
        );
      },
    );
  }

  Future<void> _applyMpvRuntimeSettings(
    Player player,
    PlaybackMpvRuntimeSettings next,
  ) async {
    final previous = _playbackSettings;
    if (mounted) {
      setState(() {
        _sessionPrimarySubtitlePosition = next.primarySubtitlePosition;
        _sessionSecondarySubtitlePosition = next.secondarySubtitlePosition;
        _sessionSecondarySubtitleScale = next.secondarySubtitleScale;
      });
    }
    await ref
        .read(settingsControllerProvider.notifier)
        .savePlaybackRuntimePreferences(
          backgroundPlaybackEnabled: next.backgroundPlaybackEnabled,
          doubleTapToSeekEnabled: next.doubleTapToSeekEnabled,
          swipeToSeekEnabled: next.swipeToSeekEnabled,
          longPressSpeedBoostEnabled: next.longPressSpeedBoostEnabled,
          stallAutoRecoveryEnabled: next.stallAutoRecoveryEnabled,
          aggressiveTuningEnabled: next.aggressiveTuningEnabled,
          subtitleScale: next.subtitleScale,
          primarySubtitlePosition: next.primarySubtitlePosition,
          secondarySubtitlePosition: next.secondarySubtitlePosition,
          secondarySubtitleScale: next.secondarySubtitleScale,
        );
    await _applyMpvSubtitleLayout(player);
    if (previous.performanceAggressivePlaybackTuningEnabled !=
        next.aggressiveTuningEnabled) {
      await _applyMpvPerformanceTuning(
        player,
        _resolvedTarget ?? widget.target,
      );
    }
    if (previous.playbackMpvStallAutoRecoveryEnabled !=
        next.stallAutoRecoveryEnabled) {
      if (next.stallAutoRecoveryEnabled) {
        _startMpvStallWatchdog(player, _resolvedTarget ?? widget.target);
      } else {
        _stopMpvStallWatchdog();
      }
    }
    await _syncBackgroundPlayback(enabled: player.state.playing);
    await _syncPlaybackSystemSession(force: true);
  }

  Future<void> _selectSubtitleTrack(
    Player player,
    List<SubtitleTrack> tracks,
    SubtitleTrack current,
  ) async {
    final revision = ++_manualTrackRevision;
    bool isCurrent() =>
        mounted && identical(_player, player) && revision == _manualTrackRevision;
    final target = _resolvedTarget ?? widget.target;
    if (target.isFntvTranscoding) {
      final selected = await showPlaybackMenuDialog<String>(
          context: context,
          builder: (context) =>
              SimpleDialog(title: const Text('字幕选择'), children: [
                TvDialogOption(
                    isTelevision: _isTelevisionPlaybackDevice,
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('关闭')),
                for (final stream in target.subtitleStreams)
                  TvDialogOption(
                      isTelevision: _isTelevisionPlaybackDevice,
                      onPressed: () => Navigator.pop(context, stream.id),
                      child: Text(_formatServerSubtitleStreamLabel(stream))),
              ]));
      if (selected != null && isCurrent()) {
        await _switchFntvPlayback(
            player, target.copyWith(preferredSubtitleStreamId: selected));
      }
      return;
    }
    final externalSubtitleStreams = target.subtitleStreams
        .where((stream) => stream.isExternal && stream.id.trim().isNotEmpty)
        .toList(growable: false);
    final selection = await showPlaybackMenuDialog<Object>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('字幕选择'),
          children: [
            TvDialogOption(
              isTelevision: _isTelevisionPlaybackDevice,
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(
                _MpvSubtitleSelectionMode.globalDefault,
              ),
              child: const Text('使用全局默认'),
            ),
            if (!kIsWeb)
              TvDialogOption(
                isTelevision: _isTelevisionPlaybackDevice,
                onPressed: () => Navigator.of(dialogContext).pop(
                  _MpvSubtitleSelectionMode.dual,
                ),
                child: Text(
                  _mpvDualSubtitleEnabled ? '特殊：双字幕模式  当前' : '特殊：双字幕模式',
                ),
              ),
            for (final track in tracks.where((track) => track.id != 'auto'))
              TvDialogOption(
                isTelevision: _isTelevisionPlaybackDevice,
                onPressed: () => Navigator.of(dialogContext).pop(track),
                child: Text(
                  track == current
                      ? '${formatPlaybackSubtitleTrackLabel(track)}  当前'
                      : formatPlaybackSubtitleTrackLabel(track),
                ),
              ),
            for (final stream in externalSubtitleStreams)
              TvDialogOption(
                isTelevision: _isTelevisionPlaybackDevice,
                onPressed: () => Navigator.of(dialogContext).pop(
                  _ServerSubtitleSelection(stream),
                ),
                child: Text(_formatServerSubtitleStreamLabel(stream)),
              ),
          ],
        );
      },
    );
    if (selection == null || !isCurrent()) {
      return;
    }

    if (selection == _MpvSubtitleSelectionMode.dual) {
      await _selectMpvDualSubtitleTracks(player, tracks);
      return;
    }
    if (selection == _MpvSubtitleSelectionMode.globalDefault) {
      final applied = await _runPlayerCommand(
        () => _applyGlobalMpvSubtitlePreference(
          player,
          _resolvedTarget ?? widget.target,
        ),
        failureMessage: '恢复全局字幕设置失败',
      );
      if (applied) {
        _showMessage('已使用全局默认字幕');
      }
      return;
    }
    if (selection is _ServerSubtitleSelection) {
      final selectedTarget = target.copyWith(
        preferredSubtitleStreamId: selection.stream.id,
      );
      final applied = await _runPlayerCommand(
        () => _applyServerExternalSubtitle(
          player,
          selectedTarget,
          selection.stream,
        ),
        failureMessage: '加载飞牛字幕失败',
      );
      if (applied && isCurrent()) {
        setState(() {
          _resolvedTarget = selectedTarget;
        });
        await _persistMpvSeriesSubtitlePreference(target, null);
      }
      return;
    }

    final selectedTrack = selection as SubtitleTrack;
    await _disableMpvDualSubtitle(player);

    final applied = await _runPlayerCommand(
      () => player.setSubtitleTrack(selectedTrack),
      failureMessage: '切换字幕失败',
    );
    if (!applied) {
      return;
    }

    final selectedServerStream = matchPlaybackSubtitleStreamForTrack(
      target: target,
      tracks: tracks,
      track: selectedTrack,
    );
    if ((selectedServerStream != null || selectedTrack.id == 'no') && mounted) {
      setState(() {
        _resolvedTarget = target.copyWith(
          preferredSubtitleStreamId: selectedServerStream?.id ?? '',
          fntvTrackSelectionExplicit: true,
        );
      });
    }
    if (!selectedTrack.uri && !selectedTrack.data) {
      _subtitleSessionPreference = switch (selectedTrack.id) {
        'auto' => null,
        'no' => const PlaybackSubtitleSessionPreference.off(),
        _ => PlaybackSubtitleSessionPreference.single(selectedTrack),
      };
      await _persistMpvSeriesSubtitlePreference(
        _resolvedTarget ?? widget.target,
        _subtitleSessionPreference,
      );
    } else {
      _subtitleSessionPreference = null;
    }
  }

  Future<void> _selectMpvDualSubtitleTracks(
    Player player,
    List<SubtitleTrack> tracks,
  ) async {
    final candidates =
        tracks.where(_canUseMpvDualSubtitleTrack).toList(growable: false);
    if (candidates.length < 2) {
      _showMessage('双字幕模式至少需要两条文本字幕');
      return;
    }

    final primaryCandidates = [...candidates]..sort((left, right) {
        final rightScore = scorePreferredSubtitleText(
          '${right.title ?? ''} ${right.language ?? ''}',
          configuredLanguages: const ['zh-cn', 'zh-tw', 'zh'],
        );
        final leftScore = scorePreferredSubtitleText(
          '${left.title ?? ''} ${left.language ?? ''}',
          configuredLanguages: const ['zh-cn', 'zh-tw', 'zh'],
        );
        return rightScore.compareTo(leftScore);
      });
    final primary = await _showMpvSubtitleTrackPicker(
      title: '双字幕：选择上方中文',
      tracks: primaryCandidates,
    );
    if (primary == null || !mounted) {
      return;
    }

    final secondaryCandidates =
        candidates.where((track) => track != primary).toList(growable: false)
          ..sort((left, right) {
            final rightScore = scorePreferredSubtitleText(
              '${right.title ?? ''} ${right.language ?? ''}',
              configuredLanguages: const ['en'],
            );
            final leftScore = scorePreferredSubtitleText(
              '${left.title ?? ''} ${left.language ?? ''}',
              configuredLanguages: const ['en'],
            );
            return rightScore.compareTo(leftScore);
          });
    final secondary = await _showMpvSubtitleTrackPicker(
      title: '双字幕：选择下方英文',
      tracks: secondaryCandidates,
    );
    if (secondary == null) {
      return;
    }

    final applied = await _runPlayerCommand(
      () async {
        await player.setSubtitleTrack(primary);
        await _setMpvSubtitleProperty(player, 'secondary-sid', secondary.id);
        await _applyMpvSubtitleLayout(player);
      },
      failureMessage: '开启双字幕失败',
    );
    if (!applied || !mounted) {
      return;
    }
    setState(() {
      _mpvDualSubtitleEnabled = true;
    });
    _subtitleSessionPreference = PlaybackSubtitleSessionPreference.dual(
      primary: primary,
      secondary: secondary,
    );
    await _persistMpvSeriesSubtitlePreference(
      _resolvedTarget ?? widget.target,
      _subtitleSessionPreference,
    );
    _showMessage('双字幕已开启：中文在上，英文在下');
  }

  Future<SubtitleTrack?> _showMpvSubtitleTrackPicker({
    required String title,
    required List<SubtitleTrack> tracks,
  }) {
    return showPlaybackMenuDialog<SubtitleTrack>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final track in tracks)
            TvDialogOption(
              isTelevision: _isTelevisionPlaybackDevice,
              autofocus: track == tracks.first,
              onPressed: () => Navigator.of(dialogContext).pop(track),
              child: Text(formatPlaybackSubtitleTrackLabel(track)),
            ),
        ],
      ),
    );
  }

  bool _canUseMpvDualSubtitleTrack(SubtitleTrack track) {
    if (track.id == 'auto' ||
        track.id == 'no' ||
        track.image == true ||
        track.uri ||
        track.data) {
      return false;
    }
    return !isBitmapSubtitle(image: track.image, codec: track.codec);
  }

  Future<void> _disableMpvDualSubtitle(Player player) async {
    if (!_mpvDualSubtitleEnabled) {
      return;
    }
    await _setMpvSubtitleProperty(player, 'secondary-sid', 'no');
    if (!mounted ||
        !identical(_player, player) ||
        !_startupTrackWorkIsCurrent) {
      return;
    }
    setState(() {
      _mpvDualSubtitleEnabled = false;
    });
  }

  Future<void> _selectFntvServerAudio(
    Player player,
    PlaybackTarget target,
    PlaybackAudioStream stream,
  ) async {
    _manualTrackRevision++;
    if (!mounted ||
        !identical(_player, player) ||
        !identical(_resolvedTarget ?? widget.target, target)) {
      return;
    }
    final profiles = fntvQualityPresets(
      target.playbackQualities
          .where((quality) => quality.serverTranscode)
          .toList(),
      target.preferredPlaybackQualityIndex,
    );
    if (profiles.isEmpty) {
      _showMessage('当前播放流无法使用此音轨，飞牛未提供可用转码档位');
      return;
    }
    final quality = await showPlaybackMenuDialog<FntvPlaybackQuality>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('使用服务端音轨 · 选择转码画质'),
        children: [
          for (final profile in profiles)
            TvDialogOption(
              isTelevision: _isTelevisionPlaybackDevice,
              onPressed: () => Navigator.of(dialogContext).pop(profile),
              child: Text(fntvQualityTitle(profile)),
            ),
        ],
      ),
    );
    if (quality == null ||
        !mounted ||
        !identical(_player, player) ||
        !identical(_resolvedTarget ?? widget.target, target)) {
      return;
    }
    await _switchFntvPlayback(
        player,
        target.copyWith(
          preferredAudioStreamId: stream.id,
          preferredPlaybackQualityIndex: quality.index,
        ));
  }

  Future<void> _selectAudioTrack(
    Player player,
    List<AudioTrack> tracks,
    AudioTrack current,
  ) async {
    _manualTrackRevision++;
    final target = _resolvedTarget ?? widget.target;
    if (target.isFntvTranscoding) {
      final selected = await showPlaybackMenuDialog<PlaybackAudioStream>(
          context: context,
          builder: (context) =>
              SimpleDialog(title: const Text('音轨选择'), children: [
                for (final stream in target.audioStreams)
                  TvDialogOption(
                    isTelevision: _isTelevisionPlaybackDevice,
                    onPressed: () => Navigator.pop(context, stream),
                    child: Text(playbackServerAudioLabel(stream)),
                  ),
              ]));
      if (selected != null &&
          mounted &&
          identical(_player, player) &&
          identical(_resolvedTarget ?? widget.target, target) &&
          selected.id != target.preferredAudioStreamId) {
        await _switchFntvPlayback(
            player, target.copyWith(preferredAudioStreamId: selected.id));
      }
      return;
    }
    final unavailable = target.sourceKind == MediaSourceKind.fntv
        ? unavailablePlaybackAudioStreams(target: target, tracks: tracks)
        : const <PlaybackAudioStream>[];
    final selection = await showPlaybackMenuDialog<Object>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('音轨选择'),
          children: [
            for (final track in tracks)
              TvDialogOption(
                isTelevision: _isTelevisionPlaybackDevice,
                autofocus: track == tracks.first,
                onPressed: () => Navigator.of(dialogContext).pop(track),
                child: Text(
                  track == current
                      ? '${_formatServerAudioTrackLabel(target, tracks, track)}  当前'
                      : _formatServerAudioTrackLabel(target, tracks, track),
                ),
              ),
            for (final stream in unavailable)
              TvDialogOption(
                isTelevision: _isTelevisionPlaybackDevice,
                onPressed: () => Navigator.of(dialogContext).pop(stream),
                child: Text('${playbackServerAudioLabel(stream)} · 需服务端转码'),
              ),
          ],
        );
      },
    );
    if (selection is PlaybackAudioStream) {
      if (mounted) await _selectFntvServerAudio(player, target, selection);
      return;
    }
    if (selection is! AudioTrack) {
      return;
    }
    if (!mounted ||
        !identical(_player, player) ||
        !identical(_resolvedTarget ?? widget.target, target)) {
      return;
    }

    final applied = await _runPlayerCommand(
      () => player.setAudioTrack(selection),
      failureMessage: '切换音轨失败',
    );
    if (!applied) {
      return;
    }
    final selectedServerStream = matchPlaybackAudioStreamForTrack(
      target: target,
      tracks: tracks,
      track: selection,
    );
    if (selectedServerStream != null && mounted) {
      setState(() {
        _resolvedTarget = target.copyWith(
          preferredAudioStreamId: selectedServerStream.id,
        );
      });
    }
  }

  Future<bool> _runPlayerCommand(
    Future<void> Function() action, {
    required String failureMessage,
  }) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failureMessage：$error')),
      );
      return false;
    }
  }
}

class _EmbeddedMpvFullscreenControlsBridge extends StatefulWidget {
  const _EmbeddedMpvFullscreenControlsBridge({
    required this.onFullscreenChanged,
    required this.child,
  });

  final ValueChanged<bool> onFullscreenChanged;
  final Widget child;

  @override
  State<_EmbeddedMpvFullscreenControlsBridge> createState() =>
      _EmbeddedMpvFullscreenControlsBridgeState();
}

class _EmbeddedMpvFullscreenControlsBridgeState
    extends State<_EmbeddedMpvFullscreenControlsBridge> {
  bool _isFullscreen = false;
  bool? _lastDispatchedFullscreen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isFullscreen = FullscreenInheritedWidget.maybeOf(context) != null;
    _dispatchFullscreenChanged(_isFullscreen);
  }

  void _dispatchFullscreenChanged(bool isFullscreen) {
    if (_lastDispatchedFullscreen == isFullscreen) {
      return;
    }
    _lastDispatchedFullscreen = isFullscreen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onFullscreenChanged(isFullscreen);
    });
  }

  @override
  void dispose() {
    if (_lastDispatchedFullscreen == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFullscreenChanged(false);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _MpvSubtitleSelectionMode { globalDefault, dual }

class _MpvPositionedSubtitleText extends StatelessWidget {
  const _MpvPositionedSubtitleText({
    required this.text,
    required this.positionPercent,
    required this.fontSize,
    required this.shadows,
  });

  final String text;
  final double positionPercent;
  final double fontSize;
  final List<Shadow> shadows;

  @override
  Widget build(BuildContext context) {
    final alignmentY =
        ((clampPlaybackSubtitlePosition(positionPercent) / 100) * 2) - 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        const referenceArea = 1920.0 * 1080.0;
        final area = constraints.maxWidth * constraints.maxHeight;
        final scale = math.sqrt((area / referenceArea).clamp(0.0, 1.0));
        return Align(
          alignment: Alignment(0, alignmentY),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              text,
              textAlign: TextAlign.center,
              textScaler: TextScaler.linear(scale),
              style: TextStyle(
                height: 1.25,
                fontSize: fontSize,
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: shadows,
              ),
            ),
          ),
        );
      },
    );
  }
}
