import 'dart:async';
import 'package:starflow/features/search/application/aliyun_to115_workflow.dart';
import 'package:starflow/features/search/application/aliyun_sync_delete_service.dart';
import 'package:starflow/features/search/application/cloud115_sync_delete_service.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/library/application/app_media_query_service.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/quark_external_storage_client.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

abstract class MediaRepository {
  Future<List<MediaSourceConfig>> fetchSources();

  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  });

  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  });

  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  });

  Future<List<MediaItem>> loadLibraryMatchItems({
    required MediaSourceConfig source,
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
    Iterable<String> titles = const <String>[],
    int year = 0,
    int limit = 2000,
  });

  Future<void> refreshSource({
    required String sourceId,
    bool forceFullRescan = false,
  });

  Future<void> cancelActiveWebDavRefreshes({
    bool includeForceFull = false,
  });

  Future<void> deleteResource({
    required String sourceId,
    required String resourcePath,
    String sectionId = '',
  });

  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  });

  Future<MediaItem?> findById(String id);

  Future<MediaItem?> matchTitle(String title);
}

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => AppMediaRepository(
    ref,
    ref.read(embyApiClientProvider),
    ref.read(webDavNasClientProvider),
    ref.read(nasMediaIndexerProvider),
    ref.read(quarkExternalStorageClientProvider),
    ref.read(quarkSaveClientProvider),
  ),
);

class AppMediaRepository implements MediaRepository {
  AppMediaRepository(
    this.ref,
    this._embyApiClient,
    this._webDavNasClient,
    this._nasMediaIndexer,
    this._quarkExternalStorageClient,
    this._quarkSaveClient,
  ) : _queryService = AppMediaQueryService(
          ref: ref,
          embyApiClient: _embyApiClient,
          webDavNasClient: _webDavNasClient,
          nasMediaIndexer: _nasMediaIndexer,
          quarkExternalStorageClient: _quarkExternalStorageClient,
        );

  final Ref ref;
  final EmbyApiClient _embyApiClient;
  MediaServerClient _serverClient(MediaSourceConfig source) =>
      source.kind == MediaSourceKind.emby
          ? _embyApiClient
          : ref.read(mediaServerClientProvider(source.kind));
  final WebDavNasClient _webDavNasClient;
  final NasMediaIndexer _nasMediaIndexer;
  final QuarkExternalStorageClient _quarkExternalStorageClient;
  final QuarkSaveClient _quarkSaveClient;
  final AppMediaQueryService _queryService;

  List<MediaSourceConfig> get _enabledSources {
    return ref
        .read(appSettingsProvider)
        .mediaSources
        .where((item) => item.enabled)
        .toList();
  }

