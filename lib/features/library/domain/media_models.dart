import 'package:starflow/features/library/domain/media_naming.dart';

enum MediaSourceKind {
  emby,
  nas,
  quark,
}

const kNoSectionsSelectedSentinel = '__none__';

extension MediaSourceKindX on MediaSourceKind {
  String get label {
    switch (this) {
      case MediaSourceKind.emby:
        return 'Emby';
      case MediaSourceKind.nas:
        return 'WebDAV';
      case MediaSourceKind.quark:
        return 'Quark';
    }
  }

  static MediaSourceKind fromName(String raw) {
    return MediaSourceKind.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => MediaSourceKind.emby,
    );
  }
}

class MediaSourceConfig {
  const MediaSourceConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.endpoint,
    required this.enabled,
    this.username = '',
    this.password = '',
    this.accessToken = '',
    this.userId = '',
    this.serverId = '',
    this.deviceId = '',
    this.libraryPath = '',
    this.featuredSectionIds = const [],
    this.webDavStructureInferenceEnabled = false,
    this.webDavSidecarScrapingEnabled = true,
    this.webDavSeriesScrapeUsesDirectoryTitleOnly = false,
    this.webDavExcludedPathKeywords = const [],
    this.webDavSeriesTitleFilterKeywords = const [],
    this.webDavSpecialEpisodeKeywords = const [],
    this.webDavExtraKeywords = const [],
  });

  final String id;
  final String name;
  final MediaSourceKind kind;
  final String endpoint;
  final bool enabled;
  final String username;
  final String password;
  final String accessToken;
  final String userId;
  final String serverId;
  final String deviceId;
  final String libraryPath;
  final List<String> featuredSectionIds;
  final bool webDavStructureInferenceEnabled;
  final bool webDavSidecarScrapingEnabled;
  final bool webDavSeriesScrapeUsesDirectoryTitleOnly;
  final List<String> webDavExcludedPathKeywords;
  final List<String> webDavSeriesTitleFilterKeywords;
  final List<String> webDavSpecialEpisodeKeywords;
  final List<String> webDavExtraKeywords;

  bool get hasAccessToken => accessToken.trim().isNotEmpty;

  bool get hasActiveSession => hasAccessToken && userId.trim().isNotEmpty;

  String get connectionStatusLabel {
    if (kind == MediaSourceKind.quark) {
      return hasConfiguredQuarkFolder ? '已配置' : '待选择目录';
    }
    if (kind != MediaSourceKind.emby) {
      return '已配置';
    }
    if (hasActiveSession) {
      return '已登录';
    }
    if (username.trim().isNotEmpty) {
      return '待登录';
    }
    return '未配置';
  }

  MediaSourceConfig copyWith({
    String? id,
    String? name,
    MediaSourceKind? kind,
    String? endpoint,
    bool? enabled,
    String? username,
    String? password,
    String? accessToken,
    String? userId,
    String? serverId,
    String? deviceId,
    String? libraryPath,
    List<String>? featuredSectionIds,
    bool? webDavStructureInferenceEnabled,
    bool? webDavSidecarScrapingEnabled,
    bool? webDavSeriesScrapeUsesDirectoryTitleOnly,
    List<String>? webDavExcludedPathKeywords,
    List<String>? webDavSeriesTitleFilterKeywords,
    List<String>? webDavSpecialEpisodeKeywords,
    List<String>? webDavExtraKeywords,
  }) {
    return MediaSourceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      endpoint: endpoint ?? this.endpoint,
      enabled: enabled ?? this.enabled,
      username: username ?? this.username,
      password: password ?? this.password,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      serverId: serverId ?? this.serverId,
      deviceId: deviceId ?? this.deviceId,
      libraryPath: libraryPath ?? this.libraryPath,
      featuredSectionIds: featuredSectionIds ?? this.featuredSectionIds,
      webDavStructureInferenceEnabled: webDavStructureInferenceEnabled ??
          this.webDavStructureInferenceEnabled,
      webDavSidecarScrapingEnabled:
          webDavSidecarScrapingEnabled ?? this.webDavSidecarScrapingEnabled,
      webDavSeriesScrapeUsesDirectoryTitleOnly:
          webDavSeriesScrapeUsesDirectoryTitleOnly ??
              this.webDavSeriesScrapeUsesDirectoryTitleOnly,
      webDavExcludedPathKeywords:
          webDavExcludedPathKeywords ?? this.webDavExcludedPathKeywords,
      webDavSeriesTitleFilterKeywords: webDavSeriesTitleFilterKeywords ??
          this.webDavSeriesTitleFilterKeywords,
      webDavSpecialEpisodeKeywords:
          webDavSpecialEpisodeKeywords ?? this.webDavSpecialEpisodeKeywords,
      webDavExtraKeywords: webDavExtraKeywords ?? this.webDavExtraKeywords,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind.name,
      'endpoint': endpoint,
      'enabled': enabled,
      'username': username,
      'password': password,
      'accessToken': accessToken,
      'userId': userId,
      'serverId': serverId,
      'deviceId': deviceId,
      'libraryPath': libraryPath,
      'featuredSectionIds': featuredSectionIds,
      'webDavStructureInferenceEnabled': webDavStructureInferenceEnabled,
      'webDavSidecarScrapingEnabled': webDavSidecarScrapingEnabled,
      'webDavSeriesScrapeUsesDirectoryTitleOnly':
          webDavSeriesScrapeUsesDirectoryTitleOnly,
      'webDavExcludedPathKeywords': webDavExcludedPathKeywords,
      'webDavSeriesTitleFilterKeywords': webDavSeriesTitleFilterKeywords,
      'webDavSpecialEpisodeKeywords': webDavSpecialEpisodeKeywords,
      'webDavExtraKeywords': webDavExtraKeywords,
    };
  }

  factory MediaSourceConfig.fromJson(Map<String, dynamic> json) {
    return MediaSourceConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: MediaSourceKindX.fromName(json['kind'] as String? ?? ''),
      endpoint: json['endpoint'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      serverId: json['serverId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      libraryPath: json['libraryPath'] as String? ?? '',
      featuredSectionIds:
          (json['featuredSectionIds'] as List<dynamic>? ?? const [])
              .map((item) => '$item')
              .where((item) => item.trim().isNotEmpty)
              .toList(),
      webDavStructureInferenceEnabled:
          json['webDavStructureInferenceEnabled'] as bool? ?? false,
      webDavSidecarScrapingEnabled:
          json['webDavSidecarScrapingEnabled'] as bool? ?? true,
      webDavSeriesScrapeUsesDirectoryTitleOnly:
          json['webDavSeriesScrapeUsesDirectoryTitleOnly'] as bool? ?? false,
      webDavExcludedPathKeywords:
          (json['webDavExcludedPathKeywords'] as List<dynamic>? ?? const [])
              .map((item) => '$item')
              .where((item) => item.trim().isNotEmpty)
              .toList(),
      webDavSeriesTitleFilterKeywords:
          (json['webDavSeriesTitleFilterKeywords'] as List<dynamic>? ??
                  const [])
              .map((item) => '$item')
              .where((item) => item.trim().isNotEmpty)
              .toList(),
      webDavSpecialEpisodeKeywords:
          (json['webDavSpecialEpisodeKeywords'] as List<dynamic>? ?? const [])
              .map((item) => '$item')
              .where((item) => item.trim().isNotEmpty)
              .toList(),
      webDavExtraKeywords:
          (json['webDavExtraKeywords'] as List<dynamic>? ?? const [])
              .map((item) => '$item')
              .where((item) => item.trim().isNotEmpty)
              .toList(),
    );
  }

  bool get hasConfiguredQuarkFolder {
    if (kind != MediaSourceKind.quark) {
      return false;
    }
    return endpoint.trim().isNotEmpty || libraryPath.trim().isNotEmpty;
  }

  String get quarkFolderId {
    if (kind != MediaSourceKind.quark) {
      return '';
    }
    final normalized = endpoint.trim();
    return normalized.isEmpty ? '0' : normalized;
  }

  String get quarkFolderPath {
    if (kind != MediaSourceKind.quark) {
      return '';
    }
    final normalized = libraryPath.trim();
    return normalized.isEmpty ? '/' : normalized;
  }
}

