import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

class PlaybackOptionsDialog extends ConsumerWidget {
  const PlaybackOptionsDialog({
    super.key,
    required this.player,
    required this.target,
    required this.isTelevision,
    required this.videoLayoutLabel,
    required this.defaultSubtitleScaleLabel,
    required this.subtitleDelayLabel,
    required this.seriesSkipLabel,
    required this.onSelectMpvQualityPreset,
    required this.onSelectVideoLayout,
    required this.onSelectSpeed,
    required this.onSelectSubtitle,
    required this.onSelectAudio,
    required this.onAdjustSubtitleDelay,
    required this.onLoadExternalSubtitle,
    required this.onSearchSubtitlesOnline,
    required this.onConfigureSeriesSkip,
  });

  final Player player;
  final PlaybackTarget target;
  final bool isTelevision;
  final String videoLayoutLabel;
  final String defaultSubtitleScaleLabel;
  final String subtitleDelayLabel;
  final String seriesSkipLabel;
  final Future<void> Function() onSelectMpvQualityPreset;
  final Future<void> Function() onSelectVideoLayout;
  final Future<void> Function(double currentRate) onSelectSpeed;
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
          defaultSubtitleScaleLabel: defaultSubtitleScaleLabel,
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
  Widget build(BuildContext context, WidgetRef ref) {
    final mpvQualityPresetLabel = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.playbackMpvQualityPreset.label,
      ),
    );
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
            videoLayoutLabel: videoLayoutLabel,
            mpvQualityPresetLabel: mpvQualityPresetLabel,
            subtitleDelayLabel: subtitleDelayLabel,
            seriesSkipLabel: seriesSkipLabel,
            onOpenSubtitleOptionsDialog: _openSubtitleOptionsDialog,
            onSelectMpvQualityPreset: onSelectMpvQualityPreset,
            onSelectVideoLayout: onSelectVideoLayout,
            onSelectSpeed: onSelectSpeed,
            onSelectAudio: onSelectAudio,
            onConfigureSeriesSkip: onConfigureSeriesSkip,
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
    required this.videoLayoutLabel,
    required this.mpvQualityPresetLabel,
    required this.subtitleDelayLabel,
    required this.seriesSkipLabel,
    required this.onOpenSubtitleOptionsDialog,
    required this.onSelectMpvQualityPreset,
    required this.onSelectVideoLayout,
    required this.onSelectSpeed,
    required this.onSelectAudio,
    required this.onConfigureSeriesSkip,
  });

  final Player player;
  final PlaybackTarget target;
  final bool isTelevision;
  final String videoLayoutLabel;
  final String mpvQualityPresetLabel;
  final String subtitleDelayLabel;
  final String seriesSkipLabel;
  final Future<void> Function(
    BuildContext context,
    Tracks tracks,
    Track currentTrack,
  ) onOpenSubtitleOptionsDialog;
  final Future<void> Function() onSelectMpvQualityPreset;
  final Future<void> Function() onSelectVideoLayout;
  final Future<void> Function(double currentRate) onSelectSpeed;
  final Future<void> Function(
    List<AudioTrack> tracks,
    AudioTrack current,
  ) onSelectAudio;
  final Future<void> Function() onConfigureSeriesSkip;

  @override
  State<_PlaybackOptionsDialogBody> createState() =>
      _PlaybackOptionsDialogBodyState();
}

