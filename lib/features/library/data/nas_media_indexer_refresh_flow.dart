part of 'nas_media_indexer.dart';

extension _NasMediaIndexerRefreshFlowX on NasMediaIndexer {
  Future<void> clearSource(String sourceId) {
    _libraryMatchCaches.remove(sourceId.trim());
    return _store.clearSource(sourceId);
  }

  bool _supportsIndexedExternalSource(MediaSourceConfig source) {
    switch (source.kind) {
      case MediaSourceKind.nas:
        return source.endpoint.trim().isNotEmpty;
      case MediaSourceKind.quark:
        return source.hasConfiguredQuarkFolder;
      case MediaSourceKind.emby:
        return false;
    }
  }

  Future<List<WebDavScannedItem>> _scanLibraryFromExternalSource(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    required int limit,
    required bool includeSidecarMetadata,
    required bool resetScanCaches,
    required bool Function() shouldCancel,
  }) {
    switch (source.kind) {
      case MediaSourceKind.quark:
        final client = _quarkExternalStorageClient;
        if (client == null) {
          return Future.value(const <WebDavScannedItem>[]);
        }
        return client.scanLibrary(
          source,
          sectionId: sectionId,
          sectionName: sectionName,
          limit: limit,
          loadSidecarMetadata: includeSidecarMetadata,
          resolvePlayableStreams: false,
          resetCaches: resetScanCaches,
          shouldCancel: shouldCancel,
        );
      case MediaSourceKind.nas:
        return _webDavNasClient.scanLibrary(
          source,
          sectionId: sectionId,
          sectionName: sectionName,
          limit: limit,
          loadSidecarMetadata: includeSidecarMetadata,
          resolvePlayableStreams: false,
          resetCaches: resetScanCaches,
          shouldCancel: shouldCancel,
        );
      case MediaSourceKind.emby:
        return Future.value(const <WebDavScannedItem>[]);
    }
  }

  Future<WebDavScannedItem?> _scanResourceFromExternalSource(
    MediaSourceConfig source, {
    required String resourceId,
    required String sectionId,
    required String sectionName,
    required bool includeSidecarMetadata,
    required bool Function() shouldCancel,
  }) {
    switch (source.kind) {
      case MediaSourceKind.quark:
        final client = _quarkExternalStorageClient;
        if (client == null) {
          return Future.value(null);
        }
        return client.scanResource(
          source,
          resourceId: resourceId,
          sectionId: sectionId,
          sectionName: sectionName,
          loadSidecarMetadata: includeSidecarMetadata,
          resolvePlayableStreams: false,
          shouldCancel: shouldCancel,
        );
      case MediaSourceKind.nas:
        return _webDavNasClient.scanResource(
          source,
          resourceId: resourceId,
          sectionId: sectionId,
          sectionName: sectionName,
          loadSidecarMetadata: includeSidecarMetadata,
          resolvePlayableStreams: false,
          shouldCancel: shouldCancel,
        );
      case MediaSourceKind.emby:
        return Future.value(null);
    }
  }

  Future<bool> tryAutoRebuildOnEmpty(
    MediaSourceConfig source, {
    List<MediaCollection>? scopedCollections,
  }) async {
    if (!_supportsIndexedExternalSource(source)) {
      return false;
    }
    final scopeKey = _buildScopeKey(source, scopedCollections);
    final existingState = await _store.loadSourceState(source.id);
    if (existingState?.scopeKey == scopeKey &&
        existingState?.emptyAutoRebuildAttempted == true) {
      return false;
    }

    final existingRecords = await _loadSourceRecordsCached(source.id);
    final now = DateTime.now();
    await _patchSourceRecords(
      sourceId: source.id,
      currentRecords: existingRecords,
      upsertedRecords: const [],
      deletedRecordIds: const [],
      state: NasMediaIndexSourceState(
        sourceId: source.id,
        lastIndexedAt: now,
        recordCount: existingRecords.length,
        scopeKey: scopeKey,
        emptyAutoRebuildAttempted: true,
      ),
    );

    await refreshSource(
      source,
      scopedCollections: scopedCollections,
      forceFullRescan: true,
    );
    return true;
  }

  Future<void> removeResourceScope({
    required String sourceId,
    required String resourcePath,
  }) async {
    final normalizedSourceId = sourceId.trim();
    final normalizedResourcePath = resourcePath.trim();
    if (normalizedSourceId.isEmpty || normalizedResourcePath.isEmpty) {
      return;
    }

    final records = await _loadSourceRecordsCached(normalizedSourceId);
    if (records.isEmpty) {
      return;
    }
    final scopeSegments = _pathSegments(_uriPath(normalizedResourcePath));
    if (scopeSegments.isEmpty) {
      return;
    }
    final nextRecords = records
        .where(
          (record) => !_isRecordWithinScope(
            record,
            scopeSegments: scopeSegments,
          ),
        )
        .toList(growable: false);
    if (nextRecords.length == records.length) {
      return;
    }
    final now = DateTime.now();
    final existingState = await _store.loadSourceState(normalizedSourceId);
    final deletedRecordIds = records
        .where(
          (record) => _isRecordWithinScope(
            record,
            scopeSegments: scopeSegments,
          ),
        )
        .map((record) => record.id)
        .toList(growable: false);
    await _patchSourceRecords(
      sourceId: normalizedSourceId,
      currentRecords: records,
      upsertedRecords: const [],
      deletedRecordIds: deletedRecordIds,
      state: NasMediaIndexSourceState(
        sourceId: normalizedSourceId,
        lastIndexedAt: now,
        recordCount: nextRecords.length,
        scopeKey: existingState?.scopeKey ?? '',
        emptyAutoRebuildAttempted: nextRecords.isNotEmpty
            ? false
            : (existingState?.emptyAutoRebuildAttempted ?? false),
      ),
    );
    _notifyIndexChangedSafely();
  }

  Future<NasMediaIndexRecord?> loadRecord({
    required String sourceId,
    required String resourceId,
  }) async {
    final normalizedSourceId = sourceId.trim();
    final normalizedResourceId = resourceId.trim();
    if (normalizedSourceId.isEmpty || normalizedResourceId.isEmpty) {
      return null;
    }
    final records = await _loadSourceRecordsCached(normalizedSourceId);
    final writableIndices = _resolveWritableRecordIndices(
      records,
      normalizedResourceId,
      resourceScopePath: '',
    );
    if (writableIndices.isEmpty) {
      return null;
    }
    return records[writableIndices.first];
  }

  Future<List<NasMediaIndexRecord>> loadRecordsInScope({
    required String sourceId,
    required String resourcePath,
  }) async {
    final normalizedSourceId = sourceId.trim();
    final normalizedResourcePath = resourcePath.trim();
    if (normalizedSourceId.isEmpty || normalizedResourcePath.isEmpty) {
      return const [];
    }

    final records = await _loadSourceRecordsCached(normalizedSourceId);
    if (records.isEmpty) {
      return const [];
    }

    final scopeSegments = _pathSegments(_uriPath(normalizedResourcePath));
    if (scopeSegments.isEmpty) {
      return const [];
    }

    return records
        .where(
          (record) => _isRecordWithinScope(
            record,
            scopeSegments: scopeSegments,
          ),
        )
        .toList(growable: false);
  }

  Future<MediaDetailTarget?> enrichDetailTargetMetadataIfNeeded(
    MediaDetailTarget target,
  ) async {
    final sourceId = target.sourceId.trim();
    final resourceId = target.itemId.trim();
    if (sourceId.isEmpty || resourceId.isEmpty) {
      return null;
    }

    final settings = _readSettingsForRefresh();
    MediaSourceConfig? source;
    for (final candidate in settings.mediaSources) {
      if (candidate.id == sourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null || !_supportsIndexedExternalSource(source)) {
      return null;
    }

    final records = await _loadSourceRecordsCached(sourceId);
    if (records.isEmpty) {
      return null;
    }

    final targetIndices = _resolveWritableRecordIndices(
      records,
      resourceId,
      resourceScopePath: target.resourcePath,
    );
    if (targetIndices.isEmpty) {
      return null;
    }

    final selectedRecords =
        targetIndices.map((index) => records[index]).toList(growable: false);
    final shouldAttemptSidecar = source.webDavSidecarScrapingEnabled &&
        selectedRecords.any(
          (record) =>
              !record.manualMetadataLocked &&
              !_hasAttemptStatus(record.sidecarStatus),
        );
    final shouldAttemptOnline = selectedRecords.any(
      (record) => _hasPendingOnlineAttempts(record, settings),
    );
    if (shouldAttemptSidecar || shouldAttemptOnline) {
      final controller = _RefreshTaskController();
      await _refreshSelectedItemsPhase(
        source,
        scannedItems: selectedRecords
            .map(_buildScannedItemFromRecord)
            .toList(growable: false),
        includeSidecarMetadata: shouldAttemptSidecar,
        includeOnlineMetadata: shouldAttemptOnline,
        phaseLabel: 'Hero 补元数据',
        controller: controller,
        reportProgress: false,
      );
    }

    final updatedRecords = await _loadSourceRecordsCached(sourceId);
    return _buildManualMetadataTarget(
      target: target,
      records: updatedRecords,
      selectedResourceIds: selectedRecords
          .map((record) => record.resourceId)
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false),
      resourceId: resourceId,
      resourcePath: target.resourcePath,
      searchQuery: target.searchQuery.trim().isEmpty
          ? target.title
          : target.searchQuery.trim(),
    );
  }

  Future<void> markDetailTargetMetadataManuallyManaged(
    MediaDetailTarget target,
  ) async {
    final sourceId = target.sourceId.trim();
    final resourceId = target.itemId.trim();
    if (sourceId.isEmpty || resourceId.isEmpty) {
      return;
    }

    final records = await _loadSourceRecordsCached(sourceId);
    if (records.isEmpty) {
      return;
    }

    final targetIndices = _resolveWritableRecordIndices(
      records,
      resourceId,
      resourceScopePath: target.resourcePath,
    );
    if (targetIndices.isEmpty) {
      return;
    }

    final nextRecords = [...records];
    final changedRecords = <NasMediaIndexRecord>[];
    var changed = false;
    final now = DateTime.now();
    for (final targetIndex in targetIndices) {
      final currentRecord = nextRecords[targetIndex];
      if (currentRecord.manualMetadataLocked) {
        continue;
      }
      final updatedRecord = NasMediaIndexRecord(
        id: currentRecord.id,
        sourceId: currentRecord.sourceId,
        sectionId: currentRecord.sectionId,
        sectionName: currentRecord.sectionName,
        resourceId: currentRecord.resourceId,
        resourcePath: currentRecord.resourcePath,
        fingerprint: currentRecord.fingerprint,
        fileSizeBytes: currentRecord.fileSizeBytes,
        modifiedAt: currentRecord.modifiedAt,
        indexedAt: now,
        scrapedAt: currentRecord.scrapedAt,
        recognizedTitle: currentRecord.recognizedTitle,
        searchQuery: currentRecord.searchQuery,
        originalFileName: currentRecord.originalFileName,
        parentTitle: currentRecord.parentTitle,
        recognizedYear: currentRecord.recognizedYear,
        recognizedItemType: currentRecord.recognizedItemType,
        preferSeries: currentRecord.preferSeries,
        recognizedSeasonNumber: currentRecord.recognizedSeasonNumber,
        recognizedEpisodeNumber: currentRecord.recognizedEpisodeNumber,
        sidecarStatus: currentRecord.sidecarStatus,
        wmdbStatus: currentRecord.wmdbStatus,
        tmdbStatus: currentRecord.tmdbStatus,
        imdbStatus: currentRecord.imdbStatus,
        metadataFailureCount: currentRecord.metadataFailureCount,
        metadataRetryAfter: currentRecord.metadataRetryAfter,
        manualMetadataLocked: true,
        item: currentRecord.item,
      );
      nextRecords[targetIndex] = updatedRecord;
      changedRecords.add(updatedRecord);
      changed = true;
    }

    if (!changed) {
      return;
    }

    final existingState = await _store.loadSourceState(sourceId);
    await _patchSourceRecords(
      sourceId: sourceId,
      currentRecords: records,
      upsertedRecords: changedRecords,
      deletedRecordIds: const [],
      state: NasMediaIndexSourceState(
        sourceId: sourceId,
        lastIndexedAt: now,
        recordCount: nextRecords.length,
        scopeKey: existingState?.scopeKey ?? '',
        emptyAutoRebuildAttempted: nextRecords.isNotEmpty
            ? false
            : (existingState?.emptyAutoRebuildAttempted ?? false),
      ),
    );
    _notifyIndexChangedSafely();
  }

  Future<List<MediaItem>> loadLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    List<MediaCollection>? scopedCollections,
    int limit = 200,
  }) async {
    final records = await _loadScopedRecords(
      source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
    );
    return _materializeLibraryItems(records)
        .take(limit)
        .toList(growable: false);
  }

  Future<List<MediaItem>> loadChildren(
    MediaSourceConfig source, {
    required String parentId,
    String sectionId = '',
    List<MediaCollection>? scopedCollections,
    int limit = 200,
  }) async {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      return const [];
    }

    if (!_isSyntheticGroupId(normalizedParentId)) {
      return const [];
    }

    final scopeKey = _buildScopeKey(source, scopedCollections);
    final state = await _store.loadSourceState(source.id);
    if (state == null || state.scopeKey != scopeKey) {
      return const [];
    }
    final normalizedSectionId = sectionId.trim();
    final hierarchyCache = await _loadLibraryMatchCache(source.id);
    if (hierarchyCache.records.isEmpty) {
      return const [];
    }
    final groupsBySeriesItemId = normalizedSectionId.isEmpty
        ? hierarchyCache.seriesGroupsByItemId
        : hierarchyCache.seriesGroupsBySectionId[normalizedSectionId] ??
            const <String, _SeriesRecordGroup>{};

    if (normalizedParentId.startsWith(NasMediaIndexer._seriesGroupPrefix)) {
      final group = groupsBySeriesItemId[normalizedParentId];
      if (group == null) {
        return const [];
      }
      final seasonGroups = group.seasonGroups;
      return seasonGroups.entries
          .map((entry) => _buildSeasonItem(group, entry.key, entry.value))
          .toList(growable: false)
        ..sort((left, right) {
          final seasonComparison =
              (left.seasonNumber ?? 0).compareTo(right.seasonNumber ?? 0);
          if (seasonComparison != 0) {
            return seasonComparison;
          }
          return left.title.compareTo(right.title);
        });
    }

    if (normalizedParentId.startsWith(NasMediaIndexer._seasonGroupPrefix)) {
      final parsed = _parseSeasonGroupId(normalizedParentId);
      if (parsed == null) {
        return const [];
      }
      final seriesItemId =
          '${NasMediaIndexer._seriesGroupPrefix}|${Uri.encodeComponent(parsed.seriesKey)}';
      final group = groupsBySeriesItemId[seriesItemId];
      if (group == null) {
        return const [];
      }
      final episodes = group.seasonGroups[parsed.seasonNumber] ??
          const <NasMediaIndexRecord>[];
      return _materializeEpisodeItems(episodes)
          .take(limit)
          .toList(growable: false);
    }

    return const [];
  }

  Future<List<MediaItem>> loadEpisodeVariants(
    MediaSourceConfig source, {
    required String itemId,
    String sectionId = '',
    List<MediaCollection>? scopedCollections,
  }) async {
    final normalizedItemId = itemId.trim();
    if (normalizedItemId.isEmpty) {
      return const [];
    }

    final records = await _loadScopedRecords(
      source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
    );
    if (records.isEmpty) {
      return const [];
    }

    final exactRecord = records
        .where((record) => record.resourceId == normalizedItemId)
        .firstOrNull;
    if (exactRecord == null) {
      return const [];
    }

    final seasonNumber = _resolvedRecordSeasonNumber(exactRecord);
    final episodeNumber = _resolvedRecordEpisodeNumber(exactRecord);
    if (seasonNumber == null || episodeNumber == null) {
      return [exactRecord.item];
    }

    final group = _groupSeriesRecords(records)
        .where(
          (candidate) => candidate.records.any(
            (record) => record.resourceId == normalizedItemId,
          ),
        )
        .firstOrNull;
    final variantScopeRecords = group?.records ?? [exactRecord];
    final specialEpisodeKeywords =
        _webDavSpecialEpisodeKeywordsForRecords(variantScopeRecords);
    final episodePart = _resolvedEpisodePartTokenForRecord(
      exactRecord,
      specialEpisodeKeywords: specialEpisodeKeywords,
    );
    final variantRecords = variantScopeRecords
        .where(
          (record) =>
              _resolvedRecordSeasonNumber(record) == seasonNumber &&
              _resolvedRecordEpisodeNumber(record) == episodeNumber &&
              _resolvedEpisodePartTokenForRecord(
                    record,
                    specialEpisodeKeywords: specialEpisodeKeywords,
                  ) ==
                  episodePart,
        )
        .toList(growable: false);
    final sortedRecords = _sortEpisodeRecordsForDisplay(
      variantRecords.isEmpty ? [exactRecord] : variantRecords,
    );
    return sortedRecords.map((record) => record.item).toList(growable: false);
  }

  Future<List<MediaItem>> loadMovieVariants(
    MediaSourceConfig source, {
    required String itemId,
    String sectionId = '',
    List<MediaCollection>? scopedCollections,
  }) async {
    final normalizedItemId = itemId.trim();
    if (normalizedItemId.isEmpty) {
      return const [];
    }

    final records = await _loadScopedRecords(
      source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
    );
    final exactRecord = records
        .where((record) => record.resourceId == normalizedItemId)
        .firstOrNull;
    if (exactRecord == null) {
      return const [];
    }

    final group = _groupMovieVariantRecords(records)
        .where(
          (candidate) => candidate.records.any(
            (record) => record.resourceId == normalizedItemId,
          ),
        )
        .firstOrNull;
    if (group == null) {
      return [exactRecord.item];
    }

    final sortedRecords = [...group.records]..sort((left, right) {
        final scoreCompare = _movieVariantRepresentativeScore(right)
            .compareTo(_movieVariantRepresentativeScore(left));
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return left.resourcePath.toLowerCase().compareTo(
              right.resourcePath.toLowerCase(),
            );
      });
    return sortedRecords.map((record) => record.item).toList(growable: false);
  }

  Future<List<MediaItem>> loadCachedLibraryMatchItems(
    MediaSourceConfig source, {
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
  }) async {
    if (!_supportsIndexedExternalSource(source)) {
      return const [];
    }

    final cache = await _loadLibraryMatchCache(source.id);
    final hasExternalIds = doubanId.trim().isNotEmpty ||
        imdbId.trim().isNotEmpty ||
        tmdbId.trim().isNotEmpty ||
        tvdbId.trim().isNotEmpty ||
        wikidataId.trim().isNotEmpty;
    if (!hasExternalIds) {
      return cache.libraryItems;
    }

    final exactMatches = cache.findByExternalIds(
      doubanId: doubanId,
      imdbId: imdbId,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      wikidataId: wikidataId,
    );
    if (exactMatches.isNotEmpty) {
      return exactMatches;
    }

    // Allow the detail matcher to fall back to title/year matching when this
    // source has indexed items but has not persisted the requested external IDs.
    return cache.libraryItems;
  }

  Future<void> refreshSource(
    MediaSourceConfig source, {
    List<MediaCollection>? scopedCollections,
    int limitPerCollection = NasMediaIndexer._defaultRefreshLimitPerCollection,
    bool forceFullRescan = false,
  }) async {
    if (!_supportsIndexedExternalSource(source)) {
      return;
    }

    final normalizedSourceId = source.id.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }
    final taskKey = _buildRefreshTaskKey(source, scopedCollections);
    final stopwatch = Stopwatch()..start();
    appLogInfo(
      'library.index',
      'Media index refresh started',
      fields: <String, Object?>{
        'sourceId': normalizedSourceId,
        'sourceKind': source.kind.name,
        'forceFullRescan': forceFullRescan,
        'scopeCount': scopedCollections?.length ?? 0,
      },
    );
    final existingActiveTask = _activeRefreshTasks[taskKey];
    if (existingActiveTask != null) {
      if (!forceFullRescan ||
          existingActiveTask.mode == _RefreshTaskMode.forceFull) {
        await existingActiveTask.future;
        return;
      }
      existingActiveTask.cancel();
      await existingActiveTask.future;
    }

    final existingBackgroundTask = _backgroundEnrichmentTasks[taskKey];
    if (existingBackgroundTask != null) {
      existingBackgroundTask.cancel();
      await existingBackgroundTask.future.catchError((_) {
        // Background enrichment is best-effort and safe to interrupt.
      });
    }

    final controller = _RefreshTaskController();
    _updateIndexerConcurrencyLimits();
    final future = _sourceBudget.withPermit(() {
      return _withGlobalBackgroundPermit(() async {
        try {
          if (forceFullRescan) {
            _wmdbMetadataClient.clearCache();
            _tmdbMetadataClient.clearCache();
            _imdbRatingClient.clearCache();
          }

          final settings = _readSettingsForRefresh();
          final shouldStageMetadata = source.webDavSidecarScrapingEnabled ||
              _hasOnlineMetadataEnabled(settings);
          final requiresSidecarMetadata = source.webDavSidecarScrapingEnabled;
          final requiresOnlineMetadata = _hasOnlineMetadataEnabled(settings);
          final phaseResult = await _refreshSourcePhase(
            source,
            scopedCollections: scopedCollections,
            limitPerCollection: limitPerCollection,
            includeSidecarMetadata: false,
            includeOnlineMetadata: false,
            forceFullRescan: forceFullRescan,
            resetScanCaches: true,
            clearProgressWhenDone: !shouldStageMetadata,
            phaseLabel: '建立索引中',
            collectEnrichmentCandidates: shouldStageMetadata,
            controller: controller,
          );
          controller.throwIfCancelled();
          appLogInfo(
            'library.index',
            'Primary media indexing completed',
            fields: <String, Object?>{
              'sourceId': normalizedSourceId,
              'forceFullRescan': forceFullRescan,
              'enrichmentCandidateCount':
                  phaseResult.enrichmentCandidates.length,
              'durationMs': stopwatch.elapsedMilliseconds,
            },
          );
          if (shouldStageMetadata) {
            if (phaseResult.enrichmentCandidates.isEmpty) {
              _clearProgressSafely(normalizedSourceId);
            } else {
              _scheduleBackgroundEnrichment(
                source,
                scopedCollections: scopedCollections,
                enrichmentCandidates: phaseResult.enrichmentCandidates,
                includeSidecarMetadata: requiresSidecarMetadata,
                includeOnlineMetadata: requiresOnlineMetadata,
                forceFullRescan: forceFullRescan,
                controller: controller,
              );
            }
          }
        } on _RefreshCancelledException {
          appLogInfo(
            'library.index',
            'Media index refresh cancelled',
            fields: <String, Object?>{
              'sourceId': normalizedSourceId,
              'forceFullRescan': forceFullRescan,
              'durationMs': stopwatch.elapsedMilliseconds,
            },
          );
          _clearProgressSafely(normalizedSourceId);
        } catch (error, stackTrace) {
          _clearProgressSafely(normalizedSourceId);
          if (_isProviderContainerDisposedError(error)) {
            return;
          }

          appLogError(
            'library.index',
            'Media index refresh failed',
            fields: <String, Object?>{
              'sourceId': normalizedSourceId,
              'sourceKind': source.kind.name,
              'forceFullRescan': forceFullRescan,
              'durationMs': stopwatch.elapsedMilliseconds,
            },
            error: error,
            stackTrace: stackTrace,
          );

          Error.throwWithStackTrace(error, stackTrace);
        } finally {
          _activeRefreshTasks.remove(taskKey);
        }
      }, maintenance: true);
    });
    _activeRefreshTasks[taskKey] = _RefreshTaskHandle(
      future: future,
      mode: forceFullRescan
          ? _RefreshTaskMode.forceFull
          : _RefreshTaskMode.incremental,
      controller: controller,
    );
    await future;
  }

  Future<MediaDetailTarget?> applyManualMetadata({
    required MediaDetailTarget target,
    required String searchQuery,
    MetadataMatchResult? metadataMatch,
    ImdbRatingMatch? imdbRatingMatch,
  }) async {
    final sourceId = target.sourceId.trim();
    final resourceId = target.itemId.trim();
    if (sourceId.isEmpty || resourceId.isEmpty) {
      return null;
    }
    if (metadataMatch == null && imdbRatingMatch == null) {
      return null;
    }

    await _cancelRefreshTasksForSource(sourceId);

    final records = await _loadSourceRecordsCached(sourceId);
    if (records.isEmpty) {
      return null;
    }
    final targetIndices = _resolveWritableRecordIndices(
      records,
      resourceId,
      resourceScopePath: target.resourcePath,
    );
    if (targetIndices.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final nextRecords = [...records];
    final changedRecords = <NasMediaIndexRecord>[];
    final selectedResourceIds = targetIndices
        .map((index) => records[index].resourceId)
        .where((id) => id.trim().isNotEmpty)
        .toList(growable: false);
    final isSyntheticGroupRequest = _isSyntheticGroupId(resourceId);
    final resolvedMetadataItemType = _resolvedMetadataItemType(metadataMatch);
    final treatSyntheticGroupAsStandaloneMovie = isSyntheticGroupRequest &&
        targetIndices.length == 1 &&
        resolvedMetadataItemType == 'movie';
    for (final targetIndex in targetIndices) {
      final currentRecord = records[targetIndex];
      final nextItem =
          isSyntheticGroupRequest && !treatSyntheticGroupAsStandaloneMovie
              ? _applyManualMetadataToGroupedItem(
                  currentRecord.item,
                  metadataMatch: metadataMatch,
                  imdbRatingMatch: imdbRatingMatch,
                )
              : _applyManualMetadataToItem(
                  currentRecord.item,
                  metadataMatch: metadataMatch,
                  imdbRatingMatch: imdbRatingMatch,
                );
      final resolvedTitle = metadataMatch?.title.trim() ?? '';
      final updatedRecord = NasMediaIndexRecord(
        id: currentRecord.id,
        sourceId: currentRecord.sourceId,
        sectionId: currentRecord.sectionId,
        sectionName: currentRecord.sectionName,
        resourceId: currentRecord.resourceId,
        resourcePath: currentRecord.resourcePath,
        fingerprint: currentRecord.fingerprint,
        fileSizeBytes: currentRecord.fileSizeBytes,
        modifiedAt: currentRecord.modifiedAt,
        indexedAt: now,
        scrapedAt: now,
        recognizedTitle: isSyntheticGroupRequest && resolvedTitle.isNotEmpty
            ? resolvedTitle
            : currentRecord.recognizedTitle,
        searchQuery: searchQuery.trim().isEmpty
            ? currentRecord.searchQuery
            : searchQuery.trim(),
        originalFileName: currentRecord.originalFileName,
        parentTitle: isSyntheticGroupRequest && resolvedTitle.isNotEmpty
            ? resolvedTitle
            : currentRecord.parentTitle,
        recognizedYear: currentRecord.recognizedYear,
        recognizedItemType: resolvedMetadataItemType == 'movie'
            ? 'movie'
            : currentRecord.recognizedItemType,
        preferSeries: resolvedMetadataItemType == 'movie'
            ? false
            : currentRecord.preferSeries,
        recognizedSeasonNumber: resolvedMetadataItemType == 'movie'
            ? null
            : currentRecord.recognizedSeasonNumber,
        recognizedEpisodeNumber: resolvedMetadataItemType == 'movie'
            ? null
            : currentRecord.recognizedEpisodeNumber,
        sidecarStatus: currentRecord.sidecarStatus,
        wmdbStatus: metadataMatch?.provider == MetadataMatchProvider.wmdb
            ? NasMetadataFetchStatus.succeeded
            : currentRecord.wmdbStatus,
        tmdbStatus: metadataMatch?.provider == MetadataMatchProvider.tmdb
            ? NasMetadataFetchStatus.succeeded
            : currentRecord.tmdbStatus,
        imdbStatus: (imdbRatingMatch?.ratingLabel.trim().isNotEmpty ?? false)
            ? NasMetadataFetchStatus.succeeded
            : currentRecord.imdbStatus,
        metadataFailureCount: 0,
        metadataRetryAfter: null,
        manualMetadataLocked: true,
        item: nextItem,
      );
      nextRecords[targetIndex] = updatedRecord;
      changedRecords.add(updatedRecord);
    }
    final existingState = await _store.loadSourceState(sourceId);
    await _patchSourceRecords(
      sourceId: sourceId,
      currentRecords: records,
      upsertedRecords: changedRecords,
      deletedRecordIds: const [],
      state: NasMediaIndexSourceState(
        sourceId: sourceId,
        lastIndexedAt: now,
        recordCount: nextRecords.length,
        scopeKey: existingState?.scopeKey ?? '',
        emptyAutoRebuildAttempted: nextRecords.isNotEmpty
            ? false
            : (existingState?.emptyAutoRebuildAttempted ?? false),
      ),
    );

    return _buildManualMetadataTarget(
      target: target,
      records: nextRecords,
      selectedResourceIds: selectedResourceIds,
      resourceId: resourceId,
      resourcePath: target.resourcePath,
      searchQuery:
          searchQuery.trim().isEmpty ? target.searchQuery : searchQuery.trim(),
    );
  }

  String _resolvedMetadataItemType(MetadataMatchResult? metadataMatch) {
    return metadataMatch?.mediaType.toItemType ?? '';
  }

  Future<void> _cancelRefreshTasksForSource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }
    final taskPrefix = '$normalizedSourceId|';
    final handles = <_RefreshTaskHandle>{
      for (final entry in _activeRefreshTasks.entries)
        if (entry.key.startsWith(taskPrefix)) entry.value,
      for (final entry in _backgroundEnrichmentTasks.entries)
        if (entry.key.startsWith(taskPrefix)) entry.value,
    }.toList(growable: false);
    if (handles.isEmpty) {
      return;
    }
    for (final handle in handles) {
      handle.cancel();
    }
    await Future.wait(
      handles.map(
        (handle) => handle.future.catchError((_) {
          // Manual metadata writes are authoritative; cancelled refreshes are expected.
        }),
      ),
    );
  }

  Future<List<WebDavScannedItem>> _scanSource(
    MediaSourceConfig source, {
    required List<MediaCollection>? scopedCollections,
    required int limitPerCollection,
    required bool includeSidecarMetadata,
    required bool resetScanCaches,
    required _RefreshTaskController controller,
  }) async {
    controller.throwIfCancelled();
    _updateIndexerConcurrencyLimits();
    if (scopedCollections != null && scopedCollections.isNotEmpty) {
      _progressController.startScanning(
        sourceId: source.id,
        sourceName: source.name,
        totalCollections: scopedCollections.length,
      );
      var completedCollections = 0;
      final groups = await Future.wait(
        scopedCollections.asMap().entries.map((entry) async {
          return _collectionBudget.withPermit(() async {
            final collectionIndex = entry.key;
            final collection = entry.value;
            controller.throwIfCancelled();
            late final List<WebDavScannedItem> result;
            try {
              result = await _scanLibraryFromExternalSource(
                source,
                sectionId: collection.id,
                sectionName: collection.title,
                limit: limitPerCollection,
                includeSidecarMetadata: includeSidecarMetadata,
                resetScanCaches: resetScanCaches && collectionIndex == 0,
                shouldCancel: controller.isCancelled,
              );
            } catch (_) {
              if (controller.cancelled) {
                throw const _RefreshCancelledException();
              }
              rethrow;
            }
            controller.throwIfCancelled();
            completedCollections += 1;
            _progressController.updateScanning(
              sourceId: source.id,
              current: completedCollections,
              total: scopedCollections.length,
              detail: collection.title,
            );

            return result;
          });
        }),
      );
      final deduped = <String, WebDavScannedItem>{};
      var dedupeCount = 0;
      for (final item in groups.expand((group) => group)) {
        deduped[item.resourceId] = item;
        dedupeCount += 1;
        if (dedupeCount % 64 == 0) {
          await Future<void>.delayed(Duration.zero);
          controller.throwIfCancelled();
        }
      }
      final items = deduped.values.toList(growable: false);
      items.sort((left, right) => right.addedAt.compareTo(left.addedAt));

      return items;
    }

    _progressController.startScanning(
      sourceId: source.id,
      sourceName: source.name,
      totalCollections: 1,
    );
    late final List<WebDavScannedItem> rootItems;
    try {
      rootItems = await _scanLibraryFromExternalSource(
        source,
        limit: limitPerCollection,
        includeSidecarMetadata: includeSidecarMetadata,
        resetScanCaches: resetScanCaches,
        shouldCancel: controller.isCancelled,
      );
    } catch (_) {
      if (controller.cancelled) {
        throw const _RefreshCancelledException();
      }
      rethrow;
    }
    controller.throwIfCancelled();
    _progressController.updateScanning(
      sourceId: source.id,
      current: 1,
      total: 1,
      detail: source.name,
    );

    return rootItems;
  }

  Future<_RefreshPhaseResult> _refreshSourcePhase(
    MediaSourceConfig source, {
    required List<MediaCollection>? scopedCollections,
    required int limitPerCollection,
    required bool includeSidecarMetadata,
    required bool includeOnlineMetadata,
    required bool forceFullRescan,
    required bool resetScanCaches,
    required bool clearProgressWhenDone,
    required String phaseLabel,
    required _RefreshTaskController controller,
    bool collectEnrichmentCandidates = false,
  }) async {
    final now = DateTime.now();
    final normalizedSourceId = source.id.trim();
    final settings = _readSettingsForRefresh();
    final phaseStopwatch = Stopwatch()..start();
    final scanStopwatch = Stopwatch()..start();
    appLogInfo(
      'library.index',
      'Media source scan phase started',
      fields: <String, Object?>{
        'sourceId': normalizedSourceId,
        'scopeCount': scopedCollections?.length ?? 0,
        'itemLimitPerCollection': limitPerCollection,
        'forceFullRescan': forceFullRescan,
      },
    );
    final scannedItems = await _scanSource(
      source,
      scopedCollections: scopedCollections,
      limitPerCollection: limitPerCollection,
      includeSidecarMetadata: includeSidecarMetadata,
      resetScanCaches: resetScanCaches,
      controller: controller,
    );
    controller.throwIfCancelled();
    appLogInfo(
      'library.index',
      'Media source scan phase completed',
      fields: <String, Object?>{
        'sourceId': normalizedSourceId,
        'itemCount': scannedItems.length,
        'durationMs': scanStopwatch.elapsedMilliseconds,
      },
    );
    final indexingStopwatch = Stopwatch()..start();
    _progressController.startIndexing(
      sourceId: normalizedSourceId,
      totalItems: scannedItems.length,
      activityLabel: phaseLabel,
      detail: scannedItems.isEmpty ? '没有发现媒体文件' : phaseLabel,
    );
    final existingRecordList = await _loadSourceRecordsCached(source.id);
    final existingRecords = <String, NasMediaIndexRecord>{};
    for (var index = 0; index < existingRecordList.length; index++) {
      final record = existingRecordList[index];
      existingRecords[record.resourceId] = record;
      if ((index + 1) % 64 == 0) {
        await Future<void>.delayed(Duration.zero);
        controller.throwIfCancelled();
      }
    }
    final nextRecords = <NasMediaIndexRecord>[];
    final recordsToUpsert = <NasMediaIndexRecord>[];
    final scannedResourceIds = <String>{};
    final enrichmentCandidates = <WebDavScannedItem>[];

    appLogInfo(
      'library.index',
      'Media item indexing phase started',
      fields: <String, Object?>{
        'sourceId': normalizedSourceId,
        'itemCount': scannedItems.length,
        'existingRecordCount': existingRecords.length,
      },
    );

    for (var index = 0; index < scannedItems.length; index++) {
      if (index > 0 && index % 24 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.throwIfCancelled();
      final scannedItem = scannedItems[index];
      scannedResourceIds.add(scannedItem.resourceId);
      final fingerprint = _buildFingerprint(
        sourceId: source.id,
        resourcePath: scannedItem.actualAddress,
        modifiedAt: scannedItem.modifiedAt,
        fileSizeBytes: scannedItem.fileSizeBytes,
        structureSignature: _buildStructureFingerprintSignature(scannedItem),
      );
      final existing = existingRecords[scannedItem.resourceId];
      final preserveManualMetadata = existing?.manualMetadataLocked == true;
      final hasRequiredSidecar = !includeSidecarMetadata ||
          preserveManualMetadata ||
          _hasAttemptStatus(existing?.sidecarStatus);
      final hasRequiredOnlineMetadata = !includeOnlineMetadata ||
          _hasCompletedOnlineAttempts(existing, settings);
      final canReuse = existing != null &&
          existing.fingerprint == fingerprint &&
          hasRequiredSidecar &&
          hasRequiredOnlineMetadata;
      final isIncrementalCandidate =
          existing == null || existing.fingerprint != fingerprint;
      final needsFurtherEnrichment = collectEnrichmentCandidates &&
          (isIncrementalCandidate ||
              (source.webDavSidecarScrapingEnabled &&
                  !_hasAttemptStatus(existing.sidecarStatus)) ||
              !_hasCompletedOnlineAttempts(existing, settings));
      if (needsFurtherEnrichment) {
        enrichmentCandidates.add(scannedItem);
      }
      if (canReuse) {
        final reusedRecord = _reuseRecord(
          existing,
          scannedItem: scannedItem,
          source: source,
          indexedAt: now,
        );
        nextRecords.add(reusedRecord);
      } else {
        final indexedRecord = await _indexScannedItem(
          source,
          scannedItem,
          indexedAt: now,
          fingerprint: fingerprint,
          existingRecord: existing != null &&
                  (existing.fingerprint == fingerprint ||
                      preserveManualMetadata)
              ? existing
              : null,
          applyOnlineMetadata: includeOnlineMetadata && !preserveManualMetadata,
          markSidecarAttempt: includeSidecarMetadata && !preserveManualMetadata,
        );
        nextRecords.add(indexedRecord);
        recordsToUpsert.add(indexedRecord);
      }
      _progressController.updateIndexing(
        sourceId: normalizedSourceId,
        current: index + 1,
        total: scannedItems.length,
        detail: scannedItem.fileName,
      );
    }

    controller.throwIfCancelled();
    appLogInfo(
      'library.index',
      'Media item indexing phase completed',
      fields: <String, Object?>{
        'sourceId': normalizedSourceId,
        'itemCount': nextRecords.length,
        'enrichmentCandidateCount': enrichmentCandidates.length,
        'durationMs': indexingStopwatch.elapsedMilliseconds,
      },
    );
    final persistenceStopwatch = Stopwatch()..start();
    appLogInfo(
      'library.index',
      'Media index persistence started',
      fields: <String, Object?>{
        'sourceId': normalizedSourceId,
        'recordCount': nextRecords.length,
      },
    );
    final existingState = await _store.loadSourceState(source.id);
    final deletedRecordIds = existingRecords.values
        .where((record) => !scannedResourceIds.contains(record.resourceId))
        .map((record) => record.id)
        .toList(growable: false);
    await _patchSourceRecords(
      sourceId: source.id,
      currentRecords: existingRecordList,
      upsertedRecords: recordsToUpsert,
      deletedRecordIds: deletedRecordIds,
      state: NasMediaIndexSourceState(
        sourceId: source.id,
        lastIndexedAt: now,
        recordCount: nextRecords.length,
        scopeKey: _buildScopeKey(source, scopedCollections),
        emptyAutoRebuildAttempted: nextRecords.isNotEmpty
            ? false
            : (existingState?.emptyAutoRebuildAttempted ?? false),
      ),
    );
    appLogInfo(
      'library.index',
      'Media index persistence completed',
      fields: <String, Object?>{
        'sourceId': normalizedSourceId,
        'recordCount': nextRecords.length,
        'updatedCount': recordsToUpsert.length,
        'deletedCount': deletedRecordIds.length,
        'durationMs': persistenceStopwatch.elapsedMilliseconds,
        'phaseDurationMs': phaseStopwatch.elapsedMilliseconds,
      },
    );
    if (recordsToUpsert.isNotEmpty || deletedRecordIds.isNotEmpty) {
      _notifyIndexChangedSafely();
    }

    if (clearProgressWhenDone) {
      _clearProgressSafely(normalizedSourceId);
    }
    return _RefreshPhaseResult(
      enrichmentCandidates: enrichmentCandidates,
    );
  }

  void _scheduleBackgroundEnrichment(
    MediaSourceConfig source, {
    required List<MediaCollection>? scopedCollections,
    required List<WebDavScannedItem> enrichmentCandidates,
    required bool includeSidecarMetadata,
    required bool includeOnlineMetadata,
    required bool forceFullRescan,
    required _RefreshTaskController controller,
  }) {
    final taskKey = _buildRefreshTaskKey(source, scopedCollections);
    if (_backgroundEnrichmentTasks.containsKey(taskKey)) {
      return;
    }
    _updateIndexerConcurrencyLimits();
    final stopwatch = Stopwatch()..start();
    final configuredItemConcurrency =
        _nasWorkConcurrency(_readSettingsForRefresh());
    final itemConcurrency =
        configuredItemConcurrency < enrichmentCandidates.length
            ? configuredItemConcurrency
            : enrichmentCandidates.length;
    appLogInfo(
      'library.index',
      'Background metadata enrichment started',
      fields: <String, Object?>{
        'sourceId': source.id,
        'itemCount': enrichmentCandidates.length,
        'itemConcurrency': itemConcurrency,
        'maintenancePermits': forceFullRescan,
        'sidecarMetadata': includeSidecarMetadata,
        'onlineMetadata': includeOnlineMetadata,
      },
    );
    final future = (() async {
      try {
        await _refreshSelectedItemsPhase(
          source,
          scannedItems: enrichmentCandidates,
          includeSidecarMetadata: includeSidecarMetadata,
          includeOnlineMetadata: includeOnlineMetadata,
          phaseLabel: forceFullRescan
              ? '全量补元数据'
              : ((includeOnlineMetadata || includeSidecarMetadata)
                  ? '增量补元数据'
                  : '后台补全'),
          controller: controller,
          useMaintenancePermits: forceFullRescan,
        );
        appLogInfo(
          'library.index',
          'Background metadata enrichment completed',
          fields: <String, Object?>{
            'sourceId': source.id,
            'itemCount': enrichmentCandidates.length,
            'itemConcurrency': itemConcurrency,
            'maintenancePermits': forceFullRescan,
            'sidecarMetadata': includeSidecarMetadata,
            'onlineMetadata': includeOnlineMetadata,
            'durationMs': stopwatch.elapsedMilliseconds,
          },
        );
      } on _RefreshCancelledException {
        _clearProgressSafely(source.id);
      } catch (error, stackTrace) {
        if (_isProviderContainerDisposedError(error)) {
          _clearProgressSafely(source.id);
          return;
        }

        _clearProgressSafely(source.id);
        appLogWarning(
          'library.index',
          'Background metadata enrichment failed',
          fields: <String, Object?>{
            'sourceId': source.id,
            'itemCount': enrichmentCandidates.length,
            'itemConcurrency': itemConcurrency,
            'maintenancePermits': forceFullRescan,
            'sidecarMetadata': includeSidecarMetadata,
            'onlineMetadata': includeOnlineMetadata,
            'durationMs': stopwatch.elapsedMilliseconds,
          },
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        _backgroundEnrichmentTasks.remove(taskKey);
      }
    })();
    _backgroundEnrichmentTasks[taskKey] = _RefreshTaskHandle(
      future: future,
      mode: forceFullRescan
          ? _RefreshTaskMode.forceFull
          : _RefreshTaskMode.incremental,
      controller: controller,
    );
  }

  Future<void> _refreshSelectedItemsPhase(
    MediaSourceConfig source, {
    required List<WebDavScannedItem> scannedItems,
    required bool includeSidecarMetadata,
    required bool includeOnlineMetadata,
    required String phaseLabel,
    required _RefreshTaskController controller,
    bool reportProgress = true,
    bool useMaintenancePermits = false,
  }) async {
    final phaseStopwatch = Stopwatch()..start();
    final normalizedSourceId = source.id.trim();
    final now = DateTime.now();
    final settings = _readSettingsForRefresh();
    controller.throwIfCancelled();
    final records = await _loadSourceRecordsCached(source.id);
    if (records.isEmpty || scannedItems.isEmpty) {
      if (reportProgress) {
        _clearProgressSafely(normalizedSourceId);
      }
      return;
    }
    final recordIndexByResourceId = <String, int>{};
    final nextRecords = [...records];
    final changedRecords = <String, NasMediaIndexRecord>{};
    final deletedRecordIds = <String>{};
    var skippedCount = 0;
    var sidecarAttemptCount = 0;
    var onlineAttemptCount = 0;
    var wmdbAttemptCount = 0;
    var tmdbAttemptCount = 0;
    var imdbAttemptCount = 0;
    var matchedCount = 0;
    var noMatchCount = 0;
    var transientFailureCount = 0;
    var permanentFailureCount = 0;
    for (var index = 0; index < nextRecords.length; index++) {
      recordIndexByResourceId[nextRecords[index].resourceId] = index;
    }
    if (reportProgress) {
      _progressController.startIndexing(
        sourceId: normalizedSourceId,
        totalItems: scannedItems.length,
        activityLabel: phaseLabel,
        detail: phaseLabel,
      );
    }
    var nextCandidateIndex = 0;
    var completedCount = 0;

    void reportItemCompleted(String detail) {
      completedCount += 1;
      if (reportProgress) {
        _progressController.updateIndexing(
          sourceId: normalizedSourceId,
          current: completedCount,
          total: scannedItems.length,
          detail: detail,
        );
      }
    }

    Future<void> processCandidate(int index) async {
      controller.throwIfCancelled();
      final scannedItem = scannedItems[index];
      final recordIndex = recordIndexByResourceId[scannedItem.resourceId];
      if (recordIndex == null) {
        reportItemCompleted('${scannedItem.fileName} 已跳过');
        return;
      }
      final currentRecord = nextRecords[recordIndex];
      final isManualMetadataLocked = currentRecord.manualMetadataLocked;
      final shouldAttemptSidecar = includeSidecarMetadata &&
          !isManualMetadataLocked &&
          !_hasAttemptStatus(currentRecord.sidecarStatus);
      final shouldAttemptOnline = includeOnlineMetadata &&
          !isManualMetadataLocked &&
          _hasPendingOnlineAttempts(currentRecord, settings);
      if (!shouldAttemptSidecar && !shouldAttemptOnline) {
        skippedCount += 1;
        reportItemCompleted('${scannedItem.fileName} 已跳过');
        return;
      }
      if (shouldAttemptSidecar) {
        sidecarAttemptCount += 1;
      }
      if (shouldAttemptOnline) {
        onlineAttemptCount += 1;
        final hasQuery = currentRecord.searchQuery.trim().isNotEmpty ||
            currentRecord.recognizedTitle.trim().isNotEmpty;
        if (hasQuery &&
            settings.wmdbMetadataMatchEnabled &&
            _shouldAttemptMetadataStatus(currentRecord.wmdbStatus)) {
          wmdbAttemptCount += 1;
        }
        if (hasQuery &&
            settings.tmdbMetadataMatchEnabled &&
            settings.tmdbReadAccessToken.trim().isNotEmpty &&
            _shouldAttemptMetadataStatus(currentRecord.tmdbStatus)) {
          tmdbAttemptCount += 1;
        }
        if (hasQuery &&
            settings.imdbRatingMatchEnabled &&
            _shouldAttemptMetadataStatus(currentRecord.imdbStatus)) {
          imdbAttemptCount += 1;
        }
      }
      final enrichedItem = shouldAttemptSidecar
          ? await (() async {
              try {
                return await _scanResourceFromExternalSource(
                  source,
                  resourceId: scannedItem.resourceId,
                  sectionId: scannedItem.sectionId,
                  sectionName: scannedItem.sectionName,
                  includeSidecarMetadata: true,
                  shouldCancel: controller.isCancelled,
                );
              } catch (_) {
                if (controller.cancelled) {
                  throw const _RefreshCancelledException();
                }
                rethrow;
              }
            })()
          : scannedItem;
      controller.throwIfCancelled();
      if (shouldAttemptSidecar && enrichedItem == null) {
        deletedRecordIds.add(currentRecord.id);
        reportItemCompleted('${scannedItem.fileName} 已删除');
        return;
      }
      final effectiveItem = _mergeStructureInferredSeed(
        source: source,
        original: scannedItem,
        enriched: enrichedItem ?? scannedItem,
      );
      final fingerprint = _buildFingerprint(
        sourceId: source.id,
        resourcePath: effectiveItem.actualAddress,
        modifiedAt: effectiveItem.modifiedAt,
        fileSizeBytes: effectiveItem.fileSizeBytes,
        structureSignature: _buildStructureFingerprintSignature(effectiveItem),
      );
      final updatedRecord = await _indexScannedItem(
        source,
        effectiveItem,
        indexedAt: now,
        fingerprint: fingerprint,
        existingRecord: currentRecord,
        applyOnlineMetadata: shouldAttemptOnline,
        markSidecarAttempt: shouldAttemptSidecar,
      );
      nextRecords[recordIndex] = updatedRecord;
      changedRecords[updatedRecord.id] = updatedRecord;
      final statuses = <NasMetadataFetchStatus>[
        updatedRecord.wmdbStatus,
        updatedRecord.tmdbStatus,
        updatedRecord.imdbStatus,
      ];
      if (statuses.contains(NasMetadataFetchStatus.transientFailure)) {
        transientFailureCount += 1;
      }
      if (statuses.contains(NasMetadataFetchStatus.permanentFailure)) {
        permanentFailureCount += 1;
      }
      if (statuses.contains(NasMetadataFetchStatus.succeeded)) {
        matchedCount += 1;
      } else if (statuses.contains(NasMetadataFetchStatus.noMatch)) {
        noMatchCount += 1;
      }
      reportItemCompleted(effectiveItem.fileName);
    }

    Future<void> runWorker() async {
      while (true) {
        controller.throwIfCancelled();
        if (nextCandidateIndex >= scannedItems.length) {
          return;
        }
        final index = nextCandidateIndex;
        nextCandidateIndex += 1;
        await _enrichmentBudget.withPermit(
          () => _withGlobalBackgroundPermit(
            () => processCandidate(index),
            maintenance: useMaintenancePermits,
          ),
        );
      }
    }

    final configuredConcurrency = _nasWorkConcurrency(settings);
    final workerCount = configuredConcurrency < scannedItems.length
        ? configuredConcurrency
        : scannedItems.length;
    await Future.wait(
      List<Future<void>>.generate(
        workerCount < 1 ? 1 : workerCount,
        (_) => runWorker(),
        growable: false,
      ),
    );
    controller.throwIfCancelled();
    if (deletedRecordIds.isNotEmpty) {
      nextRecords.removeWhere((record) => deletedRecordIds.contains(record.id));
    }
    final existingState = await _store.loadSourceState(source.id);
    final persistenceStopwatch = Stopwatch()..start();
    await _patchSourceRecords(
      sourceId: source.id,
      currentRecords: records,
      upsertedRecords: changedRecords.values.toList(growable: false),
      deletedRecordIds: deletedRecordIds.toList(growable: false),
      state: NasMediaIndexSourceState(
        sourceId: source.id,
        lastIndexedAt: now,
        recordCount: nextRecords.length,
        scopeKey: existingState?.scopeKey ?? '',
        emptyAutoRebuildAttempted: nextRecords.isNotEmpty
            ? false
            : (existingState?.emptyAutoRebuildAttempted ?? false),
      ),
    );
    if (changedRecords.isNotEmpty || deletedRecordIds.isNotEmpty) {
      _notifyIndexChangedSafely();
    }
    appLogInfo(
      'library.index',
      'Incremental metadata index patch completed',
      fields: <String, Object?>{
        'sourceId': normalizedSourceId,
        'candidateCount': scannedItems.length,
        'updatedCount': changedRecords.length,
        'deletedCount': deletedRecordIds.length,
        'skippedCount': skippedCount,
        'sidecarAttemptCount': sidecarAttemptCount,
        'onlineAttemptCount': onlineAttemptCount,
        'wmdbAttemptCount': wmdbAttemptCount,
        'tmdbAttemptCount': tmdbAttemptCount,
        'imdbAttemptCount': imdbAttemptCount,
        'matchedCount': matchedCount,
        'noMatchCount': noMatchCount,
        'transientFailureCount': transientFailureCount,
        'permanentFailureCount': permanentFailureCount,
        'recordCount': nextRecords.length,
        'itemConcurrency': workerCount,
        'persistenceDurationMs': persistenceStopwatch.elapsedMilliseconds,
        'durationMs': phaseStopwatch.elapsedMilliseconds,
      },
    );
    if (reportProgress) {
      _clearProgressSafely(normalizedSourceId);
    }
  }

  WebDavScannedItem _mergeStructureInferredSeed({
    required MediaSourceConfig source,
    required WebDavScannedItem original,
    required WebDavScannedItem enriched,
  }) {
    if (!source.webDavStructureInferenceEnabled) {
      return enriched;
    }
    final originalSeed = original.metadataSeed;
    final enrichedSeed = enriched.metadataSeed;
    final mergedSeed = enrichedSeed.copyWith(
      itemType: originalSeed.itemType.trim().isNotEmpty
          ? originalSeed.itemType
          : enrichedSeed.itemType,
      seasonNumber: originalSeed.seasonNumber ?? enrichedSeed.seasonNumber,
      episodeNumber: originalSeed.episodeNumber ?? enrichedSeed.episodeNumber,
    );
    if (identical(mergedSeed, enrichedSeed) ||
        (mergedSeed.itemType == enrichedSeed.itemType &&
            mergedSeed.seasonNumber == enrichedSeed.seasonNumber &&
            mergedSeed.episodeNumber == enrichedSeed.episodeNumber)) {
      return enriched;
    }
    return WebDavScannedItem(
      resourceId: enriched.resourceId,
      fileName: enriched.fileName,
      actualAddress: enriched.actualAddress,
      sectionId: enriched.sectionId,
      sectionName: enriched.sectionName,
      streamUrl: enriched.streamUrl,
      streamHeaders: enriched.streamHeaders,
      playbackItemId: enriched.playbackItemId,
      addedAt: enriched.addedAt,
      modifiedAt: enriched.modifiedAt,
      fileSizeBytes: enriched.fileSizeBytes,
      metadataSeed: mergedSeed,
    );
  }

  bool _isStructureInferredEpisodeLike(
    MediaSourceConfig source,
    WebDavScannedItem item,
  ) {
    if (!source.webDavStructureInferenceEnabled) {
      return false;
    }
    final seed = item.metadataSeed;
    final inferredEpisodeLike =
        seed.itemType.trim().toLowerCase() == 'episode' ||
            seed.seasonNumber != null ||
            seed.episodeNumber != null;
    return inferredEpisodeLike;
  }

  bool _shouldUseStructureInferredSeriesLevelScrape(
    MediaSourceConfig source,
    WebDavScannedItem item,
  ) {
    return source.webDavSeriesScrapeUsesDirectoryTitleOnly &&
        _isStructureInferredEpisodeLike(source, item);
  }

  String _buildRefreshTaskKey(
    MediaSourceConfig source,
    List<MediaCollection>? scopedCollections,
  ) {
    return '${source.id}|${_buildScopeKey(source, scopedCollections)}';
  }
}
