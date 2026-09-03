part of 'nas_media_indexer.dart';

extension _NasMediaIndexerGroupingSupportX on NasMediaIndexer {
  List<MediaItem> materializeLibraryItems(List<NasMediaIndexRecord> records) {
    final groups = groupSeriesRecords(records);
    return materializeLibraryItemsFromGroups(records, groups);
  }

  List<MediaItem> materializeLibraryItemsFromGroups(
    List<NasMediaIndexRecord> records,
    List<_SeriesRecordGroup> groups,
  ) {
    final nonSeriesItems = <MediaItem>[];
    final movieVariantGroups = groupMovieVariantRecords(records);
    final groupedResourceIds = <String>{
      ...groups.expand(
        (group) => group.records.map((record) => record.resourceId),
      ),
      ...movieVariantGroups.expand(
        (group) => group.records.map((record) => record.resourceId),
      ),
    };

    for (final record in records) {
      if (!groupedResourceIds.contains(record.resourceId)) {
        nonSeriesItems.add(record.item);
      }
    }

    final seriesItems = groups.map(buildSeriesItem);
    final movieVariantItems = movieVariantGroups.map(buildMovieVariantItem);
    final allItems = [
      ...nonSeriesItems,
      ...movieVariantItems,
      ...seriesItems,
    ];
    allItems.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return allItems;
  }

  List<_MovieVariantRecordGroup> groupMovieVariantRecords(
    List<NasMediaIndexRecord> records,
  ) {
    final grouped = <String, List<NasMediaIndexRecord>>{};
    final titleByKey = <String, String>{};
    final versionDirectoriesByKey = <String, Set<String>>{};
    for (final record in records) {
      if (!_isMovieVariantRecord(record)) {
        continue;
      }
      final pathInfo = _movieVariantPathInfo(record.resourcePath);
      if (pathInfo == null) {
        continue;
      }
      final rootTitle = _cleanIndexedTitleLabel(pathInfo.rootSegments.last);
      final itemTitle = _cleanIndexedTitleLabel(record.item.title);
      final title = rootTitle.isNotEmpty ? rootTitle : itemTitle;
      if (title.isEmpty) {
        continue;
      }
      final normalizedRoot = pathInfo.rootSegments
          .map((segment) => segment.trim().toLowerCase())
          .join('/');
      final key = '${record.sectionId.trim()}|$normalizedRoot';
      grouped.putIfAbsent(key, () => <NasMediaIndexRecord>[]).add(record);
      versionDirectoriesByKey
          .putIfAbsent(key, () => <String>{})
          .add(pathInfo.versionDirectory.trim().toLowerCase());
      titleByKey.putIfAbsent(key, () => title);
    }

    return grouped.entries
        .where(
          (entry) =>
              entry.value.length >= 2 &&
              (versionDirectoriesByKey[entry.key]?.length ?? 0) >= 2,
        )
        .map(
          (entry) => _MovieVariantRecordGroup(
            title: titleByKey[entry.key] ?? entry.value.first.item.title,
            records: entry.value,
          ),
        )
        .toList(growable: false);
  }

