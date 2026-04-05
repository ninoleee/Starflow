import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

class MediaPersonProfile {
  const MediaPersonProfile({
    required this.name,
    this.avatarUrl = '',
  });

  final String name;
  final String avatarUrl;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'avatarUrl': avatarUrl,
    };
  }

  factory MediaPersonProfile.fromJson(Map<String, dynamic> json) {
    return MediaPersonProfile(
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
    );
  }
}

class MediaDetailTarget {
  const MediaDetailTarget({
    required this.title,
    required this.posterUrl,
    this.posterHeaders = const {},
    required this.overview,
    this.year = 0,
    this.durationLabel = '',
    this.ratingLabels = const [],
    this.genres = const [],
    this.directors = const [],
    this.actors = const [],
    this.actorProfiles = const [],
    this.availabilityLabel = '',
    this.searchQuery = '',
    this.playbackTarget,
    this.itemId = '',
    this.sourceId = '',
    this.itemType = '',
    this.sectionId = '',
    this.sectionName = '',
    this.doubanId = '',
    this.imdbId = '',
    this.tmdbId = '',
    this.sourceKind,
    this.sourceName = '',
  });

  final String title;
  final String posterUrl;
  final Map<String, String> posterHeaders;
  final String overview;
  final int year;
  final String durationLabel;
  final List<String> ratingLabels;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final List<MediaPersonProfile> actorProfiles;
  final String availabilityLabel;
  final String searchQuery;
  final PlaybackTarget? playbackTarget;
  final String itemId;
  final String sourceId;
  final String itemType;
  final String sectionId;
  final String sectionName;
  final String doubanId;
  final String imdbId;
  final String tmdbId;
  final MediaSourceKind? sourceKind;
  final String sourceName;

  bool get isPlayable => playbackTarget?.canPlay == true;

  bool get isSeries => itemType.trim().toLowerCase() == 'series';

  bool get hasUsefulOverview => _hasUsefulOverview(overview);

  bool get needsLibraryMatch {
    return sourceId.trim().isEmpty || itemId.trim().isEmpty;
  }

  bool get needsImdbRatingMatch {
    return ratingLabels.every(
      (label) => !label.toLowerCase().startsWith('imdb '),
    );
  }

  bool get needsMetadataMatch {
    final hasPoster = posterUrl.trim().isNotEmpty;
    final hasPeople =
        directors.isNotEmpty || actors.isNotEmpty || actorProfiles.isNotEmpty;
    final hasGenres = genres.isNotEmpty;
    final hasOverview = hasUsefulOverview;
    return !hasPoster || !(hasOverview || hasPeople || hasGenres);
  }

  List<MediaPersonProfile> get resolvedActorProfiles {
    if (actorProfiles.isNotEmpty) {
      return actorProfiles;
    }
    return actors
        .where((item) => item.trim().isNotEmpty)
        .map((item) => MediaPersonProfile(name: item.trim()))
        .toList();
  }

  static bool _hasUsefulOverview(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(cleaned);
    if (uri != null && uri.hasScheme) {
      return false;
    }
    return true;
  }

