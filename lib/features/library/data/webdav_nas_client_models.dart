part of 'webdav_nas_client.dart';

class WebDavNasException implements Exception {
  const WebDavNasException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _WebDavScanCancelledException implements Exception {
  const _WebDavScanCancelledException();
}

class _WebDavEntry {
  const _WebDavEntry({
    required this.uri,
    required this.name,
    required this.isCollection,
    required this.contentType,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.isSelf,
  });

  final Uri uri;
  final String name;
  final bool isCollection;
  final String contentType;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final bool isSelf;
}

class WebDavMetadataSeed {
  const WebDavMetadataSeed({
    required this.title,
    required this.overview,
    required this.posterUrl,
    required this.posterHeaders,
    required this.backdropUrl,
    required this.backdropHeaders,
    required this.logoUrl,
    required this.logoHeaders,
    required this.bannerUrl,
    required this.bannerHeaders,
    required this.extraBackdropUrls,
    required this.extraBackdropHeaders,
    required this.year,
    required this.durationLabel,
    required this.genres,
    required this.directors,
    required this.actors,
    required this.itemType,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.imdbId,
    required this.tmdbId,
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    required this.width,
    required this.height,
    required this.bitrate,
    required this.hasSidecarMatch,
  });

  final String title;
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
  final int? seasonNumber;
  final int? episodeNumber;
  final String imdbId;
  final String tmdbId;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int? width;
  final int? height;
  final int? bitrate;
  final bool hasSidecarMatch;

  WebDavMetadataSeed copyWith({
    String? title,
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
    int? seasonNumber,
    int? episodeNumber,
    String? imdbId,
    String? tmdbId,
    String? container,
    String? videoCodec,
    String? audioCodec,
    int? width,
    int? height,
    int? bitrate,
    bool? hasSidecarMatch,
  }) {
    return WebDavMetadataSeed(
      title: title ?? this.title,
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
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      imdbId: imdbId ?? this.imdbId,
      tmdbId: tmdbId ?? this.tmdbId,
      container: container ?? this.container,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      width: width ?? this.width,
      height: height ?? this.height,
      bitrate: bitrate ?? this.bitrate,
      hasSidecarMatch: hasSidecarMatch ?? this.hasSidecarMatch,
    );
  }
}

class WebDavScannedItem {
  const WebDavScannedItem({
    required this.resourceId,
    required this.fileName,
    required this.actualAddress,
    required this.sectionId,
    required this.sectionName,
    required this.streamUrl,
    required this.streamHeaders,
    this.playbackItemId = '',
    required this.addedAt,
    required this.modifiedAt,
    required this.fileSizeBytes,
    required this.metadataSeed,
  });

  final String resourceId;
  final String fileName;
  final String actualAddress;
  final String sectionId;
  final String sectionName;
  final String streamUrl;
  final Map<String, String> streamHeaders;
  final String playbackItemId;
  final DateTime addedAt;
  final DateTime? modifiedAt;
  final int fileSizeBytes;
  final WebDavMetadataSeed metadataSeed;

  MediaItem toMediaItem(MediaSourceConfig source) {
    return MediaItem(
      id: resourceId,
      title: metadataSeed.title.trim().isEmpty
          ? _fallbackTitle(fileName)
          : metadataSeed.title,
      overview: metadataSeed.overview,
      posterUrl: metadataSeed.posterUrl,
      posterHeaders: metadataSeed.posterHeaders,
      backdropUrl: metadataSeed.backdropUrl,
      backdropHeaders: metadataSeed.backdropHeaders,
      logoUrl: metadataSeed.logoUrl,
      logoHeaders: metadataSeed.logoHeaders,
      bannerUrl: metadataSeed.bannerUrl,
      bannerHeaders: metadataSeed.bannerHeaders,
      extraBackdropUrls: metadataSeed.extraBackdropUrls,
      extraBackdropHeaders: metadataSeed.extraBackdropHeaders,
      year: metadataSeed.year,
      durationLabel: metadataSeed.durationLabel,
      genres: metadataSeed.genres,
      directors: metadataSeed.directors,
      actors: metadataSeed.actors,
      itemType: metadataSeed.itemType,
      sectionId: sectionId,
      sectionName: sectionName,
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
      streamUrl: streamUrl,
      actualAddress: actualAddress,
      streamHeaders: streamHeaders,
      playbackItemId: playbackItemId,
      seasonNumber: metadataSeed.seasonNumber,
      episodeNumber: metadataSeed.episodeNumber,
      imdbId: metadataSeed.imdbId,
      tmdbId: metadataSeed.tmdbId,
      container: metadataSeed.container,
      videoCodec: metadataSeed.videoCodec,
      audioCodec: metadataSeed.audioCodec,
      width: metadataSeed.width,
      height: metadataSeed.height,
      bitrate: metadataSeed.bitrate,
      fileSizeBytes: fileSizeBytes,
      addedAt: addedAt,
    );
  }

