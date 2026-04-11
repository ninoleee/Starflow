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
    required this.defaultSubtitleScaleLabel,
    required this.subtitleDelayLabel,
    required this.seriesSkipLabel,
    required this.onSelectMpvQualityPreset,
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
        child: StreamBuilder<Tracks>(
          stream: player.stream.tracks,
          initialData: player.state.tracks,
          builder: (context, tracksSnapshot) {
            final tracks = tracksSnapshot.data ?? const Tracks();
            return StreamBuilder<Track>(
              stream: player.stream.track,
              initialData: player.state.track,
              builder: (context, trackSnapshot) {
                final currentTrack = trackSnapshot.data ?? const Track();
                return StreamBuilder<double>(
                  stream: player.stream.rate,
                  initialData: player.state.rate,
                  builder: (context, rateSnapshot) {
                    final rate = rateSnapshot.data ?? 1.0;
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        Text(
                          target.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          buildPlaybackOptionMeta(target),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        _PlaybackOptionTile(
                          isTelevision: isTelevision,
                          title: '播放速度',
                          value: formatPlaybackSpeed(rate),
                          onPressed: () => onSelectSpeed(rate),
                        ),
                        const SizedBox(height: 10),
                        _PlaybackOptionTile(
                          isTelevision: isTelevision,
                          title: 'MPV 画质策略',
                          value: mpvQualityPresetLabel,
                          onPressed: onSelectMpvQualityPreset,
                        ),
                        const SizedBox(height: 10),
                        _PlaybackOptionTile(
                          isTelevision: isTelevision,
                          title: '字幕',
                          value: buildPlaybackSubtitleOptionsSummary(
                            currentTrack.subtitle,
                            subtitleDelayLabel: subtitleDelayLabel,
                          ),
                          onPressed: () => _openSubtitleOptionsDialog(
                            context,
                            tracks,
                            currentTrack,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PlaybackOptionTile(
                          isTelevision: isTelevision,
                          title: '音轨',
                          value: formatPlaybackAudioTrackLabel(
                            currentTrack.audio,
                          ),
                          onPressed: () =>
                              onSelectAudio(tracks.audio, currentTrack.audio),
                        ),
                        const SizedBox(height: 10),
                        _PlaybackOptionTile(
                          isTelevision: isTelevision,
                          title: '本剧跳过片头片尾',
                          value: seriesSkipLabel,
                          onPressed: onConfigureSeriesSkip,
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        StarflowButton(
          label: '关闭',
          onPressed: () => Navigator.of(context).pop(),
          variant: StarflowButtonVariant.ghost,
          compact: true,
        ),
      ],
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '默认字幕大小',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$defaultSubtitleScaleLabel，可在设置页修改',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        StarflowButton(
          label: '关闭',
          onPressed: () => Navigator.of(context).pop(),
          variant: StarflowButtonVariant.ghost,
          compact: true,
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
    return StarflowSelectionTile(
      title: title,
      subtitle: value,
      onPressed: () {
        unawaited(onPressed());
      },
    );
  }
}
