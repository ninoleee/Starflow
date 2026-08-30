import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class PlaybackMpvRuntimeSettings {
  const PlaybackMpvRuntimeSettings({
    required this.backgroundPlaybackEnabled,
    required this.doubleTapToSeekEnabled,
    required this.swipeToSeekEnabled,
    required this.longPressSpeedBoostEnabled,
    required this.stallAutoRecoveryEnabled,
    required this.aggressiveTuningEnabled,
    required this.subtitleScale,
    required this.primarySubtitlePosition,
    required this.secondarySubtitlePosition,
    required this.secondarySubtitleScale,
  });

  final bool backgroundPlaybackEnabled;
  final bool doubleTapToSeekEnabled;
  final bool swipeToSeekEnabled;
  final bool longPressSpeedBoostEnabled;
  final bool stallAutoRecoveryEnabled;
  final bool aggressiveTuningEnabled;
  final double subtitleScale;
  final double primarySubtitlePosition;
  final double secondarySubtitlePosition;
  final double secondarySubtitleScale;

  PlaybackMpvRuntimeSettings copyWith({
    bool? backgroundPlaybackEnabled,
    bool? doubleTapToSeekEnabled,
    bool? swipeToSeekEnabled,
    bool? longPressSpeedBoostEnabled,
    bool? stallAutoRecoveryEnabled,
    bool? aggressiveTuningEnabled,
    double? subtitleScale,
    double? primarySubtitlePosition,
    double? secondarySubtitlePosition,
    double? secondarySubtitleScale,
  }) {
    return PlaybackMpvRuntimeSettings(
      backgroundPlaybackEnabled:
          backgroundPlaybackEnabled ?? this.backgroundPlaybackEnabled,
      doubleTapToSeekEnabled:
          doubleTapToSeekEnabled ?? this.doubleTapToSeekEnabled,
      swipeToSeekEnabled: swipeToSeekEnabled ?? this.swipeToSeekEnabled,
      longPressSpeedBoostEnabled:
          longPressSpeedBoostEnabled ?? this.longPressSpeedBoostEnabled,
      stallAutoRecoveryEnabled:
          stallAutoRecoveryEnabled ?? this.stallAutoRecoveryEnabled,
      aggressiveTuningEnabled:
          aggressiveTuningEnabled ?? this.aggressiveTuningEnabled,
      subtitleScale: subtitleScale ?? this.subtitleScale,
      primarySubtitlePosition:
          primarySubtitlePosition ?? this.primarySubtitlePosition,
      secondarySubtitlePosition:
          secondarySubtitlePosition ?? this.secondarySubtitlePosition,
      secondarySubtitleScale:
          secondarySubtitleScale ?? this.secondarySubtitleScale,
    );
  }
}

class PlaybackOptionsDialog extends StatelessWidget {
  const PlaybackOptionsDialog({
    super.key,
    required this.player,
    required this.target,
    required this.isTelevision,
    required this.subtitleDelayLabel,
    required this.seriesSkipLabel,
    required this.onSelectSubtitle,
    required this.onSelectAudio,
    required this.onAdjustSubtitleDelay,
    required this.onLoadExternalSubtitle,
    required this.onSearchSubtitlesOnline,
    required this.onConfigureSeriesSkip,
    required this.runtimeSettings,
    required this.onApplyRuntimeSettings,
  });

  final Player player;
  final PlaybackTarget target;
  final bool isTelevision;
  final String subtitleDelayLabel;
  final String seriesSkipLabel;
  final Future<void> Function(
    List<SubtitleTrack> tracks,
    SubtitleTrack current,
  ) onSelectSubtitle;
  final Future<void> Function(
    List<AudioTrack> tracks,
    AudioTrack current,
  ) onSelectAudio;
  final Future<void> Function() onAdjustSubtitleDelay;
  final Future<void> Function() onLoadExternalSubtitle;
  final Future<void> Function() onSearchSubtitlesOnline;
  final Future<void> Function() onConfigureSeriesSkip;
  final PlaybackMpvRuntimeSettings runtimeSettings;
  final Future<void> Function(PlaybackMpvRuntimeSettings settings)
      onApplyRuntimeSettings;

