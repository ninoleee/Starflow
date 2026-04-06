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
    this.backdropUrl = '',
    this.backdropHeaders = const {},
    this.logoUrl = '',
    this.logoHeaders = const {},
    this.bannerUrl = '',
    this.bannerHeaders = const {},
    this.extraBackdropUrls = const [],
    this.extraBackdropHeaders = const {},
    required this.overview,
    this.year = 0,
    this.durationLabel = '',
    this.ratingLabels = const [],
    this.genres = const [],
    this.directors = const [],
    this.directorProfiles = const [],
    this.actors = const [],
    this.actorProfiles = const [],
    this.platforms = const [],
    this.platformProfiles = const [],
    this.availabilityLabel = '',
    this.searchQuery = '',
    this.playbackTarget,
    this.itemId = '',
    this.sourceId = '',
    this.itemType = '',
    this.seasonNumber,
    this.episodeNumber,
    this.sectionId = '',
    this.sectionName = '',
    this.resourcePath = '',
    this.doubanId = '',
    this.imdbId = '',
    this.tmdbId = '',
    this.tvdbId = '',
    this.wikidataId = '',
    this.tmdbSetId = '',
    this.providerIds = const {},
    this.sourceKind,
    this.sourceName = '',
  });

  final String title;
  final String posterUrl;
  final Map<String, String> posterHeaders;
  final String backdropUrl;
  final Map<String, String> backdropHeaders;
  final String logoUrl;
  final Map<String, String> logoHeaders;
  final String bannerUrl;
  final Map<String, String> bannerHeaders;
  final List<String> extraBackdropUrls;
  final Map<String, String> extraBackdropHeaders;
  final String overview;
  final int year;
  final String durationLabel;
  final List<String> ratingLabels;
  final List<String> genres;
  final List<String> directors;
  final List<MediaPersonProfile> directorProfiles;
  final List<String> actors;
  final List<MediaPersonProfile> actorProfiles;
  final List<String> platforms;
  final List<MediaPersonProfile> platformProfiles;
  final String availabilityLabel;
  final String searchQuery;
  final PlaybackTarget? playbackTarget;
  final String itemId;
  final String sourceId;
  final String itemType;
  final int? seasonNumber;
  final int? episodeNumber;
  final String sectionId;
  final String sectionName;
  final String resourcePath;
  final String doubanId;
  final String imdbId;
  final String tmdbId;
  final String tvdbId;
  final String wikidataId;
  final String tmdbSetId;
  final Map<String, String> providerIds;
  final MediaSourceKind? sourceKind;
  final String sourceName;

  bool get isPlayable => playbackTarget?.canPlay == true;

  bool get isSeries => itemType.trim().toLowerCase() == 'series';

  bool get hasUsefulOverview => _hasUsefulOverview(overview);

  bool get needsLibraryMatch {
    return sourceId.trim().isEmpty || itemId.trim().isEmpty;
  }

  bool get canManuallyMatchLibraryResource {
    final availability = availabilityLabel.trim();
    return !isPlayable &&
        (needsLibraryMatch || availability.isEmpty || availability == '无');
  }

  bool get shouldAutoMatchLibraryResource {
    return !isPlayable && needsLibraryMatch;
  }

  bool get needsImdbRatingMatch {
    return ratingLabels.every(
      (label) => !label.toLowerCase().startsWith('imdb '),
    );
  }

  bool get needsMetadataMatch {
    final hasPoster = posterUrl.trim().isNotEmpty;
    final hasPeople = directors.isNotEmpty ||
        directorProfiles.isNotEmpty ||
        actors.isNotEmpty ||
        actorProfiles.isNotEmpty;
    final hasGenres = genres.isNotEmpty;
    final hasOverview = hasUsefulOverview;
    return !hasPoster || !(hasOverview || hasPeople || hasGenres);
  }

  List<MediaPersonProfile> get resolvedDirectorProfiles {
    if (directorProfiles.isNotEmpty) {
      return directorProfiles;
    }
    return directors
        .where((item) => item.trim().isNotEmpty)
        .map((item) => MediaPersonProfile(name: item.trim()))
        .toList();
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

  List<MediaPersonProfile> get resolvedPlatformProfiles {
    if (platformProfiles.isNotEmpty) {
      return platformProfiles;
    }
    return platforms
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
    String? backdropUrl,
    Map<String, String>? backdropHeaders,
    String? logoUrl,
    Map<String, String>? logoHeaders,
    String? bannerUrl,
    Map<String, String>? bannerHeaders,
    List<String>? extraBackdropUrls,
    Map<String, String>? extraBackdropHeaders,
    String? overview,
    int? year,
    String? durationLabel,
    List<String>? ratingLabels,
    List<String>? genres,
    List<String>? directors,
    List<MediaPersonProfile>? directorProfiles,
    List<String>? actors,
    List<MediaPersonProfile>? actorProfiles,
    List<String>? platforms,
    List<MediaPersonProfile>? platformProfiles,
    String? availabilityLabel,
    String? searchQuery,
    PlaybackTarget? playbackTarget,
    String? itemId,
    String? sourceId,
    String? itemType,
    int? seasonNumber,
    int? episodeNumber,
    String? sectionId,
    String? sectionName,
    String? resourcePath,
    String? doubanId,
    String? imdbId,
    String? tmdbId,
    String? tvdbId,
    String? wikidataId,
    String? tmdbSetId,
    Map<String, String>? providerIds,
    MediaSourceKind? sourceKind,
    String? sourceName,
  }) {
    return MediaDetailTarget(
      title: title ?? this.title,
      posterUrl: posterUrl ?? this.posterUrl,
      posterHeaders: posterHeaders ?? this.posterHeaders,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      backdropHeaders: backdropHeaders ?? this.backdropHeaders,
      logoUrl: logoUrl ?? this.logoUrl,
      logoHeaders: logoHeaders ?? this.logoHeaders,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      bannerHeaders: bannerHeaders ?? this.bannerHeaders,
      extraBackdropUrls: extraBackdropUrls ?? this.extraBackdropUrls,
      extraBackdropHeaders: extraBackdropHeaders ?? this.extraBackdropHeaders,
      overview: overview ?? this.overview,
      year: year ?? this.year,
      durationLabel: durationLabel ?? this.durationLabel,
      ratingLabels: ratingLabels ?? this.ratingLabels,
      genres: genres ?? this.genres,
      directors: directors ?? this.directors,
      directorProfiles: directorProfiles ?? this.directorProfiles,
      actors: actors ?? this.actors,
      actorProfiles: actorProfiles ?? this.actorProfiles,
      platforms: platforms ?? this.platforms,
      platformProfiles: platformProfiles ?? this.platformProfiles,
      availabilityLabel: availabilityLabel ?? this.availabilityLabel,
      searchQuery: searchQuery ?? this.searchQuery,
      playbackTarget: playbackTarget ?? this.playbackTarget,
      itemId: itemId ?? this.itemId,
      sourceId: sourceId ?? this.sourceId,
      itemType: itemType ?? this.itemType,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      sectionId: sectionId ?? this.sectionId,
      sectionName: sectionName ?? this.sectionName,
      resourcePath: resourcePath ?? this.resourcePath,
      doubanId: doubanId ?? this.doubanId,
      imdbId: imdbId ?? this.imdbId,
      tmdbId: tmdbId ?? this.tmdbId,
      tvdbId: tvdbId ?? this.tvdbId,
      wikidataId: wikidataId ?? this.wikidataId,
      tmdbSetId: tmdbSetId ?? this.tmdbSetId,
      providerIds: providerIds ?? this.providerIds,
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
      backdropUrl: item.backdropUrl,
      backdropHeaders: item.backdropHeaders,
      logoUrl: item.logoUrl,
      logoHeaders: item.logoHeaders,
      bannerUrl: item.bannerUrl,
      bannerHeaders: item.bannerHeaders,
      extraBackdropUrls: item.extraBackdropUrls,
      extraBackdropHeaders: item.extraBackdropHeaders,
      overview: item.overview,
      year: item.year,
      durationLabel: item.durationLabel,
      ratingLabels: item.ratingLabels,
      genres: item.genres,
      directors: item.directors,
      directorProfiles: item.directors
          .where((entry) => entry.trim().isNotEmpty)
          .map((entry) => MediaPersonProfile(name: entry.trim()))
          .toList(),
      actors: item.actors,
      actorProfiles: item.actors
          .where((entry) => entry.trim().isNotEmpty)
          .map((entry) => MediaPersonProfile(name: entry.trim()))
          .toList(),
      platforms: const [],
      platformProfiles: const [],
      availabilityLabel: availabilityLabel.isNotEmpty
          ? availabilityLabel
          : item.isPlayable
              ? '资源已就绪：${item.sourceKind.label} · ${item.sourceName}'
              : '',
      searchQuery: searchQuery.isEmpty ? item.title : searchQuery,
      playbackTarget:
          item.isPlayable ? PlaybackTarget.fromMediaItem(item) : null,
      itemId: item.id,
      sourceId: item.sourceId,
      itemType: item.itemType,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      sectionId: item.sectionId,
      sectionName: item.sectionName,
      resourcePath: item.actualAddress,
      doubanId: item.doubanId,
      imdbId: item.imdbId,
      tmdbId: item.tmdbId,
      tvdbId: item.tvdbId,
      wikidataId: item.wikidataId,
      tmdbSetId: item.tmdbSetId,
      providerIds: item.providerIds,
      sourceKind: item.sourceKind,
      sourceName: item.sourceName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'posterUrl': posterUrl,
      'posterHeaders': posterHeaders,
      'backdropUrl': backdropUrl,
      'backdropHeaders': backdropHeaders,
      'logoUrl': logoUrl,
      'logoHeaders': logoHeaders,
      'bannerUrl': bannerUrl,
      'bannerHeaders': bannerHeaders,
      'extraBackdropUrls': extraBackdropUrls,
      'extraBackdropHeaders': extraBackdropHeaders,
      'overview': overview,
      'year': year,
      'durationLabel': durationLabel,
      'ratingLabels': ratingLabels,
      'genres': genres,
      'directors': directors,
      'directorProfiles':
          directorProfiles.map((item) => item.toJson()).toList(),
      'actors': actors,
      'actorProfiles': actorProfiles.map((item) => item.toJson()).toList(),
      'platforms': platforms,
      'platformProfiles':
          platformProfiles.map((item) => item.toJson()).toList(),
      'availabilityLabel': availabilityLabel,
      'searchQuery': searchQuery,
      'playbackTarget': playbackTarget?.toJson(),
      'itemId': itemId,
      'sourceId': sourceId,
      'itemType': itemType,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'sectionId': sectionId,
      'sectionName': sectionName,
      'resourcePath': resourcePath,
      'doubanId': doubanId,
      'imdbId': imdbId,
      'tmdbId': tmdbId,
      'tvdbId': tvdbId,
      'wikidataId': wikidataId,
      'tmdbSetId': tmdbSetId,
      'providerIds': providerIds,
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
      backdropUrl: json['backdropUrl'] as String? ?? '',
      backdropHeaders:
          (json['backdropHeaders'] as Map<dynamic, dynamic>? ?? const {})
              .map((key, value) => MapEntry('$key', '$value')),
      logoUrl: json['logoUrl'] as String? ?? '',
      logoHeaders: (json['logoHeaders'] as Map<dynamic, dynamic>? ?? const {})
          .map((key, value) => MapEntry('$key', '$value')),
      bannerUrl: json['bannerUrl'] as String? ?? '',
      bannerHeaders:
          (json['bannerHeaders'] as Map<dynamic, dynamic>? ?? const {})
              .map((key, value) => MapEntry('$key', '$value')),
      extraBackdropUrls:
          (json['extraBackdropUrls'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      extraBackdropHeaders:
          (json['extraBackdropHeaders'] as Map<dynamic, dynamic>? ?? const {})
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
      directorProfiles: (json['directorProfiles'] as List<dynamic>? ?? const [])
          .map(
            (item) => MediaPersonProfile.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
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
      platforms: (json['platforms'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      platformProfiles: (json['platformProfiles'] as List<dynamic>? ?? const [])
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
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      sectionId: json['sectionId'] as String? ?? '',
      sectionName: json['sectionName'] as String? ?? '',
      resourcePath: json['resourcePath'] as String? ?? '',
      doubanId: json['doubanId'] as String? ?? '',
      imdbId: json['imdbId'] as String? ?? '',
      tmdbId: json['tmdbId'] as String? ?? '',
      tvdbId: json['tvdbId'] as String? ?? '',
      wikidataId: json['wikidataId'] as String? ?? '',
      tmdbSetId: json['tmdbSetId'] as String? ?? '',
      providerIds: (json['providerIds'] as Map<dynamic, dynamic>? ?? const {})
          .map((key, value) => MapEntry('$key', '$value')),
      sourceKind: (json['sourceKind'] as String?) == null
          ? null
          : MediaSourceKindX.fromName(json['sourceKind'] as String? ?? ''),
      sourceName: json['sourceName'] as String? ?? '',
    );
  }
}
