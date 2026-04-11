import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/core/utils/playback_trace.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';

class PlayerMpvControlsOverlay extends StatefulWidget {
  const PlayerMpvControlsOverlay({
    super.key,
    required this.isFullscreen,
    required this.player,
    required this.target,
    required this.showVolumeSlider,
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
  bool _restoreAudibleVolume = false;
  bool _isDisposed = false;
  Offset? _lastHoverPosition;
  DateTime? _lastHoverAt;

  bool get _canUpdateOverlayState => mounted && context.mounted && !_isDisposed;

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

  Future<void> _toggleMute(double currentVolume) async {
    if (currentVolume <= 0.1) {
      final restoredVolume = _restoreAudibleVolume ? 100.0 : 60.0;
      _restoreAudibleVolume = false;
      await widget.player.setVolume(restoredVolume);
      return;
    }
    _restoreAudibleVolume = true;
    await widget.player.setVolume(0);
  }

  Widget _buildChromeButton({
    required IconData icon,
    required Future<void> Function() onPressed,
    String? tooltip,
    String? traceStage,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkResponse(
        radius: 22,
        onTap: () {
          _showControls(reason: 'button-tap');
          if (traceStage != null) {
            _trace(traceStage);
          }
          unawaited(onPressed());
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0x66101822),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
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
            if (_controlsVisible)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      _buildChromeButton(
                        icon: isFullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.arrow_back_rounded,
                        tooltip: isFullscreen ? '退出全屏' : '返回',
                        onPressed: widget.onBack,
                        traceStage: 'windows-mpv.overlay.action.back',
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
                            shadows: [
                              Shadow(
                                color: Color(0xA6000000),
                                blurRadius: 12,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.onShowAirPlay case final onShowAirPlay?) ...[
                        const SizedBox(width: 8),
                        _buildChromeButton(
                          icon: Icons.airplay_rounded,
                          tooltip: '投放',
                          onPressed: onShowAirPlay,
                          traceStage: 'windows-mpv.overlay.action.airplay',
                        ),
                      ],
                      if (widget.onShowPictureInPicture
                          case final onShowPictureInPicture?) ...[
                        const SizedBox(width: 8),
                        _buildChromeButton(
                          icon: Icons.picture_in_picture_alt_rounded,
                          tooltip: '画中画',
                          onPressed: onShowPictureInPicture,
                          traceStage:
                              'windows-mpv.overlay.action.picture-in-picture',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (_controlsVisible)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xAA0A0F16),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: StreamBuilder<Duration>(
                        stream: widget.player.stream.position,
                        initialData: widget.player.state.position,
                        builder: (context, positionSnapshot) {
                          return StreamBuilder<Duration>(
                            stream: widget.player.stream.duration,
                            initialData: widget.player.state.duration,
                            builder: (context, durationSnapshot) {
                              return StreamBuilder<double>(
                                stream:
                                    widget.player.stream.bufferingPercentage,
                                initialData:
                                    widget.player.state.bufferingPercentage,
                                builder: (context, bufferingSnapshot) {
                                  return StreamBuilder<bool>(
                                    stream: widget.player.stream.playing,
                                    initialData: widget.player.state.playing,
                                    builder: (context, playingSnapshot) {
                                      return StreamBuilder<double>(
                                        stream: widget.player.stream.volume,
                                        initialData: widget.player.state.volume,
                                        builder: (context, volumeSnapshot) {
                                          final duration =
                                              durationSnapshot.data ??
                                                  Duration.zero;
                                          final actualPosition =
                                              positionSnapshot.data ??
                                                  Duration.zero;
                                          final displayPosition =
                                              _draggingPositionMs == null
                                                  ? actualPosition
                                                  : Duration(
                                                      milliseconds:
                                                          _draggingPositionMs!
                                                              .round(),
                                                    );
                                          final durationMs =
                                              duration.inMilliseconds;
                                          final sliderMax = durationMs <= 0
                                              ? 1.0
                                              : durationMs.toDouble();
                                          final sliderValue =
                                              (_draggingPositionMs ??
                                                      actualPosition
                                                          .inMilliseconds
                                                          .toDouble())
                                                  .clamp(0.0, sliderMax);
                                          final playedProgress = durationMs <= 0
                                              ? 0.0
                                              : (actualPosition.inMilliseconds /
                                                      durationMs)
                                                  .clamp(0.0, 1.0);
                                          final bufferedProgress =
                                              ((bufferingSnapshot.data ?? 0.0) /
                                                      100.0)
                                                  .clamp(playedProgress, 1.0);
                                          final playing =
                                              playingSnapshot.data ?? false;
                                          final volume =
                                              (volumeSnapshot.data ?? 100.0)
                                                  .clamp(0.0, 100.0);

                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _PlayerMpvSeekBar(
                                                max: sliderMax,
                                                value: sliderValue,
                                                bufferedProgress:
                                                    bufferedProgress,
                                                enabled: durationMs > 0,
                                                onChanged: _handleSeekChanged,
                                                onChangeEnd:
                                                    _handleSeekChangeEnd,
                                              ),
                                              const SizedBox(height: 12),
                                              Row(
                                                children: [
                                                  _buildChromeButton(
                                                    icon: playing
                                                        ? Icons.pause_rounded
                                                        : Icons
                                                            .play_arrow_rounded,
                                                    tooltip:
                                                        playing ? '暂停' : '播放',
                                                    onPressed:
                                                        widget.onTogglePlayback,
                                                    traceStage:
                                                        'windows-mpv.overlay.action.toggle-playback',
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    '${formatPlaybackClockDuration(displayPosition)} / ${formatPlaybackClockDuration(duration)}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  if (widget.showVolumeSlider)
                                                    IconButton(
                                                      onPressed: () {
                                                        _showControls(
                                                          reason:
                                                              'volume-button',
                                                        );
                                                        _trace(
                                                          'windows-mpv.overlay.action.toggle-mute',
                                                        );
                                                        unawaited(
                                                          _toggleMute(volume),
                                                        );
                                                      },
                                                      splashRadius: 18,
                                                      icon: Icon(
                                                        volume <= 0.1
                                                            ? Icons
                                                                .volume_off_rounded
                                                            : volume < 50
                                                                ? Icons
                                                                    .volume_down_rounded
                                                                : Icons
                                                                    .volume_up_rounded,
                                                        color: Colors.white,
                                                        size: 20,
                                                      ),
                                                    ),
                                                  if (widget.showVolumeSlider)
                                                    SizedBox(
                                                      width: 110,
                                                      child: SliderTheme(
                                                        data: SliderTheme.of(
                                                          context,
                                                        ).copyWith(
                                                          trackHeight: 3,
                                                          overlayShape:
                                                              SliderComponentShape
                                                                  .noOverlay,
                                                          thumbShape:
                                                              const RoundSliderThumbShape(
                                                            enabledThumbRadius:
                                                                6,
                                                          ),
                                                        ),
                                                        child: Slider(
                                                          min: 0,
                                                          max: 100,
                                                          value: volume,
                                                          onChanged: (value) {
                                                            _showControls(
                                                              reason:
                                                                  'volume-slider',
                                                            );
                                                            unawaited(
                                                              widget.player
                                                                  .setVolume(
                                                                value,
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                  if (widget.showVolumeSlider)
                                                    const SizedBox(width: 6),
                                                  _buildChromeButton(
                                                    icon: Icons
                                                        .closed_caption_rounded,
                                                    tooltip: '字幕',
                                                    onPressed:
                                                        widget.onOpenSubtitle,
                                                    traceStage:
                                                        'windows-mpv.overlay.action.subtitle',
                                                  ),
                                                  const SizedBox(width: 8),
                                                  _buildChromeButton(
                                                    icon: Icons
                                                        .audiotrack_rounded,
                                                    tooltip: '音轨',
                                                    onPressed:
                                                        widget.onOpenAudio,
                                                    traceStage:
                                                        'windows-mpv.overlay.action.audio',
                                                  ),
                                                  const SizedBox(width: 8),
                                                  _buildChromeButton(
                                                    icon: Icons.tune_rounded,
                                                    tooltip: '播放设置',
                                                    onPressed:
                                                        widget.onOpenOptions,
                                                    traceStage:
                                                        'windows-mpv.overlay.action.options',
                                                  ),
                                                  const SizedBox(width: 8),
                                                  _buildChromeButton(
                                                    icon: isFullscreen
                                                        ? Icons
                                                            .fullscreen_exit_rounded
                                                        : Icons
                                                            .fullscreen_rounded,
                                                    tooltip: isFullscreen
                                                        ? '退出全屏'
                                                        : '全屏',
                                                    onPressed: widget
                                                        .onToggleFullscreen,
                                                    traceStage:
                                                        'windows-mpv.overlay.action.fullscreen',
                                                  ),
                                                ],
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
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

class _PlayerMpvSeekBar extends StatelessWidget {
  const _PlayerMpvSeekBar({
    required this.max,
    required this.value,
    required this.bufferedProgress,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double max;
  final double value;
  final double bufferedProgress;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: bufferedProgress.clamp(0.0, 1.0),
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              inactiveTrackColor: Colors.transparent,
              activeTrackColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              min: 0,
              max: max,
              value: value.clamp(0.0, max),
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
        ],
      ),
    );
  }
}
