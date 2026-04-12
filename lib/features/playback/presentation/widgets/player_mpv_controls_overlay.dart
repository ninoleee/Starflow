import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/core/utils/playback_trace.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_mpv_controls_sections.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';

class PlayerMpvControlsOverlay extends StatefulWidget {
  const PlayerMpvControlsOverlay({
    super.key,
    required this.isFullscreen,
    required this.player,
    required this.target,
    required this.showVolumeSlider,
    required this.preferLightweightChrome,
    required this.traceEnabled,
    required this.onBack,
    required this.onTogglePlayback,
    required this.onSeekTo,
    required this.onOpenSubtitle,
    required this.onOpenAudio,
    required this.onOpenOptions,
    required this.onToggleFullscreen,
    this.onShowPictureInPicture,
    this.onShowAirPlay,
  });

  final bool isFullscreen;
  final Player player;
  final PlaybackTarget target;
  final bool showVolumeSlider;
  final bool preferLightweightChrome;
  final bool traceEnabled;
  final Future<void> Function() onBack;
  final Future<void> Function() onTogglePlayback;
  final Future<void> Function(Duration position) onSeekTo;
  final Future<void> Function() onOpenSubtitle;
  final Future<void> Function() onOpenAudio;
  final Future<void> Function() onOpenOptions;
  final Future<void> Function() onToggleFullscreen;
  final Future<void> Function()? onShowPictureInPicture;
  final Future<void> Function()? onShowAirPlay;

  @override
  State<PlayerMpvControlsOverlay> createState() =>
      _PlayerMpvControlsOverlayState();
}

class _PlayerMpvControlsOverlayState extends State<PlayerMpvControlsOverlay> {
  static const _kControlsAutoHideDelay = Duration(seconds: 3);
  static const _kHoverWakeThrottle = Duration(milliseconds: 180);
  static const double _kHoverWakeDistance = 12;

  Timer? _hideTimer;
  StreamSubscription<bool>? _playingSubscription;
  bool _controlsVisible = true;
  double? _draggingPositionMs;
  bool _isDisposed = false;
  Offset? _lastHoverPosition;
  DateTime? _lastHoverAt;

  bool get _canUpdateOverlayState => mounted && context.mounted && !_isDisposed;
  bool get _showLightweightChrome =>
      widget.preferLightweightChrome && !widget.isFullscreen;
  bool get _showTooltips =>
      !widget.preferLightweightChrome || widget.isFullscreen;

