import 'dart:collection';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/webdav_trace.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/quark_external_storage_client.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_naming.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

part 'nas_media_indexer_refresh_support.dart';
part 'nas_media_indexer_grouping.dart';
part 'nas_media_indexer_refresh_flow.dart';
part 'nas_media_indexer_storage_access.dart';
part 'nas_media_indexer_indexing.dart';

final nasMediaIndexerProvider = Provider<NasMediaIndexer>((ref) {
  final indexer = NasMediaIndexer(
    store: ref.read(nasMediaIndexStoreProvider),
    webDavNasClient: ref.read(webDavNasClientProvider),
    quarkExternalStorageClient: ref.read(quarkExternalStorageClientProvider),
    wmdbMetadataClient: ref.read(wmdbMetadataClientProvider),
    tmdbMetadataClient: ref.read(tmdbMetadataClientProvider),
    imdbRatingClient: ref.read(imdbRatingClientProvider),
    readSettings: () => ref.read(appSettingsProvider),
    progressController: ref.read(webDavScrapeProgressProvider.notifier),
    notifyIndexChanged: () {
      ref.read(nasMediaIndexRevisionProvider.notifier).state++;
    },
  );
  ref.onDispose(() {
    unawaited(indexer.dispose());
  });
  return indexer;
});

class NasMediaIndexer {
  NasMediaIndexer({
    required NasMediaIndexStore store,
    required WebDavNasClient webDavNasClient,
    QuarkExternalStorageClient? quarkExternalStorageClient,
    required WmdbMetadataClient wmdbMetadataClient,
    required TmdbMetadataClient tmdbMetadataClient,
    required ImdbRatingClient imdbRatingClient,
    required AppSettings Function() readSettings,
    required WebDavScrapeProgressController progressController,
    void Function()? notifyIndexChanged,
    NasMediaIndexerConcurrencyLimits concurrencyLimits =
        const NasMediaIndexerConcurrencyLimits(),
  })  : _store = store,
        _webDavNasClient = webDavNasClient,
        _quarkExternalStorageClient = quarkExternalStorageClient,
        _wmdbMetadataClient = wmdbMetadataClient,
        _tmdbMetadataClient = tmdbMetadataClient,
        _imdbRatingClient = imdbRatingClient,
        _readSettings = readSettings,
        _progressController = progressController,
        _notifyIndexChanged = notifyIndexChanged,
        _sourceBudget = _ConcurrencyBudget(
          concurrencyLimits.normalizedSourceRefreshConcurrency,
        ),
        _collectionBudget = _ConcurrencyBudget(
          concurrencyLimits.normalizedCollectionRefreshConcurrency,
        ),
        _enrichmentBudget = _ConcurrencyBudget(
          concurrencyLimits.normalizedEnrichmentConcurrency,
        );