  MediaDetailTarget copyWith({
    String? title,
    String? posterUrl,
    Map<String, String>? posterHeaders,
    String? overview,
    int? year,
    String? durationLabel,
    List<String>? ratingLabels,
    List<String>? genres,
    List<String>? directors,
    List<String>? actors,
    List<MediaPersonProfile>? actorProfiles,
    String? availabilityLabel,
    String? searchQuery,
    PlaybackTarget? playbackTarget,
    String? itemId,
    String? sourceId,
    String? itemType,
    String? sectionId,
    String? sectionName,
    String? doubanId,
    String? imdbId,
    String? tmdbId,
    MediaSourceKind? sourceKind,
    String? sourceName,
  }) {
    return MediaDetailTarget(
      title: title ?? this.title,
      posterUrl: posterUrl ?? this.posterUrl,
      posterHeaders: posterHeaders ?? this.posterHeaders,
      overview: overview ?? this.overview,
      year: year ?? this.year,
      durationLabel: durationLabel ?? this.durationLabel,
      ratingLabels: ratingLabels ?? this.ratingLabels,
      genres: genres ?? this.genres,
      directors: directors ?? this.directors,
      actors: actors ?? this.actors,
      actorProfiles: actorProfiles ?? this.actorProfiles,
      availabilityLabel: availabilityLabel ?? this.availabilityLabel,
      searchQuery: searchQuery ?? this.searchQuery,
      playbackTarget: playbackTarget ?? this.playbackTarget,
      itemId: itemId ?? this.itemId,
      sourceId: sourceId ?? this.sourceId,
      itemType: itemType ?? this.itemType,
      sectionId: sectionId ?? this.sectionId,
      sectionName: sectionName ?? this.sectionName,
      doubanId: doubanId ?? this.doubanId,
      imdbId: imdbId ?? this.imdbId,
      tmdbId: tmdbId ?? this.tmdbId,
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
      posterHeaders: item.posterHeaders,
      overview: item.overview,
      year: item.year,
      durationLabel: item.durationLabel,
      ratingLabels: item.ratingLabels,
      genres: item.genres,
      directors: item.directors,
      actors: item.actors,
      actorProfiles: item.actors
          .where((entry) => entry.trim().isNotEmpty)
          .map((entry) => MediaPersonProfile(name: entry.trim()))
          .toList(),
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
      doubanId: item.doubanId,
      imdbId: item.imdbId,
      tmdbId: item.tmdbId,
      sourceKind: item.sourceKind,
      sourceName: item.sourceName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'posterUrl': posterUrl,
      'posterHeaders': posterHeaders,
      'overview': overview,
      'year': year,
      'durationLabel': durationLabel,
      'ratingLabels': ratingLabels,
      'genres': genres,
      'directors': directors,
      'actors': actors,
      'actorProfiles': actorProfiles.map((item) => item.toJson()).toList(),
      'availabilityLabel': availabilityLabel,
      'searchQuery': searchQuery,
      'playbackTarget': playbackTarget?.toJson(),
      'itemId': itemId,
      'sourceId': sourceId,
      'itemType': itemType,
      'sectionId': sectionId,
      'sectionName': sectionName,
      'doubanId': doubanId,
      'imdbId': imdbId,
      'tmdbId': tmdbId,
      'sourceKind': sourceKind?.name,
      'sourceName': sourceName,
    };
  }

  factory MediaDetailTarget.fromJson(Map<String, dynamic> json) {
    return MediaDetailTarget(
      title: json['title'] as String? ?? '',
      posterUrl: json['posterUrl'] as String? ?? '',
      posterHeaders:
          (json['posterHeaders'] as Map<dynamic, dynamic>? ?? const {})
              .map((key, value) => MapEntry('$key', '$value')),
      overview: json['overview'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      durationLabel: json['durationLabel'] as String? ?? '',
      ratingLabels: (json['ratingLabels'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      directors: (json['directors'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      actors: (json['actors'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      actorProfiles: (json['actorProfiles'] as List<dynamic>? ?? const [])
          .map(
            (item) => MediaPersonProfile.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      availabilityLabel: json['availabilityLabel'] as String? ?? '',
      searchQuery: json['searchQuery'] as String? ?? '',
      playbackTarget: (json['playbackTarget'] as Map?) == null
          ? null
          : PlaybackTarget.fromJson(
              Map<String, dynamic>.from(json['playbackTarget'] as Map),
            ),
      itemId: json['itemId'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      itemType: json['itemType'] as String? ?? '',
      sectionId: json['sectionId'] as String? ?? '',
      sectionName: json['sectionName'] as String? ?? '',
      doubanId: json['doubanId'] as String? ?? '',
      imdbId: json['imdbId'] as String? ?? '',
      tmdbId: json['tmdbId'] as String? ?? '',
      sourceKind: (json['sourceKind'] as String?) == null
          ? null
          : MediaSourceKindX.fromName(json['sourceKind'] as String? ?? ''),
      sourceName: json['sourceName'] as String? ?? '',
    );
  }
}