  Future<void> _openSubtitleOptionsDialog(
    BuildContext context,
    Tracks tracks,
    Track currentTrack,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _PlaybackSubtitleOptionsDialog(
          isTelevision: isTelevision,
          currentSubtitleLabel:
              formatPlaybackSubtitleTrackLabel(currentTrack.subtitle),
          subtitleDelayLabel: subtitleDelayLabel,
          onSelectSubtitle: () =>
              onSelectSubtitle(tracks.subtitle, currentTrack.subtitle),
          onAdjustSubtitleDelay: onAdjustSubtitleDelay,
          onLoadExternalSubtitle: onLoadExternalSubtitle,
          onSearchSubtitlesOnline: onSearchSubtitlesOnline,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return wrapTelevisionDialogFieldTraversal(
      enabled: isTelevision,
      child: AlertDialog(
        title: const Text('播放设置'),
        content: SizedBox(
          width: 440,
          child: _PlaybackOptionsDialogBody(
            player: player,
            target: target,
            isTelevision: isTelevision,
            subtitleDelayLabel: subtitleDelayLabel,
            seriesSkipLabel: seriesSkipLabel,
            onOpenSubtitleOptionsDialog: _openSubtitleOptionsDialog,
            onSelectAudio: onSelectAudio,
            onConfigureSeriesSkip: onConfigureSeriesSkip,
            runtimeSettings: runtimeSettings,
            onApplyRuntimeSettings: onApplyRuntimeSettings,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _PlaybackOptionsDialogBody extends StatefulWidget {
  const _PlaybackOptionsDialogBody({
    required this.player,
    required this.target,
    required this.isTelevision,
    required this.subtitleDelayLabel,
    required this.seriesSkipLabel,
    required this.onOpenSubtitleOptionsDialog,
    required this.onSelectAudio,
    required this.onConfigureSeriesSkip,
    required this.runtimeSettings,
    required this.onApplyRuntimeSettings,
  });

  final Player player;
  final PlaybackTarget target;
  final bool isTelevision;
  final String subtitleDelayLabel;
  final String seriesSkipLabel;
  final Future<void> Function(
    BuildContext context,
    Tracks tracks,
    Track currentTrack,
  ) onOpenSubtitleOptionsDialog;
  final Future<void> Function(
    List<AudioTrack> tracks,
    AudioTrack current,
  ) onSelectAudio;
  final Future<void> Function() onConfigureSeriesSkip;
  final PlaybackMpvRuntimeSettings runtimeSettings;
  final Future<void> Function(PlaybackMpvRuntimeSettings settings)
      onApplyRuntimeSettings;

  @override
  State<_PlaybackOptionsDialogBody> createState() =>
      _PlaybackOptionsDialogBodyState();
}

class _PlaybackOptionsDialogBodyState
    extends State<_PlaybackOptionsDialogBody> {
  static const List<double> _kPlaybackRatePresets = <double>[
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<Track>? _trackSubscription;
  StreamSubscription<PlaylistMode>? _playlistModeSubscription;
  StreamSubscription<double>? _rateSubscription;
  late _PlaybackDialogViewState _viewState;
  late PlaybackMpvRuntimeSettings _runtimeSettings;

  @override
  void initState() {
    super.initState();
    _bindPlayer(widget.player);
    _runtimeSettings = widget.runtimeSettings;
  }

  @override
  void didUpdateWidget(covariant _PlaybackOptionsDialogBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      _unbindPlayer();
      _bindPlayer(widget.player);
    }
  }

  @override
  void dispose() {
    _unbindPlayer();
    super.dispose();
  }

  void _bindPlayer(Player player) {
    _viewState = _PlaybackDialogViewState.fromPlayer(player);
    _tracksSubscription = player.stream.tracks.listen((tracks) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(tracks: tracks);
      });
    });
    _trackSubscription = player.stream.track.listen((track) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(currentTrack: track);
      });
    });
    _playlistModeSubscription = player.stream.playlistMode.listen((
      playlistMode,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(playlistMode: playlistMode);
      });
    });
    _rateSubscription = player.stream.rate.listen((rate) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(rate: rate);
      });
    });
  }

  void _unbindPlayer() {
    unawaited(_tracksSubscription?.cancel());
    unawaited(_trackSubscription?.cancel());
    unawaited(_playlistModeSubscription?.cancel());
    unawaited(_rateSubscription?.cancel());
    _tracksSubscription = null;
    _trackSubscription = null;
    _playlistModeSubscription = null;
    _rateSubscription = null;
  }

  Future<void> _setRate(double value) => widget.player.setRate(value);

  Future<void> _updateRuntimeSettings(
    PlaybackMpvRuntimeSettings next,
  ) async {
    setState(() {
      _runtimeSettings = next;
    });
    await widget.onApplyRuntimeSettings(next);
  }

  Future<void> _selectPlaybackSpeed() async {
    final selection = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('播放速度'),
          children: [
            for (final rate in _kPlaybackRatePresets)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(rate),
                child: Text(
                  (rate - _viewState.rate).abs() < 0.01
                      ? '${formatPlaybackSpeed(rate)}  当前'
                      : formatPlaybackSpeed(rate),
                ),
              ),
          ],
        );
      },
    );
    if (selection == null || (selection - _viewState.rate).abs() < 0.01) {
      return;
    }
    await _setRate(selection);
  }

  Future<void> _selectPlaylistMode() async {
    final selection = await showDialog<PlaylistMode>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('循环播放'),
          children: [
            for (final mode in PlaylistMode.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(mode),
                child: Text(
                  mode == _viewState.playlistMode
                      ? '${_formatPlaylistModeLabel(mode)}  当前'
                      : _formatPlaylistModeLabel(mode),
                ),
              ),
          ],
        );
      },
    );
    if (selection == null || selection == _viewState.playlistMode) {
      return;
    }
    await widget.player.setPlaylistMode(selection);
  }

  Future<void> _openMoreOptionsDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _PlaybackMoreOptionsDialog(
          isTelevision: widget.isTelevision,
          runtimeSettings: _runtimeSettings,
          onApplyRuntimeSettings: _updateRuntimeSettings,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = ListView(
      shrinkWrap: true,
      children: [
        _PlaybackReadOnlyFocusRegion(
          isTelevision: widget.isTelevision,
          autofocus: widget.isTelevision,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.target.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                buildPlaybackOptionMeta(widget.target),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionLabel(
          title: '详细设置',
          icon: Icons.tune_rounded,
        ),
        const SizedBox(height: 8),
        _PlaybackOptionTile(
          isTelevision: widget.isTelevision,
          title: '速度',
          value: formatPlaybackSpeed(_viewState.rate),
          onPressed: _selectPlaybackSpeed,
        ),
        const SizedBox(height: 8),
        _PlaybackOptionTile(
          isTelevision: widget.isTelevision,
          title: '循环播放',
          value: _formatPlaylistModeLabel(_viewState.playlistMode),
          onPressed: _selectPlaylistMode,
        ),
        const SizedBox(height: 8),
        _PlaybackOptionTile(
          isTelevision: widget.isTelevision,
          title: '字幕',
          value: buildPlaybackSubtitleOptionsSummary(
            _viewState.currentTrack.subtitle,
            subtitleDelayLabel: widget.subtitleDelayLabel,
          ),
          onPressed: () => widget.onOpenSubtitleOptionsDialog(
            context,
            _viewState.tracks,
            _viewState.currentTrack,
          ),
        ),
        const SizedBox(height: 8),
        _PlaybackOptionTile(
          isTelevision: widget.isTelevision,
          title: '音轨',
          value: formatPlaybackAudioTrackLabel(_viewState.currentTrack.audio),
          onPressed: () => widget.onSelectAudio(
            _viewState.tracks.audio,
            _viewState.currentTrack.audio,
          ),
        ),
        const SizedBox(height: 8),
        _PlaybackOptionTile(
          isTelevision: widget.isTelevision,
          title: '本剧跳过片头片尾',
          value: widget.seriesSkipLabel,
          onPressed: widget.onConfigureSeriesSkip,
        ),
        const SizedBox(height: 8),
        _PlaybackOptionTile(
          isTelevision: widget.isTelevision,
          title: '更多',
          value: '字幕布局、后台播放与 MPV 设置',
          onPressed: _openMoreOptionsDialog,
        ),
      ],
    );
    return body;
  }
}

