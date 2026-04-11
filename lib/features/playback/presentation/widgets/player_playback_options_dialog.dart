import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
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
    required this.defaultSubtitleScaleLabel,
    required this.subtitleDelayLabel,
    required this.seriesSkipLabel,
    required this.onSelectMpvQualityPreset,
    required this.onSelectSpeed,
    required this.onSelectSubtitle,
    required this.onSelectAudio,
    required this.onSetVolume,
    required this.onAdjustSubtitleDelay,
    required this.onLoadExternalSubtitle,
    required this.onSearchSubtitlesOnline,
    required this.onConfigureSeriesSkip,
  });

  final Player player;
  final PlaybackTarget target;
  final bool isTelevision;
  final String defaultSubtitleScaleLabel;
  final String subtitleDelayLabel;
  final String seriesSkipLabel;
  final Future<void> Function() onSelectMpvQualityPreset;
  final Future<void> Function(double currentRate) onSelectSpeed;
  final Future<void> Function(
    List<SubtitleTrack> tracks,
    SubtitleTrack current,
  ) onSelectSubtitle;
  final Future<void> Function(
    List<AudioTrack> tracks,
    AudioTrack current,
  ) onSelectAudio;
  final Future<void> Function(double value) onSetVolume;
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
    return AlertDialog(
      title: const Text('播放设置'),
      content: SizedBox(
        width: 440,
        child: _PlaybackOptionsDialogBody(
          player: player,
          target: target,
          isTelevision: isTelevision,
          mpvQualityPresetLabel: mpvQualityPresetLabel,
          subtitleDelayLabel: subtitleDelayLabel,
          seriesSkipLabel: seriesSkipLabel,
          onOpenSubtitleOptionsDialog: _openSubtitleOptionsDialog,
          onSelectMpvQualityPreset: onSelectMpvQualityPreset,
          onSelectSpeed: onSelectSpeed,
          onSelectAudio: onSelectAudio,
          onSetVolume: onSetVolume,
          onConfigureSeriesSkip: onConfigureSeriesSkip,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _PlaybackOptionsDialogBody extends StatefulWidget {
  const _PlaybackOptionsDialogBody({
    required this.player,
    required this.target,
    required this.isTelevision,
    required this.mpvQualityPresetLabel,
    required this.subtitleDelayLabel,
    required this.seriesSkipLabel,
    required this.onOpenSubtitleOptionsDialog,
    required this.onSelectMpvQualityPreset,
    required this.onSelectSpeed,
    required this.onSelectAudio,
    required this.onSetVolume,
    required this.onConfigureSeriesSkip,
  });

  final Player player;
  final PlaybackTarget target;
  final bool isTelevision;
  final String mpvQualityPresetLabel;
  final String subtitleDelayLabel;
  final String seriesSkipLabel;
  final Future<void> Function(
    BuildContext context,
    Tracks tracks,
    Track currentTrack,
  ) onOpenSubtitleOptionsDialog;
  final Future<void> Function() onSelectMpvQualityPreset;
  final Future<void> Function(double currentRate) onSelectSpeed;
  final Future<void> Function(
    List<AudioTrack> tracks,
    AudioTrack current,
  ) onSelectAudio;
  final Future<void> Function(double value) onSetVolume;
  final Future<void> Function() onConfigureSeriesSkip;

  @override
  State<_PlaybackOptionsDialogBody> createState() =>
      _PlaybackOptionsDialogBodyState();
}

class _PlaybackOptionsDialogBodyState extends State<_PlaybackOptionsDialogBody> {
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<Track>? _trackSubscription;
  StreamSubscription<double>? _rateSubscription;
  StreamSubscription<double>? _volumeSubscription;
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
    _rateSubscription = player.stream.rate.listen((rate) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(rate: rate);
      });
    });
    _volumeSubscription = player.stream.volume.listen((volume) {
      if (!mounted) {
        return;
      }
      setState(() {
        _viewState = _viewState.copyWith(volume: volume);
      });
    });
  }

  void _unbindPlayer() {
    unawaited(_tracksSubscription?.cancel());
    unawaited(_trackSubscription?.cancel());
    unawaited(_rateSubscription?.cancel());
    unawaited(_volumeSubscription?.cancel());
    _tracksSubscription = null;
    _trackSubscription = null;
    _rateSubscription = null;
    _volumeSubscription = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volume = _viewState.volume.clamp(0.0, 100.0);
    return ListView(
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
        _PlaybackVolumeTile(
          volume: volume,
          onChanged: widget.onSetVolume,
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
          title: 'MPV 画质策略',
          value: widget.mpvQualityPresetLabel,
          onPressed: widget.onSelectMpvQualityPreset,
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
  }
}

class _PlaybackVolumeTile extends StatelessWidget {
  const _PlaybackVolumeTile({
    required this.volume,
    required this.onChanged,
  });

  final double volume;
  final Future<void> Function(double value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        leading: const Icon(Icons.volume_up_rounded),
        title: const Text('音量'),
        subtitle: Slider(
          min: 0,
          max: 100,
          value: volume,
          onChanged: (value) {
            unawaited(onChanged(value));
          },
        ),
        trailing: SizedBox(
          width: 40,
          child: Text(
            volume.round().toString(),
            textAlign: TextAlign.right,
          ),
        ),
      ),
    );
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
    return AlertDialog(
      title: const Text('字幕'),
      content: SizedBox(
        width: 440,
        child: ListView(
          shrinkWrap: true,
          children: [
            _PlaybackOptionTile(
              isTelevision: isTelevision,
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
    );
  }
}

class _PlaybackOptionTile extends StatelessWidget {
  const _PlaybackOptionTile({
    required this.isTelevision,
    required this.title,
    required this.value,
    required this.onPressed,
  });

  final bool isTelevision;
  final String title;
  final String value;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
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

class _PlaybackDialogViewState {
  const _PlaybackDialogViewState({
    required this.tracks,
    required this.currentTrack,
    required this.rate,
    required this.volume,
  });

  factory _PlaybackDialogViewState.fromPlayer(Player player) {
    return _PlaybackDialogViewState(
      tracks: player.state.tracks,
      currentTrack: player.state.track,
      rate: player.state.rate,
      volume: player.state.volume,
    );
  }

  final Tracks tracks;
  final Track currentTrack;
  final double rate;
  final double volume;

  _PlaybackDialogViewState copyWith({
    Tracks? tracks,
    Track? currentTrack,
    double? rate,
    double? volume,
  }) {
    return _PlaybackDialogViewState(
      tracks: tracks ?? this.tracks,
      currentTrack: currentTrack ?? this.currentTrack,
      rate: rate ?? this.rate,
      volume: volume ?? this.volume,
    );
  }
}