extension MediaSourceConfigScopeX on MediaSourceConfig {
  bool get hasExplicitNoSectionsSelected {
    return featuredSectionIds.any(
      (item) => item.trim() == kNoSectionsSelectedSentinel,
    );
  }

  Set<String> get selectedSectionIds {
    return featuredSectionIds
        .map((item) => item.trim())
        .where(
          (item) => item.isNotEmpty && item != kNoSectionsSelectedSentinel,
        )
        .toSet();
  }
}

extension MediaSourceConfigEditorX on MediaSourceConfig {
  /// 编辑页「连接状态」说明文案（仅 Emby）。
  String get embyEditorStatusMessage {
    if (hasActiveSession) {
      final serverPart = serverId.trim().isEmpty ? '' : '，Server ID: $serverId';
      return '当前会话可用，登录用户 $username$serverPart';
    }
    if (accessToken.trim().isNotEmpty) {
      return '已经保存 token，但还没有拿到 User ID，建议重新测试登录。';
    }
    return '填写账号密码后可以直接验证 Emby 登录。';
  }
}

List<String> _normalizeDistinctLowerKeywords(Iterable<String> values) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final item in values) {
    final keyword = item.trim().toLowerCase();
    if (keyword.isEmpty || !seen.add(keyword)) {
      continue;
    }
    normalized.add(keyword);
  }
  return normalized;
}

