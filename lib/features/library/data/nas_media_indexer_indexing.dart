part of 'nas_media_indexer.dart';

extension _NasMediaIndexerIndexingX on NasMediaIndexer {
  List<String> _dedupe(Iterable<String> values) =>
      NasMediaIndexer._dedupe(values);

  List<String> _mergeLabels(List<String> current, List<String> next) =>
      NasMediaIndexer._mergeLabels(current, next);

  String get _webDavMetadataSchemaVersion =>
      NasMediaIndexer._webDavMetadataSchemaVersion;

  Future<NasMediaIndexRecord> _indexScannedItem(
    MediaSourceConfig source,
    WebDavScannedItem scannedItem, {
    required DateTime indexedAt,
    required String fingerprint,
    NasMediaIndexRecord? existingRecord,
    bool applyOnlineMetadata = true,
    bool markSidecarAttempt = false,
  }) async {
    final settings = _readSettingsForRefresh();
    final recognition = NasMediaRecognizer.recognize(
      scannedItem.actualAddress,
      seriesTitleFilterKeywords:
          source.normalizedWebDavSeriesTitleFilterKeywords,
      specialEpisodeKeywords: source.normalizedWebDavSpecialCategoryKeywords,
    );
    final seed = scannedItem.metadataSeed;
    final structureInferredEpisodeLike =
        _isStructureInferredEpisodeLike(source, scannedItem);
    final useSeriesLevelScrape =
        _shouldUseStructureInferredSeriesLevelScrape(source, scannedItem);

    var title =
        seed.title.trim().isNotEmpty ? seed.title.trim() : recognition.title;
    var originalTitle = '';
    var overview = seed.overview.trim();
    var posterUrl = seed.posterUrl.trim();
    var posterHeaders =
        posterUrl.isNotEmpty ? seed.posterHeaders : const <String, String>{};
    var backdropUrl = seed.backdropUrl.trim();
    var backdropHeaders = backdropUrl.isNotEmpty
        ? seed.backdropHeaders
        : const <String, String>{};
    var logoUrl = seed.logoUrl.trim();
    var logoHeaders =
        logoUrl.isNotEmpty ? seed.logoHeaders : const <String, String>{};
    var bannerUrl = seed.bannerUrl.trim();
    var bannerHeaders =
        bannerUrl.isNotEmpty ? seed.bannerHeaders : const <String, String>{};
    var extraBackdropUrls = seed.extraBackdropUrls;
    var extraBackdropHeaders = seed.extraBackdropHeaders;
    var year = seed.year > 0 ? seed.year : recognition.year;
    var durationLabel = seed.durationLabel.trim();
    var genres = _dedupe(seed.genres);
    var directors = _dedupe(seed.directors);
    var actors = _dedupe(seed.actors);
    var ratingLabels = <String>[];
    var itemType = seed.itemType.trim().isNotEmpty
        ? seed.itemType.trim()
        : recognition.itemType.trim();
    var seasonNumber = seed.seasonNumber ?? recognition.seasonNumber;
    var episodeNumber = seed.episodeNumber ?? recognition.episodeNumber;
    var doubanId = existingRecord?.item.doubanId.trim() ?? '';
    var imdbId = seed.imdbId.trim().isNotEmpty
        ? seed.imdbId.trim()
        : (existingRecord?.item.imdbId.trim().isNotEmpty == true
            ? existingRecord!.item.imdbId.trim()
            : recognition.imdbId.trim());
    var tmdbId = seed.tmdbId.trim();
    if (tmdbId.isEmpty) {
      tmdbId = existingRecord?.item.tmdbId.trim() ?? '';
    }
    final container = seed.container.trim();
    final videoCodec = seed.videoCodec.trim();
    final audioCodec = seed.audioCodec.trim();
    final width = seed.width;
    final height = seed.height;
    final bitrate = seed.bitrate;

    final structureInferredSeedHints =
        structureInferredEpisodeLike && !seed.hasSidecarMatch;
    final structureInferredMovieLikeHints = structureInferredSeedHints &&
        seed.episodeNumber == null &&
        (seed.seasonNumber == null || seed.seasonNumber == 0);
    final structureEpisodeTitleLock =
        structureInferredSeedHints && seed.episodeNumber != null;
    final titleLocked =
        (seed.hasSidecarMatch && seed.title.trim().isNotEmpty) ||
            (structureEpisodeTitleLock && seed.title.trim().isNotEmpty);
    final overviewLocked = seed.overview.trim().isNotEmpty;
    final posterLocked = seed.posterUrl.trim().isNotEmpty;
    final backdropLocked = seed.backdropUrl.trim().isNotEmpty;
    final logoLocked = seed.logoUrl.trim().isNotEmpty;
    final bannerLocked = seed.bannerUrl.trim().isNotEmpty;
    final extraBackdropsLocked = seed.extraBackdropUrls.isNotEmpty;
    final yearLocked = seed.year > 0;
    final durationLocked = seed.durationLabel.trim().isNotEmpty &&
        seed.durationLabel.trim() != '文件' &&
        !(structureInferredMovieLikeHints &&
            seed.durationLabel.trim() == '剧集' &&
            seed.episodeNumber == null);
    final genresLocked = seed.genres.isNotEmpty;
    final peopleLocked = seed.directors.isNotEmpty || seed.actors.isNotEmpty;
    final typeLocked =
        seed.itemType.trim().isNotEmpty && !structureInferredMovieLikeHints;
    final seasonLocked = seed.seasonNumber != null;
    final episodeLocked = seed.episodeNumber != null;

    var sidecarStatus =
        existingRecord?.sidecarStatus ?? NasMetadataFetchStatus.never;
    var wmdbStatus = existingRecord?.wmdbStatus ?? NasMetadataFetchStatus.never;
    var tmdbStatus = existingRecord?.tmdbStatus ?? NasMetadataFetchStatus.never;
    var imdbStatus = existingRecord?.imdbStatus ?? NasMetadataFetchStatus.never;

    if (markSidecarAttempt) {
      sidecarStatus = seed.hasSidecarMatch
          ? NasMetadataFetchStatus.succeeded
          : NasMetadataFetchStatus.failed;
    }

    final baseQuery = _buildMetadataMatchQuery(
      source: source,
      scannedItem: scannedItem,
      recognition: recognition,
      fallbackTitle:
          title.trim().isNotEmpty ? title.trim() : recognition.searchQuery,
    );
    var preferredImdbId = _normalizeImdbId(
      imdbId.trim().isNotEmpty ? imdbId : baseQuery,
    );
    var imdbIdMetadataMatched = false;
    var preferSeries = recognition.preferSeries ||
        itemType.trim().toLowerCase() == 'episode' ||
        itemType.trim().toLowerCase() == 'series';
    var resolvedOnlineMovieType = false;

    if (applyOnlineMetadata &&
        tmdbStatus == NasMetadataFetchStatus.never &&
        preferredImdbId.isNotEmpty &&
        settings.tmdbMetadataMatchEnabled &&
        settings.tmdbReadAccessToken.trim().isNotEmpty) {
      final needsTmdb = (!posterLocked && posterUrl.trim().isEmpty) ||
          (!backdropLocked && backdropUrl.trim().isEmpty) ||
          (!logoLocked && logoUrl.trim().isEmpty) ||
          (!overviewLocked && overview.trim().isEmpty) ||
          (!peopleLocked && (directors.isEmpty || actors.isEmpty)) ||
          (!genresLocked && genres.isEmpty) ||
          (!durationLocked && durationLabel.trim().isEmpty);
      if (needsTmdb) {
        try {
          final tmdbMatch = await _tmdbMetadataClient.matchByImdbId(
            imdbId: preferredImdbId,
            readAccessToken: settings.tmdbReadAccessToken.trim(),
            preferSeries: preferSeries,
          );
          if (tmdbMatch != null) {
            if (!typeLocked && !tmdbMatch.isSeries) {
              resolvedOnlineMovieType = true;
              itemType = 'movie';
              if (!seasonLocked) {
                seasonNumber = null;
              }
              if (!episodeLocked) {
                episodeNumber = null;
              }
              preferSeries = false;
            }
            var episodeStillUrl = '';
            if (!useSeriesLevelScrape &&
                itemType.trim().toLowerCase() == 'episode' &&
                tmdbMatch.isSeries &&
                seasonNumber != null &&
                seasonNumber >= 0 &&
                episodeNumber != null &&
                episodeNumber > 0) {
              try {
                episodeStillUrl =
                    await _tmdbMetadataClient.fetchEpisodeStillUrl(
                  seriesId: tmdbMatch.tmdbId,
                  seasonNumber: seasonNumber,
                  episodeNumber: episodeNumber,
                  readAccessToken: settings.tmdbReadAccessToken.trim(),
                );
              } catch (_) {
                episodeStillUrl = '';
              }
            }
            tmdbStatus = NasMetadataFetchStatus.succeeded;
            imdbIdMetadataMatched = true;
            final canOverrideStructureInferredTitle =
                structureInferredMovieLikeHints &&
                    seed.episodeNumber == null &&
                    !tmdbMatch.isSeries;
            if ((!titleLocked || canOverrideStructureInferredTitle) &&
                tmdbMatch.title.trim().isNotEmpty) {
              title = tmdbMatch.title.trim();
            }
            if (originalTitle.trim().isEmpty &&
                tmdbMatch.originalTitle.trim().isNotEmpty) {
              originalTitle = tmdbMatch.originalTitle.trim();
            }
            if (!posterLocked && tmdbMatch.posterUrl.trim().isNotEmpty) {
              posterUrl = tmdbMatch.posterUrl.trim();
              posterHeaders = const {};
            }
            final resolvedTmdbBackdrop = episodeStillUrl.trim().isNotEmpty
                ? episodeStillUrl.trim()
                : tmdbMatch.backdropUrl.trim();
            if (!backdropLocked &&
                backdropUrl.trim().isEmpty &&
                resolvedTmdbBackdrop.isNotEmpty) {
              backdropUrl = resolvedTmdbBackdrop;
              backdropHeaders = const {};
            }
            if (!logoLocked && tmdbMatch.logoUrl.trim().isNotEmpty) {
              logoUrl = tmdbMatch.logoUrl.trim();
              logoHeaders = const {};
            }
            if (!bannerLocked &&
                bannerUrl.trim().isEmpty &&
                itemType.trim().toLowerCase() == 'episode' &&
                tmdbMatch.backdropUrl.trim().isNotEmpty &&
                tmdbMatch.backdropUrl.trim() != backdropUrl.trim()) {
              bannerUrl = tmdbMatch.backdropUrl.trim();
              bannerHeaders = const {};
            }
            if (!extraBackdropsLocked &&
                tmdbMatch.extraBackdropUrls.isNotEmpty) {
              extraBackdropUrls = _dedupe([
                if (itemType.trim().toLowerCase() == 'episode' &&
                    tmdbMatch.backdropUrl.trim().isNotEmpty &&
                    tmdbMatch.backdropUrl.trim() != backdropUrl.trim())
                  tmdbMatch.backdropUrl.trim(),
                ...tmdbMatch.extraBackdropUrls,
              ]);
              extraBackdropHeaders = const {};
            }
            if (!overviewLocked &&
                overview.trim().isEmpty &&
                tmdbMatch.overview.trim().isNotEmpty) {
              overview = tmdbMatch.overview.trim();
            }
            if (!yearLocked && year <= 0 && tmdbMatch.year > 0) {
              year = tmdbMatch.year;
            }
            if (!durationLocked &&
                (durationLabel.trim().isEmpty ||
                    durationLabel.trim() == '文件' ||
                    durationLabel.trim() == '剧集') &&
                tmdbMatch.durationLabel.trim().isNotEmpty) {
              durationLabel = tmdbMatch.durationLabel.trim();
            }
            if (!genresLocked &&
                genres.isEmpty &&
                tmdbMatch.genres.isNotEmpty) {
              genres = _dedupe(tmdbMatch.genres);
            }
            if (!peopleLocked) {
              if (directors.isEmpty && tmdbMatch.directors.isNotEmpty) {
                directors = _dedupe(tmdbMatch.directors);
              }
              if (actors.isEmpty && tmdbMatch.actors.isNotEmpty) {
                actors = _dedupe(tmdbMatch.actors);
              }
            }
            ratingLabels = _mergeLabels(ratingLabels, tmdbMatch.ratingLabels);
            if (imdbId.trim().isEmpty && tmdbMatch.imdbId.trim().isNotEmpty) {
              imdbId = tmdbMatch.imdbId.trim();
            }
            if (tmdbId.trim().isEmpty && tmdbMatch.tmdbId > 0) {
              tmdbId = '${tmdbMatch.tmdbId}';
            }
            preferredImdbId = _normalizeImdbId(
              imdbId.trim().isNotEmpty ? imdbId : preferredImdbId,
            );
          } else {
            tmdbStatus = NasMetadataFetchStatus.failed;
          }
        } catch (_) {
          tmdbStatus = NasMetadataFetchStatus.failed;
        }
      }
    }

    if (applyOnlineMetadata &&
        wmdbStatus == NasMetadataFetchStatus.never &&
        settings.wmdbMetadataMatchEnabled &&
        !imdbIdMetadataMatched &&
        baseQuery.isNotEmpty) {
      try {
        final wmdbMatch = await _wmdbMetadataClient.matchTitle(
          query: baseQuery,
          year: year > 0 ? year : recognition.year,
          preferSeries: preferSeries,
          actors: actors,
        );
        if (wmdbMatch != null) {
          if (!typeLocked && wmdbMatch.isMovie) {
            resolvedOnlineMovieType = true;
            itemType = 'movie';
            if (!seasonLocked) {
              seasonNumber = null;
            }
            if (!episodeLocked) {
              episodeNumber = null;
            }
            preferSeries = false;
          }
          wmdbStatus = NasMetadataFetchStatus.succeeded;
          final canOverrideStructureInferredTitle =
              structureInferredMovieLikeHints &&
                  seed.episodeNumber == null &&
                  wmdbMatch.isMovie;
          if ((!titleLocked || canOverrideStructureInferredTitle) &&
              wmdbMatch.title.trim().isNotEmpty) {
            title = wmdbMatch.title.trim();
          }
          if (originalTitle.trim().isEmpty &&
              wmdbMatch.originalTitle.trim().isNotEmpty) {
            originalTitle = wmdbMatch.originalTitle.trim();
          }
          if (!overviewLocked && wmdbMatch.overview.trim().isNotEmpty) {
            overview = wmdbMatch.overview.trim();
          }
          if (!posterLocked && wmdbMatch.posterUrl.trim().isNotEmpty) {
            posterUrl = wmdbMatch.posterUrl.trim();
            posterHeaders = const {};
          }
          if (!backdropLocked &&
              backdropUrl.trim().isEmpty &&
              wmdbMatch.posterUrl.trim().isNotEmpty) {
            backdropUrl = wmdbMatch.posterUrl.trim();
            backdropHeaders = const {};
          }
          if (!yearLocked && wmdbMatch.year > 0) {
            year = wmdbMatch.year;
          }
          if (!durationLocked && wmdbMatch.durationLabel.trim().isNotEmpty) {
            durationLabel = wmdbMatch.durationLabel.trim();
          }
          if (!genresLocked && wmdbMatch.genres.isNotEmpty) {
            genres = _dedupe(wmdbMatch.genres);
          }
          if (!peopleLocked) {
            if (wmdbMatch.directors.isNotEmpty) {
              directors = _dedupe(wmdbMatch.directors);
            }
            if (wmdbMatch.actors.isNotEmpty) {
              actors = _dedupe(wmdbMatch.actors);
            }
          }
          ratingLabels = _mergeLabels(ratingLabels, wmdbMatch.ratingLabels);
          if (doubanId.trim().isEmpty && wmdbMatch.doubanId.trim().isNotEmpty) {
            doubanId = wmdbMatch.doubanId.trim();
          }
          if (imdbId.trim().isEmpty && wmdbMatch.imdbId.trim().isNotEmpty) {
            imdbId = wmdbMatch.imdbId.trim();
            preferredImdbId = _normalizeImdbId(imdbId);
          }
          if (tmdbId.trim().isEmpty && wmdbMatch.tmdbId.trim().isNotEmpty) {
            tmdbId = wmdbMatch.tmdbId.trim();
          }
        } else {
          wmdbStatus = NasMetadataFetchStatus.failed;
        }
      } catch (_) {
        wmdbStatus = NasMetadataFetchStatus.failed;
      }
    }

    if (applyOnlineMetadata &&
        tmdbStatus == NasMetadataFetchStatus.never &&
        settings.tmdbMetadataMatchEnabled &&
        settings.tmdbReadAccessToken.trim().isNotEmpty &&
        !imdbIdMetadataMatched &&
        baseQuery.isNotEmpty &&
        preferredImdbId.isEmpty) {
      final needsTmdb = (!posterLocked && posterUrl.trim().isEmpty) ||
          (!backdropLocked && backdropUrl.trim().isEmpty) ||
          (!logoLocked && logoUrl.trim().isEmpty) ||
          (!overviewLocked && overview.trim().isEmpty) ||
          (!peopleLocked && (directors.isEmpty || actors.isEmpty)) ||
          (!genresLocked && genres.isEmpty) ||
          (!durationLocked && durationLabel.trim().isEmpty);
      if (needsTmdb) {
        try {
          final tmdbMatch = await _tmdbMetadataClient.matchTitle(
            query: title.trim().isNotEmpty ? title.trim() : baseQuery,
            readAccessToken: settings.tmdbReadAccessToken.trim(),
            year: year,
            preferSeries: preferSeries,
          );
          if (tmdbMatch != null) {
            if (!typeLocked && !tmdbMatch.isSeries) {
              resolvedOnlineMovieType = true;
              itemType = 'movie';
              if (!seasonLocked) {
                seasonNumber = null;
              }
              if (!episodeLocked) {
                episodeNumber = null;
              }
              preferSeries = false;
            }
            var episodeStillUrl = '';
            if (!useSeriesLevelScrape &&
                itemType.trim().toLowerCase() == 'episode' &&
                tmdbMatch.isSeries &&
                seasonNumber != null &&
                seasonNumber >= 0 &&
                episodeNumber != null &&
                episodeNumber > 0) {
              try {
                episodeStillUrl =
                    await _tmdbMetadataClient.fetchEpisodeStillUrl(
                  seriesId: tmdbMatch.tmdbId,
                  seasonNumber: seasonNumber,
                  episodeNumber: episodeNumber,
                  readAccessToken: settings.tmdbReadAccessToken.trim(),
                );
              } catch (_) {
                episodeStillUrl = '';
              }
            }
            tmdbStatus = NasMetadataFetchStatus.succeeded;
            final canOverrideStructureInferredTitle =
                structureInferredMovieLikeHints &&
                    seed.episodeNumber == null &&
                    !tmdbMatch.isSeries;
            if ((!titleLocked || canOverrideStructureInferredTitle) &&
                wmdbStatus != NasMetadataFetchStatus.succeeded &&
                tmdbMatch.title.trim().isNotEmpty) {
              title = tmdbMatch.title.trim();
            }
            if (originalTitle.trim().isEmpty &&
                tmdbMatch.originalTitle.trim().isNotEmpty) {
              originalTitle = tmdbMatch.originalTitle.trim();
            }
            if (!posterLocked && tmdbMatch.posterUrl.trim().isNotEmpty) {
              posterUrl = tmdbMatch.posterUrl.trim();
              posterHeaders = const {};
            }
            final resolvedTmdbBackdrop = episodeStillUrl.trim().isNotEmpty
                ? episodeStillUrl.trim()
                : tmdbMatch.backdropUrl.trim();
            if (!backdropLocked &&
                backdropUrl.trim().isEmpty &&
                resolvedTmdbBackdrop.isNotEmpty) {
              backdropUrl = resolvedTmdbBackdrop;
              backdropHeaders = const {};
            }
            if (!logoLocked && tmdbMatch.logoUrl.trim().isNotEmpty) {
              logoUrl = tmdbMatch.logoUrl.trim();
              logoHeaders = const {};
            }
            if (!bannerLocked &&
                bannerUrl.trim().isEmpty &&
                itemType.trim().toLowerCase() == 'episode' &&
                tmdbMatch.backdropUrl.trim().isNotEmpty &&
                tmdbMatch.backdropUrl.trim() != backdropUrl.trim()) {
              bannerUrl = tmdbMatch.backdropUrl.trim();
              bannerHeaders = const {};
            }
            if (!extraBackdropsLocked &&
                tmdbMatch.extraBackdropUrls.isNotEmpty) {
              extraBackdropUrls = _dedupe([
                if (itemType.trim().toLowerCase() == 'episode' &&
                    tmdbMatch.backdropUrl.trim().isNotEmpty &&
                    tmdbMatch.backdropUrl.trim() != backdropUrl.trim())
                  tmdbMatch.backdropUrl.trim(),
                ...tmdbMatch.extraBackdropUrls,
              ]);
              extraBackdropHeaders = const {};
            }
            if (!overviewLocked &&
                overview.trim().isEmpty &&
                tmdbMatch.overview.trim().isNotEmpty) {
              overview = tmdbMatch.overview.trim();
            }
            if (!yearLocked && year <= 0 && tmdbMatch.year > 0) {
              year = tmdbMatch.year;
            }
            if (!durationLocked &&
                (durationLabel.trim().isEmpty ||
                    durationLabel.trim() == '文件' ||
                    durationLabel.trim() == '剧集') &&
                tmdbMatch.durationLabel.trim().isNotEmpty) {
              durationLabel = tmdbMatch.durationLabel.trim();
            }
            if (!genresLocked &&
                genres.isEmpty &&
                tmdbMatch.genres.isNotEmpty) {
              genres = _dedupe(tmdbMatch.genres);
            }
            if (!peopleLocked) {
              if (directors.isEmpty && tmdbMatch.directors.isNotEmpty) {
                directors = _dedupe(tmdbMatch.directors);
              }
              if (actors.isEmpty && tmdbMatch.actors.isNotEmpty) {
                actors = _dedupe(tmdbMatch.actors);
              }
            }
            ratingLabels = _mergeLabels(ratingLabels, tmdbMatch.ratingLabels);
            if (imdbId.trim().isEmpty && tmdbMatch.imdbId.trim().isNotEmpty) {
              imdbId = tmdbMatch.imdbId.trim();
              preferredImdbId = _normalizeImdbId(imdbId);
            }
            if (tmdbId.trim().isEmpty && tmdbMatch.tmdbId > 0) {
              tmdbId = '${tmdbMatch.tmdbId}';
            }
          } else {
            tmdbStatus = NasMetadataFetchStatus.failed;
          }
        } catch (_) {
          tmdbStatus = NasMetadataFetchStatus.failed;
        }
      }
    }

    if (applyOnlineMetadata &&
        imdbStatus == NasMetadataFetchStatus.never &&
        _shouldUseStandaloneImdbRating(settings) &&
        resolvePreferredPosterRatingLabel(ratingLabels).isEmpty &&
        baseQuery.isNotEmpty) {
      try {
        final imdbMatch = await _imdbRatingClient.matchRating(
          query: preferredImdbId.isNotEmpty
              ? preferredImdbId
              : (title.trim().isNotEmpty ? title.trim() : baseQuery),
          year: year,
          preferSeries: preferSeries,
          imdbId: preferredImdbId.isNotEmpty ? preferredImdbId : imdbId,
        );
        if (imdbMatch != null) {
          imdbStatus = NasMetadataFetchStatus.succeeded;
          if (imdbId.trim().isEmpty && imdbMatch.imdbId.trim().isNotEmpty) {
            imdbId = imdbMatch.imdbId.trim();
          }
          if (imdbMatch.ratingLabel.trim().isNotEmpty) {
            ratingLabels =
                _mergeLabels(ratingLabels, [imdbMatch.ratingLabel.trim()]);
          }
        } else {
          imdbStatus = NasMetadataFetchStatus.failed;
        }
      } catch (_) {
        imdbStatus = NasMetadataFetchStatus.failed;
      }
    }

    if (!typeLocked && itemType.trim().isEmpty) {
      itemType = recognition.itemType.trim();
    }
    if (!seasonLocked) {
      seasonNumber = recognition.seasonNumber;
    }
    if (!episodeLocked) {
      episodeNumber = recognition.episodeNumber;
    }
    if (resolvedOnlineMovieType) {
      itemType = 'movie';
      if (!seasonLocked) {
        seasonNumber = null;
      }
      if (!episodeLocked) {
        episodeNumber = null;
      }
      preferSeries = false;
    }
    final normalizedItemType = itemType.trim().toLowerCase();
    final resolvedRecognizedItemType = switch (normalizedItemType) {
      'movie' => 'movie',
      'series' => 'series',
      'season' => 'season',
      'episode' => 'episode',
      _ => recognition.itemType,
    };
    final resolvedPreferSeries = normalizedItemType == 'movie'
        ? false
        : (normalizedItemType == 'episode' ||
            normalizedItemType == 'series' ||
            normalizedItemType == 'season' ||
            preferSeries);
    final resolvedRecognizedSeasonNumber =
        normalizedItemType == 'movie' ? null : recognition.seasonNumber;
    final resolvedRecognizedEpisodeNumber =
        normalizedItemType == 'movie' ? null : recognition.episodeNumber;

    if (durationLabel.trim().isEmpty) {
      durationLabel = itemType.trim().toLowerCase() == 'episode' ? '剧集' : '文件';
    }
    if (title.trim().isEmpty) {
      title = recognition.title.trim().isNotEmpty
          ? recognition.title.trim()
          : scannedItem.fileName;
    }

    final item = MediaItem(
      id: scannedItem.resourceId,
      title: title.trim(),
      originalTitle: originalTitle.trim(),
      sortTitle: title.trim(),
      overview: overview.trim(),
      posterUrl: posterUrl.trim(),
      posterHeaders: posterHeaders,
      backdropUrl: backdropUrl.trim(),
      backdropHeaders: backdropHeaders,
      logoUrl: logoUrl.trim(),
      logoHeaders: logoHeaders,
      bannerUrl: bannerUrl.trim(),
      bannerHeaders: bannerHeaders,
      extraBackdropUrls: extraBackdropUrls,
      extraBackdropHeaders: extraBackdropHeaders,
      year: year,
      durationLabel: durationLabel.trim(),
      genres: _dedupe(genres),
      directors: _dedupe(directors),
      actors: _dedupe(actors),
      itemType: itemType.trim(),
      sectionId: scannedItem.sectionId,
      sectionName: scannedItem.sectionName,
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
      streamUrl: scannedItem.streamUrl,
      actualAddress: scannedItem.actualAddress,
      streamHeaders: scannedItem.streamHeaders,
      playbackItemId: scannedItem.playbackItemId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      doubanId: doubanId.trim(),
      imdbId: imdbId.trim(),
      tmdbId: tmdbId.trim(),
      ratingLabels: _dedupe(ratingLabels),
      container: container,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      width: width,
      height: height,
      bitrate: bitrate,
      fileSizeBytes: scannedItem.fileSizeBytes,
      addedAt: scannedItem.addedAt,
    );

    return NasMediaIndexRecord(
      id: NasMediaIndexRecord.buildRecordId(
        sourceId: source.id,
        resourceId: scannedItem.resourceId,
      ),
      sourceId: source.id,
      sectionId: scannedItem.sectionId,
      sectionName: scannedItem.sectionName,
      resourceId: scannedItem.resourceId,
      resourcePath: scannedItem.actualAddress,
      fingerprint: fingerprint,
      fileSizeBytes: scannedItem.fileSizeBytes,
      modifiedAt: scannedItem.modifiedAt,
      indexedAt: indexedAt,
      scrapedAt: indexedAt,
      recognizedTitle: recognition.title,
      searchQuery: baseQuery,
      originalFileName: recognition.originalFileName,
      parentTitle: recognition.parentTitle,
      recognizedYear: recognition.year,
      recognizedItemType: resolvedRecognizedItemType,
      preferSeries: resolvedPreferSeries,
      recognizedSeasonNumber: resolvedRecognizedSeasonNumber,
      recognizedEpisodeNumber: resolvedRecognizedEpisodeNumber,
      sidecarStatus: sidecarStatus,
      wmdbStatus: wmdbStatus,
      tmdbStatus: tmdbStatus,
      imdbStatus: imdbStatus,
      item: item,
    );
  }