class _PlaybackOptionsDialogBodyState
    extends State<_PlaybackOptionsDialogBody> {
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<Track>? _trackSubscription;
  StreamSubscription<PlaylistMode>? _playlistModeSubscription;
  StreamSubscription<double>? _rateSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<int?>? _widthSubscription;
  StreamSubscription<int?>? _heightSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<double>? _bufferingPercentageSubscription;
  late _PlaybackDialogViewState _viewState;

  @override
  void initState() {
    super.initState();
    _bindPlayer(widget.player);
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
    _durationSubscription = player.stream.duration.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(duration: duration);
      });
    });
    _positionSubscription = player.stream.position.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(position: position);
      });
    });
    _widthSubscription = player.stream.width.listen((width) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(width: width);
      });
    });
    _heightSubscription = player.stream.height.listen((height) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(height: height);
      });
    });
    _playingSubscription = player.stream.playing.listen((playing) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(playing: playing);
      });
    });
    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(buffering: buffering);
      });
    });
    _bufferingPercentageSubscription =
        player.stream.bufferingPercentage.listen((
      bufferingPercentage,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState =
            _viewState.copyWith(bufferingPercentage: bufferingPercentage);
      });
    });
  }

  void _unbindPlayer() {
    unawaited(_tracksSubscription?.cancel());
    unawaited(_trackSubscription?.cancel());
    unawaited(_playlistModeSubscription?.cancel());
    unawaited(_rateSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_widthSubscription?.cancel());
    unawaited(_heightSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_bufferingSubscription?.cancel());
    unawaited(_bufferingPercentageSubscription?.cancel());
    _tracksSubscription = null;
    _trackSubscription = null;
    _playlistModeSubscription = null;
    _rateSubscription = null;
    _durationSubscription = null;
    _positionSubscription = null;
    _widthSubscription = null;
    _heightSubscription = null;
    _playingSubscription = null;
    _bufferingSubscription = null;
    _bufferingPercentageSubscription = null;
  }

  Future<void> _setRate(double value) => widget.player.setRate(value);

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

  Future<void> _seekBy(Duration delta) async {
    final current = _viewState.position;
    final duration = _viewState.duration;
    var target = current + delta;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (duration > Duration.zero && target > duration) {
      target = duration;
    }
    await widget.player.seek(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positionLabel = formatPlaybackClockDuration(_viewState.position);
    final durationLabel = _viewState.duration > Duration.zero
        ? formatPlaybackClockDuration(_viewState.duration)
        : '--:--';
    final progressLabel = '$positionLabel / $durationLabel';
    final bufferLabel = '${_viewState.bufferingPercentage.round()}%';
    final videoSizeLabel = _buildVideoSizeLabel(
      _viewState.width,
      _viewState.height,
      fallback: widget.target.resolutionLabel,
    );
    final body = ListView(
      shrinkWrap: true,
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
        const SizedBox(height: 16),
        _PlaybackInfoTile(
          progressLabel: progressLabel,
          videoSizeLabel: videoSizeLabel,
          speedLabel: formatPlaybackSpeed(_viewState.rate),
          playlistModeLabel: _formatPlaylistModeLabel(_viewState.playlistMode),
          bufferingLabel: bufferLabel,
          buffering: _viewState.buffering,
          playing: _viewState.playing,
          sourceLabel: widget.target.sourceName,
          formatLabel: widget.target.formatLabel,
          bitrateLabel: widget.target.bitrateLabel,
        ),
        const SizedBox(height: 12),
        _SectionLabel(
          title: '快捷操作',
          icon: Icons.flash_on_rounded,
        ),
        const SizedBox(height: 8),
        _PlaybackQuickSpeedTile(
          isTelevision: widget.isTelevision,
          currentRate: _viewState.rate,
          onSetRate: _setRate,
        ),
        const SizedBox(height: 8),
        _PlaybackQuickSeekTile(
          isTelevision: widget.isTelevision,
          onSeekBy: _seekBy,
        ),
        const SizedBox(height: 12),
        _SectionLabel(
          title: '详细设置',
          icon: Icons.tune_rounded,
        ),
        const SizedBox(height: 8),
        _PlaybackOptionTile(
          isTelevision: widget.isTelevision,
          title: '播放速度',
          value: formatPlaybackSpeed(_viewState.rate),
          onPressed: () => widget.onSelectSpeed(_viewState.rate),
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
          title: 'MPV 画质策略',
          value: widget.mpvQualityPresetLabel,
          onPressed: widget.onSelectMpvQualityPreset,
        ),
        const SizedBox(height: 8),
        _PlaybackOptionTile(
          isTelevision: widget.isTelevision,
          title: '画面适配',
          value: widget.videoLayoutLabel,
          onPressed: widget.onSelectVideoLayout,
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
      ],
    );
    return body;
  }
}

class _PlaybackSubtitleOptionsDialog extends StatelessWidget {
  const _PlaybackSubtitleOptionsDialog({
    required this.isTelevision,
    required this.currentSubtitleLabel,
    required this.defaultSubtitleScaleLabel,
    required this.subtitleDelayLabel,
    required this.onSelectSubtitle,
    required this.onAdjustSubtitleDelay,
    required this.onLoadExternalSubtitle,
    required this.onSearchSubtitlesOnline,
  });

  final bool isTelevision;
  final String currentSubtitleLabel;
  final String defaultSubtitleScaleLabel;
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
                value: 'SubHD / 搜索引擎',
                onPressed: onSearchSubtitlesOnline,
              ),
              const SizedBox(height: 10),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  leading: const Icon(Icons.format_size_rounded),
                  title: const Text('默认字幕大小'),
                  subtitle: Text('$defaultSubtitleScaleLabel，可在设置页修改'),
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

class _PlaybackInfoTile extends StatelessWidget {
  const _PlaybackInfoTile({
    required this.progressLabel,
    required this.videoSizeLabel,
    required this.speedLabel,
    required this.playlistModeLabel,
    required this.bufferingLabel,
    required this.buffering,
    required this.playing,
    required this.sourceLabel,
    required this.formatLabel,
    required this.bitrateLabel,
  });

