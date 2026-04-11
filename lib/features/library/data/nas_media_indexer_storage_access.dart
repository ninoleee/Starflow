part of 'nas_media_indexer.dart';

extension _NasMediaIndexerStorageAccessX on NasMediaIndexer {
  MediaDetailTarget? _buildManualMetadataTarget({
    required MediaDetailTarget target,
    required List<NasMediaIndexRecord> records,
    required List<String> selectedResourceIds,
    required String resourceId,
    required String resourcePath,
    required String searchQuery,
  }) {
    final normalizedResourceId = resourceId.trim();
    if (normalizedResourceId.isEmpty) {
      return null;
    }

    final exactRecord = records
        .where((record) => record.resourceId == normalizedResourceId)
        .firstOrNull;
    if (exactRecord != null) {
      return MediaDetailTarget.fromMediaItem(
        exactRecord.item,
        availabilityLabel: target.availabilityLabel,
        searchQuery: searchQuery,
      );
    }

    if (!_isSyntheticGroupId(normalizedResourceId)) {
      return null;
    }

    final selectedIdSet = selectedResourceIds.toSet();
    final selectedRecords = records
        .where((record) => selectedIdSet.contains(record.resourceId))
        .toList(growable: false);
    if (selectedRecords.isEmpty) {
      return null;
    }
    final groups = _groupSeriesRecords(records);
    final group = groups.where(
      (candidate) => candidate.records.any(
        (record) => selectedIdSet.contains(record.resourceId),
      ),
    );
    if (group.isEmpty) {
      if (selectedRecords.length != 1) {
        return null;
      }
      final nextTarget = MediaDetailTarget.fromMediaItem(
        selectedRecords.single.item,
        availabilityLabel: target.availabilityLabel,
        searchQuery: searchQuery,
      );
      return resourcePath.trim().isEmpty
          ? nextTarget
          : nextTarget.copyWith(resourcePath: resourcePath);
    }
    final resolvedGroup = group.first;
    final scopedGroup = _SeriesRecordGroup(
      seriesKey: resolvedGroup.seriesKey,
      title: _resolveSeriesGroupTitle(
        selectedRecords,
        fallback: resolvedGroup.title,
      ),
      records: selectedRecords,
    );
    if (normalizedResourceId.startsWith(NasMediaIndexer._seriesGroupPrefix)) {
      final nextTarget = MediaDetailTarget.fromMediaItem(
        _buildSeriesItem(scopedGroup),
        availabilityLabel: target.availabilityLabel,
        searchQuery: searchQuery,
      );
      return resourcePath.trim().isEmpty
          ? nextTarget
          : nextTarget.copyWith(resourcePath: resourcePath);
    }

    final parsed = _parseSeasonGroupId(normalizedResourceId);
    if (parsed == null) {
      return null;
    }
    final seasonRecords =
        resolvedGroup.seasonGroups[parsed.seasonNumber] ?? const [];
    if (seasonRecords.isEmpty) {
      return null;
    }
    final nextTarget = MediaDetailTarget.fromMediaItem(
      _buildSeasonItem(scopedGroup, parsed.seasonNumber, seasonRecords),
      availabilityLabel: target.availabilityLabel,
      searchQuery: searchQuery,
    );
    return resourcePath.trim().isEmpty
        ? nextTarget
        : nextTarget.copyWith(resourcePath: resourcePath);
  }

  WebDavScannedItem _buildScannedItemFromRecord(NasMediaIndexRecord record) {
    final item = record.item;
    return WebDavScannedItem(
      resourceId: record.resourceId,
      fileName: _resolveRecordFileName(record),
      actualAddress: record.resourcePath.trim().isNotEmpty
          ? record.resourcePath
          : item.actualAddress,
      sectionId: record.sectionId,
      sectionName: record.sectionName,
      streamUrl: item.streamUrl,
      streamHeaders: item.streamHeaders,
      playbackItemId: item.playbackItemId,
      addedAt: item.addedAt,
      modifiedAt: record.modifiedAt,
      fileSizeBytes: record.fileSizeBytes,
      metadataSeed: WebDavMetadataSeed(
        title: item.title,
        overview: item.overview,
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
        year: item.year,
        durationLabel: item.durationLabel,
        genres: item.genres,
        directors: item.directors,
        actors: item.actors,
        itemType: item.itemType,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        imdbId: item.imdbId,
        tmdbId: item.tmdbId,
        container: item.container,
        videoCodec: item.videoCodec,
        audioCodec: item.audioCodec,
        width: item.width,
        height: item.height,
        bitrate: item.bitrate,
        hasSidecarMatch: record.sidecarMatched,
      ),
    );
  }