  String _buildMetadataMatchQuery({
    required MediaSourceConfig source,
    required WebDavScannedItem scannedItem,
    required NasMediaRecognition recognition,
    required String fallbackTitle,
  }) {
    final baseTitle = _cleanIndexedTitleLabel(fallbackTitle);
    if (!_isStructureInferredEpisodeLike(source, scannedItem)) {
      return baseTitle;
    }

    final seriesTitle = _cleanIndexedTitleLabel(
      _seriesTitleFromScannedItem(
        scannedItem,
        fileFallbackTitle: recognition.title,
        seriesTitleFilterKeywords:
            source.normalizedWebDavSeriesTitleFilterKeywords,
      ),
    );
    final fileTitle = _cleanIndexedTitleLabel(
      scannedItem.metadataSeed.title.trim().isNotEmpty
          ? scannedItem.metadataSeed.title.trim()
          : _stripExtension(scannedItem.fileName).trim(),
    );
    final normalizedSeries = _normalizeMetadataQueryToken(seriesTitle);
    final normalizedFile = _normalizeMetadataQueryToken(fileTitle);

    if (seriesTitle.isEmpty) {
      return baseTitle;
    }
    if (_shouldUseStructureInferredSeriesLevelScrape(source, scannedItem)) {
      return seriesTitle;
    }
    if (fileTitle.isEmpty) {
      return seriesTitle;
    }
    if (normalizedSeries.isNotEmpty &&
        normalizedFile.isNotEmpty &&
        (normalizedFile.contains(normalizedSeries) ||
            normalizedSeries.contains(normalizedFile))) {
      return fileTitle;
    }
    return '$seriesTitle $fileTitle'.trim();
  }