class _PlaybackMoreOptionsDialog extends StatefulWidget {
  const _PlaybackMoreOptionsDialog({
    required this.isTelevision,
    required this.runtimeSettings,
    required this.onApplyRuntimeSettings,
  });

  final bool isTelevision;
  final PlaybackMpvRuntimeSettings runtimeSettings;
  final Future<void> Function(PlaybackMpvRuntimeSettings settings)
      onApplyRuntimeSettings;

  @override
  State<_PlaybackMoreOptionsDialog> createState() =>
      _PlaybackMoreOptionsDialogState();
}

class _PlaybackMoreOptionsDialogState
    extends State<_PlaybackMoreOptionsDialog> {
  late PlaybackMpvRuntimeSettings _runtimeSettings;

  @override
  void initState() {
    super.initState();
    _runtimeSettings = widget.runtimeSettings;
  }

  Future<void> _updateRuntimeSettings(
    PlaybackMpvRuntimeSettings next,
  ) async {
    setState(() {
      _runtimeSettings = next;
    });
    await widget.onApplyRuntimeSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    return wrapTelevisionDialogFieldTraversal(
      enabled: widget.isTelevision,
      child: AlertDialog(
        title: const Text('更多'),
        content: SizedBox(
          width: 440,
          child: ListView(
            shrinkWrap: true,
            children: [
              const _SectionLabel(
                title: '字幕布局',
                icon: Icons.subtitles_rounded,
              ),
              const SizedBox(height: 8),
              _PlaybackStepperTile(
                isTelevision: widget.isTelevision,
                title: '主字幕大小',
                value: formatPlaybackSubtitleScaleLabel(
                  _runtimeSettings.subtitleScale,
                ),
                onDecrease:
                    _runtimeSettings.subtitleScale > kPlaybackSubtitleScaleMin
                        ? () => _updateRuntimeSettings(
                              _runtimeSettings.copyWith(
                                subtitleScale: stepPlaybackSubtitleScale(
                                  _runtimeSettings.subtitleScale,
                                  -1,
                                ),
                              ),
                            )
                        : null,
                onIncrease:
                    _runtimeSettings.subtitleScale < kPlaybackSubtitleScaleMax
                        ? () => _updateRuntimeSettings(
                              _runtimeSettings.copyWith(
                                subtitleScale: stepPlaybackSubtitleScale(
                                  _runtimeSettings.subtitleScale,
                                  1,
                                ),
                              ),
                            )
                        : null,
              ),
              const SizedBox(height: 8),
              _PlaybackStepperTile(
                isTelevision: widget.isTelevision,
                title: '主字幕位置',
                value: formatPlaybackSubtitlePositionLabel(
                  _runtimeSettings.primarySubtitlePosition,
                ),
                onDecrease: _runtimeSettings.primarySubtitlePosition >
                        kPlaybackSubtitlePositionMin
                    ? () => _updateRuntimeSettings(
                          _runtimeSettings.copyWith(
                            primarySubtitlePosition:
                                stepPlaybackSubtitlePositionQuick(
                              _runtimeSettings.primarySubtitlePosition,
                              -1,
                            ),
                          ),
                        )
                    : null,
                onIncrease: _runtimeSettings.primarySubtitlePosition <
                        kPlaybackSubtitlePositionMax
                    ? () => _updateRuntimeSettings(
                          _runtimeSettings.copyWith(
                            primarySubtitlePosition:
                                stepPlaybackSubtitlePositionQuick(
                              _runtimeSettings.primarySubtitlePosition,
                              1,
                            ),
                          ),
                        )
                    : null,
              ),
              const SizedBox(height: 8),
              _PlaybackStepperTile(
                isTelevision: widget.isTelevision,
                title: '副字幕位置',
                value: formatPlaybackSubtitlePositionLabel(
                  _runtimeSettings.secondarySubtitlePosition,
                ),
                onDecrease: _runtimeSettings.secondarySubtitlePosition >
                        kPlaybackSubtitlePositionMin
                    ? () => _updateRuntimeSettings(
                          _runtimeSettings.copyWith(
                            secondarySubtitlePosition:
                                stepPlaybackSubtitlePositionQuick(
                              _runtimeSettings.secondarySubtitlePosition,
                              -1,
                            ),
                          ),
                        )
                    : null,
                onIncrease: _runtimeSettings.secondarySubtitlePosition <
                        kPlaybackSubtitlePositionMax
                    ? () => _updateRuntimeSettings(
                          _runtimeSettings.copyWith(
                            secondarySubtitlePosition:
                                stepPlaybackSubtitlePositionQuick(
                              _runtimeSettings.secondarySubtitlePosition,
                              1,
                            ),
                          ),
                        )
                    : null,
              ),
              const SizedBox(height: 8),
              _PlaybackStepperTile(
                isTelevision: widget.isTelevision,
                title: '副字幕大小',
                value: formatPlaybackSecondarySubtitleScaleLabel(
                  _runtimeSettings.secondarySubtitleScale,
                ),
                onDecrease: _runtimeSettings.secondarySubtitleScale >
                        kPlaybackSecondarySubtitleScaleMin
                    ? () => _updateRuntimeSettings(
                          _runtimeSettings.copyWith(
                            secondarySubtitleScale:
                                stepPlaybackSecondarySubtitleScale(
                              _runtimeSettings.secondarySubtitleScale,
                              -1,
                            ),
                          ),
                        )
                    : null,
                onIncrease: _runtimeSettings.secondarySubtitleScale <
                        kPlaybackSecondarySubtitleScaleMax
                    ? () => _updateRuntimeSettings(
                          _runtimeSettings.copyWith(
                            secondarySubtitleScale:
                                stepPlaybackSecondarySubtitleScale(
                              _runtimeSettings.secondarySubtitleScale,
                              1,
                            ),
                          ),
                        )
                    : null,
              ),
              const SizedBox(height: 12),
              const _SectionLabel(
                title: 'MPV',
                icon: Icons.memory_rounded,
              ),
              const SizedBox(height: 8),
              _PlaybackToggleTile(
                isTelevision: widget.isTelevision,
                title: '后台播放',
                subtitle: widget.isTelevision ? 'TV 端固定禁用' : '切换应用后继续播放',
                value: !widget.isTelevision &&
                    _runtimeSettings.backgroundPlaybackEnabled,
                onChanged: widget.isTelevision
                    ? null
                    : (value) => _updateRuntimeSettings(
                          _runtimeSettings.copyWith(
                            backgroundPlaybackEnabled: value,
                          ),
                        ),
              ),
              const SizedBox(height: 8),
              _PlaybackToggleTile(
                isTelevision: widget.isTelevision,
                title: '双击快进/快退',
                value: _runtimeSettings.doubleTapToSeekEnabled,
                onChanged: (value) => _updateRuntimeSettings(
                  _runtimeSettings.copyWith(doubleTapToSeekEnabled: value),
                ),
              ),
              const SizedBox(height: 8),
              _PlaybackToggleTile(
                isTelevision: widget.isTelevision,
                title: '左右滑动调进度',
                value: _runtimeSettings.swipeToSeekEnabled,
                onChanged: (value) => _updateRuntimeSettings(
                  _runtimeSettings.copyWith(swipeToSeekEnabled: value),
                ),
              ),
              const SizedBox(height: 8),
              _PlaybackToggleTile(
                isTelevision: widget.isTelevision,
                title: '长按临时 2 倍速',
                value: _runtimeSettings.longPressSpeedBoostEnabled,
                onChanged: (value) => _updateRuntimeSettings(
                  _runtimeSettings.copyWith(longPressSpeedBoostEnabled: value),
                ),
              ),
              const SizedBox(height: 8),
              _PlaybackToggleTile(
                isTelevision: widget.isTelevision,
                title: '卡顿自动恢复',
                value: _runtimeSettings.stallAutoRecoveryEnabled,
                onChanged: (value) => _updateRuntimeSettings(
                  _runtimeSettings.copyWith(stallAutoRecoveryEnabled: value),
                ),
              ),
              const SizedBox(height: 8),
              _PlaybackToggleTile(
                isTelevision: widget.isTelevision,
                title: '激进性能调优',
                value: _runtimeSettings.aggressiveTuningEnabled,
                onChanged: (value) => _updateRuntimeSettings(
                  _runtimeSettings.copyWith(aggressiveTuningEnabled: value),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _PlaybackSubtitleOptionsDialog extends StatelessWidget {
  const _PlaybackSubtitleOptionsDialog({
    required this.isTelevision,
    required this.currentSubtitleLabel,
    required this.subtitleDelayLabel,
    required this.onSelectSubtitle,
    required this.onAdjustSubtitleDelay,
    required this.onLoadExternalSubtitle,
    required this.onSearchSubtitlesOnline,
  });

  final bool isTelevision;
  final String currentSubtitleLabel;
  final String subtitleDelayLabel;
  final Future<void> Function() onSelectSubtitle;
  final Future<void> Function() onAdjustSubtitleDelay;
  final Future<void> Function() onLoadExternalSubtitle;
  final Future<void> Function() onSearchSubtitlesOnline;

  @override
  Widget build(BuildContext context) {
    return wrapTelevisionDialogFieldTraversal(
      enabled: isTelevision,
      child: AlertDialog(
        title: const Text('字幕'),
        content: SizedBox(
          width: 440,
          child: ListView(
            shrinkWrap: true,
            children: [
              _PlaybackOptionTile(
                isTelevision: isTelevision,
                autofocus: isTelevision,
                title: '字幕选择',
                value: currentSubtitleLabel,
                onPressed: onSelectSubtitle,
              ),
              const SizedBox(height: 10),
              _PlaybackOptionTile(
                isTelevision: isTelevision,
                title: '字幕偏移',
                value: subtitleDelayLabel,
                onPressed: onAdjustSubtitleDelay,
              ),
              const SizedBox(height: 10),
              _PlaybackOptionTile(
                isTelevision: isTelevision,
                title: '加载外部字幕',
                value: '选择 SRT / ASS / SSA / VTT',
                onPressed: onLoadExternalSubtitle,
              ),
              const SizedBox(height: 10),
              _PlaybackOptionTile(
                isTelevision: isTelevision,
                title: '在线查找字幕',
                value: '在线字幕源',
                onPressed: onSearchSubtitlesOnline,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _PlaybackOptionTile extends StatelessWidget {
  const _PlaybackOptionTile({
    required this.isTelevision,
    required this.title,
    required this.value,
    required this.onPressed,
    this.autofocus = false,
  });

  final bool isTelevision;
  final String title;
  final String value;
  final Future<void> Function() onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    if (isTelevision) {
      return StarflowSelectionTile(
        title: title,
        value: value,
        onPressed: () {
          unawaited(onPressed());
        },
        autofocus: autofocus,
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        dense: !isTelevision,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        title: Text(title),
        subtitle: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          unawaited(onPressed());
        },
      ),
    );
  }
}

class _PlaybackReadOnlyFocusRegion extends StatelessWidget {
  const _PlaybackReadOnlyFocusRegion({
    required this.isTelevision,
    required this.child,
    this.autofocus = false,
    this.padding = EdgeInsets.zero,
  });

  final bool isTelevision;
  final Widget child;
  final bool autofocus;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: child,
    );
    if (!isTelevision) {
      return content;
    }
    return SizedBox(
      width: double.infinity,
      child: TvFocusableAction(
        autofocus: autofocus,
        onPressed: () {},
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        visualStyle: TvFocusVisualStyle.subtle,
        child: content,
      ),
    );
  }
}

class _PlaybackToggleTile extends StatelessWidget {
  const _PlaybackToggleTile({
    required this.isTelevision,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle = '',
  });

  final bool isTelevision;
  final String title;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool value)? onChanged;

  @override
  Widget build(BuildContext context) {
    final tile = SwitchListTile.adaptive(
      title: Text(title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      value: value,
      onChanged: onChanged == null
          ? null
          : (next) {
              unawaited(onChanged!(next));
            },
    );
    if (!isTelevision) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: tile,
      );
    }
    return TvFocusableAction(
      onPressed: onChanged == null ? () {} : () => onChanged!(!value),
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: IgnorePointer(child: tile),
      ),
    );
  }
}

class _PlaybackStepperTile extends StatelessWidget {
  const _PlaybackStepperTile({
    required this.isTelevision,
    required this.title,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final bool isTelevision;
  final String title;
  final String value;
  final Future<void> Function()? onDecrease;
  final Future<void> Function()? onIncrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(title)),
            const SizedBox(width: 12),
            _PlaybackStepperActionButton(
              isTelevision: isTelevision,
              label: '-',
              icon: Icons.remove_rounded,
              onPressed: onDecrease,
            ),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 76),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PlaybackStepperActionButton(
              isTelevision: isTelevision,
              label: '+',
              icon: Icons.add_rounded,
              onPressed: onIncrease,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackStepperActionButton extends StatelessWidget {
  const _PlaybackStepperActionButton({
    required this.isTelevision,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final bool isTelevision;
  final String label;
  final IconData icon;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    if (isTelevision) {
      return SizedBox(
        width: 56,
        child: StarflowChipButton(
          label: label,
          selected: false,
          onPressed: onPressed == null
              ? null
              : () {
                  unawaited(onPressed!());
                },
        ),
      );
    }
    return SizedBox(
      width: 42,
      height: 42,
      child: OutlinedButton(
        onPressed: onPressed == null
            ? null
            : () {
                unawaited(onPressed!());
              },
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

String _formatPlaylistModeLabel(PlaylistMode mode) {
  return switch (mode) {
    PlaylistMode.none => '关闭',
    PlaylistMode.single => '单集循环',
    PlaylistMode.loop => '列表循环',
  };
}

class _PlaybackDialogViewState {
  const _PlaybackDialogViewState({
    required this.tracks,
    required this.currentTrack,
    required this.playlistMode,
    required this.rate,
  });

  factory _PlaybackDialogViewState.fromPlayer(Player player) {
    return _PlaybackDialogViewState(
      tracks: player.state.tracks,
      currentTrack: player.state.track,
      playlistMode: player.state.playlistMode,
      rate: player.state.rate,
    );
  }

  final Tracks tracks;
  final Track currentTrack;
  final PlaylistMode playlistMode;
  final double rate;

  _PlaybackDialogViewState copyWith({
    Tracks? tracks,
    Track? currentTrack,
    PlaylistMode? playlistMode,
    double? rate,
  }) {
    return _PlaybackDialogViewState(
      tracks: tracks ?? this.tracks,
      currentTrack: currentTrack ?? this.currentTrack,
      playlistMode: playlistMode ?? this.playlistMode,
      rate: rate ?? this.rate,
    );
  }
}
