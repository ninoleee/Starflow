import 'package:starflow/features/playback/domain/playback_models.dart';

String fntvQualityTitle(FntvPlaybackQuality quality) {
  final raw = quality.resolution.trim();
  final normalized = raw.toUpperCase();
  if (const ['原画', '原始', 'ORIGINAL', 'SOURCE'].contains(normalized)) {
    return '原画';
  }
  if (const ['4K', '2160', '2160P'].contains(normalized)) return '4K';
  final height = int.tryParse(normalized.replaceFirst(RegExp(r'P$'), ''));
  if (height != null && height > 0) return '${height}P';
  return raw.isEmpty ? '画质 ${quality.index.abs() + 1}' : raw;
}

String fntvQualityDetail(FntvPlaybackQuality quality) {
  final bitrate = quality.bitrate;
  return [
    fntvQualityTitle(quality),
    if (bitrate > 0)
      bitrate >= 1000000
          ? '${(bitrate / 1000000).toStringAsFixed(1)} Mbps'
          : '${(bitrate / 1000).round()} Kbps',
  ].join(' · ');
}

List<FntvPlaybackQuality> fntvQualityPresets(
    List<FntvPlaybackQuality> qualities, int? currentIndex) {
  final groups = <String, FntvPlaybackQuality>{};
  for (final quality in qualities) {
    final title = fntvQualityTitle(quality);
    if (!groups.containsKey(title) || quality.index == currentIndex) {
      groups[title] = quality;
    }
  }
  return groups.values.toList(growable: false);
}
