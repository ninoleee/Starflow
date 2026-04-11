import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';

Future<void> showPlaybackSubtitleDelayDialog({
  required BuildContext context,
  required double initialDelay,
  required List<double> steps,
  required Future<double> Function(double nextDelay) onApplyDelay,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      var currentDelay = initialDelay;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('字幕偏移'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前偏移：${formatSubtitleDelayValue(currentDelay)}'),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final step in steps)
                      StarflowButton(
                        label: _buildSubtitleDelayStepLabel(step),
                        onPressed: () async {
                          final nextDelay =
                              step == 0 ? 0.0 : currentDelay + step;
                          final appliedDelay = await onApplyDelay(nextDelay);
                          setDialogState(() {
                            currentDelay = appliedDelay;
                          });
                        },
                        variant: StarflowButtonVariant.secondary,
                        compact: true,
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              StarflowButton(
                label: '关闭',
                onPressed: () => Navigator.of(dialogContext).pop(),
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
            ],
          );
        },
      );
    },
  );
}

Future<SeriesSkipPreference?> showPlaybackSeriesSkipDialog({
  required BuildContext context,
  required PlaybackTarget target,
  required Duration playerDuration,
  required Duration currentPosition,
  required SeriesSkipPreference seedPreference,
}) {
  return showDialog<SeriesSkipPreference>(
    context: context,
    builder: (dialogContext) {
      var enabled = seedPreference.enabled;
      var introDuration = seedPreference.introDuration;
      var outroDuration = seedPreference.outroDuration;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          final canCaptureOutro = playerDuration > Duration.zero &&
              currentPosition < playerDuration;
          return AlertDialog(
            title: Text(
              target.resolvedSeriesTitle.isEmpty ? '跳过片头片尾' : '本剧跳过设置',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarflowToggleTile(
                  title: '自动跳过',
                  subtitle: target.resolvedSeriesTitle.isEmpty
                      ? '只对当前绑定的剧集生效'
                      : '只对《${target.resolvedSeriesTitle}》生效',
                  value: enabled,
                  onChanged: (value) {
                    setDialogState(() {
                      enabled = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                StarflowSelectionTile(
                  title: '片头结束位置',
                  subtitle: introDuration > Duration.zero
                      ? formatPlaybackClockDuration(introDuration)
                      : '未设置',
                  onPressed: () {
                    setDialogState(() {
                      introDuration = currentPosition;
                    });
                  },
                  trailing: StarflowButton(
                    label: '用当前位置',
                    onPressed: () {
                      setDialogState(() {
                        introDuration = currentPosition;
                      });
                    },
                    variant: StarflowButtonVariant.secondary,
                    compact: true,
                  ),
                ),
                StarflowSelectionTile(
                  title: '片尾提前跳过',
                  subtitle: outroDuration > Duration.zero
                      ? '距结尾 ${formatPlaybackClockDuration(outroDuration)}'
                      : '未设置',
                  onPressed: !canCaptureOutro
                      ? null
                      : () {
                          setDialogState(() {
                            outroDuration = playerDuration - currentPosition;
                          });
                        },
                  trailing: StarflowButton(
                    label: '用当前位置',
                    onPressed: !canCaptureOutro
                        ? null
                        : () {
                            setDialogState(() {
                              outroDuration = playerDuration - currentPosition;
                            });
                          },
                    variant: StarflowButtonVariant.secondary,
                    compact: true,
                  ),
                ),
                if (playerDuration > Duration.zero)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '当前位置 ${formatPlaybackClockDuration(currentPosition)} / ${formatPlaybackClockDuration(playerDuration)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
            actions: [
              StarflowButton(
                label: '清空',
                onPressed: () {
                  setDialogState(() {
                    enabled = false;
                    introDuration = Duration.zero;
                    outroDuration = Duration.zero;
                  });
                },
                variant: StarflowButtonVariant.secondary,
                compact: true,
              ),
              StarflowButton(
                label: '取消',
                onPressed: () => Navigator.of(dialogContext).pop(),
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
              StarflowButton(
                label: '保存',
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    SeriesSkipPreference(
                      seriesKey: seedPreference.seriesKey,
                      updatedAt: DateTime.now(),
                      seriesTitle: target.resolvedSeriesTitle,
                      enabled: enabled,
                      introDuration: introDuration,
                      outroDuration: outroDuration,
                    ),
                  );
                },
                compact: true,
              ),
            ],
          );
        },
      );
    },
  );
}

String _buildSubtitleDelayStepLabel(double step) {
  if (step == 0) {
    return '重置';
  }
  final fixed = step.toStringAsFixed(step == step.roundToDouble() ? 0 : 1);
  return step > 0 ? '+${fixed}s' : '${fixed}s';
}
