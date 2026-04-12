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
    await _persistSourceRecords(
      sourceId: source.id,
      records: existingRecords,
      state: NasMediaIndexSourceState(
        sourceId: source.id,
        lastIndexedAt: now,
        recordCount: existingRecords.length,
        scopeKey: scopeKey,
        emptyAutoRebuildAttempted: true,
      ),
    );

    webDavTrace(
      'indexer.refresh.autoRebuildOnEmpty',
      fields: {
        'sourceId': source.id,
        'sourceName': source.name,
        'scopeKey': scopeKey,
      },
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
    await _persistSourceRecords(
      sourceId: normalizedSourceId,
      records: nextRecords,
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
    var changed = false;
    final now = DateTime.now();
    for (final targetIndex in targetIndices) {
      final currentRecord = nextRecords[targetIndex];
      if (currentRecord.manualMetadataLocked) {
        continue;
      }
      nextRecords[targetIndex] = NasMediaIndexRecord(
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
        manualMetadataLocked: true,
        item: currentRecord.item,
      );
      changed = true;
    }

    if (!changed) {
      return;
    }

    final existingState = await _store.loadSourceState(sourceId);
    await _persistSourceRecords(
      sourceId: sourceId,
      records: nextRecords,
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

    final records = await _loadScopedRecords(
      source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
    );
    final groups = _groupSeriesRecords(records);

    if (normalizedParentId.startsWith(NasMediaIndexer._seriesGroupPrefix)) {
      final targetGroup = groups.where(
        (group) => group.seriesItemId == normalizedParentId,
      );
      if (targetGroup.isEmpty) {
        return const [];
      }
      final group = targetGroup.first;
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
      final targetGroup = groups.where(
        (group) => group.seriesKey == parsed.seriesKey,
      );
      if (targetGroup.isEmpty) {
        return const [];
      }
      final episodes = targetGroup.first.seasonGroups[parsed.seasonNumber] ??
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

    return cache.findByExternalIds(
      doubanId: doubanId,
      imdbId: imdbId,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      wikidataId: wikidataId,
    );
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
      webDavTrace(
        'indexer.refresh.cancelBackground',
        fields: {
          'sourceId': source.id,
          'sourceName': source.name,
          'forceFullRescan': forceFullRescan,
        },
      );
      existingBackgroundTask.cancel();
      await existingBackgroundTask.future.catchError((_) {
        // Background enrichment is best-effort and safe to interrupt.
      });
    }

    final controller = _RefreshTaskController();
    final future = _sourceBudget.withPermit(() async {
      try {
        webDavTrace(
          'indexer.refresh.start',
          fields: {
            'sourceId': source.id,
            'sourceName': source.name,
            'endpoint': source.endpoint,
            'scopedCollections':
                scopedCollections?.map((item) => item.title).toList() ??
                    const [],
            'limitPerCollection': limitPerCollection,
            'forceFullRescan': forceFullRescan,
          },
        );
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
        _clearProgressSafely(normalizedSourceId);
      } catch (error, stackTrace) {
        _clearProgressSafely(normalizedSourceId);
        if (_isProviderContainerDisposedError(error)) {
          return;
        }
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        _activeRefreshTasks.remove(taskKey);
      }
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
      nextRecords[targetIndex] = NasMediaIndexRecord(
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
        manualMetadataLocked: true,
        item: nextItem,
      );
    }
    final existingState = await _store.loadSourceState(sourceId);
    await _persistSourceRecords(
      sourceId: sourceId,
      records: nextRecords,
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
    if (scopedCollections != null && scopedCollections.isNotEmpty) {
      webDavTrace(
        'indexer.scanSource.scoped.start',
        fields: {
          'sourceId': source.id,
          'collections': scopedCollections.map((item) => item.title).toList(),
        },
      );
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
            webDavTrace(
              'indexer.scanSource.collection.done',
              fields: {
                'sourceId': source.id,
                'collection': collection.title,
                'count': result.length,
              },
            );
            return result;
          });
        }),
      );
      final deduped = <String, WebDavScannedItem>{};
      for (final item in groups.expand((group) => group)) {
        deduped[item.resourceId] = item;
      }
      final items = deduped.values.toList(growable: false);
      items.sort((left, right) => right.addedAt.compareTo(left.addedAt));
      webDavTrace(
        'indexer.scanSource.scoped.done',
        fields: {
          'sourceId': source.id,
          'dedupedCount': items.length,
        },
      );
      return items;
    }
    webDavTrace(
      'indexer.scanSource.root.start',
      fields: {
        'sourceId': source.id,
        'sourceName': source.name,
      },
    );
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
    webDavTrace(
      'indexer.scanSource.root.done',
      fields: {
        'sourceId': source.id,
        'count': rootItems.length,
      },
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
    final scannedItems = await _scanSource(
      source,
      scopedCollections: scopedCollections,
      limitPerCollection: limitPerCollection,
      includeSidecarMetadata: includeSidecarMetadata,
      resetScanCaches: resetScanCaches,
      controller: controller,
    );
    controller.throwIfCancelled();
    _progressController.startIndexing(
      sourceId: normalizedSourceId,
      totalItems: scannedItems.length,
      activityLabel: phaseLabel,
      detail: scannedItems.isEmpty ? '没有发现媒体文件' : phaseLabel,
    );
    final existingRecords = {
      for (final record in await _loadSourceRecordsCached(source.id))
        record.resourceId: record,
    };
    final nextRecords = <NasMediaIndexRecord>[];
    final enrichmentCandidates = <WebDavScannedItem>[];

    for (var index = 0; index < scannedItems.length; index++) {
      controller.throwIfCancelled();
      final scannedItem = scannedItems[index];
      final fingerprint = _buildFingerprint(
        sourceId: source.id,
        resourcePath: scannedItem.actualAddress,
        modifiedAt: scannedItem.modifiedAt,
        fileSizeBytes: scannedItem.fileSizeBytes,
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
      final needsFurtherEnrichment =
          collectEnrichmentCandidates && isIncrementalCandidate;
      if (needsFurtherEnrichment) {
        enrichmentCandidates.add(scannedItem);
      }
      if (canReuse) {
        webDavTrace(
          'indexer.refresh.reuse',
          fields: {
            'resourceId': scannedItem.resourceId,
            'path': scannedItem.actualAddress,
            'title': scannedItem.metadataSeed.title,
            'phase': phaseLabel,
          },
        );
        nextRecords.add(
          _reuseRecord(
            existing,
            scannedItem: scannedItem,
            source: source,
            indexedAt: now,
          ),
        );
      } else {
        webDavTrace(
          'indexer.refresh.index',
          fields: {
            'resourceId': scannedItem.resourceId,
            'path': scannedItem.actualAddress,
            'title': scannedItem.metadataSeed.title,
            'itemType': scannedItem.metadataSeed.itemType,
            'season': scannedItem.metadataSeed.seasonNumber,
            'episode': scannedItem.metadataSeed.episodeNumber,
            'phase': phaseLabel,
          },
        );
        nextRecords.add(
          await _indexScannedItem(
            source,
            scannedItem,
            indexedAt: now,
            fingerprint: fingerprint,
            existingRecord: existing != null &&
                    (existing.fingerprint == fingerprint ||
                        preserveManualMetadata)
                ? existing
                : null,
            applyOnlineMetadata:
                includeOnlineMetadata && !preserveManualMetadata,
            markSidecarAttempt:
                includeSidecarMetadata && !preserveManualMetadata,
          ),
        );
      }
      _progressController.updateIndexing(
        sourceId: normalizedSourceId,
        current: index + 1,
        total: scannedItems.length,
        detail: scannedItem.fileName,
      );
    }

    controller.throwIfCancelled();
    final existingState = await _store.loadSourceState(source.id);
    await _persistSourceRecords(
      sourceId: source.id,
      records: nextRecords,
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
    _notifyIndexChangedSafely();
    webDavTrace(
      'indexer.refresh.done',
      fields: {
        'sourceId': source.id,
        'recordCount': nextRecords.length,
        'phase': phaseLabel,
      },
    );
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
    final future = _enrichmentBudget.withPermit(() async {
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
        );
      } on _RefreshCancelledException {
        _clearProgressSafely(source.id);
      } catch (error) {
        if (_isProviderContainerDisposedError(error)) {
          _clearProgressSafely(source.id);
          return;
        }
        webDavTrace(
          'indexer.refresh.background.error',
          fields: {
            'sourceId': source.id,
            'error': '$error',
          },
        );
        _clearProgressSafely(source.id);
      } finally {
        _backgroundEnrichmentTasks.remove(taskKey);
      }
    });
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
  }) async {
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
    for (var index = 0; index < scannedItems.length; index++) {
      controller.throwIfCancelled();
      final scannedItem = scannedItems[index];
      final recordIndex = recordIndexByResourceId[scannedItem.resourceId];
      if (recordIndex == null) {
        continue;
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
        if (reportProgress) {
          _progressController.updateIndexing(
            sourceId: normalizedSourceId,
            current: index + 1,
            total: scannedItems.length,
            detail: '${scannedItem.fileName} 已跳过',
          );
        }
        continue;
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
        nextRecords.removeAt(recordIndex);
        recordIndexByResourceId
          ..clear()
          ..addEntries(
            nextRecords.indexed.map(
              (entry) => MapEntry(entry.$2.resourceId, entry.$1),
            ),
          );
        if (reportProgress) {
          _progressController.updateIndexing(
            sourceId: normalizedSourceId,
            current: index + 1,
            total: scannedItems.length,
            detail: '${scannedItem.fileName} 已删除',
          );
        }
        continue;
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
      );
      nextRecords[recordIndex] = await _indexScannedItem(
        source,
        effectiveItem,
        indexedAt: now,
        fingerprint: fingerprint,
        existingRecord: currentRecord,
        applyOnlineMetadata: shouldAttemptOnline,
        markSidecarAttempt: shouldAttemptSidecar,
      );
      if (reportProgress) {
        _progressController.updateIndexing(
          sourceId: normalizedSourceId,
          current: index + 1,
          total: scannedItems.length,
          detail: effectiveItem.fileName,
        );
      }
    }
    controller.throwIfCancelled();
    final existingState = await _store.loadSourceState(source.id);
    await _persistSourceRecords(
      sourceId: source.id,
      records: nextRecords,
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
    _notifyIndexChangedSafely();
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