  String get _quarkCookie {
    return ref.read(appSettingsProvider).networkStorage.quarkCookie.trim();
  }

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
    return _queryService.fetchSources();
  }

  @override
  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async {
    return _queryService.fetchCollections(
      kind: kind,
      sourceId: sourceId,
    );
  }

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    return _queryService.fetchLibrary(
      kind: kind,
      sourceId: sourceId,
      sectionId: sectionId,
      limit: limit,
    );
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    return _queryService.fetchRecentlyAdded(
      kind: kind,
      limit: limit,
    );
  }

  @override
  Future<List<MediaItem>> loadLibraryMatchItems({
    required MediaSourceConfig source,
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
    Iterable<String> titles = const <String>[],
    int year = 0,
    int limit = 2000,
  }) async {
    switch (source.kind) {
      case MediaSourceKind.emby:
      case MediaSourceKind.fntv:
        return _queryService.loadCachedEmbyLibraryMatchItems(
          source,
          titles: titles,
          year: year,
          doubanId: doubanId,
          imdbId: imdbId,
          tmdbId: tmdbId,
          tvdbId: tvdbId,
          wikidataId: wikidataId,
          limit: limit,
        );
      case MediaSourceKind.nas:
        return _nasMediaIndexer.loadCachedLibraryMatchItems(
          source,
          doubanId: doubanId,
          imdbId: imdbId,
          tmdbId: tmdbId,
          tvdbId: tvdbId,
          wikidataId: wikidataId,
        );
      case MediaSourceKind.quark:
        return fetchLibrary(
          kind: MediaSourceKind.quark,
          sourceId: source.id,
          limit: limit,
        );
    }
  }

  @override
  Future<void> refreshSource({
    required String sourceId,
    bool forceFullRescan = false,
  }) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }
    MediaSourceConfig? source;
    for (final candidate in _enabledSources) {
      if (candidate.id == normalizedSourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null) {
      return;
    }

    if ((source.kind == MediaSourceKind.nas &&
            source.endpoint.trim().isNotEmpty) ||
        (source.kind == MediaSourceKind.quark &&
            source.hasConfiguredQuarkFolder)) {
      ref.read(webDavScrapeProgressProvider.notifier).startScanning(
            sourceId: source.id,
            sourceName: source.name,
            totalCollections: 1,
          );
    }

    if (source.kind.isMediaServer) {
      if (!source.hasActiveSession) {
        return;
      }
      await _queryService.refreshEmbySourceCache(source);
      return;
    }

    final previousIndexedRecords = await _nasMediaIndexer.loadSourceRecords(
      source.id,
    );

    if (source.hasExplicitNoSectionsSelected) {
      await _nasMediaIndexer.clearSource(source.id);
      await _clearIndexedSourceLocalState(source.id, previousIndexedRecords);
      return;
    }
    final selectedCollections = await _selectedCollectionsForSource(source);

    if (_hasScopedSections(source) && selectedCollections.isEmpty) {
      await _nasMediaIndexer.clearSource(source.id);
      await _clearIndexedSourceLocalState(source.id, previousIndexedRecords);
      return;
    }
    if (forceFullRescan) {
      await _nasMediaIndexer.clearSource(source.id);
      await ref
          .read(localStorageCacheRepositoryProvider)
          .clearDetailCacheForSource(source.id);
    }
    await _nasMediaIndexer.refreshSource(
      source,
      scopedCollections:
          _hasScopedSections(source) ? selectedCollections : null,
      forceFullRescan: forceFullRescan,
    );
    final nextIndexedRecords = await _nasMediaIndexer.loadSourceRecords(
      source.id,
    );

    if (!forceFullRescan) {
      await _clearRemovedIndexedResources(
        sourceId: source.id,
        previousRecords: previousIndexedRecords,
        nextRecords: nextIndexedRecords,
      );
    }
  }

  Future<void> _clearIndexedSourceLocalState(
    String sourceId,
    List<NasMediaIndexRecord> previousRecords,
  ) async {
    await ref
        .read(localStorageCacheRepositoryProvider)
        .clearDetailCacheForSource(sourceId);
    for (final record in previousRecords) {
      await ref.read(playbackMemoryRepositoryProvider).clearEntriesForResource(
            sourceId: sourceId,
            resourceId: record.resourceId,
            resourcePath: record.resourcePath,
          );
    }
  }

  Future<void> _clearRemovedIndexedResources({
    required String sourceId,
    required List<NasMediaIndexRecord> previousRecords,
    required List<NasMediaIndexRecord> nextRecords,
  }) async {
    if (previousRecords.isEmpty) {
      return;
    }
    final remainingIds = nextRecords
        .map((record) => record.resourceId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final removedRecords = previousRecords
        .where((record) => !remainingIds.contains(record.resourceId.trim()))
        .toList(growable: false);
    if (removedRecords.isEmpty) {
      return;
    }
    for (final record in removedRecords) {
      await ref
          .read(localStorageCacheRepositoryProvider)
          .clearDetailCacheForResource(
            sourceId: sourceId,
            resourceId: record.resourceId,
            resourcePath: record.resourcePath,
          );
      await ref.read(playbackMemoryRepositoryProvider).clearEntriesForResource(
            sourceId: sourceId,
            resourceId: record.resourceId,
            resourcePath: record.resourcePath,
          );
    }
  }

  @override
  Future<void> cancelActiveWebDavRefreshes({
    bool includeForceFull = false,
  }) {
    return _nasMediaIndexer.cancelAllRefreshTasks(
      includeForceFull: includeForceFull,
    );
  }

  Future<void> updateRatingCount({
    required String sourceId,
    required String itemId,
    required String resourcePath,
    required int ratingCount,
  }) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty || ratingCount <= 0) {
      return;
    }
    MediaSourceConfig? source;
    for (final candidate in _enabledSources) {
      if (candidate.id == normalizedSourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null) {
      return;
    }
    if (source.kind.isMediaServer) {
      await ref
          .read(localStorageCacheRepositoryProvider)
          .updateMediaItemRatingCount(
            sourceId: normalizedSourceId,
            itemId: itemId,
            ratingCount: ratingCount,
          );
      return;
    }
    if (source.kind == MediaSourceKind.nas ||
        source.kind == MediaSourceKind.quark) {
      await _nasMediaIndexer.updateRatingCount(
        sourceId: normalizedSourceId,
        resourceId: itemId,
        resourcePath: resourcePath,
        ratingCount: ratingCount,
      );
    }
  }

  @override
  Future<void> deleteResource({
    required String sourceId,
    required String resourcePath,
    String sectionId = '',
  }) async {
    final normalizedSourceId = sourceId.trim();
    final normalizedResourcePath = resourcePath.trim();
    if (normalizedSourceId.isEmpty || normalizedResourcePath.isEmpty) {
      return;
    }

    MediaSourceConfig? source;
    for (final candidate in _enabledSources) {
      if (candidate.id == normalizedSourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null) {
      return;
    }

    if (source.kind == MediaSourceKind.quark) {
      final cookie = _quarkCookie;
      if (cookie.isEmpty) {
        throw Exception('请先在「网盘与转存 → 夸克云盘」中填写 Cookie');
      }
      final parsed = _parseQuarkResourceId(normalizedResourcePath);
      final directResourceId = normalizedResourcePath;
      final record = parsed != null
          ? await _nasMediaIndexer.loadRecord(
              sourceId: normalizedSourceId,
              resourceId: directResourceId,
            )
          : null;
      final effectiveResourcePath = parsed?.path.trim().isNotEmpty == true
          ? parsed!.path.trim()
          : (record?.resourcePath.trim().isNotEmpty == true
              ? record!.resourcePath.trim()
              : normalizedResourcePath);
      final directoryEntry = parsed == null
          ? await _quarkSaveClient.resolveDirectoryByPath(
              cookie: cookie,
              path: _normalizeQuarkDirectoryPath(effectiveResourcePath),
            )
          : null;
      final scopeRecords = directoryEntry != null
          ? const <NasMediaIndexRecord>[]
          : parsed?.fid.trim().isNotEmpty == true
              ? (record == null ? const <NasMediaIndexRecord>[] : [record])
              : await _nasMediaIndexer.loadRecordsInScope(
                  sourceId: normalizedSourceId,
                  resourcePath: effectiveResourcePath,
                );
      final fids = <String>{
        if (directoryEntry?.fid.trim().isNotEmpty == true)
          directoryEntry!.fid.trim(),
        if (parsed?.fid.trim().isNotEmpty == true) parsed!.fid.trim(),
        for (final scopedRecord in scopeRecords)
          if (_parseQuarkResourceId(scopedRecord.resourceId)
                  ?.fid
                  .trim()
                  .isNotEmpty ==
              true)
            _parseQuarkResourceId(scopedRecord.resourceId)!.fid.trim(),
      }.toList(growable: false);
      if (fids.isEmpty) {
        throw Exception('没有可删除的夸克资源 ID');
      }
      await _quarkSaveClient.deleteEntries(
        cookie: cookie,
        fids: fids,
      );
      await _nasMediaIndexer.removeResourceScope(
        sourceId: normalizedSourceId,
        resourcePath: effectiveResourcePath,
      );
      final treatAsScope =
          !_looksLikePlayableResourcePath(effectiveResourcePath);
      await ref
          .read(localStorageCacheRepositoryProvider)
          .clearDetailCacheForResource(
            sourceId: normalizedSourceId,
            resourceId: parsed != null ? directResourceId : '',
            resourcePath: effectiveResourcePath,
            treatAsScope: treatAsScope,
          );
      await ref.read(playbackMemoryRepositoryProvider).clearEntriesForResource(
            sourceId: normalizedSourceId,
            resourceId: parsed != null ? directResourceId : '',
            resourcePath: effectiveResourcePath,
            treatAsScope: treatAsScope,
          );
      return;
    }

    if (source.kind != MediaSourceKind.nas) {
      return;
    }

    final directResourceUri = Uri.tryParse(normalizedResourcePath);
    final isDirectResourceId =
        directResourceUri != null && directResourceUri.hasScheme;
    final record = isDirectResourceId
        ? await _nasMediaIndexer.loadRecord(
            sourceId: normalizedSourceId,
            resourceId: normalizedResourcePath,
          )
        : null;
    final effectiveResourcePath = record?.resourcePath.trim().isNotEmpty == true
        ? record!.resourcePath.trim()
        : normalizedResourcePath;
    final cloud115DeleteService =
        Cloud115SyncDeleteService(ref.read(cloud115SaveClientProvider));
    final aliyunDeleteService =
        AliyunSyncDeleteService(ref.read(aliyunTo115WorkflowProvider));
    final aliyunDeletePlan = await aliyunDeleteService.prepare(
        config: ref.read(appSettingsProvider).networkStorage,
        sourceId: source.id,
        resourcePath: _webDavNasClient
            .resolveResourceUri(source,
                resourcePath: normalizedResourcePath, sectionId: sectionId)
            .toString());
    final cloud115DeletePlan = await cloud115DeleteService.prepare(
      config: ref.read(appSettingsProvider).networkStorage,
      sourceId: source.id,
      resourcePath: _webDavNasClient
          .resolveResourceUri(
            source,
            resourcePath: normalizedResourcePath,
            sectionId: sectionId,
          )
          .toString(),
    );
    final quarkDeletePlan = await _prepareQuarkSyncDeletePlan(
      source: source,
      resourcePath: normalizedResourcePath,
      effectiveResourcePath: effectiveResourcePath,
      sectionId: sectionId,
    );

    if ([cloud115DeletePlan, quarkDeletePlan, aliyunDeletePlan]
            .where((p) => p != null)
            .length >
        1) {
      throw const QuarkSaveException('多个网盘删除监听范围重叠，未执行删除');
    }

    var quarkDeleteCompleted = false;
    try {
      await _webDavNasClient.deleteResource(
        source,
        resourcePath: normalizedResourcePath,
        sectionId: sectionId,
      );
    } on WebDavDeleteException catch (error, stackTrace) {
      if (cloud115DeletePlan != null) {
        appLogWarning(
          '115.sync-delete',
          '115 sync deletion skipped after WebDAV failure',
          fields: {'sourceId': source.id, 'statusCode': error.statusCode},
        );
      }
      final canDeleteFromQuarkSource = quarkDeletePlan != null &&
          const <int>{403, 405}.contains(error.statusCode);
      if (!canDeleteFromQuarkSource) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      quarkDeleteCompleted =
          await _deleteMatchedQuarkDirectory(quarkDeletePlan);
      if (!quarkDeleteCompleted) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    if (quarkDeletePlan != null && !quarkDeleteCompleted) {
      await _deleteMatchedQuarkDirectory(quarkDeletePlan);
    }
    if (cloud115DeletePlan != null) {
      try {
        await cloud115DeleteService.execute(cloud115DeletePlan);
      } catch (_) {
        throw const QuarkSaveException('WebDAV 已删除，但 115 删除未确认，请检查网盘；本地索引暂未清理');
      }
    }
    if (aliyunDeletePlan != null) {
      try {
        await aliyunDeleteService.execute(aliyunDeletePlan);
      } catch (_) {
        throw const QuarkSaveException('WebDAV 已删除，但阿里删除未确认，请检查网盘；本地索引暂未清理');
      }
    }
    await _nasMediaIndexer.removeResourceScope(
      sourceId: normalizedSourceId,
      resourcePath: effectiveResourcePath,
    );
    final treatAsScope = !_looksLikePlayableResourcePath(effectiveResourcePath);
    await ref
        .read(localStorageCacheRepositoryProvider)
        .clearDetailCacheForResource(
          sourceId: normalizedSourceId,
          resourceId: isDirectResourceId ? normalizedResourcePath : '',
          resourcePath: effectiveResourcePath,
          treatAsScope: treatAsScope,
        );
    await ref.read(playbackMemoryRepositoryProvider).clearEntriesForResource(
          sourceId: normalizedSourceId,
          resourceId: isDirectResourceId ? normalizedResourcePath : '',
          resourcePath: effectiveResourcePath,
          treatAsScope: treatAsScope,
        );
  }

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    return _queryService.fetchChildren(
      sourceId: sourceId,
      parentId: parentId,
      sectionId: sectionId,
      sectionName: sectionName,
      limit: limit,
    );
  }

  @override
  Future<MediaItem?> findById(String id) async {
    return _queryService.findById(id);
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    return _queryService.matchTitle(title);
  }

  Future<List<MediaCollection>> _selectedCollectionsForSource(
    MediaSourceConfig source,
  ) async {
    if (!_hasScopedSections(source)) {
      return const [];
    }
    return _fetchCollectionsForSource(source);
  }

  bool _hasScopedSections(MediaSourceConfig source) {
    return source.featuredSectionIds.any((item) => item.trim().isNotEmpty);
  }

  Future<List<MediaCollection>> _fetchCollectionsForSource(
    MediaSourceConfig source, {
    bool applySelection = true,
  }) async {
    late final List<MediaCollection> collections;
    if (source.kind.isMediaServer) {
      if (!source.hasActiveSession) {
        return const [];
      }
      collections = await _serverClient(source).fetchCollections(source);
    } else if (source.kind == MediaSourceKind.quark) {
      collections = await _quarkExternalStorageClient.fetchCollections(source);
    } else {
      if (source.endpoint.trim().isEmpty) {
        return const [];
      }
      collections = await _webDavNasClient.fetchCollections(source);
    }

    if (!applySelection) {
      return collections;
    }
    if (source.hasExplicitNoSectionsSelected) {
      return const [];
    }
    final selectedIds = source.selectedSectionIds;
    if (selectedIds.isEmpty) {
      return collections;
    }
    return collections
        .where((collection) => selectedIds.contains(collection.id))
        .toList();
  }

  String _normalizeQuarkDirectoryPath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '/';
    }
    final normalized =
        trimmed.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
    final withLeadingSlash =
        normalized.startsWith('/') ? normalized : '/$normalized';
    return withLeadingSlash.endsWith('/')
        ? withLeadingSlash.substring(0, withLeadingSlash.length - 1)
        : withLeadingSlash;
  }

  _ParsedQuarkResourceId? _parseQuarkResourceId(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'quark') {
      return null;
    }
    final segments = uri.pathSegments
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }
    final fid = Uri.decodeComponent(segments.last);
    if (fid.isEmpty) {
      return null;
    }
    return _ParsedQuarkResourceId(
      fid: fid,
      path: uri.queryParameters['path']?.trim() ?? '',
    );
  }

  bool _looksLikePlayableResourcePath(String value) {
    final normalized = value.trim().toLowerCase();
    return const [
      '.mp4',
      '.m4v',
      '.mov',
      '.mkv',
      '.avi',
      '.ts',
      '.webm',
      '.flv',
      '.wmv',
      '.mpg',
      '.mpeg',
      '.strm',
    ].any(normalized.endsWith);
  }

  Future<_MatchedQuarkDirectory?> _prepareQuarkSyncDeletePlan({
    required MediaSourceConfig source,
    required String resourcePath,
    required String effectiveResourcePath,
    required String sectionId,
  }) async {
    final isDirectoryScope =
        !_looksLikePlayableResourcePath(effectiveResourcePath);
    final networkStorage = ref.read(appSettingsProvider).networkStorage;
    if (!networkStorage.syncDeleteQuarkEnabled) {
      _logQuarkSyncDelete(
        'prepare.skip',
        fields: {
          'reason': 'setting_disabled',
          'sourceId': source.id,
          'resourcePath': resourcePath,
          'effectiveResourcePath': effectiveResourcePath,
        },
      );
      return null;
    }
    final matchedScope = _matchSyncDeleteWebDavDirectory(
      source: source,
      resourcePath: effectiveResourcePath,
      directories: networkStorage.syncDeleteQuarkWebDavDirectories,
    );
    if (matchedScope == null) {
      _logQuarkSyncDelete(
        'prepare.skip',
        fields: {
          'reason': 'resource_outside_selected_scope',
          'sourceId': source.id,
          'sourceName': source.name,
          'resourcePath': resourcePath,
          'effectiveResourcePath': effectiveResourcePath,
          'configuredScopes': networkStorage.syncDeleteQuarkWebDavDirectories
              .map(
                (item) =>
                    '${item.sourceName}[${item.sourceId}]=>${item.directoryId}',
              )
              .toList(growable: false),
        },
      );
      return null;
    }
    if (_isExactSyncDeleteScopeRoot(
      resourcePath: effectiveResourcePath,
      scopeDirectoryId: matchedScope.directory.directoryId,
    )) {
      _logQuarkSyncDelete(
        'prepare.skip',
        fields: {
          'reason': 'selected_scope_root_deleted',
          'sourceId': source.id,
          'resourcePath': resourcePath,
          'effectiveResourcePath': effectiveResourcePath,
          'scopeDirectoryId': matchedScope.directory.directoryId,
        },
      );
      return null;
    }
    _logQuarkSyncDelete(
      'prepare.scopeMatched',
      fields: {
        'sourceId': source.id,
        'resourcePath': resourcePath,
        'effectiveResourcePath': effectiveResourcePath,
        'isDirectoryScope': isDirectoryScope,
        'scopeMatchMode': matchedScope.matchMode,
        'scopeDirectoryId': matchedScope.directory.directoryId,
        'scopeDirectoryLabel': matchedScope.directory.directoryLabel,
      },
    );

    final cookie = networkStorage.quarkCookie.trim();
    final parentFid = networkStorage.quarkSaveFolderId.trim();
    if (cookie.isEmpty || parentFid.isEmpty) {
      _logQuarkSyncDelete(
        'prepare.skip',
        fields: {
          'reason': 'missing_quark_config',
          'sourceId': source.id,
          'resourcePath': resourcePath,
          'hasCookie': cookie.isNotEmpty,
          'parentFid': parentFid,
        },
      );
      return null;
    }

    final candidateNames = _buildScopedQuarkDirectoryNameCandidates(
      resourcePath: effectiveResourcePath,
      scopeDirectoryId: matchedScope.directory.directoryId,
      treatAsDirectoryScope: isDirectoryScope,
    );
    _logQuarkSyncDelete(
      'prepare.candidates',
      fields: {
        'sourceId': source.id,
        'resourcePath': resourcePath,
        'effectiveResourcePath': effectiveResourcePath,
        'isDirectoryScope': isDirectoryScope,
        'candidateNames': candidateNames,
      },
    );
    if (candidateNames.isEmpty) {
      _logQuarkSyncDelete(
        'prepare.skip',
        fields: {
          'reason': 'no_candidate_names',
          'sourceId': source.id,
          'resourcePath': resourcePath,
          'effectiveResourcePath': effectiveResourcePath,
        },
      );
      return null;
    }

    final matchedDirectory = await _findMatchingQuarkDirectory(
      cookie: cookie,
      parentFid: parentFid,
      candidateNames: candidateNames,
    );
    if (matchedDirectory == null) {
      _logQuarkSyncDelete(
        'prepare.skip',
        fields: {
          'reason': 'directory_not_found',
          'sourceId': source.id,
          'resourcePath': resourcePath,
          'parentFid': parentFid,
          'candidateNames': candidateNames,
        },
      );
      return null;
    }

    _logQuarkSyncDelete(
      'prepare.match',
      fields: {
        'sourceId': source.id,
        'resourcePath': resourcePath,
        'matchedFid': matchedDirectory.fid,
        'matchedName': matchedDirectory.name,
        'matchedPath': matchedDirectory.path,
      },
    );
    return _MatchedQuarkDirectory(
      cookie: cookie,
      fid: matchedDirectory.fid,
      name: matchedDirectory.name,
      path: matchedDirectory.path,
    );
  }

  Future<QuarkDirectoryEntry?> _findMatchingQuarkDirectory({
    required String cookie,
    required String parentFid,
    required List<String> candidateNames,
  }) async {
    try {
      final directories = await _quarkSaveClient.listDirectories(
        cookie: cookie,
        parentFid: parentFid,
      );
      _logQuarkSyncDelete(
        'match.directories',
        fields: {
          'parentFid': parentFid,
          'candidateNames': candidateNames,
          'directoryNames':
              directories.map((directory) => directory.name).toList(),
          'directoryPaths':
              directories.map((directory) => directory.path).toList(),
        },
      );
      if (directories.isEmpty) {
        return null;
      }

      for (final candidateName in candidateNames) {
        final normalizedCandidate =
            _normalizeQuarkDirectoryComparisonText(candidateName);
        if (normalizedCandidate.isEmpty) {
          continue;
        }
        for (final directory in directories) {
          final normalizedDirectory =
              _normalizeQuarkDirectoryComparisonText(directory.name);
          if (normalizedDirectory == normalizedCandidate) {
            _logQuarkSyncDelete(
              'match.hit',
              fields: {
                'mode': 'exact',
                'candidateName': candidateName,
                'directoryName': directory.name,
                'directoryPath': directory.path,
                'directoryFid': directory.fid,
              },
            );
            return directory;
          }
        }
      }

      for (final candidateName in candidateNames) {
        final normalizedCandidate =
            _normalizeQuarkDirectoryComparisonText(candidateName);
        if (normalizedCandidate.isEmpty) {
          continue;
        }
        for (final directory in directories) {
          final normalizedDirectory =
              _normalizeQuarkDirectoryComparisonText(directory.name);
          if (normalizedDirectory.isEmpty) {
            continue;
          }
          if (normalizedDirectory.contains(normalizedCandidate) ||
              normalizedCandidate.contains(normalizedDirectory)) {
            _logQuarkSyncDelete(
              'match.hit',
              fields: {
                'mode': 'fuzzy',
                'candidateName': candidateName,
                'directoryName': directory.name,
                'directoryPath': directory.path,
                'directoryFid': directory.fid,
              },
            );
            return directory;
          }
        }
      }
    } catch (error) {
      _logQuarkSyncDelete(
        'match.error',
        fields: {
          'parentFid': parentFid,
          'candidateNames': candidateNames,
          'error': error,
        },
      );
      return null;
    }

    return null;
  }

  Future<bool> _deleteMatchedQuarkDirectory(
    _MatchedQuarkDirectory directory,
  ) async {
    try {
      _logQuarkSyncDelete(
        'delete.start',
        fields: {
          'fid': directory.fid,
          'name': directory.name,
          'path': directory.path,
        },
      );
      await _quarkSaveClient.deleteEntries(
        cookie: directory.cookie,
        fids: [directory.fid],
      );
      _logQuarkSyncDelete(
        'delete.done',
        fields: {
          'fid': directory.fid,
          'name': directory.name,
          'path': directory.path,
        },
      );
      return true;
    } catch (error) {
      _logQuarkSyncDelete(
        'delete.error',
        fields: {
          'fid': directory.fid,
          'name': directory.name,
          'path': directory.path,
          'error': error,
        },
      );
      // WebDAV delete has already succeeded; Quark sync delete is best-effort.
      return false;
    }
  }

  _MatchedSyncDeleteScope? _matchSyncDeleteWebDavDirectory({
    required MediaSourceConfig source,
    required String resourcePath,
    required List<NetworkStorageWebDavDirectory> directories,
  }) {
    _MatchedSyncDeleteScope? exactMatch;
    _MatchedSyncDeleteScope? sourceNameMatch;
    _MatchedSyncDeleteScope? uniquePathFallback;
    final pathOnlyMatches = <_MatchedSyncDeleteScope>[];
    final normalizedSourceName = source.name.trim().toLowerCase();

    _MatchedSyncDeleteScope withGreaterDepth(
      _MatchedSyncDeleteScope? current,
      _MatchedSyncDeleteScope next,
    ) {
      if (current == null || next.depth > current.depth) {
        return next;
      }
      return current;
    }

    for (final directory in directories) {
      final sourceIdMatches = directory.sourceId.trim() == source.id.trim();
      final normalizedDirectorySourceName =
          directory.sourceName.trim().toLowerCase();
      final sourceNameMatches = normalizedSourceName.isNotEmpty &&
          normalizedDirectorySourceName.isNotEmpty &&
          normalizedDirectorySourceName == normalizedSourceName;
      final alignedScopeSegments = _alignedScopeSegments(
        resourcePath: resourcePath,
        scopeDirectoryId: directory.directoryId,
        allowRelocatedScope: sourceIdMatches || sourceNameMatches,
      );
      if (alignedScopeSegments == null) {
        continue;
      }
      final candidate = _MatchedSyncDeleteScope(
        directory: directory,
        depth: alignedScopeSegments.length,
        matchMode: 'path_only',
      );
      if (sourceIdMatches) {
        exactMatch = withGreaterDepth(
          exactMatch,
          candidate.copyWith(matchMode: 'source_id'),
        );
        continue;
      }
      if (sourceNameMatches) {
        sourceNameMatch = withGreaterDepth(
          sourceNameMatch,
          candidate.copyWith(matchMode: 'source_name'),
        );
        continue;
      }
      pathOnlyMatches.add(candidate);
    }

    if (exactMatch != null) {
      return exactMatch;
    }
    if (sourceNameMatch != null) {
      return sourceNameMatch;
    }
    if (pathOnlyMatches.length == 1) {
      uniquePathFallback = pathOnlyMatches.single;
    }
    return uniquePathFallback;
  }

  bool _isExactSyncDeleteScopeRoot({
    required String resourcePath,
    required String scopeDirectoryId,
  }) {
    final resourceSegments = _pathSegments(_uriPath(resourcePath));
    final alignedScopeSegments = _alignedScopeSegments(
      resourcePath: resourcePath,
      scopeDirectoryId: scopeDirectoryId,
    );
    if (alignedScopeSegments == null) {
      return false;
    }
    return resourceSegments.length == alignedScopeSegments.length;
  }

  List<String> _buildScopedQuarkDirectoryNameCandidates({
    required String resourcePath,
    required String scopeDirectoryId,
    required bool treatAsDirectoryScope,
  }) {
    final resourceSegments = _pathSegments(_uriPath(resourcePath));
    final scopeSegments = _alignedScopeSegments(
          resourcePath: resourcePath,
          scopeDirectoryId: scopeDirectoryId,
        ) ??
        const <String>[];
    final candidates = <String>[];
    final seen = <String>{};

    void addCandidate(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        return;
      }
      candidates.add(trimmed);
    }

    if (resourceSegments.length > scopeSegments.length) {
      final relativeSegments = resourceSegments.sublist(scopeSegments.length);
      final scopeRootName =
          relativeSegments.length == 1 && !treatAsDirectoryScope
              ? _stripFileExtension(relativeSegments.first)
              : relativeSegments.first;
      for (final candidate in _buildQuarkDirectoryCandidateVariations(
        scopeRootName,
      )) {
        addCandidate(candidate);
      }
    }

    final shouldAppendFallback = treatAsDirectoryScope ||
        resourceSegments.length > scopeSegments.length + 1;
    if (shouldAppendFallback) {
      for (final candidate in _buildQuarkDirectoryNameCandidates(
        resourcePath,
        treatAsDirectoryScope: treatAsDirectoryScope,
      )) {
        addCandidate(candidate);
      }
    }

    return candidates;
  }

  List<String> _buildQuarkDirectoryNameCandidates(
    String resourcePath, {
    required bool treatAsDirectoryScope,
  }) {
    final segments = _pathSegments(_uriPath(resourcePath));
    if (segments.length < 2) {
      return const [];
    }

    final directories = treatAsDirectoryScope
        ? segments
        : segments.sublist(0, segments.length - 1);
    if (directories.isEmpty) {
      return const [];
    }

    final rawRootName = _resolveMediaRootDirectoryName(directories);
    if (rawRootName.isEmpty) {
      return const [];
    }

    return _buildQuarkDirectoryCandidateVariations(rawRootName);
  }

  String _resolveMediaRootDirectoryName(List<String> directories) {
    final normalized = directories
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return '';
    }

    final lastDirectory = normalized.last;
    if (_looksLikeSeasonFolderLabel(lastDirectory) && normalized.length > 1) {
      return normalized[normalized.length - 2];
    }

    final nearestNonSeason = _nearestNonSeasonDirectory(normalized);
    if (nearestNonSeason.isNotEmpty) {
      return nearestNonSeason;
    }
    return lastDirectory;
  }

  String _normalizeQuarkDirectoryComparisonText(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'\{[^}]+\}'), ' ')
        .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
        .replaceAll(RegExp(r'\(\d{4}\)'), ' ')
        .replaceAll(
          RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'),
          '',
        )
        .toLowerCase();
    return normalized;
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

  bool _looksLikeSeasonFolderLabel(String value) {
    return looksLikeSeasonFolderLabel(value) ||
        looksLikeNumericTopicSeason(value);
  }

  List<String> _buildQuarkDirectoryCandidateVariations(String rawValue) {
    final candidates = <String>[];
    final seen = <String>{};

    void addCandidate(String value) {
      final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        return;
      }
      candidates.add(trimmed);
    }

    addCandidate(rawValue);
    addCandidate(rawValue.replaceAll(RegExp(r'\{[^}]+\}'), ' '));
    addCandidate(rawValue.replaceAll(RegExp(r'\[[^\]]+\]'), ' '));
    addCandidate(
      rawValue
          .replaceAll(RegExp(r'\{[^}]+\}'), ' ')
          .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
          .replaceAll(RegExp(r'\(\d{4}\)'), ' '),
    );
    addCandidate(
      rawValue
          .replaceAll(RegExp(r'\{[^}]+\}'), ' ')
          .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
          .replaceAll(RegExp(r'\(\d{4}\)'), ' ')
          .replaceAll(
            RegExp(r'\b(?:2160p|1080p|720p|4k|remux|web-dl|bluray)\b',
                caseSensitive: false),
            ' ',
          ),
    );
    return candidates;
  }

  String _stripFileExtension(String value) {
    final trimmed = value.trim();
    final dotIndex = trimmed.lastIndexOf('.');
    if (dotIndex <= 0) {
      return trimmed;
    }
    return trimmed.substring(0, dotIndex);
  }

  List<String>? _alignedScopeSegments({
    required String resourcePath,
    required String scopeDirectoryId,
    bool allowRelocatedScope = false,
  }) {
    final resourceSegments = _pathSegments(_uriPath(resourcePath));
    final scopeSegments = _pathSegments(_uriPath(scopeDirectoryId));
    if (resourceSegments.isEmpty || scopeSegments.isEmpty) {
      return null;
    }
    for (var start = 0; start < scopeSegments.length; start++) {
      final candidate = scopeSegments.sublist(start);
      if (candidate.length > resourceSegments.length) {
        continue;
      }
      if (_startsWithSegments(resourceSegments, candidate)) {
        return candidate;
      }
    }
    if (!allowRelocatedScope) {
      return null;
    }

    for (var suffixLength = scopeSegments.length;
        suffixLength >= 2;
        suffixLength--) {
      final suffix = scopeSegments.sublist(scopeSegments.length - suffixLength);
      for (var resourceStart = 0;
          resourceStart + suffix.length <= resourceSegments.length;
          resourceStart++) {
        final resourceCandidate = resourceSegments.sublist(
          resourceStart,
          resourceStart + suffix.length,
        );
        if (_startsWithSegments(resourceCandidate, suffix)) {
          return resourceSegments.sublist(
            0,
            resourceStart + suffix.length,
          );
        }
      }
    }
    return null;
  }

  bool _startsWithSegments(
    List<String> value,
    List<String> prefix,
  ) {
    if (prefix.length > value.length) {
      return false;
    }
    for (var index = 0; index < prefix.length; index++) {
      if (value[index] != prefix[index]) {
        return false;
      }
    }
    return true;
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

  void _logQuarkSyncDelete(
    String action, {
    Map<String, Object?> fields = const {},
  }) {}
}