extension MediaSourceConfigWebDavFilterX on MediaSourceConfig {
  List<String> get normalizedWebDavExcludedPathKeywords {
    return _normalizeDistinctLowerKeywords(webDavExcludedPathKeywords);
  }

  List<String> get normalizedWebDavSeriesTitleFilterKeywords {
    return _normalizeDistinctLowerKeywords(webDavSeriesTitleFilterKeywords);
  }

  List<String> get normalizedWebDavSpecialEpisodeKeywords {
    // Special / extras keywords are now code-defined so hidden legacy per-source
    // values do not keep affecting scans after the settings UI removes them.
    return _normalizeDistinctLowerKeywords(
      kDefaultVarietySpecialEpisodeKeywords,
    );
  }

  List<String> get normalizedWebDavExtraKeywords {
    return _normalizeDistinctLowerKeywords(kDefaultVarietyExtraKeywords);
  }

  List<String> get normalizedWebDavSpecialCategoryKeywords {
    return _normalizeDistinctLowerKeywords([
      ...kDefaultVarietySpecialEpisodeKeywords,
      ...kDefaultVarietyExtraKeywords,
    ]);
  }

  bool matchesWebDavExcludedPath(String rawPath) {
    if (kind != MediaSourceKind.nas && kind != MediaSourceKind.quark) {
      return false;
    }
    final keywords = normalizedWebDavExcludedPathKeywords;
    if (keywords.isEmpty) {
      return false;
    }
    final haystacks = <String>{};
    final trimmed = rawPath.trim();
    if (trimmed.isNotEmpty) {
      haystacks.add(trimmed.toLowerCase());
      try {
        haystacks.add(Uri.decodeFull(trimmed).toLowerCase());
      } catch (_) {
        // Keep the raw path when percent-decoding fails.
      }
    }
    return keywords.any(
      (keyword) => haystacks.any((path) => path.contains(keyword)),
    );
  }

  bool matchesWebDavExcludedUri(Uri uri) {
    return matchesWebDavExcludedPath(uri.toString()) ||
        matchesWebDavExcludedPath(uri.path);
  }

  bool matchesWebDavSeriesTitleFilter(String rawValue) {
    if (kind != MediaSourceKind.nas && kind != MediaSourceKind.quark) {
      return false;
    }
    final keywords = normalizedWebDavSeriesTitleFilterKeywords;
    if (keywords.isEmpty) {
      return false;
    }
    final normalized = rawValue.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return keywords.any(normalized.contains);
  }

  bool matchesWebDavSpecialEpisodeKeyword(String rawValue) {
    if (kind != MediaSourceKind.nas && kind != MediaSourceKind.quark) {
      return false;
    }
    final keywords = normalizedWebDavSpecialCategoryKeywords;
    if (keywords.isEmpty) {
      return false;
    }
    return MediaNaming.matchesAnyKeyword(
      [rawValue],
      keywords: keywords,
    );
  }