  MediaItem buildMovieVariantItem(_MovieVariantRecordGroup group) {
    final records = [...group.records]..sort((left, right) {
        final scoreCompare = movieVariantRepresentativeScore(right)
            .compareTo(movieVariantRepresentativeScore(left));
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return right.item.addedAt.compareTo(left.item.addedAt);
      });
    final base = records.first.item;
    final latestAddedAt = records
        .map((record) => record.item.addedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    return base.copyWith(
      title: group.title,
      sortTitle: group.title,
      itemType: 'movie',
      durationLabel:
          base.durationLabel.trim() == '剧集' ? '文件' : base.durationLabel,
      addedAt: latestAddedAt,
    );
  }

  bool _isMovieVariantRecord(NasMediaIndexRecord record) {
    final itemType = record.item.itemType.trim().toLowerCase();
    final recognizedItemType = record.recognizedItemType.trim().toLowerCase();
    if (itemType == 'episode' ||
        itemType == 'series' ||
        itemType == 'season' ||
        recognizedItemType == 'episode' ||
        recognizedItemType == 'series' ||
        recognizedItemType == 'season') {
      return false;
    }
    if (itemType != 'movie' &&
        recognizedItemType != 'movie' &&
        record.preferSeries) {
      return false;
    }
    return record.item.seasonNumber == null &&
        record.item.episodeNumber == null &&
        record.recognizedSeasonNumber == null &&
        record.recognizedEpisodeNumber == null;
  }

  _MovieVariantPathInfo? _movieVariantPathInfo(String resourcePath) {
    final segments = _pathSegments(resourcePath);
    if (segments.length < 3) {
      return null;
    }
    // A version directory can contain one or more organization layers below
    // it. Find the outermost matching ancestor so every file in that version
    // still shares the movie root with its sibling versions.
    for (var index = 1; index < segments.length - 1; index++) {
      if (NasMediaRecognizer.matchesMovieVersionFolderLabel(segments[index])) {
        final rootSegments = segments.sublist(0, index);
        if (rootSegments.isEmpty) {
          return null;
        }
        return _MovieVariantPathInfo(
          rootSegments: rootSegments,
          versionDirectory: segments[index],
        );
      }
    }
    return null;
  }

  int movieVariantRepresentativeScore(NasMediaIndexRecord record) {
    final item = record.item;
    var score = item.isPlayable ? 1000 : 0;
    score += item.posterUrl.trim().isNotEmpty ? 100 : 0;
    score += item.backdropUrl.trim().isNotEmpty ? 50 : 0;
    score += item.overview.trim().isNotEmpty ? 25 : 0;
    score += (item.width ?? 0) ~/ 100;
    score += (item.bitrate ?? 0) ~/ 1000000;
    return score;
  }

  List<_SeriesRecordGroup> groupSeriesRecords(
    List<NasMediaIndexRecord> records,
  ) {
    final seriesTitleFilterKeywords =
        _webDavSeriesTitleFilterKeywordsForRecords(records);
    final grouped = <String, List<NasMediaIndexRecord>>{};
    for (final record in records) {
      if (!_shouldGroupAsSeries(record)) {
        continue;
      }
      final title = _seriesTitleForRecord(
        record,
        seriesTitleFilterKeywords: seriesTitleFilterKeywords,
      );
      if (title.isEmpty) {
        continue;
      }
      final key = _buildSeriesGroupKey(
        record,
        title,
        seriesTitleFilterKeywords: seriesTitleFilterKeywords,
      );
      grouped.putIfAbsent(key, () => <NasMediaIndexRecord>[]).add(record);
    }
    final groups = grouped.entries
        .map(
          (entry) => _SeriesRecordGroup(
            seriesKey: entry.key,
            records: entry.value,
            title: _seriesTitleForRecord(
              entry.value.first,
              seriesTitleFilterKeywords: seriesTitleFilterKeywords,
            ),
          ),
        )
        .toList(growable: false);
    return groups;
  }

  MediaItem buildSeriesItem(_SeriesRecordGroup group) {
    final records = [...group.records]
      ..sort((left, right) => right.item.addedAt.compareTo(left.item.addedAt));
    final base = records.first;
    final bestOverview = records
        .map((record) => record.item.overview.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final bestPoster = records
        .map((record) => record.item.posterUrl.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final posterHeaders = records
        .map((record) => record.item.posterHeaders)
        .firstWhere((value) => value.isNotEmpty, orElse: () => const {});
    final bestBackdrop = records
        .map((record) => record.item.backdropUrl.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final backdropHeaders = records
        .map((record) => record.item.backdropHeaders)
        .firstWhere((value) => value.isNotEmpty, orElse: () => const {});
    final bestLogo = records
        .map((record) => record.item.logoUrl.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final logoHeaders = records
        .map((record) => record.item.logoHeaders)
        .firstWhere((value) => value.isNotEmpty, orElse: () => const {});
    final bestBanner = records
        .map((record) => record.item.bannerUrl.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final bannerHeaders = records
        .map((record) => record.item.bannerHeaders)
        .firstWhere((value) => value.isNotEmpty, orElse: () => const {});
    final extraBackdropUrls = records
        .map((record) => record.item.extraBackdropUrls)
        .firstWhere((value) => value.isNotEmpty, orElse: () => const []);
    final extraBackdropHeaders = records
        .map((record) => record.item.extraBackdropHeaders)
        .firstWhere((value) => value.isNotEmpty, orElse: () => const {});
    final bestYear = records
        .map((record) => record.item.year)
        .firstWhere((value) => value > 0, orElse: () => 0);
    final ratingLabels = NasMediaIndexer._mergeLabels(
      const [],
      records.expand((record) => record.item.ratingLabels).toList(),
    );
    final genres = NasMediaIndexer._dedupe(
        records.expand((record) => record.item.genres).toList());
    final directors = NasMediaIndexer._dedupe(
        records.expand((record) => record.item.directors).toList());
    final actors = NasMediaIndexer._dedupe(
        records.expand((record) => record.item.actors).toList());
    final imdbId = records
        .map((record) => record.item.imdbId.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final tmdbId = records
        .map((record) => record.item.tmdbId.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final doubanId = records
        .map((record) => record.item.doubanId.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final tvdbId = records
        .map((record) => _resolveLibraryMatchTvdbId(record.item))
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final wikidataId = records
        .map((record) => _resolveLibraryMatchWikidataId(record.item))
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final providerIds = _mergeProviderIdMaps(
      records.map((record) => record.item.providerIds),
    );
    final lastAddedAt = records
        .map((record) => record.item.addedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);

    final seriesItem = MediaItem(
      id: _buildSeriesItemId(group.seriesKey),
      title: group.title,
      overview: bestOverview,
      posterUrl: bestPoster,
      posterHeaders: posterHeaders,
      backdropUrl: bestBackdrop,
      backdropHeaders: backdropHeaders,
      logoUrl: bestLogo,
      logoHeaders: logoHeaders,
      bannerUrl: bestBanner,
      bannerHeaders: bannerHeaders,
      extraBackdropUrls: extraBackdropUrls,
      extraBackdropHeaders: extraBackdropHeaders,
      year: bestYear,
      durationLabel: '剧集',
      genres: genres,
      directors: directors,
      actors: actors,
      itemType: 'series',
      sectionId: base.sectionId,
      sectionName: base.sectionName,
      sourceId: base.sourceId,
      sourceName: base.item.sourceName,
      sourceKind: base.item.sourceKind,
      streamUrl: '',
      actualAddress: _commonDirectoryPath(
        records.map((record) => record.resourcePath),
      ),
      streamHeaders: const {},
      imdbId: imdbId,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      wikidataId: wikidataId,
      doubanId: doubanId,
      providerIds: providerIds,
      ratingLabels: ratingLabels,
      addedAt: lastAddedAt,
    );

    return seriesItem;
  }

  MediaItem buildSeasonItem(
    _SeriesRecordGroup group,
    int seasonNumber,
    List<NasMediaIndexRecord> records,
  ) {
    final sorted = [...records]
      ..sort((left, right) => right.item.addedAt.compareTo(left.item.addedAt));
    final base = sorted.first;
    final label = _seasonLabel(
      group: group,
      seasonNumber: seasonNumber,
      records: records,
    );
    final seasonItem = MediaItem(
      id: _buildSeasonItemId(group.seriesKey, seasonNumber),
      title: label,
      overview: base.item.overview,
      posterUrl: base.item.posterUrl,
      posterHeaders: base.item.posterHeaders,
      backdropUrl: base.item.backdropUrl,
      backdropHeaders: base.item.backdropHeaders,
      logoUrl: base.item.logoUrl,
      logoHeaders: base.item.logoHeaders,
      bannerUrl: base.item.bannerUrl,
      bannerHeaders: base.item.bannerHeaders,
      extraBackdropUrls: base.item.extraBackdropUrls,
      extraBackdropHeaders: base.item.extraBackdropHeaders,
      year: base.item.year,
      durationLabel: '剧集',
      genres: NasMediaIndexer._dedupe(
        records.expand((record) => record.item.genres).toList(),
      ),
      directors: NasMediaIndexer._dedupe(
          records.expand((record) => record.item.directors).toList()),
      actors: NasMediaIndexer._dedupe(
        records.expand((record) => record.item.actors).toList(),
      ),
      itemType: 'season',
      sectionId: base.sectionId,
      sectionName: base.sectionName,
      sourceId: base.sourceId,
      sourceName: base.item.sourceName,
      sourceKind: base.item.sourceKind,
      streamUrl: '',
      actualAddress: _commonDirectoryPath(
        records.map((record) => record.resourcePath),
      ),
      streamHeaders: const {},
      seasonNumber: seasonNumber,
      imdbId: base.item.imdbId,
      tmdbId: base.item.tmdbId,
      tvdbId: _resolveLibraryMatchTvdbId(base.item),
      wikidataId: _resolveLibraryMatchWikidataId(base.item),
      doubanId: base.item.doubanId,
      providerIds: base.item.providerIds,
      ratingLabels: NasMediaIndexer._mergeLabels(
        const [],
        records.expand((e) => e.item.ratingLabels).toList(),
      ),
      addedAt: sorted.first.item.addedAt,
    );

    return seasonItem;
  }

  List<MediaItem> materializeEpisodeItems(
      Iterable<NasMediaIndexRecord> records) {
    final recordList = records.toList(growable: false);
    final specialEpisodeKeywords =
        _webDavSpecialEpisodeKeywordsForRecords(recordList);
    final grouped = <String, List<NasMediaIndexRecord>>{};
    final passthrough = <MediaItem>[];
    for (final record in recordList) {
      final key = _episodeMergeGroupKey(
        record,
        specialEpisodeKeywords: specialEpisodeKeywords,
      );
      if (key == null) {
        passthrough.add(record.item);
        continue;
      }
      grouped.putIfAbsent(key, () => <NasMediaIndexRecord>[]).add(record);
    }

    final items = <MediaItem>[
      ...passthrough,
      ...grouped.values.map(
        (records) => _mergeEpisodeVariantRecords(
          records,
          specialEpisodeKeywords: specialEpisodeKeywords,
        ),
      ),
    ]..sort((left, right) {
        final seasonComparison =
            (left.seasonNumber ?? 0).compareTo(right.seasonNumber ?? 0);
        if (seasonComparison != 0) {
          return seasonComparison;
        }
        final episodeComparison =
            (left.episodeNumber ?? 0).compareTo(right.episodeNumber ?? 0);
        if (episodeComparison != 0) {
          return episodeComparison;
        }
        return left.title.toLowerCase().compareTo(right.title.toLowerCase());
      });
    return items;
  }

  int? resolvedRecordSeasonNumber(NasMediaIndexRecord record) {
    return record.item.seasonNumber ?? record.recognizedSeasonNumber;
  }

  int? resolvedRecordEpisodeNumber(NasMediaIndexRecord record) {
    return record.item.episodeNumber ?? record.recognizedEpisodeNumber;
  }

  List<NasMediaIndexRecord> sortEpisodeRecordsForDisplay(
    Iterable<NasMediaIndexRecord> records,
  ) {
    final sorted = records.toList(growable: false)
      ..sort(_compareEpisodeRecordsForDisplay);
    return sorted;
  }

  String? _episodeMergeGroupKey(
    NasMediaIndexRecord record, {
    required List<String> specialEpisodeKeywords,
  }) {
    final seasonNumber = resolvedRecordSeasonNumber(record);
    final episodeNumber = resolvedRecordEpisodeNumber(record);
    if (_isSpecialEpisodeRecord(
      record,
      specialEpisodeKeywords: specialEpisodeKeywords,
    )) {
      final specialTitle = _normalizedSpecialEpisodeMergeTitle(record);
      if (specialTitle.isNotEmpty) {
        final seasonKey = seasonNumber ?? 0;
        return '$seasonKey|special:$specialTitle';
      }
    }
    if (seasonNumber == null || episodeNumber == null) {
      final normalizedTitle = _normalizedEpisodeMergeTitle(record.item.title);
      if (normalizedTitle.isEmpty) {
        return null;
      }
      final seasonKey = seasonNumber ?? 0;
      return '$seasonKey|title:$normalizedTitle';
    }
    final episodePart = _resolvedEpisodePartTokenForRecord(
      record,
      specialEpisodeKeywords: specialEpisodeKeywords,
    );
    if (episodePart.isNotEmpty) {
      return '$seasonNumber|$episodeNumber|part:$episodePart';
    }
    return '$seasonNumber|$episodeNumber';
  }

  String _normalizedEpisodeMergeTitle(String value) {
    final cleaned = _cleanIndexedTitleLabel(value);
    if (cleaned.isEmpty) {
      return '';
    }
    return _normalizeMetadataQueryToken(cleaned);
  }

  int _compareEpisodeRecordsForDisplay(
    NasMediaIndexRecord left,
    NasMediaIndexRecord right,
  ) {
    final seasonComparison = (resolvedRecordSeasonNumber(left) ?? 0)
        .compareTo(resolvedRecordSeasonNumber(right) ?? 0);
    if (seasonComparison != 0) {
      return seasonComparison;
    }

    final episodeComparison = (resolvedRecordEpisodeNumber(left) ?? 0)
        .compareTo(resolvedRecordEpisodeNumber(right) ?? 0);
    if (episodeComparison != 0) {
      return episodeComparison;
    }

    final resolutionComparison = _compareNullableIntsDescending(
      _resolvedPixelCount(left.item),
      _resolvedPixelCount(right.item),
    );
    if (resolutionComparison != 0) {
      return resolutionComparison;
    }

    final bitrateComparison = _compareNullableIntsDescending(
      left.item.bitrate,
      right.item.bitrate,
    );
    if (bitrateComparison != 0) {
      return bitrateComparison;
    }

    final fileSizeComparison = _compareNullableIntsDescending(
      left.fileSizeBytes,
      right.fileSizeBytes,
    );
    if (fileSizeComparison != 0) {
      return fileSizeComparison;
    }

    final addedAtComparison = right.item.addedAt.compareTo(left.item.addedAt);
    if (addedAtComparison != 0) {
      return addedAtComparison;
    }

    final titleComparison =
        left.item.title.toLowerCase().compareTo(right.item.title.toLowerCase());
    if (titleComparison != 0) {
      return titleComparison;
    }

    return left.resourcePath.compareTo(right.resourcePath);
  }

  int _compareNullableIntsDescending(int? left, int? right) {
    return (right ?? 0).compareTo(left ?? 0);
  }

  int _resolvedPixelCount(MediaItem item) {
    final width = item.width ?? 0;
    final height = item.height ?? 0;
    if (width <= 0 || height <= 0) {
      return 0;
    }
    return width * height;
  }

  MediaItem _mergeEpisodeVariantRecords(
    List<NasMediaIndexRecord> records, {
    required List<String> specialEpisodeKeywords,
  }) {
    final sorted = sortEpisodeRecordsForDisplay(records);
    final base = sorted.first;
    final preferredSpecialTitle = _resolvePreferredSpecialEpisodeTitle(
      sorted,
      specialEpisodeKeywords: specialEpisodeKeywords,
    );

    String pickString(String Function(MediaItem item) selector) {
      for (final record in sorted) {
        final candidate = selector(record.item).trim();
        if (candidate.isNotEmpty) {
          return candidate;
        }
      }
      return selector(base.item).trim();
    }

    Map<String, String> pickHeaders(
      String Function(MediaItem item) selector,
      Map<String, String> Function(MediaItem item) headersSelector,
    ) {
      for (final record in sorted) {
        if (selector(record.item).trim().isNotEmpty) {
          return headersSelector(record.item);
        }
      }
      return headersSelector(base.item);
    }

    List<String> pickBackdropUrls() {
      for (final record in sorted) {
        if (record.item.extraBackdropUrls.isNotEmpty) {
          return record.item.extraBackdropUrls;
        }
      }
      return base.item.extraBackdropUrls;
    }

    final mergedGenres = NasMediaIndexer._dedupe(
      sorted.expand((record) => record.item.genres).toList(),
    );
    final mergedDirectors = NasMediaIndexer._dedupe(
      sorted.expand((record) => record.item.directors).toList(),
    );
    final mergedActors = NasMediaIndexer._dedupe(
      sorted.expand((record) => record.item.actors).toList(),
    );
    final mergedRatingLabels = NasMediaIndexer._mergeLabels(
      const [],
      sorted.expand((record) => record.item.ratingLabels).toList(),
    );
    final maxAddedAt = sorted
        .map((record) => record.item.addedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    DateTime? lastWatchedAt;
    double? maxPlaybackProgress;
    for (final record in sorted) {
      final candidateLastWatchedAt = record.item.lastWatchedAt;
      if (candidateLastWatchedAt != null &&
          (lastWatchedAt == null ||
              candidateLastWatchedAt.isAfter(lastWatchedAt))) {
        lastWatchedAt = candidateLastWatchedAt;
      }
      final candidateProgress = record.item.playbackProgress;
      if (candidateProgress != null &&
          (maxPlaybackProgress == null ||
              candidateProgress > maxPlaybackProgress)) {
        maxPlaybackProgress = candidateProgress;
      }
    }

    return base.item.copyWith(
      title: preferredSpecialTitle,
      overview: pickString((item) => item.overview),
      posterUrl: pickString((item) => item.posterUrl),
      posterHeaders: pickHeaders(
        (item) => item.posterUrl,
        (item) => item.posterHeaders,
      ),
      backdropUrl: pickString((item) => item.backdropUrl),
      backdropHeaders: pickHeaders(
        (item) => item.backdropUrl,
        (item) => item.backdropHeaders,
      ),
      logoUrl: pickString((item) => item.logoUrl),
      logoHeaders: pickHeaders(
        (item) => item.logoUrl,
        (item) => item.logoHeaders,
      ),
      bannerUrl: pickString((item) => item.bannerUrl),
      bannerHeaders: pickHeaders(
        (item) => item.bannerUrl,
        (item) => item.bannerHeaders,
      ),
      extraBackdropUrls: pickBackdropUrls(),
      extraBackdropHeaders: pickHeaders(
        (item) =>
            item.extraBackdropUrls.isEmpty ? '' : item.extraBackdropUrls.first,
        (item) => item.extraBackdropHeaders,
      ),
      year: sorted
          .map((record) => record.item.year)
          .firstWhere((value) => value > 0, orElse: () => base.item.year),
      durationLabel: pickString((item) => item.durationLabel),
      genres: mergedGenres,
      directors: mergedDirectors,
      actors: mergedActors,
      playbackProgress: maxPlaybackProgress ?? base.item.playbackProgress,
      ratingLabels: mergedRatingLabels,
      addedAt: maxAddedAt,
      lastWatchedAt: lastWatchedAt ?? base.item.lastWatchedAt,
    );
  }

  String _resolvePreferredSpecialEpisodeTitle(
    List<NasMediaIndexRecord> records, {
    required List<String> specialEpisodeKeywords,
  }) {
    if (records.isEmpty) {
      return '';
    }
    if (!records.any(
      (record) => _isSpecialEpisodeRecord(
        record,
        specialEpisodeKeywords: specialEpisodeKeywords,
      ),
    )) {
      return records.first.item.title;
    }
    for (final record in records) {
      final candidate = _preferredSpecialEpisodeTitle(record);
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }
    return records.first.item.title;
  }

  bool _isSpecialEpisodeRecord(
    NasMediaIndexRecord record, {
    required List<String> specialEpisodeKeywords,
  }) {
    final seasonNumber = resolvedRecordSeasonNumber(record);
    if (seasonNumber == 0) {
      return true;
    }
    // Indexing already resolved a real season for this record, so a keyword
    // in the name is just part of the title.  Merging it by title instead of
    // by season/episode would break variant merging for regular episodes.
    if (seasonNumber != null) {
      return false;
    }
    return _matchedSpecialEpisodeKeyword(
          record,
          specialEpisodeKeywords: specialEpisodeKeywords,
        ) !=
        null;
  }

  String _normalizedSpecialEpisodeMergeTitle(NasMediaIndexRecord record) {
    final preferredTitle = _preferredSpecialEpisodeTitle(record);
    if (preferredTitle.isEmpty) {
      return '';
    }
    return _normalizeMetadataQueryToken(preferredTitle);
  }

  String _preferredSpecialEpisodeTitle(NasMediaIndexRecord record) {
    for (final candidate in [
      record.originalFileName,
      _lastPathSegment(record.resourcePath),
      record.item.title,
      record.recognizedTitle,
    ]) {
      final cleaned = _cleanSpecialEpisodeTitle(candidate);
      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }
    return '';
  }

  String _cleanSpecialEpisodeTitle(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return '';
    }
    final slashIndex = value.lastIndexOf('/');
    if (slashIndex >= 0 && slashIndex + 1 < value.length) {
      value = value.substring(slashIndex + 1);
    }
    value = value.replaceAll(RegExp(r'\.[A-Za-z0-9]{1,6}$'), ' ');
    value = stripEmbeddedExternalIdTags(value).trim();
    value = value.replaceAll(RegExp(r'[_\.]+'), ' ');
    value = value.replaceAll(RegExp(r'[【\[\(].*?[】\]\)]'), ' ');
    value = MediaNaming.stripCommonTitleNoiseTokens(value);
    value = value.replaceAllMapped(
      RegExp(r'^(19\d{2}|20\d{2})[ ._\-](\d{1,2})[ ._\-](\d{1,2})[ ._\-]*'),
      (match) => '${match.group(2)} ${match.group(3)}-',
    );
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value;
  }

  String? _matchedSpecialEpisodeKeyword(
    NasMediaIndexRecord record, {
    required List<String> specialEpisodeKeywords,
  }) {
    return MediaNaming.bestMatchedSpecialCategoryKeyword(
      [
        record.originalFileName,
        record.item.title,
        record.recognizedTitle,
        // Scoped to the containing directory on purpose: matching the whole
        // resource path let a keyword in the mount point or library root
        // reclassify every file below it.
        _lastPathSegment(_parentDirectoryPath(record.resourcePath)),
        record.parentTitle,
      ],
      keywords: specialEpisodeKeywords,
    );
  }

  String _parentDirectoryPath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    final slashIndex = normalized.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '';
    }
    return normalized.substring(0, slashIndex);
  }

  String _seasonLabel({
    required _SeriesRecordGroup group,
    required int seasonNumber,
    required List<NasMediaIndexRecord> records,
  }) {
    if (seasonNumber == 0) {
      return '特别篇';
    }
    final commonPath = _commonDirectoryPath(
      records.map((record) => record.resourcePath),
    );
    final commonSegments = _pathSegments(commonPath);
    final explicitSeasonLabel = commonSegments.firstWhere(
      _looksLikeSeasonFolderLabel,
      orElse: () => '',
    );
    if (explicitSeasonLabel.isNotEmpty) {
      if (_looksLikeNumericTopicSeason(explicitSeasonLabel)) {
        return explicitSeasonLabel;
      }
      if (_parseSeasonNumberFromLabel(explicitSeasonLabel) != null) {
        return '第 $seasonNumber 季';
      }
    }
    final lastSegment = _lastPathSegment(commonPath);
    if (lastSegment.isEmpty) {
      return '第 $seasonNumber 季';
    }
    if (_looksLikeNumericTopicSeason(lastSegment)) {
      return lastSegment;
    }
    if (_parseSeasonNumberFromLabel(lastSegment) != null) {
      return '第 $seasonNumber 季';
    }
    if (lastSegment == group.title) {
      return '第 $seasonNumber 季';
    }
    if (NasMediaRecognizer.matchesWrapperFolderLabel(lastSegment)) {
      return '第 $seasonNumber 季';
    }
    return lastSegment;
  }

  String _buildSeriesItemId(String seriesKey) {
    return '${NasMediaIndexer._seriesGroupPrefix}|${Uri.encodeComponent(seriesKey)}';
  }

  String _commonDirectoryPath(Iterable<String> paths) {
    final directories = paths
        .map(_directoryPath)
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (directories.isEmpty) {
      return '';
    }
    if (directories.length == 1) {
      return directories.first;
    }

    final splitDirectories =
        directories.map((value) => value.split('/')).toList(growable: false);
    final first = splitDirectories.first;
    var maxLength = first.length;
    for (final segments in splitDirectories.skip(1)) {
      if (segments.length < maxLength) {
        maxLength = segments.length;
      }
    }

    var commonLength = 0;
    while (commonLength < maxLength) {
      final candidate = first[commonLength];
      final matchesAll = splitDirectories.every(
        (segments) => segments[commonLength] == candidate,
      );
      if (!matchesAll) {
        break;
      }
      commonLength += 1;
    }

    if (commonLength == 0) {
      return directories.first;
    }
    final joined = first.take(commonLength).join('/');
    return joined.isEmpty ? '/' : joined;
  }

  String _directoryPath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) {
      return '';
    }
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final lastSlash = trimmed.lastIndexOf('/');
    if (lastSlash <= 0) {
      return trimmed;
    }
    return trimmed.substring(0, lastSlash);
  }

  String _lastPathSegment(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) {
      return '';
    }
    final segments = normalized
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? '' : segments.last;
  }

  String _buildSeasonItemId(String seriesKey, int seasonNumber) {
    return '${NasMediaIndexer._seasonGroupPrefix}|${Uri.encodeComponent(seriesKey)}|$seasonNumber';
  }

  bool _shouldGroupAsSeries(NasMediaIndexRecord record) {
    final itemType = record.item.itemType.trim().toLowerCase();
    final recognizedItemType = record.recognizedItemType.trim().toLowerCase();
    if (itemType == 'series' || itemType == 'season' || itemType == 'movie') {
      return false;
    }
    if (recognizedItemType == 'movie' &&
        record.item.seasonNumber == null &&
        record.item.episodeNumber == null &&
        record.recognizedSeasonNumber == null &&
        record.recognizedEpisodeNumber == null) {
      return false;
    }
    return itemType == 'episode' ||
        recognizedItemType == 'episode' ||
        record.preferSeries ||
        record.recognizedSeasonNumber != null ||
        record.recognizedEpisodeNumber != null;
  }

  String _seriesTitleForRecord(
    NasMediaIndexRecord record, {
    List<String> seriesTitleFilterKeywords = const [],
  }) {
    final itemTitle = _cleanIndexedTitleLabel(record.item.title);
    final parentTitle = _cleanIndexedTitleLabel(record.parentTitle);
    final recognizedTitle = _cleanIndexedTitleLabel(record.recognizedTitle);
    final itemType = record.item.itemType.trim().toLowerCase();
    final structureResolution = _resolveSeriesRootForRecord(
      record,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
    final structureSeriesTitle = structureResolution.title;
    final parentLooksLikeSeason =
        _looksLikeSeasonFolderLabel(record.parentTitle.trim());
    final parentMatchesFilter = NasMediaPathPolicy.matchesConfiguredBoundary(
      record.parentTitle,
      configuredKeywords: seriesTitleFilterKeywords,
    );
    final parentIsGroupingDescription =
        looksLikeYearGroupingFolderLabel(record.parentTitle) ||
            looksLikeQualityEpisodeCountFolderLabel(record.parentTitle);
    final canUseParentTitle = parentTitle.isNotEmpty &&
        !parentLooksLikeSeason &&
        !parentIsGroupingDescription &&
        !parentMatchesFilter;
    final prefersStructureGrouping =
        _prefersStructureRootSeriesGrouping(record, structureResolution);
    final hasCanonicalIds = record.item.imdbId.trim().isNotEmpty ||
        record.item.tmdbId.trim().isNotEmpty ||
        record.item.doubanId.trim().isNotEmpty;
    if (prefersStructureGrouping && structureSeriesTitle.isNotEmpty) {
      if (record.manualMetadataLocked && hasCanonicalIds && canUseParentTitle) {
        // A manual edit applied to the synthetic mother series deliberately
        // renames that series. Automatic child/file metadata never reaches
        // this branch because it is not manually locked.
        return parentTitle;
      }
      // Structure inference owns the series boundary. Child directories and
      // files may supply season, episode, and display metadata, but they must
      // never replace the mother directory as the series title.
      return structureSeriesTitle;
    }
    if (itemType == 'episode' && hasCanonicalIds && canUseParentTitle) {
      return parentTitle;
    }
    if (itemType == 'episode') {
      if (canUseParentTitle) {
        return parentTitle;
      }
      if (structureSeriesTitle.isNotEmpty) {
        return structureSeriesTitle;
      }
      if (recognizedTitle.isNotEmpty) {
        return recognizedTitle;
      }
    }
    if (record.preferSeries && canUseParentTitle) {
      return parentTitle;
    }
    if (record.preferSeries && recognizedTitle.isNotEmpty) {
      return recognizedTitle;
    }
    if (structureSeriesTitle.isNotEmpty &&
        (itemType == 'episode' ||
            record.preferSeries ||
            record.item.seasonNumber != null ||
            record.recognizedSeasonNumber != null)) {
      return structureSeriesTitle;
    }
    return itemTitle;
  }

  bool _prefersStructureRootSeriesGrouping(
    NasMediaIndexRecord record,
    NasSeriesRootResolution resolution,
  ) {
    if (record.item.sourceKind != MediaSourceKind.nas &&
        record.item.sourceKind != MediaSourceKind.quark) {
      return false;
    }
    final structureTitle = resolution.title.trim();
    if (structureTitle.isEmpty) {
      return false;
    }
    final itemType = record.item.itemType.trim().toLowerCase();
    final recognizedItemType = record.recognizedItemType.trim().toLowerCase();
    return itemType == 'episode' ||
        recognizedItemType == 'episode' ||
        record.preferSeries ||
        record.item.seasonNumber != null ||
        record.recognizedSeasonNumber != null ||
        record.item.episodeNumber != null ||
        record.recognizedEpisodeNumber != null;
  }

  NasSeriesRootResolution _resolveSeriesRootForRecord(
    NasMediaIndexRecord record, {
    List<String> seriesTitleFilterKeywords = const [],
  }) {
    final hasSeasonHint = record.item.seasonNumber != null ||
        record.recognizedSeasonNumber != null;
    final itemType = record.item.itemType.trim().toLowerCase();
    final recognizedItemType = record.recognizedItemType.trim().toLowerCase();
    final fileFallbackTitle = _cleanIndexedTitleLabel(
      record.recognizedTitle.trim().isNotEmpty
          ? record.recognizedTitle
          : record.originalFileName,
    );
    final source = _mediaSourceForSourceId(record.sourceId);
    final configuredSectionPath = record.sectionId.trim().isNotEmpty
        ? record.sectionId
        : source?.libraryPath.trim() ?? '';
    return NasMediaPathPolicy.resolveSeriesRoot(
      resourcePath: record.resourcePath,
      sectionId: configuredSectionPath,
      fileFallbackTitle: fileFallbackTitle,
      seriesLike: hasSeasonHint ||
          itemType == 'episode' ||
          recognizedItemType == 'episode' ||
          record.preferSeries ||
          record.item.episodeNumber != null ||
          record.recognizedEpisodeNumber != null,
      configuredKeywords: seriesTitleFilterKeywords,
    );
  }

  List<String> _webDavSeriesTitleFilterKeywordsForRecords(
    List<NasMediaIndexRecord> records,
  ) {
    if (records.isEmpty) {
      return const [];
    }
    return _webDavSeriesTitleFilterKeywordsForSourceId(records.first.sourceId);
  }

  List<String> _webDavSeriesTitleFilterKeywordsForSourceId(String sourceId) {
    return _mediaSourceForSourceId(sourceId)
            ?.normalizedWebDavSeriesTitleFilterKeywords ??
        const [];
  }

  List<String> _webDavSpecialEpisodeKeywordsForRecords(
    List<NasMediaIndexRecord> records,
  ) {
    if (records.isEmpty) {
      return const [];
    }
    return _webDavSpecialEpisodeKeywordsForSourceId(records.first.sourceId);
  }

  List<String> _webDavSpecialEpisodeKeywordsForSourceId(String sourceId) {
    return _mediaSourceForSourceId(sourceId)
            ?.normalizedWebDavSpecialCategoryKeywords ??
        const [];
  }

  MediaSourceConfig? _mediaSourceForSourceId(String sourceId) {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return null;
    }
    final settings = _readSettingsForRefresh();
    for (final candidate in settings.mediaSources) {
      if (candidate.id == normalizedSourceId &&
          (candidate.kind == MediaSourceKind.nas ||
              candidate.kind == MediaSourceKind.quark)) {
        return candidate;
      }
    }
    return null;
  }

  String _buildSeriesGroupKey(
    NasMediaIndexRecord record,
    String title, {
    List<String> seriesTitleFilterKeywords = const [],
  }) {
    final structureGroupKey = _structureSeriesGroupKey(
      record,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
    if (structureGroupKey.isNotEmpty) {
      return structureGroupKey;
    }
    final imdbId = record.item.imdbId.trim();
    if (imdbId.isNotEmpty) {
      return 'imdb:$imdbId';
    }
    final tmdbId = record.item.tmdbId.trim();
    if (tmdbId.isNotEmpty) {
      return 'tmdb:$tmdbId';
    }
    return 'title:${record.sectionId.trim()}|${title.toLowerCase()}';
  }

  String _structureSeriesGroupKey(
    NasMediaIndexRecord record, {
    List<String> seriesTitleFilterKeywords = const [],
  }) {
    final resolution = _resolveSeriesRootForRecord(
      record,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
    if (!_prefersStructureRootSeriesGrouping(record, resolution)) {
      return '';
    }
    final rootSegments = resolution.rootSegments;
    if (rootSegments.isEmpty) {
      return '';
    }
    final normalizedPath =
        rootSegments.map((segment) => segment.toLowerCase()).join('/');
    return 'structure:${record.sectionId.trim()}|$normalizedPath';
  }
}

String _resolvedEpisodePartTokenForRecord(
  NasMediaIndexRecord record, {
  List<String> specialEpisodeKeywords = const <String>[],
}) {
  for (final candidate in [
    record.originalFileName,
    _lastPathSegmentForEpisodePart(record.resourcePath),
    record.item.title,
    record.recognizedTitle,
  ]) {
    final partToken = NasMediaRecognizer.resolveEpisodePartToken(
      candidate,
      specialEpisodeKeywords: specialEpisodeKeywords,
    );
    if (partToken.isNotEmpty) {
      return partToken;
    }
  }
  return '';
}

String _lastPathSegmentForEpisodePart(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return '';
  }
  final slashIndex = normalized.lastIndexOf('/');
  if (slashIndex < 0 || slashIndex + 1 >= normalized.length) {
    return normalized;
  }
  return normalized.substring(slashIndex + 1);
}

class _SeriesRecordGroup {
  const _SeriesRecordGroup({
    required this.seriesKey,
    required this.records,
    required this.title,
  });

  final String seriesKey;
  final List<NasMediaIndexRecord> records;
  final String title;

  String get seriesItemId {
    return '${NasMediaIndexer._seriesGroupPrefix}|${Uri.encodeComponent(seriesKey)}';
  }

  Map<int, List<NasMediaIndexRecord>> get seasonGroups {
    final grouped = <int, List<NasMediaIndexRecord>>{};
    final fallbackSeasonNumber = parseSeasonNumberFromFolderLabel(title) ?? 1;
    for (final record in records) {
      final seasonNumber = record.item.seasonNumber ??
          record.recognizedSeasonNumber ??
          fallbackSeasonNumber;
      grouped
          .putIfAbsent(seasonNumber, () => <NasMediaIndexRecord>[])
          .add(record);
    }
    return grouped;
  }
}

class _MovieVariantRecordGroup {
  const _MovieVariantRecordGroup({
    required this.title,
    required this.records,
  });

  final String title;
  final List<NasMediaIndexRecord> records;
}

class _MovieVariantPathInfo {
  const _MovieVariantPathInfo({
    required this.rootSegments,
    required this.versionDirectory,
  });

  final List<String> rootSegments;
  final String versionDirectory;
}

class _ParsedSeasonGroupId {
  const _ParsedSeasonGroupId({
    required this.seriesKey,
    required this.seasonNumber,
  });

  final String seriesKey;
  final int seasonNumber;
}
