import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/webdav_trace.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final nasMediaIndexerProvider = Provider<NasMediaIndexer>((ref) {
  return NasMediaIndexer(
    store: ref.read(nasMediaIndexStoreProvider),
    webDavNasClient: ref.read(webDavNasClientProvider),
    wmdbMetadataClient: ref.read(wmdbMetadataClientProvider),
    tmdbMetadataClient: ref.read(tmdbMetadataClientProvider),
    imdbRatingClient: ref.read(imdbRatingClientProvider),
    readSettings: () => ref.read(appSettingsProvider),
    progressController: ref.read(webDavScrapeProgressProvider.notifier),
    notifyIndexChanged: () {
      ref.read(nasMediaIndexRevisionProvider.notifier).state++;
    },
  );
});

class NasMediaIndexer {
  NasMediaIndexer({
    required NasMediaIndexStore store,
    required WebDavNasClient webDavNasClient,
    required WmdbMetadataClient wmdbMetadataClient,
    required TmdbMetadataClient tmdbMetadataClient,
    required ImdbRatingClient imdbRatingClient,
    required AppSettings Function() readSettings,
    required WebDavScrapeProgressController progressController,
    void Function()? notifyIndexChanged,
  })  : _store = store,
        _webDavNasClient = webDavNasClient,
        _wmdbMetadataClient = wmdbMetadataClient,
        _tmdbMetadataClient = tmdbMetadataClient,
        _imdbRatingClient = imdbRatingClient,
        _readSettings = readSettings,
        _progressController = progressController,
        _notifyIndexChanged = notifyIndexChanged;

  static const int _defaultRefreshLimitPerCollection = 1200;
  static const String _seriesGroupPrefix = 'webdav-series';
  static const String _seasonGroupPrefix = 'webdav-season';
  static const String _webDavMetadataSchemaVersion = 'webdav-v6';

  final NasMediaIndexStore _store;
  final WebDavNasClient _webDavNasClient;
  final WmdbMetadataClient _wmdbMetadataClient;
  final TmdbMetadataClient _tmdbMetadataClient;
  final ImdbRatingClient _imdbRatingClient;
  final AppSettings Function() _readSettings;
  final WebDavScrapeProgressController _progressController;
  final void Function()? _notifyIndexChanged;
  final Map<String, _RefreshTaskHandle> _activeRefreshTasks =
      <String, _RefreshTaskHandle>{};
  final Map<String, _RefreshTaskHandle> _backgroundEnrichmentTasks =
      <String, _RefreshTaskHandle>{};
  final Map<String, _NasLibraryMatchCache> _libraryMatchCaches =
      <String, _NasLibraryMatchCache>{};

  Future<void> cancelAllRefreshTasks() async {
    final handles = <_RefreshTaskHandle>{
      ..._activeRefreshTasks.values,
      ..._backgroundEnrichmentTasks.values,
    }.toList(growable: false);
    if (handles.isEmpty) {
      return;
    }

    webDavTrace(
      'indexer.refresh.cancelAll',
      fields: {
        'activeCount': _activeRefreshTasks.length,
        'backgroundCount': _backgroundEnrichmentTasks.length,
      },
    );

    for (final handle in handles) {
      handle.cancel();
    }

    await Future.wait(
      handles.map(
        (handle) => handle.future.catchError((_) {
          // Cancellation is best-effort; individual tasks already clean up.
        }),
      ),
    );
  }

  Future<void> clearSource(String sourceId) {
    _libraryMatchCaches.remove(sourceId.trim());
    return _store.clearSource(sourceId);
  }