  String _normalizeMetadataQueryToken(String value) {
    return _cleanIndexedTitleLabel(value).toLowerCase().replaceAll(
          RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'),
          '',
        );
  }

  String _normalizeImdbId(String value) {
    final match =
        RegExp(r'\btt\d{7,9}\b', caseSensitive: false).firstMatch(value);
    final normalized = (match?.group(0) ?? '').trim().toLowerCase();
    if (!RegExp(r'^tt\d{7,9}$').hasMatch(normalized)) {
      return '';
    }
    return normalized;
  }

  String _seriesTitleFromScannedItem(
    WebDavScannedItem item, {
    required String fileFallbackTitle,
    List<String> seriesTitleFilterKeywords = const [],
  }) {
    final resourceSegments = _pathSegments(item.actualAddress);
    if (resourceSegments.isEmpty) {
      return '';
    }

    final hasSeasonHint = item.metadataSeed.seasonNumber != null ||
        item.metadataSeed.episodeNumber != null;
    final itemType = item.metadataSeed.itemType.trim().toLowerCase();
    final sectionSegments = _pathSegments(_uriPath(item.sectionId));
    final cleanedFileFallbackTitle = _cleanIndexedTitleLabel(fileFallbackTitle);

    var commonLength = 0;
    while (commonLength < sectionSegments.length &&
        commonLength < resourceSegments.length &&
        sectionSegments[commonLength] == resourceSegments[commonLength]) {
      commonLength += 1;
    }

    final relativeDirectories = resourceSegments.length <= commonLength + 1
        ? <String>[]
        : resourceSegments.sublist(commonLength, resourceSegments.length - 1);
    if (relativeDirectories.isEmpty) {
      if (hasSeasonHint && sectionSegments.isNotEmpty) {
        final filteredSectionFallback = _fallbackTitleFromFilteredSectionRoot(
          sectionSegments: sectionSegments,
          relativeDirectories: relativeDirectories,
          fileFallbackTitle: cleanedFileFallbackTitle,
          seriesTitleFilterKeywords: seriesTitleFilterKeywords,
        );
        if (filteredSectionFallback != null) {
          return filteredSectionFallback;
        }
        return _cleanIndexedTitleLabel(sectionSegments.last);
      }
      return '';
    }

    final stoppedTitle = _stoppedSeriesTitleByFilteredDirectory(
      relativeDirectories: relativeDirectories,
      fileFallbackTitle: cleanedFileFallbackTitle,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
    if (stoppedTitle != null && (hasSeasonHint || itemType == 'episode')) {
      return stoppedTitle;
    }

    final seasonDirectoryIndex =
        relativeDirectories.indexWhere(_looksLikeSeasonFolderLabel);
    if (seasonDirectoryIndex > 0) {
      return _cleanIndexedTitleLabel(
        relativeDirectories[seasonDirectoryIndex - 1],
      );
    }
    if (seasonDirectoryIndex == 0 && sectionSegments.isNotEmpty) {
      final filteredSectionFallback = _fallbackTitleFromFilteredSectionRoot(
        sectionSegments: sectionSegments,
        relativeDirectories: relativeDirectories,
        fileFallbackTitle: cleanedFileFallbackTitle,
        seriesTitleFilterKeywords: seriesTitleFilterKeywords,
      );
      if (filteredSectionFallback != null) {
        return filteredSectionFallback;
      }
      return _cleanIndexedTitleLabel(sectionSegments.last);
    }

    final trailingStructureRoot =
        _nearestNonSeasonDirectory(relativeDirectories);
    if (trailingStructureRoot.isNotEmpty &&
        (hasSeasonHint || itemType == 'episode')) {
      return _cleanIndexedTitleLabel(trailingStructureRoot);
    }

    return _cleanIndexedTitleLabel(relativeDirectories.first);
  }

  String? _fallbackTitleFromFilteredSectionRoot({
    required List<String> sectionSegments,
    required List<String> relativeDirectories,
    required String fileFallbackTitle,
    required List<String> seriesTitleFilterKeywords,
  }) {
    if (sectionSegments.isEmpty || seriesTitleFilterKeywords.isEmpty) {
      return null;
    }
    final rawSectionRoot = sectionSegments.last.trim();
    if (rawSectionRoot.isEmpty) {
      return null;
    }
    final cleanedSectionRoot = _cleanIndexedTitleLabel(rawSectionRoot);
    if (!_matchesSeriesTitleFilterKeyword(
      rawSectionRoot,
      cleanedValue: cleanedSectionRoot,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    )) {
      return null;
    }

    var lastInferredTitle = '';
    for (var index = relativeDirectories.length - 1; index >= 0; index--) {
      final rawDirectory = relativeDirectories[index].trim();
      final canUseSeasonDirectory = index == 0 &&
          _canUseSeasonDirectoryAsSeriesRoot(
            rawDirectory,
            parentMatchesFilter: true,
          );
      if (rawDirectory.isEmpty ||
          (_looksLikeSeasonFolderLabel(rawDirectory) &&
              !canUseSeasonDirectory)) {
        continue;
      }
      final cleanedDirectory = _cleanIndexedTitleLabel(rawDirectory);
      if (cleanedDirectory.isEmpty) {
        continue;
      }
      if (lastInferredTitle.isEmpty) {
        lastInferredTitle = cleanedDirectory;
      }
    }
    if (lastInferredTitle.isEmpty) {
      lastInferredTitle = fileFallbackTitle.trim();
    }
    if (lastInferredTitle.isEmpty) {
      return null;
    }
    return lastInferredTitle;
  }

  String _stripExtension(String value) {
    final trimmed = value.trim();
    final lastDot = trimmed.lastIndexOf('.');
    if (lastDot <= 0) {
      return trimmed;
    }
    return trimmed.substring(0, lastDot);
  }

  String _buildScopeKey(
    MediaSourceConfig source,
    List<MediaCollection>? scopedCollections,
  ) {
    final excludedKeywords =
        source.normalizedWebDavExcludedPathKeywords.join(',');
    final seriesTitleFilterKeywords =
        source.normalizedWebDavSeriesTitleFilterKeywords.join(',');
    final specialEpisodeKeywords =
        source.normalizedWebDavSpecialEpisodeKeywords.join(',');
    final extraKeywords = source.normalizedWebDavExtraKeywords.join(',');
    final quarkPathNormalizationVersion =
        source.kind == MediaSourceKind.quark ? '|quark-paths:v2' : '';
    if (scopedCollections != null && scopedCollections.isNotEmpty) {
      final ids = scopedCollections
          .map((item) => item.id.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
        ..sort();
      final seriesLevelScrape = source.webDavSeriesScrapeUsesDirectoryTitleOnly
          ? '|series-level-scrape:true'
          : '';
      return 'collections|${ids.join(',')}|structure:${source.webDavStructureInferenceEnabled}|scrape:${source.webDavSidecarScrapingEnabled}$seriesLevelScrape|exclude:$excludedKeywords|title-filter:$seriesTitleFilterKeywords|special-filter:$specialEpisodeKeywords|extra-filter:$extraKeywords$quarkPathNormalizationVersion|schema:$_webDavMetadataSchemaVersion';
    }
    final root = source.libraryPath.trim().isNotEmpty
        ? source.libraryPath.trim()
        : source.endpoint.trim();
    final seriesLevelScrape = source.webDavSeriesScrapeUsesDirectoryTitleOnly
        ? '|series-level-scrape:true'
        : '';
    return 'root|$root|structure:${source.webDavStructureInferenceEnabled}|scrape:${source.webDavSidecarScrapingEnabled}$seriesLevelScrape|exclude:$excludedKeywords|title-filter:$seriesTitleFilterKeywords|special-filter:$specialEpisodeKeywords|extra-filter:$extraKeywords$quarkPathNormalizationVersion|schema:$_webDavMetadataSchemaVersion';
  }

  String _buildFingerprint({
    required String sourceId,
    required String resourcePath,
    required DateTime? modifiedAt,
    required int fileSizeBytes,
  }) {
    return [
      sourceId.trim(),
      resourcePath.trim(),
      modifiedAt?.toUtc().toIso8601String() ?? '',
      '$fileSizeBytes',
    ].join('|');
  }
}
