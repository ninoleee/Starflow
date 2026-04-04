import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

class MediaDetailTarget {
  const MediaDetailTarget({
    required this.title,
    required this.posterUrl,
    required this.overview,
    this.year = 0,
    this.durationLabel = '',
    this.genres = const [],
    this.directors = const [],
    this.actors = const [],
    this.availabilityLabel = '',
    this.searchQuery = '',
    this.playbackTarget,
    this.sourceKind,
    this.sourceName = '',
  });

  final String title;
  final String posterUrl;
  final String overview;
  final int year;
  final String durationLabel;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final String availabilityLabel;
  final String searchQuery;
  final PlaybackTarget? playbackTarget;
  final MediaSourceKind? sourceKind;
  final String sourceName;

  bool get isPlayable =>
      playbackTarget != null && playbackTarget!.streamUrl.trim().isNotEmpty;

  factory MediaDetailTarget.fromMediaItem(
    MediaItem item, {
    String availabilityLabel = '',
    String searchQuery = '',
  }) {
    return MediaDetailTarget(
      title: item.title,
      posterUrl: item.posterUrl,
      overview: item.overview,
      year: item.year,
      durationLabel: item.durationLabel,
      genres: item.genres,
      directors: item.directors,
      actors: item.actors,
      availabilityLabel: availabilityLabel.isEmpty
          ? '资源已就绪：${item.sourceKind.label} · ${item.sourceName}'
          : availabilityLabel,
      searchQuery: searchQuery.isEmpty ? item.title : searchQuery,
      playbackTarget: PlaybackTarget.fromMediaItem(item),
      sourceKind: item.sourceKind,
      sourceName: item.sourceName,
    );
  }
}