class _MatchedQuarkDirectory {
  const _MatchedQuarkDirectory({
    required this.cookie,
    required this.fid,
    required this.name,
    required this.path,
  });

  final String cookie;
  final String fid;
  final String name;
  final String path;
}

class _MatchedSyncDeleteScope {
  const _MatchedSyncDeleteScope({
    required this.directory,
    required this.depth,
    required this.matchMode,
  });

  final NetworkStorageWebDavDirectory directory;
  final int depth;
  final String matchMode;

  _MatchedSyncDeleteScope copyWith({
    NetworkStorageWebDavDirectory? directory,
    int? depth,
    String? matchMode,
  }) {
    return _MatchedSyncDeleteScope(
      directory: directory ?? this.directory,
      depth: depth ?? this.depth,
      matchMode: matchMode ?? this.matchMode,
    );
  }
}

extension MediaRepositoryRatingCountX on MediaRepository {
  Future<void> updateRatingCount({
    required String sourceId,
    required String itemId,
    required String resourcePath,
    required int ratingCount,
  }) {
    final repository = this;
    if (repository is AppMediaRepository) {
      return repository.updateRatingCount(
        sourceId: sourceId,
        itemId: itemId,
        resourcePath: resourcePath,
        ratingCount: ratingCount,
      );
    }
    return Future<void>.value();
  }
}

class _ParsedQuarkResourceId {
  const _ParsedQuarkResourceId({
    required this.fid,
    required this.path,
  });

  final String fid;
  final String path;
}
