import 'package:starflow/features/playback/domain/playback_models.dart';

String playerTitle(PlaybackTarget target) {
  final title = target.title.trim();
  final series = target.seriesTitle.trim();
  final episode = target.episodeNumber;
  if (episode != null && episode > 0) {
    final name = series.isNotEmpty ? series : title;
    final marker = RegExp(
      '第\\s*0?$episode\\s*集|\\b(?:s\\d+)?e0?$episode\\b',
      caseSensitive: false,
    );
    if (marker.hasMatch(name)) return name;
    return name.isEmpty ? '第 $episode 集' : '$name · 第 $episode 集';
  }
  return title.isNotEmpty ? title : (series.isNotEmpty ? series : 'Starflow');
}