  @override
  void initState() {
    super.initState();
    _trace(
      'windows-mpv.overlay.init',
      fields: {
        'fullscreen': widget.isFullscreen,
        'controlsVisible': _controlsVisible,
      },
    );
    _playingSubscription = widget.player.stream.playing.listen((playing) {
      if (!mounted) {
        return;
      }
      if (!playing) {
        _syncAutoHide(forceShow: true, reason: 'player-paused');
        return;
      }
      _syncAutoHide(reason: 'player-playing');
    });
    _syncAutoHide(reason: 'init');
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cancelHideTimer();
    _resetPointerWakeState();
    unawaited(_playingSubscription?.cancel());
    _trace(
      'windows-mpv.overlay.dispose',
      fields: {
        'fullscreen': widget.isFullscreen,
        'controlsVisible': _controlsVisible,
      },
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlayerMpvControlsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasFullscreen = oldWidget.isFullscreen;
    final isFullscreen = widget.isFullscreen;
    if (wasFullscreen != isFullscreen) {
      _cancelHideTimer();
      _resetPointerWakeState();
      _trace(
        'windows-mpv.overlay.fullscreen-state',
        fields: {'fullscreen': isFullscreen},
      );
      _syncAutoHide(forceShow: true, reason: 'fullscreen-changed');
    }
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _resetPointerWakeState() {
    _lastHoverPosition = null;
    _lastHoverAt = null;
  }

  bool _shouldWakeControlsFromPointer(
    Offset position,
    DateTime now, {
    required Offset? previousPosition,
    required DateTime? previousAt,
  }) {
    if (widget.isFullscreen) {
      return true;
    }
    if (previousPosition == null) {
      return false;
    }
    final movedDistance = (position - previousPosition).distance;
    final isThrottled =
        previousAt != null && now.difference(previousAt) < _kHoverWakeThrottle;
    if (isThrottled || movedDistance < _kHoverWakeDistance) {
      return false;
    }
    return true;
  }

  void _trace(
    String stage, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    if (!widget.traceEnabled) {
      return;
    }
    playbackTrace(
      stage,
      fields: <String, Object?>{
        'title': widget.target.title.trim().isEmpty
            ? 'Starflow'
            : widget.target.title.trim(),
        'fullscreen': widget.isFullscreen,
        ...fields,
      },
    );
  }

  void _setControlsVisible(
    bool visible, {
    required String reason,
  }) {
    if (!_canUpdateOverlayState) {
      return;
    }
    if (_controlsVisible == visible) {
      return;
    }
    setState(() {
      _controlsVisible = visible;
    });
    _trace(
      'windows-mpv.overlay.controls-visibility',
      fields: {
        'visible': visible,
        'reason': reason,
        'playing': widget.player.state.playing,
        'dragging': _draggingPositionMs != null,
      },
    );
  }

  void _syncAutoHide({
    bool forceShow = false,
    String reason = 'sync',
  }) {
    if (!_canUpdateOverlayState) {
      return;
    }
    if (forceShow && !_controlsVisible) {
      _setControlsVisible(true, reason: reason);
    }
    if (!widget.player.state.playing || _draggingPositionMs != null) {
      _cancelHideTimer();
      if (!_controlsVisible) {
        _setControlsVisible(true, reason: 'paused-or-dragging');
      }
      return;
    }
    _cancelHideTimer();
    _hideTimer = Timer(_kControlsAutoHideDelay, () {
      if (!_canUpdateOverlayState ||
          _draggingPositionMs != null ||
          !widget.player.state.playing) {
        return;
      }
      _setControlsVisible(false, reason: 'auto-hide-timer');
    });
  }

  void _showControls({String reason = 'show-controls'}) {
    _syncAutoHide(forceShow: true, reason: reason);
  }

  void _handlePointerEnter(PointerEnterEvent event) {
    final previousPosition = _lastHoverPosition;
    final previousAt = _lastHoverAt;
    final now = DateTime.now();
    _lastHoverPosition = event.position;
    _lastHoverAt = now;
    if (_controlsVisible) {
      _syncAutoHide(reason: 'pointer-enter');
      return;
    }
    if (_shouldWakeControlsFromPointer(
      event.position,
      now,
      previousPosition: previousPosition,
      previousAt: previousAt,
    )) {
      _showControls(reason: 'pointer-enter');
    }
  }

  void _handlePointerExit(PointerExitEvent event) {
    _lastHoverPosition = event.position;
    _lastHoverAt = DateTime.now();
  }

  void _handlePointerHover(PointerHoverEvent event) {
    final previousPosition = _lastHoverPosition;
    final previousAt = _lastHoverAt;
    final now = DateTime.now();
    _lastHoverPosition = event.position;
    _lastHoverAt = now;

    if (_controlsVisible) {
      _showControls(reason: 'pointer-hover');
      return;
    }

    if (!widget.isFullscreen) {
      if (!_shouldWakeControlsFromPointer(
        event.position,
        now,
        previousPosition: previousPosition,
        previousAt: previousAt,
      )) {
        return;
      }
    }

    _showControls(reason: 'pointer-hover');
  }

  void _toggleControlsVisibility() {
    if (_controlsVisible) {
      _cancelHideTimer();
      _setControlsVisible(false, reason: 'tap-toggle-hide');
      return;
    }
    _showControls(reason: 'tap-toggle-show');
  }

  Future<void> _handleSeekChanged(double value) async {
    if (!_canUpdateOverlayState) {
      return;
    }
    final wasDragging = _draggingPositionMs != null;
    setState(() {
      _draggingPositionMs = value;
    });
    if (!wasDragging) {
      _trace(
        'windows-mpv.overlay.seek-drag-start',
        fields: {'positionMs': value.round()},
      );
    }
    _cancelHideTimer();
  }

  Future<void> _handleSeekChangeEnd(double value) async {
    final position = Duration(milliseconds: value.round());
    if (_canUpdateOverlayState) {
      setState(() {
        _draggingPositionMs = null;
      });
    }
    _trace(
      'windows-mpv.overlay.seek-drag-end',
      fields: {'positionMs': position.inMilliseconds},
    );
    await widget.onSeekTo(position);
    _showControls(reason: 'seek-complete');
  }

  Widget _buildChromeButton({
    required IconData icon,
    required Future<void> Function() onPressed,
    String? tooltip,
    String? traceStage,
    bool compact = false,
  }) {
    return Tooltip(
      message: _showTooltips ? (tooltip ?? '') : '',
      child: IconButton(
        onPressed: () {
          _showControls(reason: 'button-tap');
          if (traceStage != null) {
            _trace(traceStage);
          }
          unawaited(onPressed());
        },
        icon: Icon(icon, size: compact ? 16 : 18),
        color: Colors.white,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(
          width: compact ? 32 : 36,
          height: compact ? 32 : 36,
        ),
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildVisibilityShell(Widget child) {
    final visible = _controlsVisible;
    return IgnorePointer(
      ignoring: !visible,
      child: Opacity(
        opacity: visible ? 1 : 0,
        alwaysIncludeSemantics: false,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFullscreen = widget.isFullscreen;
    return MouseRegion(
      onEnter: _handlePointerEnter,
      onExit: _handlePointerExit,
      onHover: _handlePointerHover,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControlsVisibility,
        onDoubleTap: () {
          _showControls(reason: 'double-tap');
          _trace('windows-mpv.overlay.gesture.double-tap-fullscreen');
          unawaited(widget.onToggleFullscreen());
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _buildVisibilityShell(
                SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      _buildChromeButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: '返回',
                        onPressed: widget.onBack,
                        traceStage: 'windows-mpv.overlay.action.back',
                        compact: _showLightweightChrome,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.target.title.trim().isEmpty
                              ? 'Starflow'
                              : widget.target.title.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.onShowAirPlay != null) ...[
                        const SizedBox(width: 8),
                        _buildChromeButton(
                          icon: Icons.airplay_rounded,
                          tooltip: '投放',
                          onPressed: widget.onShowAirPlay!,
                          traceStage: 'windows-mpv.overlay.action.airplay',
                        ),
                      ],
                      if (widget.onShowPictureInPicture != null) ...[
                        const SizedBox(width: 8),
                        _buildChromeButton(
                          icon: Icons.picture_in_picture_alt_rounded,
                          tooltip: '画中画',
                          onPressed: widget.onShowPictureInPicture!,
                          traceStage:
                              'windows-mpv.overlay.action.picture-in-picture',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildVisibilityShell(
                SafeArea(
                  top: false,
                  child: PlayerMpvBottomPanel(
                    backgroundColor: _showLightweightChrome
                        ? const Color(0xD610141A)
                        : const Color(0xC810141A),
                    borderRadius: _showLightweightChrome ? 14 : 18,
                    showBorder: false,
                    padding: EdgeInsets.fromLTRB(
                      _showLightweightChrome ? 12 : 16,
                      _showLightweightChrome ? 10 : 12,
                      _showLightweightChrome ? 12 : 16,
                      _showLightweightChrome ? 10 : 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PlayerMpvSeekSectionBinding(
                          player: widget.player,
                          draggingPositionMs: _draggingPositionMs,
                          onChanged: _handleSeekChanged,
                          onChangeEnd: _handleSeekChangeEnd,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _PlayerMpvPlaybackInfoSectionBinding(
                                player: widget.player,
                                draggingPositionMs: _draggingPositionMs,
                                compact: _showLightweightChrome,
                                showTooltips: _showTooltips,
                                onTogglePlayback: () {
                                  _showControls(reason: 'toggle-playback');
                                  _trace(
                                    'windows-mpv.overlay.action.toggle-playback',
                                  );
                                  unawaited(widget.onTogglePlayback());
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            PlayerMpvActionButtonsSection(
                              data: PlayerMpvActionButtonsSectionData(
                                isFullscreen: isFullscreen,
                                onOpenSubtitle: null,
                                onOpenAudio: null,
                                onOpenOptions: () {
                                  _showControls(reason: 'options');
                                  _trace(
                                    'windows-mpv.overlay.action.options',
                                  );
                                  unawaited(widget.onOpenOptions());
                                },
                                onToggleFullscreen: () {
                                  _showControls(reason: 'fullscreen');
                                  _trace(
                                    'windows-mpv.overlay.action.fullscreen',
                                  );
                                  unawaited(widget.onToggleFullscreen());
                                },
                                leanMode: _showLightweightChrome,
                                showSubtitleButton: false,
                                showAudioButton: false,
                                showTooltips: _showTooltips,
                                compact: _showLightweightChrome,
                                optionsIcon: Icons.more_horiz_rounded,
                                optionsTooltip: '更多',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerMpvSeekSectionBinding extends StatelessWidget {
  const _PlayerMpvSeekSectionBinding({
    required this.player,
    required this.draggingPositionMs,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final Player player;
  final double? draggingPositionMs;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration>(
          stream: player.stream.duration,
          initialData: player.state.duration,
          builder: (context, durationSnapshot) {
            return StreamBuilder<double>(
              stream: player.stream.bufferingPercentage,
              initialData: player.state.bufferingPercentage,
              builder: (context, bufferingSnapshot) {
                final duration = durationSnapshot.data ?? Duration.zero;
                final actualPosition = positionSnapshot.data ?? Duration.zero;
                final durationMs = duration.inMilliseconds;
                final sliderMax = durationMs <= 0 ? 1.0 : durationMs.toDouble();
                final sliderValue = (draggingPositionMs ??
                        actualPosition.inMilliseconds.toDouble())
                    .clamp(0.0, sliderMax);
                final playedProgress = durationMs <= 0
                    ? 0.0
                    : (actualPosition.inMilliseconds / durationMs)
                        .clamp(0.0, 1.0);
                final bufferedProgress =
                    ((bufferingSnapshot.data ?? 0.0) / 100.0)
                        .clamp(playedProgress, 1.0);

                return PlayerMpvSeekSection(
                  data: PlayerMpvSeekSectionData(
                    max: sliderMax,
                    value: sliderValue,
                    bufferedProgress: bufferedProgress,
                    enabled: durationMs > 0,
                    onChanged: onChanged,
                    onChangeEnd: onChangeEnd,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PlayerMpvPlaybackInfoSectionBinding extends StatelessWidget {
  const _PlayerMpvPlaybackInfoSectionBinding({
    required this.player,
    required this.draggingPositionMs,
    required this.compact,
    required this.showTooltips,
    required this.onTogglePlayback,
  });

  final Player player;
  final double? draggingPositionMs;
  final bool compact;
  final bool showTooltips;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, playingSnapshot) {
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, positionSnapshot) {
            return StreamBuilder<Duration>(
              stream: player.stream.duration,
              initialData: player.state.duration,
              builder: (context, durationSnapshot) {
                final duration = durationSnapshot.data ?? Duration.zero;
                final actualPosition = positionSnapshot.data ?? Duration.zero;
                final displayPosition = draggingPositionMs == null
                    ? actualPosition
                    : Duration(milliseconds: draggingPositionMs!.round());
                return PlayerMpvPlaybackInfoSection(
                  data: PlayerMpvPlaybackInfoSectionData(
                    isPlaying: playingSnapshot.data ?? false,
                    positionText:
                        '${formatPlaybackClockDuration(displayPosition)} / ${formatPlaybackClockDuration(duration)}',
                    onTogglePlayback: onTogglePlayback,
                    compact: compact,
                    showTooltips: showTooltips,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