  String _resolveRecordFileName(NasMediaIndexRecord record) {
    final original = record.originalFileName.trim();
    if (original.isNotEmpty) {
      return original;
    }
    final path = record.resourcePath.trim();
    if (path.isEmpty) {
      return record.resourceId;
    }
    final normalized = path.replaceAll('\\', '/');
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash < 0 || lastSlash == normalized.length - 1) {
      return normalized;
    }
    return normalized.substring(lastSlash + 1);
  }

  List<int> _filterRecordIndicesByScope(
    List<NasMediaIndexRecord> records,
    List<int> candidateIndices, {
    required String resourceScopePath,
  }) {
    final normalizedScopeSegments = _pathSegments(_uriPath(resourceScopePath));
    if (normalizedScopeSegments.isEmpty) {
      return candidateIndices;
    }
    return candidateIndices.where((index) {
      if (index < 0 || index >= records.length) {
        return false;
      }
      return _isRecordWithinScope(
        records[index],
        scopeSegments: normalizedScopeSegments,
      );
    }).toList(growable: false);
  }

  bool _isRecordWithinScope(
    NasMediaIndexRecord record, {
    required List<String> scopeSegments,
  }) {
    final recordSegments = _pathSegments(_uriPath(record.resourcePath));
    if (recordSegments.isEmpty) {
      return false;
    }
    for (var offset = 0; offset < scopeSegments.length; offset++) {
      final scopedTail = scopeSegments.sublist(offset);
      if (scopedTail.length > recordSegments.length) {
        continue;
      }
      var matches = true;
      for (var index = 0; index < scopedTail.length; index++) {
        if (recordSegments[index] != scopedTail[index]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return true;
      }
    }
    return false;
  }

  String _resolveSeriesGroupTitle(
    List<NasMediaIndexRecord> records, {
    required String fallback,
  }) {
    for (final record in records) {
      final candidates = <String>[
        record.parentTitle,
        record.recognizedTitle,
        record.item.title,
      ];
      for (final candidate in candidates) {
        final normalized = _cleanIndexedTitleLabel(candidate);
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }
    return _cleanIndexedTitleLabel(fallback);
  }

  NasMediaIndexRecord _reuseRecord(
    NasMediaIndexRecord existing, {
    required WebDavScannedItem scannedItem,
    required MediaSourceConfig source,
    required DateTime indexedAt,
  }) {
    final refreshedItem = MediaItem(
      id: scannedItem.resourceId,
      title: existing.item.title,
      originalTitle: existing.item.originalTitle,
      sortTitle: existing.item.sortTitle,
      overview: existing.item.overview,
      posterUrl: existing.item.posterUrl,
      posterHeaders: existing.item.posterHeaders,
      backdropUrl: existing.item.backdropUrl,
      backdropHeaders: existing.item.backdropHeaders,
      logoUrl: existing.item.logoUrl,
      logoHeaders: existing.item.logoHeaders,
      bannerUrl: existing.item.bannerUrl,
      bannerHeaders: existing.item.bannerHeaders,
      extraBackdropUrls: existing.item.extraBackdropUrls,
      extraBackdropHeaders: existing.item.extraBackdropHeaders,
      year: existing.item.year,
      durationLabel: existing.item.durationLabel,
      genres: existing.item.genres,
      directors: existing.item.directors,
      actors: existing.item.actors,
      itemType: existing.item.itemType,
      sectionId: scannedItem.sectionId,
      sectionName: scannedItem.sectionName,
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
      streamUrl: scannedItem.streamUrl,
      actualAddress: scannedItem.actualAddress,
      streamHeaders: scannedItem.streamHeaders,
      playbackItemId: scannedItem.playbackItemId.trim().isNotEmpty
          ? scannedItem.playbackItemId
          : existing.item.playbackItemId,
      preferredMediaSourceId: existing.item.preferredMediaSourceId,
      seasonNumber: existing.item.seasonNumber,
      episodeNumber: existing.item.episodeNumber,
      playbackProgress: existing.item.playbackProgress,
      doubanId: existing.item.doubanId,
      imdbId: existing.item.imdbId,
      tmdbId: existing.item.tmdbId,
      ratingLabels: existing.item.ratingLabels,
      container: existing.item.container,
      videoCodec: existing.item.videoCodec,
      audioCodec: existing.item.audioCodec,
      width: existing.item.width,
      height: existing.item.height,
      bitrate: existing.item.bitrate,
      fileSizeBytes: scannedItem.fileSizeBytes,
      addedAt: scannedItem.addedAt,
      lastWatchedAt: existing.item.lastWatchedAt,
    );
    return NasMediaIndexRecord(
      id: existing.id,
      sourceId: existing.sourceId,
      sectionId: scannedItem.sectionId,
      sectionName: scannedItem.sectionName,
      resourceId: existing.resourceId,
      resourcePath: scannedItem.actualAddress,
      fingerprint: existing.fingerprint,
      fileSizeBytes: scannedItem.fileSizeBytes,
      modifiedAt: scannedItem.modifiedAt,
      indexedAt: indexedAt,
      scrapedAt: existing.scrapedAt,
      recognizedTitle: existing.recognizedTitle,
      searchQuery: existing.searchQuery,
      originalFileName: scannedItem.fileName,
      parentTitle: existing.parentTitle,
      recognizedYear: existing.recognizedYear,
      recognizedItemType: existing.recognizedItemType,
      preferSeries: existing.preferSeries,
      recognizedSeasonNumber: existing.recognizedSeasonNumber,
      recognizedEpisodeNumber: existing.recognizedEpisodeNumber,
      sidecarStatus: existing.sidecarStatus,
      wmdbStatus: existing.wmdbStatus,
      tmdbStatus: existing.tmdbStatus,
      imdbStatus: existing.imdbStatus,
      item: refreshedItem,
    );
  }

  List<String> _dedupe(Iterable<String> values) =>
      NasMediaIndexer._dedupe(values);

  List<String> _mergeLabels(List<String> current, List<String> next) =>
      NasMediaIndexer._mergeLabels(current, next);

  bool _hasRatingLabelKeyword(Iterable<String> labels, String keyword) =>
      NasMediaIndexer._hasRatingLabelKeyword(labels, keyword);

  MediaItem _applyManualMetadataToItem(
    MediaItem item, {
    MetadataMatchResult? metadataMatch,
    ImdbRatingMatch? imdbRatingMatch,
  }) {
    var nextItem = item;
    if (metadataMatch != null) {
      final resolvedItemType = _resolvedMetadataItemType(metadataMatch);
      final filteredRatingLabels = _filterSupplementalRatingLabels(
        existing: nextItem.ratingLabels,
        supplemental: metadataMatch.ratingLabels,
      );
      final resolvedTitle = metadataMatch.title.trim();
      final resolvedPosterUrl = metadataMatch.posterUrl.trim();
      final resolvedBackdropUrl = metadataMatch.backdropUrl.trim();
      final resolvedLogoUrl = metadataMatch.logoUrl.trim();
      final resolvedBannerUrl = metadataMatch.bannerUrl.trim();
      nextItem = nextItem.copyWith(
        title: resolvedTitle.isNotEmpty ? resolvedTitle : nextItem.title,
        originalTitle: metadataMatch.originalTitle.trim().isNotEmpty
            ? metadataMatch.originalTitle.trim()
            : nextItem.originalTitle,
        sortTitle:
            resolvedTitle.isNotEmpty ? resolvedTitle : nextItem.sortTitle,
        overview: metadataMatch.overview.trim().isNotEmpty
            ? metadataMatch.overview.trim()
            : nextItem.overview,
        posterUrl: resolvedPosterUrl.isNotEmpty
            ? resolvedPosterUrl
            : nextItem.posterUrl,
        posterHeaders: resolvedPosterUrl.isNotEmpty
            ? const <String, String>{}
            : nextItem.posterHeaders,
        backdropUrl: resolvedBackdropUrl.isNotEmpty
            ? resolvedBackdropUrl
            : nextItem.backdropUrl,
        backdropHeaders: resolvedBackdropUrl.isNotEmpty
            ? const <String, String>{}
            : nextItem.backdropHeaders,
        logoUrl:
            resolvedLogoUrl.isNotEmpty ? resolvedLogoUrl : nextItem.logoUrl,
        logoHeaders: resolvedLogoUrl.isNotEmpty
            ? const <String, String>{}
            : nextItem.logoHeaders,
        bannerUrl: resolvedBannerUrl.isNotEmpty
            ? resolvedBannerUrl
            : nextItem.bannerUrl,
        bannerHeaders: resolvedBannerUrl.isNotEmpty
            ? const <String, String>{}
            : nextItem.bannerHeaders,
        extraBackdropUrls: metadataMatch.extraBackdropUrls.isNotEmpty
            ? _dedupe(metadataMatch.extraBackdropUrls)
            : nextItem.extraBackdropUrls,
        extraBackdropHeaders: metadataMatch.extraBackdropUrls.isNotEmpty
            ? const <String, String>{}
            : nextItem.extraBackdropHeaders,
        year: metadataMatch.year > 0 ? metadataMatch.year : nextItem.year,
        durationLabel: metadataMatch.durationLabel.trim().isNotEmpty
            ? metadataMatch.durationLabel.trim()
            : nextItem.durationLabel,
        genres: metadataMatch.genres.isNotEmpty
            ? _dedupe(metadataMatch.genres)
            : nextItem.genres,
        directors: metadataMatch.directors.isNotEmpty
            ? _dedupe(metadataMatch.directors)
            : nextItem.directors,
        actors: metadataMatch.actors.isNotEmpty
            ? _dedupe(metadataMatch.actors)
            : nextItem.actors,
        doubanId: metadataMatch.doubanId.trim().isNotEmpty
            ? metadataMatch.doubanId.trim()
            : nextItem.doubanId,
        imdbId: metadataMatch.imdbId.trim().isNotEmpty
            ? metadataMatch.imdbId.trim()
            : nextItem.imdbId,
        tmdbId: metadataMatch.tmdbId.trim().isNotEmpty
            ? metadataMatch.tmdbId.trim()
            : nextItem.tmdbId,
        itemType:
            resolvedItemType.isNotEmpty ? resolvedItemType : nextItem.itemType,
        ratingLabels: _mergeLabels(nextItem.ratingLabels, filteredRatingLabels),
      );
    }
    if (imdbRatingMatch != null &&
        imdbRatingMatch.ratingLabel.trim().isNotEmpty) {
      nextItem = nextItem.copyWith(
        imdbId: imdbRatingMatch.imdbId.trim().isNotEmpty
            ? imdbRatingMatch.imdbId.trim()
            : nextItem.imdbId,
        ratingLabels: _mergeLabels(
          nextItem.ratingLabels,
          [imdbRatingMatch.ratingLabel.trim()],
        ),
      );
    }
    return nextItem;
  }

  MediaItem _applyManualMetadataToGroupedItem(
    MediaItem item, {
    MetadataMatchResult? metadataMatch,
    ImdbRatingMatch? imdbRatingMatch,
  }) {
    var nextItem = item;
    if (metadataMatch != null) {
      final filteredRatingLabels = _filterSupplementalRatingLabels(
        existing: nextItem.ratingLabels,
        supplemental: metadataMatch.ratingLabels,
      );
      final resolvedPosterUrl = metadataMatch.posterUrl.trim();
      final resolvedBackdropUrl = metadataMatch.backdropUrl.trim();
      final resolvedLogoUrl = metadataMatch.logoUrl.trim();
      final resolvedBannerUrl = metadataMatch.bannerUrl.trim();
      nextItem = nextItem.copyWith(
        overview: metadataMatch.overview.trim().isNotEmpty
            ? metadataMatch.overview.trim()
            : nextItem.overview,
        posterUrl: resolvedPosterUrl.isNotEmpty
            ? resolvedPosterUrl
            : nextItem.posterUrl,
        posterHeaders: resolvedPosterUrl.isNotEmpty
            ? const <String, String>{}
            : nextItem.posterHeaders,
        backdropUrl: resolvedBackdropUrl.isNotEmpty
            ? resolvedBackdropUrl
            : nextItem.backdropUrl,
        backdropHeaders: resolvedBackdropUrl.isNotEmpty
            ? const <String, String>{}
            : nextItem.backdropHeaders,
        logoUrl:
            resolvedLogoUrl.isNotEmpty ? resolvedLogoUrl : nextItem.logoUrl,
        logoHeaders: resolvedLogoUrl.isNotEmpty
            ? const <String, String>{}
            : nextItem.logoHeaders,
        bannerUrl: resolvedBannerUrl.isNotEmpty
            ? resolvedBannerUrl
            : nextItem.bannerUrl,
        bannerHeaders: resolvedBannerUrl.isNotEmpty
            ? const <String, String>{}
            : nextItem.bannerHeaders,
        extraBackdropUrls: metadataMatch.extraBackdropUrls.isNotEmpty
            ? _dedupe(metadataMatch.extraBackdropUrls)
            : nextItem.extraBackdropUrls,
        extraBackdropHeaders: metadataMatch.extraBackdropUrls.isNotEmpty
            ? const <String, String>{}
            : nextItem.extraBackdropHeaders,
        year: metadataMatch.year > 0 ? metadataMatch.year : nextItem.year,
        durationLabel: metadataMatch.durationLabel.trim().isNotEmpty
            ? metadataMatch.durationLabel.trim()
            : nextItem.durationLabel,
        genres: metadataMatch.genres.isNotEmpty
            ? _dedupe(metadataMatch.genres)
            : nextItem.genres,
        directors: metadataMatch.directors.isNotEmpty
            ? _dedupe(metadataMatch.directors)
            : nextItem.directors,
        actors: metadataMatch.actors.isNotEmpty
            ? _dedupe(metadataMatch.actors)
            : nextItem.actors,
        doubanId: metadataMatch.doubanId.trim().isNotEmpty
            ? metadataMatch.doubanId.trim()
            : nextItem.doubanId,
        imdbId: metadataMatch.imdbId.trim().isNotEmpty
            ? metadataMatch.imdbId.trim()
            : nextItem.imdbId,
        tmdbId: metadataMatch.tmdbId.trim().isNotEmpty
            ? metadataMatch.tmdbId.trim()
            : nextItem.tmdbId,
        ratingLabels: _mergeLabels(nextItem.ratingLabels, filteredRatingLabels),
      );
    }
    if (imdbRatingMatch != null &&
        imdbRatingMatch.ratingLabel.trim().isNotEmpty) {
      nextItem = nextItem.copyWith(
        imdbId: imdbRatingMatch.imdbId.trim().isNotEmpty
            ? imdbRatingMatch.imdbId.trim()
            : nextItem.imdbId,
        ratingLabels: _mergeLabels(
          nextItem.ratingLabels,
          [imdbRatingMatch.ratingLabel.trim()],
        ),
      );
    }
    return nextItem;
  }

  List<String> _filterSupplementalRatingLabels({
    required List<String> existing,
    required List<String> supplemental,
  }) {
    if (!_hasRatingLabelKeyword(existing, '豆瓣')) {
      return supplemental;
    }
    return supplemental
        .where((label) => !label.trim().toLowerCase().contains('豆瓣'))
        .toList(growable: false);
  }

  Future<void> _persistSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
  }) async {
    final normalizedSourceId = sourceId.trim();
    final normalizedRecords = List<NasMediaIndexRecord>.unmodifiable(records);
    await _store.replaceSourceRecords(
      sourceId: normalizedSourceId,
      records: normalizedRecords,
      state: state,
    );
    _libraryMatchCaches[normalizedSourceId] =
        _buildLibraryMatchCache(normalizedRecords);
  }

  Future<List<NasMediaIndexRecord>> _loadSourceRecordsCached(
    String sourceId,
  ) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return const [];
    }
    final cached = _libraryMatchCaches[normalizedSourceId];
    if (cached != null) {
      return cached.records;
    }
    final records = await _store.loadSourceRecords(normalizedSourceId);
    _libraryMatchCaches[normalizedSourceId] = _buildLibraryMatchCache(records);
    return _libraryMatchCaches[normalizedSourceId]?.records ?? records;
  }

  Future<_NasLibraryMatchCache> _loadLibraryMatchCache(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    final cached = _libraryMatchCaches[normalizedSourceId];
    if (cached != null) {
      return cached;
    }
    final records = await _store.loadSourceRecords(normalizedSourceId);
    final nextCache = _buildLibraryMatchCache(records);
    _libraryMatchCaches[normalizedSourceId] = nextCache;
    return nextCache;
  }

  _NasLibraryMatchCache _buildLibraryMatchCache(
    List<NasMediaIndexRecord> records,
  ) {
    final normalizedRecords = List<NasMediaIndexRecord>.unmodifiable(records);
    final libraryItems = List<MediaItem>.unmodifiable(
      _materializeLibraryItems(normalizedRecords),
    );
    final itemsByLookupKey = <String, List<MediaItem>>{};
    for (final item in libraryItems) {
      for (final lookupKey in _buildLibraryMatchLookupKeys(item)) {
        itemsByLookupKey.putIfAbsent(lookupKey, () => <MediaItem>[]).add(item);
      }
    }
    return _NasLibraryMatchCache(
      records: normalizedRecords,
      libraryItems: libraryItems,
      itemsByLookupKey: itemsByLookupKey,
    );
  }

  List<String> _buildLibraryMatchLookupKeys(MediaItem item) {
    final keys = <String>{};

    void addKey(String prefix, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      keys.add('$prefix|$trimmed');
    }

    addKey('douban', item.doubanId);
    addKey('imdb', item.imdbId.toLowerCase());
    addKey('tmdb', item.tmdbId);
    addKey('tvdb', _resolveLibraryMatchTvdbId(item));
    addKey('wikidata', _resolveLibraryMatchWikidataId(item).toUpperCase());
    return keys.toList(growable: false);
  }

  String _resolveLibraryMatchTvdbId(MediaItem item) {
    final current = item.tvdbId.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return item.providerIds['Tvdb']?.trim() ??
        item.providerIds['TVDb']?.trim() ??
        item.providerIds['tvdb']?.trim() ??
        '';
  }

  String _resolveLibraryMatchWikidataId(MediaItem item) {
    final current = item.wikidataId.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return item.providerIds['Wikidata']?.trim() ??
        item.providerIds['WikiData']?.trim() ??
        item.providerIds['wikidata']?.trim() ??
        '';
  }

  Map<String, String> _mergeProviderIdMaps(
    Iterable<Map<String, String>> providerIdMaps,
  ) {
    final merged = <String, String>{};
    for (final entry in providerIdMaps) {
      entry.forEach((key, value) {
        final normalizedKey = key.trim();
        final normalizedValue = value.trim();
        if (normalizedKey.isEmpty ||
            normalizedValue.isEmpty ||
            merged.containsKey(normalizedKey)) {
          return;
        }
        merged[normalizedKey] = normalizedValue;
      });
    }
    return merged;
  }
}

class _NasLibraryMatchCache {
  const _NasLibraryMatchCache({
    required this.records,
    required this.libraryItems,
    required this.itemsByLookupKey,
  });

  final List<NasMediaIndexRecord> records;
  final List<MediaItem> libraryItems;
  final Map<String, List<MediaItem>> itemsByLookupKey;

  List<MediaItem> findByExternalIds({
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
  }) {
    final matchesById = <String, MediaItem>{};

    void collect(String prefix, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      final items = itemsByLookupKey['$prefix|$trimmed'];
      if (items == null) {
        return;
      }
      for (final item in items) {
        matchesById[item.id] = item;
      }
    }

    collect('douban', doubanId);
    collect('imdb', imdbId.toLowerCase());
    collect('tmdb', tmdbId);
    collect('tvdb', tvdbId);
    collect('wikidata', wikidataId.toUpperCase());
    return matchesById.values.toList(growable: false);
  }
}
