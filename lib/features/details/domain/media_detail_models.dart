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
    this.itemId = '',
    this.sourceId = '',
    this.itemType = '',
    this.sectionId = '',
    this.sectionName = '',
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
  final String itemId;
  final String sourceId;
  final String itemType;
  final String sectionId;
  final String sectionName;
  final MediaSourceKind? sourceKind;
  final String sourceName;

  bool get isPlayable => playbackTarget?.canPlay == true;

  bool get isSeries => itemType.trim().toLowerCase() == 'series';

  bool get needsMetadataMatch =>
      posterUrl.trim().isEmpty &&
      overview.trim().isEmpty &&
      directors.isEmpty &&
      actors.isEmpty &&
      genres.isEmpty;

  MediaDetailTarget copyWith({
    String? title,
    String? posterUrl,
    String? overview,
    int? year,
    String? durationLabel,
    List<String>? genres,
    List<String>? directors,
    List<String>? actors,
    String? availabilityLabel,
    String? searchQuery,
    PlaybackTarget? playbackTarget,
    String? itemId,
    String? sourceId,
    String? itemType,
    String? sectionId,
    String? sectionName,
    MediaSourceKind? sourceKind,
    String? sourceName,
  }) {
    return MediaDetailTarget(
      title: title ?? this.title,
      posterUrl: posterUrl ?? this.posterUrl,
      overview: overview ?? this.overview,
      year: year ?? this.year,
      durationLabel: durationLabel ?? this.durationLabel,
      genres: genres ?? this.genres,
      directors: directors ?? this.directors,
      actors: actors ?? this.actors,
      availabilityLabel: availabilityLabel ?? this.availabilityLabel,
      searchQuery: searchQuery ?? this.searchQuery,
      playbackTarget: playbackTarget ?? this.playbackTarget,
      itemId: itemId ?? this.itemId,
      sourceId: sourceId ?? this.sourceId,
      itemType: itemType ?? this.itemType,
      sectionId: sectionId ?? this.sectionId,
      sectionName: sectionName ?? this.sectionName,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceName: sourceName ?? this.sourceName,
    );
  }

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
      playbackTarget:
          item.isPlayable ? PlaybackTarget.fromMediaItem(item) : null,
      itemId: item.id,
      sourceId: item.sourceId,
      itemType: item.itemType,
      sectionId: item.sectionId,
      sectionName: item.sectionName,
      sourceKind: item.sourceKind,
      sourceName: item.sourceName,
    );
  }
}