  final String progressLabel;
  final String videoSizeLabel;
  final String speedLabel;
  final String playlistModeLabel;
  final String bufferingLabel;
  final bool buffering;
  final bool playing;
  final String sourceLabel;
  final String formatLabel;
  final String bitrateLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '播放信息',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _InfoRow(label: '进度', value: progressLabel),
            _InfoRow(label: '画面', value: videoSizeLabel),
            _InfoRow(label: '速度', value: speedLabel),
            _InfoRow(label: '循环', value: playlistModeLabel),
            _InfoRow(
              label: '状态',
              value: buffering ? '缓冲中' : (playing ? '播放中' : '已暂停'),
            ),
            _InfoRow(label: '缓冲进度', value: bufferingLabel),
            _InfoRow(label: '来源', value: sourceLabel),
            if (formatLabel.isNotEmpty)
              _InfoRow(label: '封装', value: formatLabel),
            if (bitrateLabel.isNotEmpty)
              _InfoRow(label: '码率', value: bitrateLabel),
          ],
        ),
      ),
    );
  }
}

class _PlaybackQuickSpeedTile extends StatelessWidget {
  const _PlaybackQuickSpeedTile({
    required this.isTelevision,
    required this.currentRate,
    required this.onSetRate,
  });

  final bool isTelevision;
  final double currentRate;
  final Future<void> Function(double value) onSetRate;

  static const List<double> _presetRates = <double>[
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '速度快捷',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _presetRates.map((rate) {
                final selected = (currentRate - rate).abs() < 0.01;
                return _ActionChipButton(
                  isTelevision: isTelevision,
                  label: formatPlaybackSpeed(rate),
                  selected: selected,
                  autofocus: isTelevision && rate == _presetRates.first,
                  onTap: () => onSetRate(rate),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackQuickSeekTile extends StatelessWidget {
  const _PlaybackQuickSeekTile({
    required this.isTelevision,
    required this.onSeekBy,
  });

  final bool isTelevision;
  final Future<void> Function(Duration delta) onSeekBy;

  static const List<Duration> _seekDeltas = <Duration>[
    Duration(seconds: -30),
    Duration(seconds: -10),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '快捷跳转',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _seekDeltas.map((delta) {
                final seconds = delta.inSeconds;
                final label = seconds > 0 ? '+${seconds}s' : '${seconds}s';
                return _ActionChipButton(
                  isTelevision: isTelevision,
                  label: label,
                  icon: seconds < 0
                      ? Icons.replay_10_rounded
                      : Icons.forward_10_rounded,
                  onTap: () => onSeekBy(delta),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.isTelevision,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.autofocus = false,
  });

  final bool isTelevision;
  final String label;
  final IconData? icon;
  final Future<void> Function() onTap;
  final bool selected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    if (isTelevision) {
      return StarflowChipButton(
        label: label,
        icon: icon,
        selected: selected,
        autofocus: autofocus,
        onPressed: () {
          unawaited(onTap());
        },
      );
    }
    return ActionChip(
      avatar: icon == null ? null : Icon(icon, size: 18),
      label: Text(label),
      onPressed: () {
        unawaited(onTap());
      },
      backgroundColor:
          selected ? Theme.of(context).colorScheme.primaryContainer : null,
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

String _buildVideoSizeLabel(int? width, int? height,
    {required String fallback}) {
  final resolvedWidth = width ?? 0;
  final resolvedHeight = height ?? 0;
  if (resolvedWidth > 0 && resolvedHeight > 0) {
    return '${resolvedWidth}x$resolvedHeight';
  }
  if (fallback.trim().isNotEmpty) {
    return fallback.trim();
  }
  return '识别中';
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
    required this.duration,
    required this.position,
    required this.width,
    required this.height,
    required this.playing,
    required this.buffering,
    required this.bufferingPercentage,
  });

  factory _PlaybackDialogViewState.fromPlayer(Player player) {
    return _PlaybackDialogViewState(
      tracks: player.state.tracks,
      currentTrack: player.state.track,
      playlistMode: player.state.playlistMode,
      rate: player.state.rate,
      duration: player.state.duration,
      position: player.state.position,
      width: player.state.width,
      height: player.state.height,
      playing: player.state.playing,
      buffering: player.state.buffering,
      bufferingPercentage: player.state.bufferingPercentage,
    );
  }

  final Tracks tracks;
  final Track currentTrack;
  final PlaylistMode playlistMode;
  final double rate;
  final Duration duration;
  final Duration position;
  final int? width;
  final int? height;
  final bool playing;
  final bool buffering;
  final double bufferingPercentage;

  _PlaybackDialogViewState copyWith({
    Tracks? tracks,
    Track? currentTrack,
    PlaylistMode? playlistMode,
    double? rate,
    Duration? duration,
    Duration? position,
    int? width,
    int? height,
    bool? playing,
    bool? buffering,
    double? bufferingPercentage,
  }) {
    return _PlaybackDialogViewState(
      tracks: tracks ?? this.tracks,
      currentTrack: currentTrack ?? this.currentTrack,
      playlistMode: playlistMode ?? this.playlistMode,
      rate: rate ?? this.rate,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      bufferingPercentage: bufferingPercentage ?? this.bufferingPercentage,
    );
  }
}