  static String _fallbackTitle(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }
}

class _ParsedNfoMetadata {
  const _ParsedNfoMetadata({
    required this.title,
    required this.overview,
    required this.thumbUrl,
    required this.backdropUrl,
    required this.logoUrl,
    required this.bannerUrl,
    required this.extraBackdropUrls,
    required this.year,
    required this.durationLabel,
    required this.genres,
    required this.directors,
    required this.actors,
    required this.itemType,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.imdbId,
    required this.tmdbId,
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    required this.width,
    required this.height,
    required this.bitrate,
  });

  final String title;
  final String overview;
  final String thumbUrl;
  final String backdropUrl;
  final String logoUrl;
  final String bannerUrl;
  final List<String> extraBackdropUrls;
  final int year;
  final String durationLabel;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final String itemType;
  final int? seasonNumber;
  final int? episodeNumber;
  final String imdbId;
  final String tmdbId;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int? width;
  final int? height;
  final int? bitrate;
}

class _ArtworkResolution {
  const _ArtworkResolution({
    this.url = '',
    this.headers = const {},
  });

  final String url;
  final Map<String, String> headers;
}

class _NfoStreamDetails {
  const _NfoStreamDetails({
    this.container = '',
    this.videoCodec = '',
    this.audioCodec = '',
    this.width,
    this.height,
    this.bitrate,
  });

  final String container;
  final String videoCodec;
  final String audioCodec;
  final int? width;
  final int? height;
  final int? bitrate;
}

class _SeriesRootInferencePlan {
  const _SeriesRootInferencePlan({
    required this.rootItemsAsSpecials,
    required this.seasonNumberByChildDirectory,
    this.collapseChildDirectoriesToRoot = const <String>{},
  });

  final bool rootItemsAsSpecials;
  final Map<String, int?> seasonNumberByChildDirectory;
  final Set<String> collapseChildDirectoriesToRoot;
}

class _SeasonDirectoryHint {
  const _SeasonDirectoryHint({
    required this.seasonNumber,
  });

  final int? seasonNumber;
}

class _InferredMediaInfo {
  const _InferredMediaInfo({
    this.container = '',
    this.videoCodec = '',
    this.audioCodec = '',
    this.width,
    this.height,
    this.bitrate,
  });

  final String container;
  final String videoCodec;
  final String audioCodec;
  final int? width;
  final int? height;
  final int? bitrate;
}

const String _directSeasonGroupKey = '__root__';
const String _implicitSeasonGroupKey = '__implicit__';

typedef _PendingWebDavScannedItem = ExternalScanPendingItem;

class ExternalScanPendingItem {
  const ExternalScanPendingItem({
    required this.resourceId,
    required this.fileName,
    required this.actualAddress,
    required this.sectionId,
    required this.sectionName,
    required this.streamUrl,
    required this.streamHeaders,
    this.playbackItemId = '',
    required this.addedAt,
    required this.modifiedAt,
    required this.fileSizeBytes,
    required this.metadataSeed,
    required this.relativeDirectories,
  });

  final String resourceId;
  final String fileName;
  final String actualAddress;
  final String sectionId;
  final String sectionName;
  final String streamUrl;
  final Map<String, String> streamHeaders;
  final String playbackItemId;
  final DateTime addedAt;
  final DateTime? modifiedAt;
  final int fileSizeBytes;
  final WebDavMetadataSeed metadataSeed;
  final List<String> relativeDirectories;

  ExternalScanPendingItem copyWith({
    WebDavMetadataSeed? metadataSeed,
    String? sectionId,
    String? sectionName,
    List<String>? relativeDirectories,
  }) {
    return ExternalScanPendingItem(
      resourceId: resourceId,
      fileName: fileName,
      actualAddress: actualAddress,
      sectionId: sectionId ?? this.sectionId,
      sectionName: sectionName ?? this.sectionName,
      streamUrl: streamUrl,
      streamHeaders: streamHeaders,
      playbackItemId: playbackItemId,
      addedAt: addedAt,
      modifiedAt: modifiedAt,
      fileSizeBytes: fileSizeBytes,
      metadataSeed: metadataSeed ?? this.metadataSeed,
      relativeDirectories: relativeDirectories ?? this.relativeDirectories,
    );
  }

  WebDavScannedItem toScannedItem() {
    return WebDavScannedItem(
      resourceId: resourceId,
      fileName: fileName,
      actualAddress: actualAddress,
      sectionId: sectionId,
      sectionName: sectionName,
      streamUrl: streamUrl,
      streamHeaders: streamHeaders,
      playbackItemId: playbackItemId,
      addedAt: addedAt,
      modifiedAt: modifiedAt,
      fileSizeBytes: fileSizeBytes,
      metadataSeed: metadataSeed,
    );
  }
}

class _DirectoryWalkResult {
  const _DirectoryWalkResult({
    this.items = const [],
    this.truncated = false,
  });

  final List<ExternalScanPendingItem> items;
  final bool truncated;
}

class _DirectorySubtreeCacheEntry {
  const _DirectorySubtreeCacheEntry({
    required this.directoryModifiedAt,
    required this.items,
  });

  final DateTime directoryModifiedAt;
  final List<ExternalScanPendingItem> items;
}

class _ResolvedPlayableSource {
  const _ResolvedPlayableSource({
    required this.streamUrl,
    required this.headers,
  });

  final String streamUrl;
  final Map<String, String> headers;
}