  bool matchesWebDavExtraKeyword(String rawValue) {
    if (kind != MediaSourceKind.nas && kind != MediaSourceKind.quark) {
      return false;
    }
    final keywords = normalizedWebDavExtraKeywords;
    if (keywords.isEmpty) {
      return false;
    }
    return MediaNaming.matchesAnyKeyword(
      [rawValue],
      keywords: keywords,
    );
  }
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.sortTitle = '',
    required this.overview,
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
    required this.year,
    required this.durationLabel,
    required this.genres,
    this.directors = const [],
    this.actors = const [],
    this.itemType = '',
    this.isFolder = false,
    this.sectionId = '',
    this.sectionName = '',
    required this.sourceId,
    required this.sourceName,
    required this.sourceKind,
    required this.streamUrl,
    this.actualAddress = '',
    this.streamHeaders = const {},
    this.playbackItemId = '',
    this.preferredMediaSourceId = '',
    this.seasonNumber,
    this.episodeNumber,
    this.playbackProgress,
    this.doubanId = '',
    this.imdbId = '',
    this.tmdbId = '',
    this.tvdbId = '',
    this.wikidataId = '',
    this.tmdbSetId = '',
    this.providerIds = const {},
    this.ratingLabels = const [],
    this.container = '',
    this.videoCodec = '',
    this.audioCodec = '',
    this.width,
    this.height,
    this.bitrate,
    this.fileSizeBytes,
    required this.addedAt,
    this.lastWatchedAt,
  });

  final String id;
  final String title;
  final String originalTitle;
  final String sortTitle;
  final String overview;
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
  final int year;
  final String durationLabel;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final String itemType;
  final bool isFolder;
  final String sectionId;
  final String sectionName;
  final String sourceId;
  final String sourceName;
  final MediaSourceKind sourceKind;
  final String streamUrl;
  final String actualAddress;
  final Map<String, String> streamHeaders;
  final String playbackItemId;
  final String preferredMediaSourceId;
  final int? seasonNumber;
  final int? episodeNumber;
  final double? playbackProgress;
  final String doubanId;
  final String imdbId;
  final String tmdbId;
  final String tvdbId;
  final String wikidataId;
  final String tmdbSetId;
  final Map<String, String> providerIds;
  final List<String> ratingLabels;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int? width;
  final int? height;
  final int? bitrate;
  final int? fileSizeBytes;
  final DateTime addedAt;
  final DateTime? lastWatchedAt;

  bool get isPlayable =>
      streamUrl.trim().isNotEmpty || playbackItemId.trim().isNotEmpty;

  MediaItem copyWith({
    String? id,
    String? title,
    String? originalTitle,
    String? sortTitle,
    String? overview,
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
    int? year,
    String? durationLabel,
    List<String>? genres,
    List<String>? directors,
    List<String>? actors,
    String? itemType,
    bool? isFolder,
    String? sectionId,
    String? sectionName,
    String? sourceId,
    String? sourceName,
    MediaSourceKind? sourceKind,
    String? streamUrl,
    String? actualAddress,
    Map<String, String>? streamHeaders,
    String? playbackItemId,
    String? preferredMediaSourceId,
    int? seasonNumber,
    int? episodeNumber,
    double? playbackProgress,
    String? doubanId,
    String? imdbId,
    String? tmdbId,
    String? tvdbId,
    String? wikidataId,
    String? tmdbSetId,
    Map<String, String>? providerIds,
    List<String>? ratingLabels,
    String? container,
    String? videoCodec,
    String? audioCodec,
    int? width,
    int? height,
    int? bitrate,
    int? fileSizeBytes,
    DateTime? addedAt,
    DateTime? lastWatchedAt,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      sortTitle: sortTitle ?? this.sortTitle,
      overview: overview ?? this.overview,
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
      year: year ?? this.year,
      durationLabel: durationLabel ?? this.durationLabel,
      genres: genres ?? this.genres,
      directors: directors ?? this.directors,
      actors: actors ?? this.actors,
      itemType: itemType ?? this.itemType,
      isFolder: isFolder ?? this.isFolder,
      sectionId: sectionId ?? this.sectionId,
      sectionName: sectionName ?? this.sectionName,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      sourceKind: sourceKind ?? this.sourceKind,
      streamUrl: streamUrl ?? this.streamUrl,
      actualAddress: actualAddress ?? this.actualAddress,
      streamHeaders: streamHeaders ?? this.streamHeaders,
      playbackItemId: playbackItemId ?? this.playbackItemId,
      preferredMediaSourceId:
          preferredMediaSourceId ?? this.preferredMediaSourceId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      playbackProgress: playbackProgress ?? this.playbackProgress,
      doubanId: doubanId ?? this.doubanId,
      imdbId: imdbId ?? this.imdbId,
      tmdbId: tmdbId ?? this.tmdbId,
      tvdbId: tvdbId ?? this.tvdbId,
      wikidataId: wikidataId ?? this.wikidataId,
      tmdbSetId: tmdbSetId ?? this.tmdbSetId,
      providerIds: providerIds ?? this.providerIds,
      ratingLabels: ratingLabels ?? this.ratingLabels,
      container: container ?? this.container,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      width: width ?? this.width,
      height: height ?? this.height,
      bitrate: bitrate ?? this.bitrate,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      addedAt: addedAt ?? this.addedAt,
      lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'originalTitle': originalTitle,
      'sortTitle': sortTitle,
      'overview': overview,
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
      'year': year,
      'durationLabel': durationLabel,
      'genres': genres,
      'directors': directors,
      'actors': actors,
      'itemType': itemType,
      'isFolder': isFolder,
      'sectionId': sectionId,
      'sectionName': sectionName,
      'sourceId': sourceId,
      'sourceName': sourceName,
      'sourceKind': sourceKind.name,
      'streamUrl': streamUrl,
      'actualAddress': actualAddress,
      'streamHeaders': streamHeaders,
      'playbackItemId': playbackItemId,
      'preferredMediaSourceId': preferredMediaSourceId,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'playbackProgress': playbackProgress,
      'doubanId': doubanId,
      'imdbId': imdbId,
      'tmdbId': tmdbId,
      'tvdbId': tvdbId,
      'wikidataId': wikidataId,
      'tmdbSetId': tmdbSetId,
      'providerIds': providerIds,
      'ratingLabels': ratingLabels,
      'container': container,
      'videoCodec': videoCodec,
      'audioCodec': audioCodec,
      'width': width,
      'height': height,
      'bitrate': bitrate,
      'fileSizeBytes': fileSizeBytes,
      'addedAt': addedAt.toIso8601String(),
      'lastWatchedAt': lastWatchedAt?.toIso8601String(),
    };
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      originalTitle: json['originalTitle'] as String? ?? '',
      sortTitle: json['sortTitle'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
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
      year: (json['year'] as num?)?.toInt() ?? 0,
      durationLabel: json['durationLabel'] as String? ?? '',
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      directors: (json['directors'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      actors: (json['actors'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      itemType: json['itemType'] as String? ?? '',
      isFolder: json['isFolder'] as bool? ?? false,
      sectionId: json['sectionId'] as String? ?? '',
      sectionName: json['sectionName'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      sourceKind:
          MediaSourceKindX.fromName(json['sourceKind'] as String? ?? ''),
      streamUrl: json['streamUrl'] as String? ?? '',
      actualAddress: json['actualAddress'] as String? ?? '',
      streamHeaders:
          (json['streamHeaders'] as Map<dynamic, dynamic>? ?? const {})
              .map((key, value) => MapEntry('$key', '$value')),
      playbackItemId: json['playbackItemId'] as String? ?? '',
      preferredMediaSourceId: json['preferredMediaSourceId'] as String? ?? '',
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      playbackProgress: (json['playbackProgress'] as num?)?.toDouble(),
      doubanId: json['doubanId'] as String? ?? '',
      imdbId: json['imdbId'] as String? ?? '',
      tmdbId: json['tmdbId'] as String? ?? '',
      tvdbId: json['tvdbId'] as String? ?? '',
      wikidataId: json['wikidataId'] as String? ?? '',
      tmdbSetId: json['tmdbSetId'] as String? ?? '',
      providerIds: (json['providerIds'] as Map<dynamic, dynamic>? ?? const {})
          .map((key, value) => MapEntry('$key', '$value')),
      ratingLabels: (json['ratingLabels'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      container: json['container'] as String? ?? '',
      videoCodec: json['videoCodec'] as String? ?? '',
      audioCodec: json['audioCodec'] as String? ?? '',
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      bitrate: (json['bitrate'] as num?)?.toInt(),
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt(),
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
      lastWatchedAt: DateTime.tryParse(json['lastWatchedAt'] as String? ?? ''),
    );
  }
}

class MediaCollection {
  const MediaCollection({
    required this.id,
    required this.title,
    required this.sourceId,
    required this.sourceName,
    required this.sourceKind,
    this.subtitle = '',
  });

  final String id;
  final String title;
  final String sourceId;
  final String sourceName;
  final MediaSourceKind sourceKind;
  final String subtitle;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'sourceId': sourceId,
      'sourceName': sourceName,
      'sourceKind': sourceKind.name,
      'subtitle': subtitle,
    };
  }

  factory MediaCollection.fromJson(Map<String, dynamic> json) {
    return MediaCollection(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      sourceKind:
          MediaSourceKindX.fromName(json['sourceKind'] as String? ?? ''),
      subtitle: json['subtitle'] as String? ?? '',
    );
  }
}