  static const int _defaultRefreshLimitPerCollection = 1200;
  static const String _seriesGroupPrefix = 'webdav-series';
  static const String _seasonGroupPrefix = 'webdav-season';
  static const String _webDavMetadataSchemaVersion = 'webdav-v6';
  final NasMediaIndexStore _store;
  final WebDavNasClient _webDavNasClient;
  final QuarkExternalStorageClient? _quarkExternalStorageClient;
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
  bool _isDisposed = false;
  final _ConcurrencyBudget _sourceBudget;
  final _ConcurrencyBudget _collectionBudget;
  final _ConcurrencyBudget _enrichmentBudget;

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await cancelAllRefreshTasks(includeForceFull: true);
  }

  Future<void> cancelAllRefreshTasks({
    bool includeForceFull = false,
  }) async {
    final handles = <_RefreshTaskHandle>{
      ..._activeRefreshTasks.values,
      ..._backgroundEnrichmentTasks.values,
    }.where((handle) {
      if (includeForceFull) {
        return true;
      }
      return handle.mode != _RefreshTaskMode.forceFull;
    }).toList(growable: false);
    if (handles.isEmpty) {
      return;
    }

    webDavTrace(
      'indexer.refresh.cancelAll',
      fields: {
        'activeCount': _activeRefreshTasks.length,
        'backgroundCount': _backgroundEnrichmentTasks.length,
        'includeForceFull': includeForceFull,
        'cancelledCount': handles.length,
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

  Future<void> clearSource(String sourceId) =>
      _NasMediaIndexerRefreshFlowX(this).clearSource(sourceId);

  Future<bool> tryAutoRebuildOnEmpty(
    MediaSourceConfig source, {
    List<MediaCollection>? scopedCollections,
  }) =>
      _NasMediaIndexerRefreshFlowX(this).tryAutoRebuildOnEmpty(
        source,
        scopedCollections: scopedCollections,
      );

  Future<void> removeResourceScope({
    required String sourceId,
    required String resourcePath,
  }) =>
      _NasMediaIndexerRefreshFlowX(this).removeResourceScope(
        sourceId: sourceId,
        resourcePath: resourcePath,
      );

  Future<NasMediaIndexRecord?> loadRecord({
    required String sourceId,
    required String resourceId,
  }) =>
      _NasMediaIndexerRefreshFlowX(this).loadRecord(
        sourceId: sourceId,
        resourceId: resourceId,
      );

  Future<List<NasMediaIndexRecord>> loadRecordsInScope({
    required String sourceId,
    required String resourcePath,
  }) =>
      _NasMediaIndexerRefreshFlowX(this).loadRecordsInScope(
        sourceId: sourceId,
        resourcePath: resourcePath,
      );

  Future<List<NasMediaIndexRecord>> loadSourceRecords(String sourceId) =>
      _loadSourceRecordsCached(sourceId);

  Future<MediaDetailTarget?> enrichDetailTargetMetadataIfNeeded(
    MediaDetailTarget target,
  ) =>
      _NasMediaIndexerRefreshFlowX(this).enrichDetailTargetMetadataIfNeeded(
        target,
      );

  Future<void> markDetailTargetMetadataManuallyManaged(
    MediaDetailTarget target,
  ) =>
      _NasMediaIndexerRefreshFlowX(this)
          .markDetailTargetMetadataManuallyManaged(target);

  Future<List<MediaItem>> loadLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    List<MediaCollection>? scopedCollections,
    int limit = 200,
  }) =>
      _NasMediaIndexerRefreshFlowX(this).loadLibrary(
        source,
        sectionId: sectionId,
        scopedCollections: scopedCollections,
        limit: limit,
      );

  Future<List<MediaItem>> loadChildren(
    MediaSourceConfig source, {
    required String parentId,
    String sectionId = '',
    List<MediaCollection>? scopedCollections,
    int limit = 200,
  }) =>
      _NasMediaIndexerRefreshFlowX(this).loadChildren(
        source,
        parentId: parentId,
        sectionId: sectionId,
        scopedCollections: scopedCollections,
        limit: limit,
      );

  Future<List<MediaItem>> loadEpisodeVariants(
    MediaSourceConfig source, {
    required String itemId,
    String sectionId = '',
    List<MediaCollection>? scopedCollections,
  }) =>
      _NasMediaIndexerRefreshFlowX(this).loadEpisodeVariants(
        source,
        itemId: itemId,
        sectionId: sectionId,
        scopedCollections: scopedCollections,
      );

  Future<List<MediaItem>> loadCachedLibraryMatchItems(
    MediaSourceConfig source, {
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
  }) =>
      _NasMediaIndexerRefreshFlowX(this).loadCachedLibraryMatchItems(
        source,
        doubanId: doubanId,
        imdbId: imdbId,
        tmdbId: tmdbId,
        tvdbId: tvdbId,
        wikidataId: wikidataId,
      );

  Future<void> refreshSource(
    MediaSourceConfig source, {
    List<MediaCollection>? scopedCollections,
    int limitPerCollection = NasMediaIndexer._defaultRefreshLimitPerCollection,
    bool forceFullRescan = false,
  }) =>
      _NasMediaIndexerRefreshFlowX(this).refreshSource(
        source,
        scopedCollections: scopedCollections,
        limitPerCollection: limitPerCollection,
        forceFullRescan: forceFullRescan,
      );

  Future<MediaDetailTarget?> applyManualMetadata({
    required MediaDetailTarget target,
    required String searchQuery,
    MetadataMatchResult? metadataMatch,
    ImdbRatingMatch? imdbRatingMatch,
  }) =>
      _NasMediaIndexerRefreshFlowX(this).applyManualMetadata(
        target: target,
        searchQuery: searchQuery,
        metadataMatch: metadataMatch,
        imdbRatingMatch: imdbRatingMatch,
      );

  String _resolvedMetadataItemType(MetadataMatchResult? metadataMatch) =>
      _NasMediaIndexerRefreshFlowX(this)._resolvedMetadataItemType(
        metadataMatch,
      );

  bool _isStructureInferredEpisodeLike(
    MediaSourceConfig source,
    WebDavScannedItem item,
  ) =>
      _NasMediaIndexerRefreshFlowX(this)._isStructureInferredEpisodeLike(
        source,
        item,
      );

  bool _shouldUseStructureInferredSeriesLevelScrape(
    MediaSourceConfig source,
    WebDavScannedItem item,
  ) =>
      _NasMediaIndexerRefreshFlowX(this)
          ._shouldUseStructureInferredSeriesLevelScrape(source, item);

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
    return _NasMediaIndexerGroupingSupportX(this)
        .materializeLibraryItems(records);
  }

  List<_SeriesRecordGroup> _groupSeriesRecords(
    List<NasMediaIndexRecord> records,
  ) {
    return _NasMediaIndexerGroupingSupportX(this).groupSeriesRecords(records);
  }

  MediaItem _buildSeriesItem(_SeriesRecordGroup group) {
    return _NasMediaIndexerGroupingSupportX(this).buildSeriesItem(group);
  }

  MediaItem _buildSeasonItem(
    _SeriesRecordGroup group,
    int seasonNumber,
    List<NasMediaIndexRecord> records,
  ) {
    return _NasMediaIndexerGroupingSupportX(
      this,
    ).buildSeasonItem(group, seasonNumber, records);
  }

  List<MediaItem> _materializeEpisodeItems(
    Iterable<NasMediaIndexRecord> records,
  ) {
    return _NasMediaIndexerGroupingSupportX(this)
        .materializeEpisodeItems(records);
  }

  int? _resolvedRecordSeasonNumber(NasMediaIndexRecord record) {
    return record.item.seasonNumber ?? record.recognizedSeasonNumber;
  }

  int? _resolvedRecordEpisodeNumber(NasMediaIndexRecord record) {
    return record.item.episodeNumber ?? record.recognizedEpisodeNumber;
  }

  List<NasMediaIndexRecord> _sortEpisodeRecordsForDisplay(
    Iterable<NasMediaIndexRecord> records,
  ) {
    final sorted = records.toList(growable: false)
      ..sort(_compareEpisodeRecordsForDisplay);
    return sorted;
  }

  int _compareEpisodeRecordsForDisplay(
    NasMediaIndexRecord left,
    NasMediaIndexRecord right,
  ) {
    final seasonComparison = (_resolvedRecordSeasonNumber(left) ?? 0)
        .compareTo(_resolvedRecordSeasonNumber(right) ?? 0);
    if (seasonComparison != 0) {
      return seasonComparison;
    }

    final episodeComparison = (_resolvedRecordEpisodeNumber(left) ?? 0)
        .compareTo(_resolvedRecordEpisodeNumber(right) ?? 0);
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

  String _nearestNonSeasonDirectory(Iterable<String> directories) {
    return _NasMediaIndexerGroupingSupportX(this)
        .nearestNonSeasonDirectoryForMain(directories);
  }

  String? _stoppedSeriesTitleByFilteredDirectory({
    required List<String> relativeDirectories,
    required String fileFallbackTitle,
    required List<String> seriesTitleFilterKeywords,
  }) {
    return _NasMediaIndexerGroupingSupportX(this)
        .stoppedSeriesTitleByFilteredDirectoryForMain(
      relativeDirectories: relativeDirectories,
      fileFallbackTitle: fileFallbackTitle,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
  }

  bool _matchesSeriesTitleFilterKeyword(
    String rawValue, {
    required String cleanedValue,
    required List<String> seriesTitleFilterKeywords,
  }) {
    return _NasMediaIndexerGroupingSupportX(this)
        .matchesSeriesTitleFilterKeywordForMain(
      rawValue,
      cleanedValue: cleanedValue,
      seriesTitleFilterKeywords: seriesTitleFilterKeywords,
    );
  }

  bool _canUseSeasonDirectoryAsSeriesRoot(
    String rawDirectory, {
    required bool parentMatchesFilter,
  }) {
    return _NasMediaIndexerGroupingSupportX(this)
        .canUseSeasonDirectoryAsSeriesRootForMain(
      rawDirectory,
      parentMatchesFilter: parentMatchesFilter,
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

  bool _looksLikeSeasonFolderLabel(String value) {
    return looksLikeSeasonFolderLabel(value);
  }

  int? _parseSeasonNumberFromLabel(String value) {
    return parseSeasonNumberFromFolderLabel(value);
  }

  bool _looksLikeNumericTopicSeason(String value) {
    return looksLikeNumericTopicSeason(value);
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
  }) =>
      _NasMediaIndexerStorageAccessX(this)._buildManualMetadataTarget(
        target: target,
        records: records,
        selectedResourceIds: selectedResourceIds,
        resourceId: resourceId,
        resourcePath: resourcePath,
        searchQuery: searchQuery,
      );

  WebDavScannedItem _buildScannedItemFromRecord(NasMediaIndexRecord record) =>
      _NasMediaIndexerStorageAccessX(this)._buildScannedItemFromRecord(record);

  List<int> _filterRecordIndicesByScope(
    List<NasMediaIndexRecord> records,
    List<int> candidateIndices, {
    required String resourceScopePath,
  }) =>
      _NasMediaIndexerStorageAccessX(this)._filterRecordIndicesByScope(
        records,
        candidateIndices,
        resourceScopePath: resourceScopePath,
      );

  bool _isRecordWithinScope(
    NasMediaIndexRecord record, {
    required List<String> scopeSegments,
  }) =>
      _NasMediaIndexerStorageAccessX(this)._isRecordWithinScope(
        record,
        scopeSegments: scopeSegments,
      );

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
  }) =>
      _NasMediaIndexerStorageAccessX(this)._reuseRecord(
        existing,
        scannedItem: scannedItem,
        source: source,
        indexedAt: indexedAt,
      );
  Future<NasMediaIndexRecord> _indexScannedItem(
    MediaSourceConfig source,
    WebDavScannedItem scannedItem, {
    required DateTime indexedAt,
    required String fingerprint,
    NasMediaIndexRecord? existingRecord,
    bool applyOnlineMetadata = true,
    bool markSidecarAttempt = false,
  }) =>
      _NasMediaIndexerIndexingX(this)._indexScannedItem(
        source,
        scannedItem,
        indexedAt: indexedAt,
        fingerprint: fingerprint,
        existingRecord: existingRecord,
        applyOnlineMetadata: applyOnlineMetadata,
        markSidecarAttempt: markSidecarAttempt,
      );

  String? _fallbackTitleFromFilteredSectionRoot({
    required List<String> sectionSegments,
    required List<String> relativeDirectories,
    required String fileFallbackTitle,
    required List<String> seriesTitleFilterKeywords,
  }) =>
      _NasMediaIndexerIndexingX(this)._fallbackTitleFromFilteredSectionRoot(
        sectionSegments: sectionSegments,
        relativeDirectories: relativeDirectories,
        fileFallbackTitle: fileFallbackTitle,
        seriesTitleFilterKeywords: seriesTitleFilterKeywords,
      );

  String _buildScopeKey(
    MediaSourceConfig source,
    List<MediaCollection>? scopedCollections,
  ) =>
      _NasMediaIndexerIndexingX(this)._buildScopeKey(source, scopedCollections);

  String _buildFingerprint({
    required String sourceId,
    required String resourcePath,
    required DateTime? modifiedAt,
    required int fileSizeBytes,
  }) =>
      _NasMediaIndexerIndexingX(this)._buildFingerprint(
        sourceId: sourceId,
        resourcePath: resourcePath,
        modifiedAt: modifiedAt,
        fileSizeBytes: fileSizeBytes,
      );
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
        settings.imdbRatingMatchEnabled;
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
    if (record.manualMetadataLocked) {
      return true;
    }
    if (settings.wmdbMetadataMatchEnabled && !record.wmdbStatus.hasAttempted) {
      return false;
    }
    if (settings.tmdbMetadataMatchEnabled &&
        settings.tmdbReadAccessToken.trim().isNotEmpty &&
        !record.tmdbStatus.hasAttempted) {
      return false;
    }
    if (settings.imdbRatingMatchEnabled && !record.imdbStatus.hasAttempted) {
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

  void _clearProgressSafely(String sourceId) {
    try {
      _progressController.clear(sourceId);
    } catch (_) {
      // The provider may already be disposed in tests or after page teardown.
    }
  }

  AppSettings _readSettingsForRefresh() {
    if (_isDisposed) {
      throw const _RefreshCancelledException();
    }
    try {
      return _readSettings();
    } catch (error, stackTrace) {
      if (_isProviderContainerDisposedError(error)) {
        throw const _RefreshCancelledException();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _notifyIndexChangedSafely() {
    final notifyIndexChanged = _notifyIndexChanged;
    if (notifyIndexChanged == null || _isDisposed) {
      return;
    }
    try {
      notifyIndexChanged();
    } catch (error, stackTrace) {
      if (_isProviderContainerDisposedError(error)) {
        return;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  bool _isProviderContainerDisposedError(Object error) {
    if (_isDisposed) {
      return true;
    }
    final message = error.toString().toLowerCase();
    if (!message.contains('providercontainer')) {
      return false;
    }
    return message.contains('disposed') ||
        message.contains('dispose was called');
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
  }) =>
      _NasMediaIndexerStorageAccessX(this)._applyManualMetadataToItem(
        item,
        metadataMatch: metadataMatch,
        imdbRatingMatch: imdbRatingMatch,
      );

  MediaItem _applyManualMetadataToGroupedItem(
    MediaItem item, {
    MetadataMatchResult? metadataMatch,
    ImdbRatingMatch? imdbRatingMatch,
  }) =>
      _NasMediaIndexerStorageAccessX(this)._applyManualMetadataToGroupedItem(
        item,
        metadataMatch: metadataMatch,
        imdbRatingMatch: imdbRatingMatch,
      );

  Future<void> _persistSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
  }) =>
      _NasMediaIndexerStorageAccessX(this)._persistSourceRecords(
        sourceId: sourceId,
        records: records,
        state: state,
      );

  Future<List<NasMediaIndexRecord>> _loadSourceRecordsCached(
    String sourceId,
  ) =>
      _NasMediaIndexerStorageAccessX(this)._loadSourceRecordsCached(sourceId);

  Future<_NasLibraryMatchCache> _loadLibraryMatchCache(String sourceId) =>
      _NasMediaIndexerStorageAccessX(this)._loadLibraryMatchCache(sourceId);

  String _resolveLibraryMatchTvdbId(MediaItem item) =>
      _NasMediaIndexerStorageAccessX(this)._resolveLibraryMatchTvdbId(item);

  String _resolveLibraryMatchWikidataId(MediaItem item) =>
      _NasMediaIndexerStorageAccessX(this)._resolveLibraryMatchWikidataId(item);

  Map<String, String> _mergeProviderIdMaps(
    Iterable<Map<String, String>> providerIdMaps,
  ) =>
      _NasMediaIndexerStorageAccessX(this)._mergeProviderIdMaps(
        providerIdMaps,
      );
}
