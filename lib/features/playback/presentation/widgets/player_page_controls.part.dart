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
    if (!_isReady || player == null || videoController == null) {
      final startupOverlay = PlayerStartupOverlay(
        target: _resolvedTarget ?? widget.target,
        speedLabel: _startupProbe.speedLabel,
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
    final video = Video(
      controller: videoController,
      controls: isTelevision
          ? NoVideoControls
          : (state) {
              return _EmbeddedMpvFullscreenControlsBridge(
                onFullscreenChanged:
                    _handleObservedEmbeddedMpvFullscreenChanged,
                child: _buildAdaptiveEmbeddedVideoControls(
                  state,
                  settings: settings,
                ),
              );
            },
      fill: Colors.black,
      fit: _resolvedVideoBoxFit(),
      aspectRatio: _resolvedVideoAspectRatioOverride(),
      subtitleViewConfiguration: _buildSubtitleViewConfiguration(
        settings,
        isTelevision: isTelevision,
      ),
    );
    return video;
  }

  Widget _buildAdaptiveEmbeddedVideoControls(
    VideoState state, {
    required AppSettings settings,
  }) {
    final materialThemeData = _buildAdaptiveMaterialControlsThemeData(
      state.context,
      settings: settings,
      fullscreen: false,
      state: state,
    );
    final materialFullscreenThemeData = _buildAdaptiveMaterialControlsThemeData(
      state.context,
      settings: settings,
      fullscreen: true,
      state: state,
    );
    final desktopThemeData = _buildAdaptiveDesktopControlsThemeData(
      state.context,
      settings: settings,
      fullscreen: false,
      state: state,
    );
    final desktopFullscreenThemeData = _buildAdaptiveDesktopControlsThemeData(
      state.context,
      settings: settings,
      fullscreen: true,
      state: state,
    );
    return MaterialVideoControlsTheme(
      normal: materialThemeData,
      fullscreen: materialFullscreenThemeData,
      child: MaterialDesktopVideoControlsTheme(
        normal: desktopThemeData,
        fullscreen: desktopFullscreenThemeData,
        child: KeyedSubtree(
          key: ValueKey('adaptive-controls-$_adaptiveGestureLevelsRevision'),
          child: AdaptiveVideoControls(state),
        ),
      ),
    );
  }

  MaterialVideoControlsThemeData _buildAdaptiveMaterialControlsThemeData(
    BuildContext context, {
    required AppSettings settings,
    required bool fullscreen,
    required VideoState state,
  }) {
    final materialTopButtonBar = _buildAdaptiveMaterialTopButtonBar(
      state,
      settings: settings,
    );
    final isPortrait = _shouldInsetAdaptivePortraitControls(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    const portraitTopInset = 18.0;
    const portraitBottomInset = 28.0;
    const portraitFullscreenBottomInset = 64.0;
    final controlsPadding = isPortrait
        ? EdgeInsets.fromLTRB(
            viewPadding.left,
            viewPadding.top + portraitTopInset,
            viewPadding.right,
            viewPadding.bottom + portraitBottomInset,
          )
        : null;
    final bottomInset = isPortrait
        ? fullscreen
            ? portraitFullscreenBottomInset
            : portraitBottomInset
        : fullscreen
            ? 42.0
            : 0.0;
    final enableVerticalGestureControls = _supportsAdaptiveVerticalGestures;
    final seekBarMargin = isPortrait
        ? EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: bottomInset,
          )
        : fullscreen
            ? const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 42,
              )
            : EdgeInsets.zero;
    return MaterialVideoControlsThemeData(
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
      padding: controlsPadding,
      topButtonBar: materialTopButtonBar,
      topButtonBarMargin: EdgeInsets.fromLTRB(16, isPortrait ? 12 : 0, 16, 0),
      bottomButtonBarMargin: EdgeInsets.only(
        left: 16,
        right: 8,
        bottom: bottomInset,
      ),
      seekBarMargin: seekBarMargin,
    );
  }

  MaterialDesktopVideoControlsThemeData _buildAdaptiveDesktopControlsThemeData(
    BuildContext context, {
    required AppSettings settings,
    required bool fullscreen,
    required VideoState state,
  }) {
    final desktopTopButtonBar = _buildAdaptiveDesktopTopButtonBar(
      state,
      settings: settings,
    );
    final isPortrait = _shouldInsetAdaptivePortraitControls(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    const portraitTopInset = 18.0;
    const portraitBottomInset = 28.0;
    final controlsPadding = isPortrait
        ? EdgeInsets.fromLTRB(
            viewPadding.left,
            viewPadding.top + portraitTopInset,
            viewPadding.right,
            viewPadding.bottom + portraitBottomInset,
          )
        : null;
    final bottomInset = isPortrait ? portraitBottomInset : 0.0;
    return MaterialDesktopVideoControlsThemeData(
      padding: controlsPadding,
      topButtonBar: desktopTopButtonBar,
      topButtonBarMargin: EdgeInsets.fromLTRB(16, isPortrait ? 12 : 0, 16, 0),
      bottomButtonBarMargin: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
      seekBarMargin: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        bottomInset,
      ),
    );
  }

  bool _shouldInsetAdaptivePortraitControls(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.height > size.width;
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
    final brightnessChanged =
        brightness != null &&
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
      const Spacer(),
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
      const Spacer(),
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
        backgroundColor: Colors.transparent,
        shadows: _buildSubtitleOutlineShadows(
          simplifyForPerformance: simplifyForPerformance,
        ),
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
          subtitleDelayLabel: formatSubtitleDelayLabel(
            _subtitleDelaySeconds,
            supported: _subtitleDelaySupported,
          ),
          seriesSkipLabel: formatSeriesSkipPreferenceLabel(
            _seriesSkipPreference,
            target: _resolvedTarget ?? widget.target,
          ),
          onSelectSubtitleScale: _selectSubtitleScale,
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
        );
      },
    );
  }

  Future<void> _selectSubtitleScale() async {
    final currentScale = ref.read(appSettingsProvider).playbackSubtitleScale;
    final selection = await showDialog<PlaybackSubtitleScale>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('字幕大小'),
          children: [
            for (final scale in PlaybackSubtitleScale.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(scale),
                child: Text(
                  scale == currentScale ? '${scale.label}  当前' : scale.label,
                ),
              ),
          ],
        );
      },
    );
    if (selection == null || selection == currentScale) {
      return;
    }

    await ref
        .read(settingsControllerProvider.notifier)
        .setPlaybackSubtitleScale(selection);
    if (!mounted) {
      return;
    }
    setState(() {});
    _showMessage('字幕大小已切换为 ${selection.label}');
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
