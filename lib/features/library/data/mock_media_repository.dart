import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/application/app_media_query_service.dart';
import 'package:starflow/features/library/application/empty_library_auto_rebuild_scheduler.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/quark_external_storage_client.dart';
import 'package:starflow/features/library/data/season_folder_label_parser.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:xml/xml.dart';

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
  )   : _queryService = AppMediaQueryService(
          ref: ref,
          embyApiClient: _embyApiClient,
          webDavNasClient: _webDavNasClient,
          nasMediaIndexer: _nasMediaIndexer,
          quarkExternalStorageClient: _quarkExternalStorageClient,
        ),
        _emptyLibraryAutoRebuildScheduler = EmptyLibraryAutoRebuildScheduler();

  final Ref ref;
  final EmbyApiClient _embyApiClient;
  final WebDavNasClient _webDavNasClient;
  final NasMediaIndexer _nasMediaIndexer;
  final QuarkExternalStorageClient _quarkExternalStorageClient;
  final QuarkSaveClient _quarkSaveClient;
  final AppMediaQueryService _queryService;
  final EmptyLibraryAutoRebuildScheduler _emptyLibraryAutoRebuildScheduler;

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

    if (source.kind == MediaSourceKind.emby) {
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
    if (!forceFullRescan) {
      final nextIndexedRecords = await _nasMediaIndexer.loadSourceRecords(
        source.id,
      );
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

  // ignore: unused_element
  Future<void> _refreshQuarkSource(
    MediaSourceConfig source, {
    required bool forceFullRescan,
  }) async {
    if (forceFullRescan) {
      await ref
          .read(localStorageCacheRepositoryProvider)
          .clearDetailCacheForSource(source.id);
    }
    if (!source.hasConfiguredQuarkFolder) {
      return;
    }
    final cookie = _quarkCookie;
    if (cookie.isEmpty) {
      return;
    }
    if (source.hasExplicitNoSectionsSelected) {
      return;
    }
    final selectedCollections = await _selectedCollectionsForSource(source);
    try {
      if (_hasScopedSections(source)) {
        if (selectedCollections.isEmpty) {
          return;
        }
        await _loadQuarkLibraryFromRoots(
          source,
          cookie: cookie,
          roots: selectedCollections
              .map(
                (collection) => _QuarkDirectoryCursor(
                  fid: collection.id,
                  path: collection.subtitle,
                  sectionId: collection.id,
                  sectionName: collection.title,
                ),
              )
              .toList(growable: false),
          limit: 200 * selectedCollections.length,
          reportRefreshProgress: true,
        );
        return;
      }
      await _loadQuarkLibraryFromRoots(
        source,
        cookie: cookie,
        roots: [
          _QuarkDirectoryCursor(
            fid: source.quarkFolderId,
            path: source.quarkFolderPath,
          ),
        ],
        limit: 200,
        reportRefreshProgress: true,
      );
    } finally {
      _clearQuarkRefreshProgress(source.id);
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
        throw Exception('请先在夸克与 STRM 里填写夸克 Cookie');
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
    final quarkDeletePlan = await _prepareQuarkSyncDeletePlan(
      source: source,
      resourcePath: normalizedResourcePath,
      effectiveResourcePath: effectiveResourcePath,
      sectionId: sectionId,
    );

    await _webDavNasClient.deleteResource(
      source,
      resourcePath: normalizedResourcePath,
      sectionId: sectionId,
    );
    if (quarkDeletePlan != null) {
      await _deleteMatchedQuarkDirectory(quarkDeletePlan);
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

  Future<String> _resolveSectionName(
    MediaSourceConfig source,
    String? sectionId,
  ) async {
    final normalized = sectionId?.trim() ?? '';
    if (normalized.isEmpty) {
      return '';
    }

    final collections = await _fetchCollectionsForSource(
      source,
      applySelection: false,
    );
    for (final collection in collections) {
      if (collection.id == normalized) {
        return collection.title;
      }
    }
    return '';
  }

  Future<String> _resolveSectionPath(
    MediaSourceConfig source,
    String? sectionId,
  ) async {
    final normalized = sectionId?.trim() ?? '';
    if (normalized.isEmpty) {
      return '';
    }

    final collections = await _fetchCollectionsForSource(
      source,
      applySelection: false,
    );
    for (final collection in collections) {
      if (collection.id == normalized) {
        return collection.subtitle.trim();
      }
    }
    return '';
  }

  // ignore: unused_element
  Future<_SourceFetchResult> _fetchLibraryForSource(
    MediaSourceConfig source, {
    required String? sectionId,
    required int limit,
    required List<MediaItem> seededLibrary,
  }) async {
    // Transitional path kept while query responsibilities finish moving out.
    try {
      final hasScopedSections = _hasScopedSections(source);
      if (source.kind == MediaSourceKind.emby) {
        if (!source.hasActiveSession) {
          return const _SourceFetchResult(items: <MediaItem>[]);
        }
        if (sectionId?.trim().isNotEmpty == true) {
          return _SourceFetchResult(
            items: await _embyApiClient.fetchLibrary(
              source,
              limit: limit,
              sectionId: sectionId,
              sectionName: await _resolveSectionName(source, sectionId),
            ),
          );
        }

        final selectedCollections = await _selectedCollectionsForSource(source);
        if (hasScopedSections) {
          if (selectedCollections.isEmpty) {
            return const _SourceFetchResult(items: <MediaItem>[]);
          }
          return _SourceFetchResult(
            items: await _fetchLibraryFromCollections(
              source,
              selectedCollections,
              limit: limit,
            ),
          );
        }

        return _SourceFetchResult(
          items: await _embyApiClient.fetchLibrary(
            source,
            limit: limit,
          ),
        );
      }

      if (source.kind == MediaSourceKind.quark) {
        if (!source.hasConfiguredQuarkFolder) {
          return const _SourceFetchResult(items: <MediaItem>[]);
        }
        if (sectionId?.trim().isNotEmpty == true) {
          final resolvedSectionId = sectionId!.trim();
          final resolvedSectionName =
              await _resolveSectionName(source, sectionId);
          return _SourceFetchResult(
            items: await _loadNasLibraryWithAutoRebuild(
              source,
              sectionId: resolvedSectionId,
              scopedCollections: [
                MediaCollection(
                  id: resolvedSectionId,
                  title: resolvedSectionName,
                  sourceId: source.id,
                  sourceName: source.name,
                  sourceKind: source.kind,
                  subtitle: await _resolveSectionPath(source, sectionId),
                ),
              ],
              limit: limit,
              autoRebuildInBackground: false,
            ),
          );
        }

        final selectedCollections = await _selectedCollectionsForSource(source);
        if (hasScopedSections) {
          if (selectedCollections.isEmpty) {
            return const _SourceFetchResult(items: <MediaItem>[]);
          }
          return _SourceFetchResult(
            items: await _loadNasLibraryWithAutoRebuild(
              source,
              scopedCollections: selectedCollections,
              limit: limit,
              autoRebuildInBackground: false,
            ),
          );
        }

        return _SourceFetchResult(
          items: await _loadNasLibraryWithAutoRebuild(
            source,
            limit: limit,
            autoRebuildInBackground: false,
          ),
        );
      }

      if (source.endpoint.trim().isNotEmpty) {
        if (source.hasExplicitNoSectionsSelected) {
          await _nasMediaIndexer.clearSource(source.id);
          return const _SourceFetchResult(items: <MediaItem>[]);
        }
        if (sectionId?.trim().isNotEmpty == true) {
          final resolvedSectionId = sectionId!.trim();
          final resolvedSectionName =
              await _resolveSectionName(source, sectionId);
          final scopedCollections = [
            MediaCollection(
              id: resolvedSectionId,
              title: resolvedSectionName,
              sourceId: source.id,
              sourceName: source.name,
              sourceKind: source.kind,
            ),
          ];
          return _SourceFetchResult(
            items: await _loadNasLibraryWithAutoRebuild(
              source,
              sectionId: resolvedSectionId,
              scopedCollections: scopedCollections,
              limit: limit,
            ),
          );
        }

        final selectedCollections = await _selectedCollectionsForSource(source);
        if (hasScopedSections) {
          if (selectedCollections.isEmpty) {
            await _nasMediaIndexer.clearSource(source.id);
            return const _SourceFetchResult(items: <MediaItem>[]);
          }
          return _SourceFetchResult(
            items: await _loadNasLibraryWithAutoRebuild(
              source,
              scopedCollections: selectedCollections,
              limit: limit,
            ),
          );
        }

        return _SourceFetchResult(
          items: await _loadNasLibraryWithAutoRebuild(
            source,
            limit: limit,
          ),
        );
      }

      return _SourceFetchResult(
        items: seededLibrary
            .where((item) => item.sourceId == source.id)
            .where(
              (item) =>
                  sectionId == null ||
                  sectionId.trim().isEmpty ||
                  item.sectionId == sectionId,
            )
            .where(
              (item) =>
                  source.featuredSectionIds.isEmpty ||
                  source.featuredSectionIds.contains(item.sectionId),
            )
            .toList(),
      );
    } catch (error, stackTrace) {
      return _SourceFetchResult(
        items: const <MediaItem>[],
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<MediaItem>> _fetchLibraryFromCollections(
    MediaSourceConfig source,
    List<MediaCollection> collections, {
    required int limit,
  }) async {
    final groups = await Future.wait(
      collections.map((collection) async {
        if (source.kind == MediaSourceKind.emby) {
          return _embyApiClient.fetchLibrary(
            source,
            limit: limit,
            sectionId: collection.id,
            sectionName: collection.title,
          );
        }
        if (source.kind == MediaSourceKind.quark) {
          return _loadNasLibraryWithAutoRebuild(
            source,
            sectionId: collection.id,
            scopedCollections: [collection],
            limit: limit,
            autoRebuildInBackground: false,
          );
        }
        return _nasMediaIndexer.loadLibrary(
          source,
          sectionId: collection.id,
          scopedCollections: [collection],
          limit: limit,
        );
      }),
    );
    return groups.expand((group) => group).toList();
  }

  Future<List<MediaItem>> _loadNasLibraryWithAutoRebuild(
    MediaSourceConfig source, {
    String? sectionId,
    List<MediaCollection>? scopedCollections,
    required int limit,
    bool autoRebuildInBackground = true,
  }) async {
    final scopeKey = _buildEmptyLibraryAutoRebuildScopeKey(
      source: source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
    );
    var items = await _nasMediaIndexer.loadLibrary(
      source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
      limit: limit,
    );
    if (items.isNotEmpty) {
      _emptyLibraryAutoRebuildScheduler.markScopeHealthy(scopeKey);
      return items;
    }

    if (!autoRebuildInBackground) {
      final rebuilt = await _nasMediaIndexer.tryAutoRebuildOnEmpty(
        source,
        scopedCollections: scopedCollections,
      );
      if (!rebuilt) {
        return items;
      }
      items = await _nasMediaIndexer.loadLibrary(
        source,
        sectionId: sectionId,
        scopedCollections: scopedCollections,
        limit: limit,
      );
      if (items.isNotEmpty) {
        _emptyLibraryAutoRebuildScheduler.markScopeHealthy(scopeKey);
      }
      return items;
    }

    _scheduleEmptyLibraryAutoRebuild(
      source: source,
      scopedCollections: scopedCollections,
      scopeKey: scopeKey,
    );
    return items;
  }

  void _scheduleEmptyLibraryAutoRebuild({
    required MediaSourceConfig source,
    List<MediaCollection>? scopedCollections,
    required String scopeKey,
  }) {
    _emptyLibraryAutoRebuildScheduler.schedule(
      scopeKey: scopeKey,
      task: () async {
        await _nasMediaIndexer.tryAutoRebuildOnEmpty(
          source,
          scopedCollections: scopedCollections,
        );
      },
    );
  }

  String _buildEmptyLibraryAutoRebuildScopeKey({
    required MediaSourceConfig source,
    String? sectionId,
    List<MediaCollection>? scopedCollections,
  }) {
    final normalizedSourceId = source.id.trim();
    final normalizedScopeIds = <String>{
      for (final collection in scopedCollections ?? const <MediaCollection>[])
        if (collection.id.trim().isNotEmpty) collection.id.trim(),
      if (sectionId?.trim().isNotEmpty == true) sectionId!.trim(),
    }.toList(growable: false)
      ..sort();
    return '$normalizedSourceId::${normalizedScopeIds.join("|")}';
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
    if (source.kind == MediaSourceKind.emby) {
      if (!source.hasActiveSession) {
        return const [];
      }
      collections = await _embyApiClient.fetchCollections(source);
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

  // ignore: unused_element
  Future<List<MediaItem>> _loadQuarkLibrary(
    MediaSourceConfig source, {
    required String cookie,
    required String parentFid,
    String parentPath = '',
    String sectionId = '',
    String sectionName = '',
    required int limit,
  }) async {
    return _loadQuarkLibraryFromRoots(
      source,
      cookie: cookie,
      roots: [
        _QuarkDirectoryCursor(
          fid: parentFid,
          path: parentPath,
          sectionId: sectionId,
          sectionName: sectionName,
        ),
      ],
      limit: limit,
    );
  }

  Future<List<MediaItem>> _loadQuarkLibraryFromRoots(
    MediaSourceConfig source, {
    required String cookie,
    required List<_QuarkDirectoryCursor> roots,
    required int limit,
    bool reportRefreshProgress = false,
  }) async {
    final normalizedCookie = cookie.trim();
    if (normalizedCookie.isEmpty) {
      return const [];
    }
    final scanResult = await _scanQuarkLibrary(
      source,
      cookie: normalizedCookie,
      roots: roots,
      limit: limit,
      reportRefreshProgress: reportRefreshProgress,
    );
    if (scanResult.mediaEntries.isEmpty) {
      if (reportRefreshProgress) {
        _quarkRefreshProgressController.startIndexing(
          sourceId: source.id,
          totalItems: 0,
          detail: '没有发现媒体文件',
        );
      }
      return const [];
    }
    final textFileCache = <String, Future<String>>{};
    final downloadCache = <String, Future<QuarkResolvedDownload>>{};
    if (reportRefreshProgress) {
      _quarkRefreshProgressController.startIndexing(
        sourceId: source.id,
        totalItems: scanResult.mediaEntries.length,
      );
    }
    final items = <MediaItem>[];
    for (var index = 0; index < scanResult.mediaEntries.length; index++) {
      final queuedEntry = scanResult.mediaEntries[index];
      items.add(
        await _buildQuarkMediaItem(
          source: source,
          entry: queuedEntry.entry,
          cookie: normalizedCookie,
          sectionId: queuedEntry.sectionId,
          sectionName: queuedEntry.sectionName,
          directoryEntriesByPath: scanResult.directoryEntriesByPath,
          textFileCache: textFileCache,
          downloadCache: downloadCache,
        ),
      );
      if (reportRefreshProgress) {
        _quarkRefreshProgressController.updateIndexing(
          sourceId: source.id,
          current: index + 1,
          total: scanResult.mediaEntries.length,
          detail: queuedEntry.entry.name,
        );
      }
    }

    return items;
  }

  Future<_QuarkLibraryScanResult> _scanQuarkLibrary(
    MediaSourceConfig source, {
    required String cookie,
    required List<_QuarkDirectoryCursor> roots,
    required int limit,
    required bool reportRefreshProgress,
  }) async {
    final normalizedRoots = <_QuarkDirectoryCursor>[];
    for (final root in roots) {
      final normalizedParentFid =
          root.fid.trim().isEmpty ? source.quarkFolderId : root.fid.trim();
      final normalizedParentPath = _normalizeQuarkDirectoryPath(
        root.path.trim().isNotEmpty
            ? root.path.trim()
            : normalizedParentFid == source.quarkFolderId
                ? source.quarkFolderPath
                : '/',
      );
      if (source.matchesWebDavExcludedPath(normalizedParentPath)) {
        continue;
      }
      normalizedRoots.add(
        _QuarkDirectoryCursor(
          fid: normalizedParentFid,
          path: normalizedParentPath,
          sectionId: root.sectionId,
          sectionName: root.sectionName,
        ),
      );
    }
    if (normalizedRoots.isEmpty) {
      return const _QuarkLibraryScanResult();
    }

    if (reportRefreshProgress) {
      _quarkRefreshProgressController.startScanning(
        sourceId: source.id,
        sourceName: source.name,
        totalCollections: normalizedRoots.length,
        detail: normalizedRoots.first.path,
      );
    }

    final directoryEntriesByPath = <String, List<QuarkFileEntry>>{};
    final mediaEntries = <_QuarkQueuedMediaEntry>[];
    final queue = [...normalizedRoots];
    for (var index = 0;
        index < queue.length && mediaEntries.length < limit;
        index++) {
      final cursor = queue[index];
      final entries = await _quarkSaveClient.listEntries(
        cookie: cookie,
        parentFid: cursor.fid,
      );
      directoryEntriesByPath[cursor.path] = entries;
      for (final entry in entries) {
        if (source.matchesWebDavExcludedPath(entry.path)) {
          continue;
        }
        if (entry.isDirectory) {
          queue.add(
            _QuarkDirectoryCursor(
              fid: entry.fid,
              path: _normalizeQuarkDirectoryPath(entry.path),
              sectionId: cursor.sectionId,
              sectionName: cursor.sectionName,
            ),
          );
          continue;
        }
        if (!entry.isVideo) {
          continue;
        }
        mediaEntries.add(
          _QuarkQueuedMediaEntry(
            entry: entry,
            sectionId: cursor.sectionId,
            sectionName: cursor.sectionName,
          ),
        );
        if (mediaEntries.length >= limit) {
          break;
        }
      }
      if (reportRefreshProgress) {
        _quarkRefreshProgressController.updateScanning(
          sourceId: source.id,
          current: index + 1,
          total: queue.length,
          detail: cursor.path,
        );
      }
    }

    return _QuarkLibraryScanResult(
      directoryEntriesByPath: directoryEntriesByPath,
      mediaEntries: mediaEntries,
    );
  }

  WebDavScrapeProgressController get _quarkRefreshProgressController {
    return ref.read(webDavScrapeProgressProvider.notifier);
  }

  void _clearQuarkRefreshProgress(String sourceId) {
    try {
      _quarkRefreshProgressController.clear(sourceId);
    } catch (_) {
      // The provider may already be disposed after page teardown or in tests.
    }
  }

  Future<MediaItem> _buildQuarkMediaItem({
    required MediaSourceConfig source,
    required QuarkFileEntry entry,
    required String cookie,
    required String sectionId,
    required String sectionName,
    required Map<String, List<QuarkFileEntry>> directoryEntriesByPath,
    required Map<String, Future<String>> textFileCache,
    required Map<String, Future<QuarkResolvedDownload>> downloadCache,
  }) async {
    final recognition = _resolveQuarkRecognition(source, entry);
    var seed = _buildQuarkBaseMetadataSeed(
      source: source,
      entry: entry,
      recognition: recognition,
    );
    if (source.webDavSidecarScrapingEnabled) {
      seed = await _applyQuarkSidecarMetadata(
        source: source,
        entry: entry,
        cookie: cookie,
        seed: seed,
        directoryEntriesByPath: directoryEntriesByPath,
        textFileCache: textFileCache,
        downloadCache: downloadCache,
      );
    }
    final normalizedTitle = seed.title.trim().isNotEmpty
        ? seed.title.trim()
        : _stripFileExtension(entry.name);
    final resourceId = _buildQuarkResourceId(
      fid: entry.fid,
      path: entry.path,
    );
    return MediaItem(
      id: resourceId,
      title: normalizedTitle,
      originalTitle: _stripFileExtension(entry.name),
      sortTitle: normalizedTitle,
      overview: seed.overview,
      posterUrl: seed.posterUrl,
      posterHeaders: seed.posterHeaders,
      backdropUrl: seed.backdropUrl,
      backdropHeaders: seed.backdropHeaders,
      logoUrl: seed.logoUrl,
      logoHeaders: seed.logoHeaders,
      bannerUrl: seed.bannerUrl,
      bannerHeaders: seed.bannerHeaders,
      extraBackdropUrls: seed.extraBackdropUrls,
      extraBackdropHeaders: seed.extraBackdropHeaders,
      year: seed.year,
      durationLabel: seed.durationLabel,
      genres: seed.genres,
      directors: seed.directors,
      actors: seed.actors,
      itemType: seed.itemType,
      isFolder: false,
      sectionId: sectionId,
      sectionName: sectionName,
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
      streamUrl: '',
      actualAddress: entry.path,
      playbackItemId: entry.fid,
      seasonNumber: seed.seasonNumber,
      episodeNumber: seed.episodeNumber,
      imdbId: seed.imdbId,
      tmdbId: seed.tmdbId,
      ratingLabels: const [],
      container: seed.container,
      videoCodec: seed.videoCodec,
      audioCodec: seed.audioCodec,
      width: seed.width,
      height: seed.height,
      bitrate: seed.bitrate,
      fileSizeBytes: entry.sizeBytes,
      addedAt: entry.updatedAt ?? DateTime.now(),
    );
  }

  NasMediaRecognition _resolveQuarkRecognition(
    MediaSourceConfig source,
    QuarkFileEntry entry,
  ) {
    final useStructureInference = source.webDavStructureInferenceEnabled;
    return NasMediaRecognizer.recognize(
      useStructureInference ? entry.path : entry.name,
      seriesTitleFilterKeywords: useStructureInference
          ? source.normalizedWebDavSeriesTitleFilterKeywords
          : const <String>[],
      specialEpisodeKeywords: source.normalizedWebDavSpecialCategoryKeywords,
    );
  }

  WebDavMetadataSeed _buildQuarkBaseMetadataSeed({
    required MediaSourceConfig source,
    required QuarkFileEntry entry,
    required NasMediaRecognition recognition,
  }) {
    final normalizedTitle = recognition.title.trim().isNotEmpty
        ? recognition.title.trim()
        : _stripFileExtension(entry.name);
    final normalizedItemType = recognition.itemType.trim().isNotEmpty
        ? recognition.itemType.trim()
        : 'movie';
    return WebDavMetadataSeed(
      title: normalizedTitle,
      overview: '',
      posterUrl: '',
      posterHeaders: const <String, String>{},
      backdropUrl: '',
      backdropHeaders: const <String, String>{},
      logoUrl: '',
      logoHeaders: const <String, String>{},
      bannerUrl: '',
      bannerHeaders: const <String, String>{},
      extraBackdropUrls: const <String>[],
      extraBackdropHeaders: const <String, String>{},
      year: recognition.year,
      durationLabel: normalizedItemType == 'episode' ? '剧集' : '文件',
      genres: const <String>[],
      directors: const <String>[],
      actors: const <String>[],
      itemType: normalizedItemType,
      seasonNumber: recognition.seasonNumber,
      episodeNumber: recognition.episodeNumber,
      imdbId: recognition.imdbId,
      tmdbId: '',
      container: entry.extension,
      videoCodec: '',
      audioCodec: '',
      width: null,
      height: null,
      bitrate: null,
      hasSidecarMatch: false,
    );
  }

  Future<WebDavMetadataSeed> _applyQuarkSidecarMetadata({
    required MediaSourceConfig source,
    required QuarkFileEntry entry,
    required String cookie,
    required WebDavMetadataSeed seed,
    required Map<String, List<QuarkFileEntry>> directoryEntriesByPath,
    required Map<String, Future<String>> textFileCache,
    required Map<String, Future<QuarkResolvedDownload>> downloadCache,
  }) async {
    final currentDirectoryPath = _parentQuarkDirectoryPath(entry.path) ?? '/';
    final parentDirectoryPath = _parentQuarkDirectoryPath(currentDirectoryPath);
    final grandParentDirectoryPath = parentDirectoryPath == null
        ? null
        : _parentQuarkDirectoryPath(parentDirectoryPath);
    final siblings = directoryEntriesByPath[currentDirectoryPath] ??
        const <QuarkFileEntry>[];
    final parentEntries = parentDirectoryPath == null
        ? const <QuarkFileEntry>[]
        : (directoryEntriesByPath[parentDirectoryPath] ??
            const <QuarkFileEntry>[]);
    final grandParentEntries = grandParentDirectoryPath == null
        ? const <QuarkFileEntry>[]
        : (directoryEntriesByPath[grandParentDirectoryPath] ??
            const <QuarkFileEntry>[]);

    final primaryNfoEntry = _findBestQuarkNfoEntry(entry, siblings);
    final seasonNfoEntry = _findNamedQuarkFileEntry(
      siblings,
      const ['season.nfo', 'index.nfo'],
      excluding: primaryNfoEntry,
    );
    final seriesNfoEntry = _findNamedQuarkFileEntry(
          parentEntries,
          const ['tvshow.nfo', 'index.nfo'],
        ) ??
        _findNamedQuarkFileEntry(
          grandParentEntries,
          const ['tvshow.nfo', 'index.nfo'],
        );

    final primaryNfoMetadata = await _loadQuarkNfoMetadata(
      entry: primaryNfoEntry,
      cookie: cookie,
      textFileCache: textFileCache,
    );
    final seasonNfoMetadata = await _loadQuarkNfoMetadata(
      entry: seasonNfoEntry,
      cookie: cookie,
      textFileCache: textFileCache,
    );
    final seriesNfoMetadata = await _loadQuarkNfoMetadata(
      entry: seriesNfoEntry,
      cookie: cookie,
      textFileCache: textFileCache,
    );
    final nfoMetadata = _mergeQuarkNfoMetadata(
      primary: primaryNfoMetadata,
      secondary: _mergeQuarkNfoMetadata(
        primary: seasonNfoMetadata,
        secondary: seriesNfoMetadata,
      ),
    );

    final posterEntry = _findBestQuarkPosterEntry(entry, siblings) ??
        _findQuarkArtworkByRole(
            parentEntries, const ['poster', 'folder', 'cover']) ??
        _findQuarkArtworkByRole(
          grandParentEntries,
          const ['poster', 'folder', 'cover'],
        );
    final backdropEntry = _findQuarkArtworkByRole(
            siblings, const ['fanart', 'backdrop', 'landscape']) ??
        _findQuarkArtworkByRole(
          parentEntries,
          const ['fanart', 'backdrop', 'landscape'],
        ) ??
        _findQuarkArtworkByRole(
          grandParentEntries,
          const ['fanart', 'backdrop', 'landscape'],
        );
    final logoEntry = _findQuarkArtworkByRole(
          siblings,
          const ['clearlogo', 'logo'],
        ) ??
        _findQuarkArtworkByRole(
          parentEntries,
          const ['clearlogo', 'logo'],
        ) ??
        _findQuarkArtworkByRole(
          grandParentEntries,
          const ['clearlogo', 'logo'],
        );
    final bannerEntry = _findQuarkArtworkByRole(
          siblings,
          const ['banner'],
        ) ??
        _findQuarkArtworkByRole(
          parentEntries,
          const ['banner'],
        ) ??
        _findQuarkArtworkByRole(
          grandParentEntries,
          const ['banner'],
        );

    final posterArtwork = await _resolveQuarkArtwork(
      localEntry: posterEntry,
      remoteUrl: nfoMetadata?.thumbUrl ?? '',
      cookie: cookie,
      downloadCache: downloadCache,
    );
    final backdropArtwork = await _resolveQuarkArtwork(
      localEntry: backdropEntry,
      remoteUrl: nfoMetadata?.backdropUrl ?? '',
      cookie: cookie,
      downloadCache: downloadCache,
    );
    final logoArtwork = await _resolveQuarkArtwork(
      localEntry: logoEntry,
      remoteUrl: nfoMetadata?.logoUrl ?? '',
      cookie: cookie,
      downloadCache: downloadCache,
    );
    final bannerArtwork = await _resolveQuarkArtwork(
      localEntry: bannerEntry,
      remoteUrl: nfoMetadata?.bannerUrl ?? '',
      cookie: cookie,
      downloadCache: downloadCache,
    );

    final hasSidecarMatch = nfoMetadata != null ||
        posterArtwork.url.isNotEmpty ||
        backdropArtwork.url.isNotEmpty ||
        logoArtwork.url.isNotEmpty ||
        bannerArtwork.url.isNotEmpty ||
        (nfoMetadata?.extraBackdropUrls.isNotEmpty ?? false);
    return seed.copyWith(
      title: nfoMetadata?.title.trim().isNotEmpty == true
          ? nfoMetadata!.title.trim()
          : seed.title,
      overview: nfoMetadata?.overview.trim().isNotEmpty == true
          ? nfoMetadata!.overview.trim()
          : seed.overview,
      posterUrl:
          posterArtwork.url.isNotEmpty ? posterArtwork.url : seed.posterUrl,
      posterHeaders: posterArtwork.url.isNotEmpty
          ? posterArtwork.headers
          : seed.posterHeaders,
      backdropUrl: backdropArtwork.url.isNotEmpty
          ? backdropArtwork.url
          : seed.backdropUrl,
      backdropHeaders: backdropArtwork.url.isNotEmpty
          ? backdropArtwork.headers
          : seed.backdropHeaders,
      logoUrl: logoArtwork.url.isNotEmpty ? logoArtwork.url : seed.logoUrl,
      logoHeaders:
          logoArtwork.url.isNotEmpty ? logoArtwork.headers : seed.logoHeaders,
      bannerUrl:
          bannerArtwork.url.isNotEmpty ? bannerArtwork.url : seed.bannerUrl,
      bannerHeaders: bannerArtwork.url.isNotEmpty
          ? bannerArtwork.headers
          : seed.bannerHeaders,
      extraBackdropUrls: nfoMetadata?.extraBackdropUrls.isNotEmpty == true
          ? nfoMetadata!.extraBackdropUrls
          : seed.extraBackdropUrls,
      extraBackdropHeaders: nfoMetadata?.extraBackdropUrls.isNotEmpty == true
          ? const <String, String>{}
          : seed.extraBackdropHeaders,
      year: (nfoMetadata?.year ?? 0) > 0 ? nfoMetadata!.year : seed.year,
      durationLabel: nfoMetadata?.durationLabel.trim().isNotEmpty == true
          ? nfoMetadata!.durationLabel.trim()
          : seed.durationLabel,
      genres: nfoMetadata?.genres.isNotEmpty == true
          ? nfoMetadata!.genres
          : seed.genres,
      directors: nfoMetadata?.directors.isNotEmpty == true
          ? nfoMetadata!.directors
          : seed.directors,
      actors: nfoMetadata?.actors.isNotEmpty == true
          ? nfoMetadata!.actors
          : seed.actors,
      itemType: nfoMetadata?.itemType.trim().isNotEmpty == true
          ? nfoMetadata!.itemType.trim()
          : seed.itemType,
      seasonNumber: nfoMetadata?.seasonNumber ?? seed.seasonNumber,
      episodeNumber: nfoMetadata?.episodeNumber ?? seed.episodeNumber,
      imdbId: nfoMetadata?.imdbId.trim().isNotEmpty == true
          ? nfoMetadata!.imdbId.trim()
          : seed.imdbId,
      tmdbId: nfoMetadata?.tmdbId.trim().isNotEmpty == true
          ? nfoMetadata!.tmdbId.trim()
          : seed.tmdbId,
      container: nfoMetadata?.container.trim().isNotEmpty == true
          ? nfoMetadata!.container.trim()
          : seed.container,
      videoCodec: nfoMetadata?.videoCodec.trim().isNotEmpty == true
          ? nfoMetadata!.videoCodec.trim()
          : seed.videoCodec,
      audioCodec: nfoMetadata?.audioCodec.trim().isNotEmpty == true
          ? nfoMetadata!.audioCodec.trim()
          : seed.audioCodec,
      width: nfoMetadata?.width ?? seed.width,
      height: nfoMetadata?.height ?? seed.height,
      bitrate: nfoMetadata?.bitrate ?? seed.bitrate,
      hasSidecarMatch: seed.hasSidecarMatch || hasSidecarMatch,
    );
  }

  Future<_QuarkParsedNfoMetadata?> _loadQuarkNfoMetadata({
    required QuarkFileEntry? entry,
    required String cookie,
    required Map<String, Future<String>> textFileCache,
  }) async {
    if (entry == null) {
      return null;
    }
    try {
      final raw = await textFileCache.putIfAbsent(
        entry.fid,
        () => _quarkSaveClient.readTextFile(
          cookie: cookie,
          fid: entry.fid,
        ),
      );
      return _parseQuarkNfoMetadata(raw);
    } catch (_) {
      return null;
    }
  }

  _QuarkParsedNfoMetadata? _parseQuarkNfoMetadata(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final document = XmlDocument.parse(trimmed);
      final root = document.rootElement;
      final durationLabel = _formatRuntimeLabel(
        _quarkXmlSingleText(root, 'runtime'),
      );
      return _QuarkParsedNfoMetadata(
        title: _quarkXmlSingleText(root, 'title'),
        overview: _quarkXmlSingleText(root, 'plot'),
        thumbUrl: _quarkResolveNfoArtUrl(
          root,
          tagNames: const ['thumb', 'poster'],
        ),
        backdropUrl: _quarkResolveNfoArtUrl(
          root,
          tagNames: const ['fanart', 'backdrop', 'landscape'],
        ),
        logoUrl: _quarkResolveNfoArtUrl(
          root,
          tagNames: const ['clearlogo', 'logo'],
        ),
        bannerUrl: _quarkResolveNfoArtUrl(
          root,
          tagNames: const ['banner'],
        ),
        extraBackdropUrls: _quarkResolveNfoExtraBackdropUrls(root),
        year: _parseQuarkNfoYear(
          _quarkXmlSingleText(root, 'year'),
          fallbackDateText:
              '${_quarkXmlSingleText(root, 'premiered')} ${_quarkXmlSingleText(root, 'aired')}',
        ),
        durationLabel: durationLabel,
        genres: _quarkXmlTexts(root, 'genre'),
        directors: _quarkXmlTexts(root, 'director'),
        actors: _quarkResolveNfoActors(root),
        itemType: _resolveQuarkNfoItemType(root.name.local),
        seasonNumber: _tryParseInt(_quarkXmlSingleText(root, 'season')),
        episodeNumber: _tryParseInt(_quarkXmlSingleText(root, 'episode')),
        imdbId: _resolveQuarkNfoExternalId(
          root,
          type: 'imdb',
          fallbackTag: 'imdbid',
        ),
        tmdbId: _resolveQuarkNfoExternalId(
          root,
          type: 'tmdb',
          fallbackTag: 'tmdbid',
        ),
        container: _quarkResolveNfoStreamValue(
          root,
          primary: 'container',
          section: 'fileinfo',
        ),
        videoCodec: _quarkResolveNfoStreamValue(
          root,
          primary: 'codec',
          section: 'video',
        ),
        audioCodec: _quarkResolveNfoStreamValue(
          root,
          primary: 'codec',
          section: 'audio',
        ),
        width: _tryParseInt(
          _quarkResolveNfoStreamValue(
            root,
            primary: 'width',
            section: 'video',
          ),
        ),
        height: _tryParseInt(
          _quarkResolveNfoStreamValue(
            root,
            primary: 'height',
            section: 'video',
          ),
        ),
        bitrate: _tryParseInt(
          _quarkResolveNfoStreamValue(
            root,
            primary: 'bitrate',
            section: 'video',
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  _QuarkParsedNfoMetadata? _mergeQuarkNfoMetadata({
    required _QuarkParsedNfoMetadata? primary,
    required _QuarkParsedNfoMetadata? secondary,
  }) {
    if (primary == null) {
      return secondary;
    }
    if (secondary == null) {
      return primary;
    }
    return _QuarkParsedNfoMetadata(
      title: primary.title.trim().isNotEmpty ? primary.title : secondary.title,
      overview: primary.overview.trim().isNotEmpty
          ? primary.overview
          : secondary.overview,
      thumbUrl: primary.thumbUrl.trim().isNotEmpty
          ? primary.thumbUrl
          : secondary.thumbUrl,
      backdropUrl: primary.backdropUrl.trim().isNotEmpty
          ? primary.backdropUrl
          : secondary.backdropUrl,
      logoUrl: primary.logoUrl.trim().isNotEmpty
          ? primary.logoUrl
          : secondary.logoUrl,
      bannerUrl: primary.bannerUrl.trim().isNotEmpty
          ? primary.bannerUrl
          : secondary.bannerUrl,
      extraBackdropUrls: primary.extraBackdropUrls.isNotEmpty
          ? primary.extraBackdropUrls
          : secondary.extraBackdropUrls,
      year: primary.year > 0 ? primary.year : secondary.year,
      durationLabel: primary.durationLabel.trim().isNotEmpty &&
              primary.durationLabel.trim() != '文件'
          ? primary.durationLabel
          : secondary.durationLabel,
      genres: primary.genres.isNotEmpty ? primary.genres : secondary.genres,
      directors: primary.directors.isNotEmpty
          ? primary.directors
          : secondary.directors,
      actors: primary.actors.isNotEmpty ? primary.actors : secondary.actors,
      itemType: primary.itemType.trim().isNotEmpty
          ? primary.itemType
          : secondary.itemType,
      seasonNumber: primary.seasonNumber ?? secondary.seasonNumber,
      episodeNumber: primary.episodeNumber ?? secondary.episodeNumber,
      imdbId:
          primary.imdbId.trim().isNotEmpty ? primary.imdbId : secondary.imdbId,
      tmdbId:
          primary.tmdbId.trim().isNotEmpty ? primary.tmdbId : secondary.tmdbId,
      container: primary.container.trim().isNotEmpty
          ? primary.container
          : secondary.container,
      videoCodec: primary.videoCodec.trim().isNotEmpty
          ? primary.videoCodec
          : secondary.videoCodec,
      audioCodec: primary.audioCodec.trim().isNotEmpty
          ? primary.audioCodec
          : secondary.audioCodec,
      width: primary.width ?? secondary.width,
      height: primary.height ?? secondary.height,
      bitrate: primary.bitrate ?? secondary.bitrate,
    );
  }

  QuarkFileEntry? _findBestQuarkNfoEntry(
    QuarkFileEntry videoEntry,
    List<QuarkFileEntry> siblings,
  ) {
    final baseName = _stripFileExtension(videoEntry.name).toLowerCase();
    return _findNamedQuarkFileEntry(
      siblings,
      [
        '$baseName.nfo',
        'movie.nfo',
        'tvshow.nfo',
        'index.nfo',
      ],
    );
  }

  QuarkFileEntry? _findNamedQuarkFileEntry(
    List<QuarkFileEntry> entries,
    List<String> preferredNames, {
    QuarkFileEntry? excluding,
  }) {
    final loweredEntries = entries
        .where((entry) => !entry.isDirectory)
        .where((entry) => entry.name.toLowerCase().endsWith('.nfo'))
        .toList(growable: false);
    for (final preferredName in preferredNames) {
      for (final entry in loweredEntries) {
        if (excluding != null && entry.fid == excluding.fid) {
          continue;
        }
        if (entry.name.toLowerCase() == preferredName.toLowerCase()) {
          return entry;
        }
      }
    }
    return null;
  }

  QuarkFileEntry? _findBestQuarkPosterEntry(
    QuarkFileEntry videoEntry,
    List<QuarkFileEntry> siblings,
  ) {
    final baseName = _stripFileExtension(videoEntry.name);
    return _findQuarkArtworkByRole(
      siblings,
      [
        '$baseName-poster',
        baseName,
        'poster',
        'folder',
        'cover',
      ],
    );
  }

  QuarkFileEntry? _findQuarkArtworkByRole(
    List<QuarkFileEntry> entries,
    List<String> names,
  ) {
    final preferredNames = _expandQuarkArtworkNames(names);
    final imageEntries = entries
        .where((entry) => !entry.isDirectory && _isQuarkImageEntry(entry))
        .toList(growable: false);
    for (final preferredName in preferredNames) {
      for (final entry in imageEntries) {
        if (entry.name.toLowerCase() == preferredName.toLowerCase()) {
          return entry;
        }
      }
    }
    return null;
  }

  List<String> _expandQuarkArtworkNames(List<String> names) {
    final values = <String>[];
    final seen = <String>{};
    for (final rawName in names) {
      final normalized = rawName.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (normalized.contains('.')) {
        final lowered = normalized.toLowerCase();
        if (seen.add(lowered)) {
          values.add(normalized);
        }
        continue;
      }
      for (final extension in _quarkImageExtensions) {
        final candidate = '$normalized.$extension';
        final lowered = candidate.toLowerCase();
        if (seen.add(lowered)) {
          values.add(candidate);
        }
      }
    }
    return values;
  }

  bool _isQuarkImageEntry(QuarkFileEntry entry) {
    return _quarkImageExtensions.contains(entry.extension.trim().toLowerCase());
  }

  Future<_QuarkArtworkResolution> _resolveQuarkArtwork({
    required QuarkFileEntry? localEntry,
    required String remoteUrl,
    required String cookie,
    required Map<String, Future<QuarkResolvedDownload>> downloadCache,
  }) async {
    if (localEntry != null) {
      try {
        final download = await downloadCache.putIfAbsent(
          localEntry.fid,
          () => _quarkSaveClient.resolveDownload(
            cookie: cookie,
            fid: localEntry.fid,
          ),
        );
        return _QuarkArtworkResolution(
          url: download.url,
          headers: download.headers,
        );
      } catch (_) {
        // Fall through to remote artwork URL when local sidecar download fails.
      }
    }
    final normalizedRemoteUrl = remoteUrl.trim();
    final parsedRemoteUrl = Uri.tryParse(normalizedRemoteUrl);
    if (parsedRemoteUrl != null && parsedRemoteUrl.hasScheme) {
      return _QuarkArtworkResolution(url: normalizedRemoteUrl);
    }
    return const _QuarkArtworkResolution();
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

  String? _parentQuarkDirectoryPath(String raw) {
    final normalized = _normalizeQuarkDirectoryPath(raw);
    if (normalized == '/') {
      return null;
    }
    final segments = normalized
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }
    if (segments.length == 1) {
      return '/';
    }
    return '/${segments.take(segments.length - 1).join('/')}';
  }

  String _quarkXmlSingleText(XmlElement node, String localName) {
    final match = node.descendants.whereType<XmlElement>().firstWhere(
          (element) => element.name.local == localName,
          orElse: () => XmlElement(XmlName(localName)),
        );
    return match.innerText.trim();
  }

  List<String> _quarkXmlTexts(XmlElement node, String localName) {
    return node.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == localName)
        .map((element) => element.innerText.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _quarkResolveNfoActors(XmlElement root) {
    return root.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'actor')
        .map((element) => _quarkXmlSingleText(element, 'name'))
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
  }

  String _resolveQuarkNfoItemType(String rawRootName) {
    switch (rawRootName.trim().toLowerCase()) {
      case 'movie':
        return 'movie';
      case 'tvshow':
        return 'series';
      case 'episodedetails':
        return 'episode';
      default:
        return '';
    }
  }

  String _formatRuntimeLabel(String raw) {
    final minutes = _tryParseInt(raw);
    if (minutes != null && minutes > 0) {
      return '$minutes分钟';
    }
    return '文件';
  }

  int? _tryParseInt(String raw) {
    return int.tryParse(raw.trim());
  }

  int _parseQuarkNfoYear(
    String raw, {
    String fallbackDateText = '',
  }) {
    final parsed = _tryParseInt(raw);
    if (parsed != null && parsed > 0) {
      return parsed;
    }
    final match = RegExp(r'(\d{4})').firstMatch(fallbackDateText);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  String _resolveQuarkNfoExternalId(
    XmlElement root, {
    required String type,
    required String fallbackTag,
  }) {
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'uniqueid') {
        continue;
      }
      final idType = element.getAttribute('type')?.trim().toLowerCase() ?? '';
      if (idType == type) {
        final value = element.innerText.trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return _quarkXmlSingleText(root, fallbackTag);
  }

  String _quarkResolveNfoArtUrl(
    XmlElement root, {
    required List<String> tagNames,
  }) {
    final normalizedTagNames =
        tagNames.map((item) => item.trim().toLowerCase()).toSet();
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (!normalizedTagNames.contains(element.name.local.toLowerCase())) {
        continue;
      }
      final value = element.innerText.trim();
      final parsed = Uri.tryParse(value);
      if (parsed != null && parsed.hasScheme) {
        return value;
      }
    }
    for (final art in root.descendants.whereType<XmlElement>()) {
      if (art.name.local != 'art') {
        continue;
      }
      for (final child in art.children.whereType<XmlElement>()) {
        if (!normalizedTagNames.contains(child.name.local.toLowerCase())) {
          continue;
        }
        final value = child.innerText.trim();
        final parsed = Uri.tryParse(value);
        if (parsed != null && parsed.hasScheme) {
          return value;
        }
      }
    }
    return '';
  }

  List<String> _quarkResolveNfoExtraBackdropUrls(XmlElement root) {
    final urls = <String>[];
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'thumb') {
        continue;
      }
      final parentName = element.parentElement?.name.local.toLowerCase() ?? '';
      if (parentName != 'fanart') {
        continue;
      }
      final value = element.innerText.trim();
      final parsed = Uri.tryParse(value);
      if (parsed != null && parsed.hasScheme) {
        urls.add(value);
      }
    }
    return urls;
  }

  String _quarkResolveNfoStreamValue(
    XmlElement root, {
    required String primary,
    required String section,
  }) {
    final streamDetails = root.descendants.whereType<XmlElement>().firstWhere(
          (element) => element.name.local == 'streamdetails',
          orElse: () => XmlElement(XmlName('streamdetails')),
        );
    if (streamDetails.children.isEmpty) {
      return '';
    }

    for (final child in streamDetails.descendants.whereType<XmlElement>()) {
      if (child.name.local != section) {
        continue;
      }
      final value = _quarkXmlSingleText(child, primary);
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  String _buildQuarkResourceId({
    required String fid,
    required String path,
  }) {
    final normalizedFid = Uri.encodeComponent(fid.trim());
    return Uri(
      scheme: 'quark',
      host: 'entry',
      path: '/$normalizedFid',
      queryParameters: {
        if (path.trim().isNotEmpty) 'path': path.trim(),
      },
    ).toString();
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

  Future<void> _deleteMatchedQuarkDirectory(
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
      final alignedScopeSegments = _alignedScopeSegments(
        resourcePath: resourcePath,
        scopeDirectoryId: directory.directoryId,
      );
      if (alignedScopeSegments == null) {
        continue;
      }
      final candidate = _MatchedSyncDeleteScope(
        directory: directory,
        depth: alignedScopeSegments.length,
        matchMode: 'path_only',
      );
      if (directory.sourceId.trim() == source.id.trim()) {
        exactMatch = withGreaterDepth(
          exactMatch,
          candidate.copyWith(matchMode: 'source_id'),
        );
        continue;
      }
      final normalizedDirectorySourceName =
          directory.sourceName.trim().toLowerCase();
      if (normalizedSourceName.isNotEmpty &&
          normalizedDirectorySourceName.isNotEmpty &&
          normalizedDirectorySourceName == normalizedSourceName) {
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

class _SourceFetchResult {
  const _SourceFetchResult({
    required this.items,
    this.error,
    this.stackTrace,
  });

  final List<MediaItem> items;
  final Object? error;
  final StackTrace? stackTrace;
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

class _QuarkDirectoryCursor {
  const _QuarkDirectoryCursor({
    required this.fid,
    required this.path,
    this.sectionId = '',
    this.sectionName = '',
  });

  final String fid;
  final String path;
  final String sectionId;
  final String sectionName;
}

class _QuarkQueuedMediaEntry {
  const _QuarkQueuedMediaEntry({
    required this.entry,
    required this.sectionId,
    required this.sectionName,
  });

  final QuarkFileEntry entry;
  final String sectionId;
  final String sectionName;
}

class _QuarkLibraryScanResult {
  const _QuarkLibraryScanResult({
    this.directoryEntriesByPath = const <String, List<QuarkFileEntry>>{},
    this.mediaEntries = const <_QuarkQueuedMediaEntry>[],
  });

  final Map<String, List<QuarkFileEntry>> directoryEntriesByPath;
  final List<_QuarkQueuedMediaEntry> mediaEntries;
}

class _QuarkParsedNfoMetadata {
  const _QuarkParsedNfoMetadata({
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

class _QuarkArtworkResolution {
  const _QuarkArtworkResolution({
    this.url = '',
    this.headers = const <String, String>{},
  });

  final String url;
  final Map<String, String> headers;
}

const Set<String> _quarkImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
};

class _ParsedQuarkResourceId {
  const _ParsedQuarkResourceId({
    required this.fid,
    required this.path,
  });

  final String fid;
  final String path;
}
