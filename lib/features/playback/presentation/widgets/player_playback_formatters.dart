import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

String buildPlaybackSubtitleOptionsSummary(
  SubtitleTrack track, {
  required String subtitleDelayLabel,
}) {
  return '${formatPlaybackSubtitleTrackLabel(track)} · 偏移 $subtitleDelayLabel';
}

String buildPlaybackOptionMeta(PlaybackTarget target) {
  final parts = <String>[
    if (target.resolutionLabel.isNotEmpty) target.resolutionLabel,
    if (target.formatLabel.isNotEmpty) target.formatLabel,
    if (target.bitrateLabel.isNotEmpty) target.bitrateLabel,
  ];
  if (parts.isEmpty) {
    return '${target.sourceKind.label} · ${target.sourceName}';
  }
  return '${target.sourceKind.label} · ${target.sourceName} · ${parts.join(' · ')}';
}

String buildPlaybackStartupFormatValue(PlaybackTarget target) {
  final parts = <String>[
    if (target.resolutionLabel.isNotEmpty) target.resolutionLabel,
    if (target.formatLabel.isNotEmpty) target.formatLabel,
    if (target.bitrateLabel.isNotEmpty) target.bitrateLabel,
  ];
  if (parts.isEmpty) {
    return '识别中';
  }
  return parts.join(' · ');
}

String formatPlaybackSpeed(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toStringAsFixed(0)}x';
  }
  return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
}

String formatSubtitleDelayLabel(
  double seconds, {
  required bool supported,
}) {
  if (!supported) {
    return '当前内核暂不支持';
  }
  return formatSubtitleDelayValue(seconds);
}

String formatSubtitleDelayValue(double seconds) {
  if (seconds.abs() < 0.001) {
    return '0s';
  }
  final normalized = seconds
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return seconds > 0 ? '+${normalized}s' : '${normalized}s';
}

String formatSeriesSkipPreferenceLabel(
  SeriesSkipPreference? preference, {
  required PlaybackTarget target,
}) {
  final seriesKey = buildSeriesKeyForTarget(target);
  if (seriesKey.isEmpty) {
    return '当前内容没有可绑定的剧集信息';
  }
  if (preference == null ||
      (!preference.enabled &&
          preference.introDuration <= Duration.zero &&
          preference.outroDuration <= Duration.zero)) {
    return '未设置';
  }

  final parts = <String>[
    preference.enabled ? '已开启' : '已关闭',
    if (preference.introDuration > Duration.zero)
      '片头 ${formatPlaybackClockDuration(preference.introDuration)}',
    if (preference.outroDuration > Duration.zero)
      '片尾 ${formatPlaybackClockDuration(preference.outroDuration)}',
  ];
  return parts.join(' · ');
}

String formatPlaybackClockDuration(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatPlaybackAudioTrackLabel(AudioTrack track) {
  if (track.id == 'auto') {
    return '自动';
  }
  if (track.id == 'no') {
    return '关闭';
  }

  final parts = <String>[
    if ((track.title ?? '').trim().isNotEmpty) track.title!.trim(),
    if ((track.language ?? '').trim().isNotEmpty)
      track.language!.trim().toUpperCase(),
    if ((track.codec ?? '').trim().isNotEmpty)
      track.codec!.trim().toUpperCase(),
  ];
  final channelCount = track.audiochannels ?? track.channelscount;
  if (channelCount != null && channelCount > 0) {
    parts.add('${channelCount}ch');
  }
  if (track.isDefault == true) {
    parts.add('默认');
  }
  return parts.isEmpty ? '音轨 ${track.id}' : parts.join(' · ');
}

String formatPlaybackSubtitleTrackLabel(SubtitleTrack track) {
  if (track.id == 'auto') {
    return '自动';
  }
  if (track.id == 'no') {
    return '关闭';
  }

  final parts = <String>[
    if ((track.title ?? '').trim().isNotEmpty) track.title!.trim(),
    if ((track.language ?? '').trim().isNotEmpty)
      track.language!.trim().toUpperCase(),
  ];
  if (track.isDefault == true) {
    parts.add('默认');
  }
  return parts.isEmpty ? '字幕 ${track.id}' : parts.join(' · ');
}