  Future<bool> tryAutoRebuildOnEmpty(
    MediaSourceConfig source, {
    List<MediaCollection>? scopedCollections,
  }) async {
    if (source.kind != MediaSourceKind.nas || source.endpoint.trim().isEmpty) {
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
    _notifyIndexChanged?.call();
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

    final settings = _readSettings();
    MediaSourceConfig? source;
    for (final candidate in settings.mediaSources) {
      if (candidate.id == sourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null ||
        source.kind != MediaSourceKind.nas ||
        source.endpoint.trim().isEmpty) {
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
          (record) => !_hasAttemptStatus(record.sidecarStatus),
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

    if (normalizedParentId.startsWith(_seriesGroupPrefix)) {
      final targetGroup = groups.where(
        (group) => group.seriesItemId == normalizedParentId,
      );
      if (targetGroup.isEmpty) {
        return const [];
      }
      final group = targetGroup.first;
      final seasonGroups = group.seasonGroups;
      if (_shouldFlattenSingleSeasonGroup(group, seasonGroups)) {
        return _materializeEpisodeItems(seasonGroups.values.expand((e) => e))
            .take(limit)
            .toList(growable: false);
      }
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

    if (normalizedParentId.startsWith(_seasonGroupPrefix)) {
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

  Future<List<MediaItem>> loadCachedLibraryMatchItems(
    MediaSourceConfig source, {
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
  }) async {
    if (source.kind != MediaSourceKind.nas || source.endpoint.trim().isEmpty) {
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
    int limitPerCollection = _defaultRefreshLimitPerCollection,
    bool forceFullRescan = false,
  }) async {
    if (source.kind != MediaSourceKind.nas || source.endpoint.trim().isEmpty) {
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
    final task = Future<void>(() async {
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

        final settings = _readSettings();
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
      } catch (_) {
        _clearProgressSafely(normalizedSourceId);
        rethrow;
      } finally {
        _activeRefreshTasks.remove(taskKey);
      }
    });
    _activeRefreshTasks[taskKey] = _RefreshTaskHandle(
      future: task,
      mode: forceFullRescan
          ? _RefreshTaskMode.forceFull
          : _RefreshTaskMode.incremental,
      controller: controller,
    );
    await task;
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
          final collectionIndex = entry.key;
          final collection = entry.value;
          controller.throwIfCancelled();
          late final List<WebDavScannedItem> result;
          try {
            result = await _webDavNasClient.scanLibrary(
              source,
              sectionId: collection.id,
              sectionName: collection.title,
              limit: limitPerCollection,
              loadSidecarMetadata: includeSidecarMetadata,
              resolvePlayableStreams: false,
              resetCaches: resetScanCaches && collectionIndex == 0,
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
      rootItems = await _webDavNasClient.scanLibrary(
        source,
        limit: limitPerCollection,
        loadSidecarMetadata: includeSidecarMetadata,
        resolvePlayableStreams: false,
        resetCaches: resetScanCaches,
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
    final settings = _readSettings();
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
      final hasRequiredSidecar =
          !includeSidecarMetadata || _hasAttemptStatus(existing?.sidecarStatus);
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
            existingRecord:
                existing != null && existing.fingerprint == fingerprint
                    ? existing
                    : null,
            applyOnlineMetadata: includeOnlineMetadata,
            markSidecarAttempt: includeSidecarMetadata,
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
    _notifyIndexChanged?.call();
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
    final future = Future<void>(() async {
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
  }) async {
    final normalizedSourceId = source.id.trim();
    final now = DateTime.now();
    final settings = _readSettings();
    controller.throwIfCancelled();
    final records = await _loadSourceRecordsCached(source.id);
    if (records.isEmpty || scannedItems.isEmpty) {
      _clearProgressSafely(normalizedSourceId);
      return;
    }
    final recordIndexByResourceId = <String, int>{};
    final nextRecords = [...records];
    for (var index = 0; index < nextRecords.length; index++) {
      recordIndexByResourceId[nextRecords[index].resourceId] = index;
    }
    _progressController.startIndexing(
      sourceId: normalizedSourceId,
      totalItems: scannedItems.length,
      activityLabel: phaseLabel,
      detail: phaseLabel,
    );
    for (var index = 0; index < scannedItems.length; index++) {
      controller.throwIfCancelled();
      final scannedItem = scannedItems[index];
      final recordIndex = recordIndexByResourceId[scannedItem.resourceId];
      if (recordIndex == null) {
        continue;
      }
      final currentRecord = nextRecords[recordIndex];
      final shouldAttemptSidecar = includeSidecarMetadata &&
          !_hasAttemptStatus(currentRecord.sidecarStatus);
      final shouldAttemptOnline = includeOnlineMetadata &&
          _hasPendingOnlineAttempts(currentRecord, settings);
      if (!shouldAttemptSidecar && !shouldAttemptOnline) {
        _progressController.updateIndexing(
          sourceId: normalizedSourceId,
          current: index + 1,
          total: scannedItems.length,
          detail: '${scannedItem.fileName} 已跳过',
        );
        continue;
      }
      final enrichedItem = shouldAttemptSidecar
          ? await (() async {
              try {
                return await _webDavNasClient.scanResource(
                  source,
                  resourceId: scannedItem.resourceId,
                  sectionId: scannedItem.sectionId,
                  sectionName: scannedItem.sectionName,
                  loadSidecarMetadata: true,
                  resolvePlayableStreams: false,
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
        _progressController.updateIndexing(
          sourceId: normalizedSourceId,
          current: index + 1,
          total: scannedItems.length,
          detail: '${scannedItem.fileName} 已删除',
        );
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
      _progressController.updateIndexing(
        sourceId: normalizedSourceId,
        current: index + 1,
        total: scannedItems.length,
        detail: effectiveItem.fileName,
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
        scopeKey: existingState?.scopeKey ?? '',
        emptyAutoRebuildAttempted: nextRecords.isNotEmpty
            ? false
            : (existingState?.emptyAutoRebuildAttempted ?? false),
      ),
    );
    _notifyIndexChanged?.call();
    _clearProgressSafely(normalizedSourceId);
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

  String _buildRefreshTaskKey(
    MediaSourceConfig source,
    List<MediaCollection>? scopedCollections,
  ) {
    return '${source.id}|${_buildScopeKey(source, scopedCollections)}';
  }

  Future<List<NasMediaIndexRecord>> _loadScopedRecords(
    MediaSourceConfig source, {
    String? sectionId,
    List<MediaCollection>? scopedCollections,
  }) async {
    final scopeKey = _buildScopeKey(source, scopedCollections);
    final state = await _store.loadSourceState(source.id);
    if (state == null) {
      webDavTrace(
        'indexer.loadScopedRecords.miss',
        fields: {
          'sourceId': source.id,
          'scopeKey': scopeKey,
        },
      );
      return const <NasMediaIndexRecord>[];
    }
    if (state.scopeKey != scopeKey) {
      webDavTrace(
        'indexer.loadScopedRecords.scopeMismatch',
        fields: {
          'sourceId': source.id,
          'storedScopeKey': state.scopeKey,
          'requestedScopeKey': scopeKey,
        },
      );
      return const <NasMediaIndexRecord>[];
    }

    final normalizedSectionId = sectionId?.trim() ?? '';
    final records = await _loadSourceRecordsCached(source.id);
    return records
        .where(
          (record) =>
              normalizedSectionId.isEmpty ||
              record.sectionId == normalizedSectionId,
        )
        .toList(growable: false);
  }

  List<MediaItem> _materializeLibraryItems(List<NasMediaIndexRecord> records) {
    final nonSeriesItems = <MediaItem>[];
    final groups = _groupSeriesRecords(records);
    final groupedResourceIds = groups
        .expand((group) => group.records.map((record) => record.resourceId))
        .toSet();

    for (final record in records) {
      if (!groupedResourceIds.contains(record.resourceId)) {
        nonSeriesItems.add(record.item);
      }
    }

    final seriesItems = groups.map(_buildSeriesItem);
    final allItems = [...nonSeriesItems, ...seriesItems];
    allItems.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return allItems;
  }

  List<_SeriesRecordGroup> _groupSeriesRecords(
      List<NasMediaIndexRecord> records) {
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
      webDavTrace(
        'indexer.groupSeries.record',
        fields: {
          'resourceId': record.resourceId,
          'path': record.resourcePath,
          'title': record.item.title,
          'seriesTitle': title,
          'groupKey': key,
          'season': record.item.seasonNumber ?? record.recognizedSeasonNumber,
          'episode':
              record.item.episodeNumber ?? record.recognizedEpisodeNumber,
        },
      );
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
    webDavTrace(
      'indexer.groupSeries.done',
      fields: {
        'groupCount': groups.length,
        'groups': groups
            .map((group) => '${group.title}:${group.records.length}')
            .toList(),
      },
    );
    return groups;
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
    final structureSeriesTitle = _seriesTitleFromStructurePath(
      record,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
    final parentLooksLikeSeason =
        _looksLikeSeasonFolderLabel(record.parentTitle.trim());
    final prefersStructureGrouping =
        _prefersStructureRootSeriesGrouping(record, structureSeriesTitle);
    final hasCanonicalIds = record.item.imdbId.trim().isNotEmpty ||
        record.item.tmdbId.trim().isNotEmpty ||
        record.item.doubanId.trim().isNotEmpty;
    if (prefersStructureGrouping && structureSeriesTitle.isNotEmpty) {
      final normalizedParentTitle = _normalizeMetadataQueryToken(parentTitle);
      final normalizedStructureTitle =
          _normalizeMetadataQueryToken(structureSeriesTitle);
      if (itemType == 'episode' &&
          parentTitle.isNotEmpty &&
          !parentLooksLikeSeason &&
          normalizedParentTitle.isNotEmpty &&
          normalizedParentTitle == normalizedStructureTitle) {
        return parentTitle;
      }
      return structureSeriesTitle;
    }
    if (itemType == 'episode' &&
        hasCanonicalIds &&
        parentTitle.isNotEmpty &&
        !parentLooksLikeSeason) {
      return parentTitle;
    }
    if (itemType == 'episode') {
      if (parentTitle.isNotEmpty && !parentLooksLikeSeason) {
        return parentTitle;
      }
      if (structureSeriesTitle.isNotEmpty) {
        return structureSeriesTitle;
      }
      if (recognizedTitle.isNotEmpty) {
        return recognizedTitle;
      }
    }
    if (record.preferSeries && parentTitle.isNotEmpty) {
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
    NasMediaIndexRecord record, [
    String? resolvedStructureTitle,
  ]) {
    if (record.item.sourceKind != MediaSourceKind.nas) {
      return false;
    }
    final structureTitle =
        (resolvedStructureTitle ?? _seriesTitleFromStructurePath(record))
            .trim();
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

  String _seriesTitleFromStructurePath(
    NasMediaIndexRecord record, {
    List<String> seriesTitleFilterKeywords = const [],
  }) {
    final resourceSegments = _pathSegments(record.resourcePath);
    if (resourceSegments.isEmpty) {
      return '';
    }

    final hasSeasonHint = record.item.seasonNumber != null ||
        record.recognizedSeasonNumber != null;
    final itemType = record.item.itemType.trim().toLowerCase();
    final sectionSegments = _pathSegments(_uriPath(record.sectionId));

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
        return _cleanIndexedTitleLabel(sectionSegments.last);
      }
      return '';
    }

    final stoppedTitle = _stoppedSeriesTitleByFilteredDirectory(
      relativeDirectories: relativeDirectories,
      fileFallbackTitle: _cleanIndexedTitleLabel(
        record.recognizedTitle.trim().isNotEmpty
            ? record.recognizedTitle
            : record.originalFileName,
      ),
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
    if (stoppedTitle != null &&
        (hasSeasonHint || record.preferSeries || itemType == 'episode')) {
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
      return _cleanIndexedTitleLabel(sectionSegments.last);
    }

    final trailingStructureRoot =
        _nearestNonSeasonDirectory(relativeDirectories);
    if (trailingStructureRoot.isNotEmpty &&
        (hasSeasonHint || record.preferSeries || itemType == 'episode')) {
      return _cleanIndexedTitleLabel(trailingStructureRoot);
    }

    if (relativeDirectories.isNotEmpty) {
      return _cleanIndexedTitleLabel(relativeDirectories.first);
    }

    if (hasSeasonHint && sectionSegments.isNotEmpty) {
      return _cleanIndexedTitleLabel(sectionSegments.last);
    }
    return '';
  }

  List<String> _seriesStructureRootSegments(
    NasMediaIndexRecord record, {
    List<String> seriesTitleFilterKeywords = const [],
  }) {
    final resourceSegments = _pathSegments(record.resourcePath);
    if (resourceSegments.isEmpty) {
      return const [];
    }

    final hasSeasonHint = record.item.seasonNumber != null ||
        record.recognizedSeasonNumber != null;
    final itemType = record.item.itemType.trim().toLowerCase();
    final sectionSegments = _pathSegments(_uriPath(record.sectionId));

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
      return const [];
    }

    final stoppedRootSegments = _stoppedSeriesRootSegmentsByFilteredDirectory(
      relativeDirectories: relativeDirectories,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
    if (stoppedRootSegments != null &&
        (hasSeasonHint || record.preferSeries || itemType == 'episode')) {
      return stoppedRootSegments;
    }

    final seasonDirectoryIndex =
        relativeDirectories.indexWhere(_looksLikeSeasonFolderLabel);
    if (seasonDirectoryIndex > 0) {
      return relativeDirectories.sublist(0, seasonDirectoryIndex);
    }
    if (seasonDirectoryIndex == 0) {
      return const [];
    }

    final trailingRootIndex = _lastNonSeasonDirectoryIndex(relativeDirectories);
    if (trailingRootIndex >= 0 &&
        (hasSeasonHint || record.preferSeries || itemType == 'episode')) {
      return relativeDirectories.sublist(0, trailingRootIndex + 1);
    }
    return const [];
  }

  bool _shouldFlattenSingleSeasonGroup(
    _SeriesRecordGroup group,
    Map<int, List<NasMediaIndexRecord>> seasonGroups,
  ) {
    if (seasonGroups.length != 1) {
      return false;
    }
    final onlySeasonRecords = seasonGroups.values.first;
    return !_hasExplicitSeasonDirectory(onlySeasonRecords);
  }

  bool _hasExplicitSeasonDirectory(Iterable<NasMediaIndexRecord> records) {
    for (final record in records) {
      if (_recordHasExplicitSeasonDirectory(record)) {
        return true;
      }
    }
    return false;
  }

  bool _recordHasExplicitSeasonDirectory(NasMediaIndexRecord record) {
    final resourceSegments = _pathSegments(record.resourcePath);
    if (resourceSegments.isEmpty) {
      return false;
    }

    final sectionSegments = _pathSegments(_uriPath(record.sectionId));
    var commonLength = 0;
    while (commonLength < sectionSegments.length &&
        commonLength < resourceSegments.length &&
        sectionSegments[commonLength] == resourceSegments[commonLength]) {
      commonLength += 1;
    }

    final relativeDirectories = resourceSegments.length <= commonLength + 1
        ? const <String>[]
        : resourceSegments.sublist(commonLength, resourceSegments.length - 1);
    return relativeDirectories.any(_looksLikeSeasonFolderLabel);
  }

  String _nearestNonSeasonDirectory(Iterable<String> directories) {
    final normalized = directories
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    for (var index = normalized.length - 1; index >= 0; index--) {
      final candidate = normalized[index];
      if (_looksLikeSeasonFolderLabel(candidate)) {
        continue;
      }
      return candidate;
    }
    return '';
  }

  int _lastNonSeasonDirectoryIndex(List<String> directories) {
    for (var index = directories.length - 1; index >= 0; index--) {
      if (_looksLikeSeasonFolderLabel(directories[index])) {
        continue;
      }
      return index;
    }
    return -1;
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
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return const [];
    }
    final settings = _readSettings();
    for (final candidate in settings.mediaSources) {
      if (candidate.id == normalizedSourceId &&
          candidate.kind == MediaSourceKind.nas) {
        return candidate.normalizedWebDavSeriesTitleFilterKeywords;
      }
    }
    return const [];
  }

  String? _stoppedSeriesTitleByFilteredDirectory({
    required List<String> relativeDirectories,
    required String fileFallbackTitle,
    required List<String> seriesTitleFilterKeywords,
  }) {
    if (seriesTitleFilterKeywords.isEmpty || relativeDirectories.isEmpty) {
      return null;
    }
    var lastInferredTitle = fileFallbackTitle.trim();
    var hitFilteredDirectory = false;
    for (var index = relativeDirectories.length - 1; index >= 0; index--) {
      final rawDirectory = relativeDirectories[index].trim();
      if (rawDirectory.isEmpty || _looksLikeSeasonFolderLabel(rawDirectory)) {
        continue;
      }
      final cleanedDirectory = _cleanIndexedTitleLabel(rawDirectory);
      if (cleanedDirectory.isEmpty) {
        continue;
      }
      if (_matchesSeriesTitleFilterKeyword(
        rawDirectory,
        cleanedValue: cleanedDirectory,
        seriesTitleFilterKeywords: seriesTitleFilterKeywords,
      )) {
        hitFilteredDirectory = true;
        break;
      }
      lastInferredTitle = cleanedDirectory;
    }
    if (!hitFilteredDirectory || lastInferredTitle.isEmpty) {
      return null;
    }
    return lastInferredTitle;
  }

  List<String>? _stoppedSeriesRootSegmentsByFilteredDirectory({
    required List<String> relativeDirectories,
    required List<String> seriesTitleFilterKeywords,
  }) {
    if (seriesTitleFilterKeywords.isEmpty || relativeDirectories.isEmpty) {
      return null;
    }
    int? filteredIndex;
    int? lastUsableIndex;
    for (var index = relativeDirectories.length - 1; index >= 0; index--) {
      final rawDirectory = relativeDirectories[index].trim();
      if (rawDirectory.isEmpty || _looksLikeSeasonFolderLabel(rawDirectory)) {
        continue;
      }
      final cleanedDirectory = _cleanIndexedTitleLabel(rawDirectory);
      if (cleanedDirectory.isEmpty) {
        continue;
      }
      if (_matchesSeriesTitleFilterKeyword(
        rawDirectory,
        cleanedValue: cleanedDirectory,
        seriesTitleFilterKeywords: seriesTitleFilterKeywords,
      )) {
        filteredIndex = index;
        break;
      }
      lastUsableIndex = index;
    }
    if (filteredIndex == null) {
      return null;
    }
    if (lastUsableIndex == null || lastUsableIndex <= filteredIndex) {
      return const [];
    }
    return relativeDirectories.sublist(filteredIndex + 1, lastUsableIndex + 1);
  }

  bool _matchesSeriesTitleFilterKeyword(
    String rawValue, {
    required String cleanedValue,
    required List<String> seriesTitleFilterKeywords,
  }) {
    if (seriesTitleFilterKeywords.isEmpty) {
      return false;
    }
    final haystacks = <String>{
      rawValue.trim().toLowerCase(),
      cleanedValue.trim().toLowerCase(),
    }..removeWhere((value) => value.isEmpty);
    return seriesTitleFilterKeywords.any(
      (keyword) => haystacks.any((value) => value.contains(keyword)),
    );
  }

  String _uriPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.path.isNotEmpty) {
      return uri.path;
    }
    return trimmed;
  }

  List<String> _pathSegments(String value) {
    return value
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .map((segment) {
      try {
        return Uri.decodeComponent(segment);
      } catch (_) {
        return segment;
      }
    }).toList(growable: false);
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
    final structureTitle = _seriesTitleFromStructurePath(
      record,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    ).trim();
    if (!_prefersStructureRootSeriesGrouping(record, structureTitle)) {
      return '';
    }
    final rootSegments = _seriesStructureRootSegments(
      record,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
    if (rootSegments.isEmpty) {
      return '';
    }
    final normalizedPath =
        rootSegments.map((segment) => segment.toLowerCase()).join('/');
    return 'structure:${record.sectionId.trim()}|$normalizedPath';
  }

  MediaItem _buildSeriesItem(_SeriesRecordGroup group) {
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
    final ratingLabels = _mergeLabels(
      const [],
      records.expand((record) => record.item.ratingLabels).toList(),
    );
    final genres =
        _dedupe(records.expand((record) => record.item.genres).toList());
    final directors =
        _dedupe(records.expand((record) => record.item.directors).toList());
    final actors =
        _dedupe(records.expand((record) => record.item.actors).toList());
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
    webDavTrace(
      'indexer.buildSeriesItem',
      fields: {
        'title': seriesItem.title,
        'id': seriesItem.id,
        'recordCount': records.length,
        'actualAddress': seriesItem.actualAddress,
      },
    );
    return seriesItem;
  }

  MediaItem _buildSeasonItem(
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
      genres: _dedupe(records.expand((record) => record.item.genres).toList()),
      directors:
          _dedupe(records.expand((record) => record.item.directors).toList()),
      actors: _dedupe(records.expand((record) => record.item.actors).toList()),
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
      ratingLabels: _mergeLabels(
          const [], records.expand((e) => e.item.ratingLabels).toList()),
      addedAt: sorted.first.item.addedAt,
    );
    webDavTrace(
      'indexer.buildSeasonItem',
      fields: {
        'seriesTitle': group.title,
        'seasonTitle': seasonItem.title,
        'seasonNumber': seasonNumber,
        'recordCount': records.length,
        'actualAddress': seasonItem.actualAddress,
      },
    );
    return seasonItem;
  }

  List<MediaItem> _materializeEpisodeItems(
      Iterable<NasMediaIndexRecord> records) {
    final items = records.map((record) => record.item).toList(growable: false)
      ..sort((left, right) {
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
        return left.title.compareTo(right.title);
      });
    return items;
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
    return lastSegment;
  }

  String _buildSeriesItemId(String seriesKey) {
    return '$_seriesGroupPrefix|${Uri.encodeComponent(seriesKey)}';
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

  bool _looksLikeSeasonFolderLabel(String value) {
    return looksLikeSeasonFolderLabel(value);
  }

  int? _parseSeasonNumberFromLabel(String value) {
    return parseSeasonNumberFromFolderLabel(value);
  }

  bool _looksLikeNumericTopicSeason(String value) {
    return looksLikeNumericTopicSeason(value);
  }

  String _buildSeasonItemId(String seriesKey, int seasonNumber) {
    return '$_seasonGroupPrefix|${Uri.encodeComponent(seriesKey)}|$seasonNumber';
  }

  List<int> _resolveWritableRecordIndices(
      List<NasMediaIndexRecord> records, String resourceId,
      {required String resourceScopePath}) {
    final normalizedResourceId = resourceId.trim();
    if (normalizedResourceId.isEmpty) {
      return const [];
    }

    final exactIndices = <int>[];
    for (var index = 0; index < records.length; index++) {
      if (records[index].resourceId == normalizedResourceId) {
        exactIndices.add(index);
      }
    }
    if (exactIndices.isNotEmpty) {
      return exactIndices;
    }
    if (!_isSyntheticGroupId(normalizedResourceId)) {
      return const [];
    }

    final recordIndexByResourceId = <String, int>{};
    for (var index = 0; index < records.length; index++) {
      recordIndexByResourceId[records[index].resourceId] = index;
    }
    final groups = _groupSeriesRecords(records);

    if (normalizedResourceId.startsWith(_seriesGroupPrefix)) {
      final group = groups.where(
        (candidate) => candidate.seriesItemId == normalizedResourceId,
      );
      if (group.isEmpty) {
        return const [];
      }
      final indices = group.first.records
          .map((record) => recordIndexByResourceId[record.resourceId])
          .whereType<int>()
          .toList(growable: false);
      return _filterRecordIndicesByScope(
        records,
        indices,
        resourceScopePath: resourceScopePath,
      );
    }

    final parsed = _parseSeasonGroupId(normalizedResourceId);
    if (parsed == null) {
      return const [];
    }
    final group = groups.where(
      (candidate) => candidate.seriesKey == parsed.seriesKey,
    );
    if (group.isEmpty) {
      return const [];
    }
    final seasonRecords =
        group.first.seasonGroups[parsed.seasonNumber] ?? const [];
    final indices = seasonRecords
        .map((record) => recordIndexByResourceId[record.resourceId])
        .whereType<int>()
        .toList(growable: false);
    return _filterRecordIndicesByScope(
      records,
      indices,
      resourceScopePath: resourceScopePath,
    );
  }

  bool _isSyntheticGroupId(String id) {
    return id.startsWith(_seriesGroupPrefix) ||
        id.startsWith(_seasonGroupPrefix);
  }

  _ParsedSeasonGroupId? _parseSeasonGroupId(String id) {
    final parts = id.split('|');
    if (parts.length != 3 || parts.first != _seasonGroupPrefix) {
      return null;
    }
    final seriesKey = Uri.decodeComponent(parts[1]);
    final seasonNumber = int.tryParse(parts[2]);
    if (seasonNumber == null) {
      return null;
    }
    return _ParsedSeasonGroupId(
      seriesKey: seriesKey,
      seasonNumber: seasonNumber,
    );
  }

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
    if (normalizedResourceId.startsWith(_seriesGroupPrefix)) {
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

  String _cleanIndexedTitleLabel(String value) {
    return stripEmbeddedExternalIdTags(value)
        .replaceAll(RegExp(r'[_\.]+'), ' ')
        .replaceAll(RegExp(r'[【\[\(].*?[】\]\)]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
      playbackItemId: existing.item.playbackItemId,
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

  Future<NasMediaIndexRecord> _indexScannedItem(
    MediaSourceConfig source,
    WebDavScannedItem scannedItem, {
    required DateTime indexedAt,
    required String fingerprint,
    NasMediaIndexRecord? existingRecord,
    bool applyOnlineMetadata = true,
    bool markSidecarAttempt = false,
  }) async {
    final settings = _readSettings();
    final recognition = NasMediaRecognizer.recognize(
      scannedItem.actualAddress,
      seriesTitleFilterKeywords:
          source.normalizedWebDavSeriesTitleFilterKeywords,
    );
    final seed = scannedItem.metadataSeed;
    final structureInferredEpisodeLike =
        _isStructureInferredEpisodeLike(source, scannedItem);

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
            if (itemType.trim().toLowerCase() == 'episode' &&
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
            if (itemType.trim().toLowerCase() == 'episode' &&
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
        !_hasRatingLabelKeyword(ratingLabels, 'imdb') &&
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
        return _cleanIndexedTitleLabel(sectionSegments.last);
      }
      return '';
    }

    final stoppedTitle = _stoppedSeriesTitleByFilteredDirectory(
      relativeDirectories: relativeDirectories,
      fileFallbackTitle: _cleanIndexedTitleLabel(fileFallbackTitle),
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
    if (scopedCollections != null && scopedCollections.isNotEmpty) {
      final ids = scopedCollections
          .map((item) => item.id.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
        ..sort();
      return 'collections|${ids.join(',')}|structure:${source.webDavStructureInferenceEnabled}|scrape:${source.webDavSidecarScrapingEnabled}|exclude:$excludedKeywords|schema:$_webDavMetadataSchemaVersion';
    }
    final root = source.libraryPath.trim().isNotEmpty
        ? source.libraryPath.trim()
        : source.endpoint.trim();
    return 'root|$root|structure:${source.webDavStructureInferenceEnabled}|scrape:${source.webDavSidecarScrapingEnabled}|exclude:$excludedKeywords|schema:$_webDavMetadataSchemaVersion';
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

  static List<String> _dedupe(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  static List<String> _mergeLabels(
    List<String> current,
    List<String> next,
  ) {
    return _dedupe([...current, ...next]);
  }

  bool _hasOnlineMetadataEnabled(AppSettings settings) {
    return settings.wmdbMetadataMatchEnabled ||
        (settings.tmdbMetadataMatchEnabled &&
            settings.tmdbReadAccessToken.trim().isNotEmpty) ||
        _shouldUseStandaloneImdbRating(settings);
  }

  bool _hasAttemptStatus(NasMetadataFetchStatus? status) {
    return (status ?? NasMetadataFetchStatus.never).hasAttempted;
  }

  bool _hasCompletedOnlineAttempts(
    NasMediaIndexRecord? record,
    AppSettings settings,
  ) {
    if (record == null) {
      return false;
    }
    if (settings.wmdbMetadataMatchEnabled && !record.wmdbStatus.hasAttempted) {
      return false;
    }
    if (settings.tmdbMetadataMatchEnabled &&
        settings.tmdbReadAccessToken.trim().isNotEmpty &&
        !record.tmdbStatus.hasAttempted) {
      return false;
    }
    if (_shouldUseStandaloneImdbRating(settings) &&
        !record.imdbStatus.hasAttempted) {
      return false;
    }
    return true;
  }

  bool _hasPendingOnlineAttempts(
    NasMediaIndexRecord record,
    AppSettings settings,
  ) {
    return !_hasCompletedOnlineAttempts(record, settings);
  }

  bool _shouldUseStandaloneImdbRating(AppSettings settings) {
    return settings.imdbRatingMatchEnabled &&
        (!settings.tmdbMetadataMatchEnabled ||
            settings.tmdbReadAccessToken.trim().isEmpty);
  }

  void _clearProgressSafely(String sourceId) {
    try {
      _progressController.clear(sourceId);
    } catch (_) {
      // The provider may already be disposed in tests or after page teardown.
    }
  }

  static bool _hasRatingLabelKeyword(
    Iterable<String> labels,
    String keyword,
  ) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.isEmpty) {
      return false;
    }
    return labels.any(
      (label) => label.trim().toLowerCase().contains(normalizedKeyword),
    );
  }

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
    for (final record in records) {
      final seasonNumber =
          record.item.seasonNumber ?? record.recognizedSeasonNumber ?? 1;
      grouped
          .putIfAbsent(seasonNumber, () => <NasMediaIndexRecord>[])
          .add(record);
    }
    return grouped;
  }
}

class _ParsedSeasonGroupId {
  const _ParsedSeasonGroupId({
    required this.seriesKey,
    required this.seasonNumber,
  });

  final String seriesKey;
  final int seasonNumber;
}

class _RefreshPhaseResult {
  const _RefreshPhaseResult({
    required this.enrichmentCandidates,
  });

  final List<WebDavScannedItem> enrichmentCandidates;
}

enum _RefreshTaskMode {
  incremental,
  forceFull,
}

class _RefreshTaskHandle {
  const _RefreshTaskHandle({
    required this.future,
    required this.mode,
    required this.controller,
  });

  final Future<void> future;
  final _RefreshTaskMode mode;
  final _RefreshTaskController controller;

  void cancel() {
    controller.cancel();
  }
}

class _RefreshTaskController {
  bool _isCancelled = false;

  bool get cancelled => _isCancelled;

  bool Function() get isCancelled => () => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const _RefreshCancelledException();
    }
  }
}

class _RefreshCancelledException implements Exception {
  const _RefreshCancelledException();
}
