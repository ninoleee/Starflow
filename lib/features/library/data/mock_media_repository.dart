import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
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

  Future<void> refreshSource({
    required String sourceId,
    bool forceFullRescan = false,
  });

  Future<void> cancelActiveWebDavRefreshes();

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
    ref.read(quarkSaveClientProvider),
  ),
);

class AppMediaRepository implements MediaRepository {
  AppMediaRepository(
    this.ref,
    this._embyApiClient,
    this._webDavNasClient,
    this._nasMediaIndexer,
    this._quarkSaveClient,
  );

  final Ref ref;
  final EmbyApiClient _embyApiClient;
  final WebDavNasClient _webDavNasClient;
  final NasMediaIndexer _nasMediaIndexer;
  final QuarkSaveClient _quarkSaveClient;

  List<MediaSourceConfig> get _enabledSources {
    return ref
        .read(appSettingsProvider)
        .mediaSources
        .where((item) => item.enabled)
        .toList();
  }

  List<MediaItem> get _enabledLibrary {
    final enabledSourceIds = _enabledSources.map((item) => item.id).toSet();
    return SeedData.seedLibrary
        .where((item) => enabledSourceIds.contains(item.sourceId))
        .toList();
  }

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _enabledSources;
  }

  @override
  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async {
    final sources = _enabledSources
        .where(
          (item) =>
              (kind == null || item.kind == kind) &&
              (sourceId == null || sourceId == item.id),
        )
        .toList();
    final collections = await Future.wait(
      sources.map((source) async {
        try {
          return await _fetchCollectionsForSource(source);
        } catch (_) {
          return const <MediaCollection>[];
        }
      }),
    );

    return collections.expand((item) => item).toList();
  }

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    final sources = _enabledSources
        .where(
          (item) =>
              (kind == null || item.kind == kind) &&
              (sourceId == null || sourceId == item.id),
        )
        .toList();
    final seededLibrary = _enabledLibrary;
    final sourceResults = await Future.wait(
      sources.map(
        (source) => _fetchLibraryForSource(
          source,
          sectionId: sectionId,
          limit: limit,
          seededLibrary: seededLibrary,
        ),
      ),
    );
    final items = sourceResults.expand((group) => group.items).toList();

    if (items.isEmpty) {
      for (final result in sourceResults) {
        if (result.error != null) {
          Error.throwWithStackTrace(
            result.error!,
            result.stackTrace ?? StackTrace.current,
          );
        }
      }
    }

    items.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return items;
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    final items = await fetchLibrary(kind: kind, limit: limit);
    return items.take(limit).toList();
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
      final selectedCollections = await _selectedCollectionsForSource(source);
      if (_hasScopedSections(source) && selectedCollections.isEmpty) {
        return;
      }
      if (_hasScopedSections(source)) {
        await _fetchLibraryFromCollections(
          source,
          selectedCollections,
          limit: 200,
        );
        return;
      }
      await _embyApiClient.fetchCollections(source);
      await _embyApiClient.fetchLibrary(source, limit: 200);
      return;
    }

    if (source.hasExplicitNoSectionsSelected) {
      await _nasMediaIndexer.clearSource(source.id);
      return;
    }
    final selectedCollections = await _selectedCollectionsForSource(source);
    if (_hasScopedSections(source) && selectedCollections.isEmpty) {
      await _nasMediaIndexer.clearSource(source.id);
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
  }

  @override
  Future<void> cancelActiveWebDavRefreshes() {
    return _nasMediaIndexer.cancelAllRefreshTasks();
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
    if (source == null || source.kind != MediaSourceKind.nas) {
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
    await ref
        .read(localStorageCacheRepositoryProvider)
        .clearDetailCacheForResource(
          sourceId: normalizedSourceId,
          resourceId: isDirectResourceId ? normalizedResourcePath : '',
          resourcePath: effectiveResourcePath,
          treatAsScope: !_looksLikePlayableResourcePath(effectiveResourcePath),
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
    final normalizedSourceId = sourceId.trim();
    final normalizedParentId = parentId.trim();
    if (normalizedSourceId.isEmpty || normalizedParentId.isEmpty) {
      return const [];
    }

    MediaSourceConfig? source;
    for (final candidate in _enabledSources) {
      if (candidate.id == normalizedSourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null || !source.enabled) {
      return const [];
    }

    if (source.kind == MediaSourceKind.emby) {
      if (!source.hasActiveSession) {
        return const [];
      }
      return _embyApiClient.fetchChildren(
        source,
        parentId: normalizedParentId,
        sectionId: sectionId,
        sectionName: sectionName,
        limit: limit,
      );
    }
    final scopedCollections = _hasScopedSections(source)
        ? await _selectedCollectionsForSource(source)
        : null;
    return _nasMediaIndexer.loadChildren(
      source,
      parentId: normalizedParentId,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
      limit: limit,
    );
  }

  @override
  Future<MediaItem?> findById(String id) async {
    final matches = (await fetchLibrary()).where((item) => item.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    final library = await fetchLibrary(limit: 2000);
    return matchMediaItemByTitles(library, titles: [title]);
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

  Future<_SourceFetchResult> _fetchLibraryForSource(
    MediaSourceConfig source, {
    required String? sectionId,
    required int limit,
    required List<MediaItem> seededLibrary,
  }) async {
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
  }) async {
    var items = await _nasMediaIndexer.loadLibrary(
      source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
      limit: limit,
    );
    if (items.isNotEmpty) {
      return items;
    }

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
    return items;
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
    final List<NasMediaIndexRecord> scopeRecords = isDirectoryScope
        ? await _nasMediaIndexer.loadRecordsInScope(
            sourceId: source.id,
            resourcePath: effectiveResourcePath,
          )
        : const <NasMediaIndexRecord>[];
    if (!isDirectoryScope &&
        !_looksLikeStrmResourcePath(effectiveResourcePath)) {
      _logQuarkSyncDelete(
        'prepare.skip',
        fields: {
          'reason': 'not_strm',
          'sourceId': source.id,
          'resourcePath': resourcePath,
          'effectiveResourcePath': effectiveResourcePath,
        },
      );
      return null;
    }
    if (isDirectoryScope && scopeRecords.isEmpty) {
      _logQuarkSyncDelete(
        'prepare.skip',
        fields: {
          'reason': 'directory_scope_without_records',
          'sourceId': source.id,
          'resourcePath': resourcePath,
          'effectiveResourcePath': effectiveResourcePath,
        },
      );
      return null;
    }

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

    final resolvedTargetUrl = await _resolveScopeQuarkTargetUrl(
      source: source,
      resourcePath: resourcePath,
      effectiveResourcePath: effectiveResourcePath,
      sectionId: sectionId,
      scopeRecords: scopeRecords,
    );
    _logQuarkSyncDelete(
      'prepare.resolvedTarget',
      fields: {
        'sourceId': source.id,
        'resourcePath': resourcePath,
        'effectiveResourcePath': effectiveResourcePath,
        'isDirectoryScope': isDirectoryScope,
        'scopeRecordCount': isDirectoryScope ? scopeRecords.length : 0,
        'resolvedTargetUrl': resolvedTargetUrl,
      },
    );
    if (!_looksLikeQuarkNetdiskUrl(resolvedTargetUrl)) {
      _logQuarkSyncDelete(
        'prepare.skip',
        fields: {
          'reason': 'resolved_target_not_quark',
          'sourceId': source.id,
          'resourcePath': resourcePath,
          'resolvedTargetUrl': resolvedTargetUrl,
        },
      );
      return null;
    }

    final candidateNames = _buildQuarkDirectoryNameCandidates(
      effectiveResourcePath,
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

  Future<String> _resolveScopeQuarkTargetUrl({
    required MediaSourceConfig source,
    required String resourcePath,
    required String effectiveResourcePath,
    required String sectionId,
    required List<NasMediaIndexRecord> scopeRecords,
  }) async {
    if (!_looksLikePlayableResourcePath(effectiveResourcePath)) {
      for (final record in scopeRecords) {
        if (!_looksLikeStrmResourcePath(record.resourcePath)) {
          continue;
        }
        final resolvedTargetUrl = await _resolveStrmTargetUrlSafely(
          source: source,
          resourcePath: record.resourceId.trim().isNotEmpty
              ? record.resourceId
              : record.resourcePath,
          sectionId: record.sectionId,
        );
        _logQuarkSyncDelete(
          'prepare.scopeRecordResolved',
          fields: {
            'scopeResourcePath': effectiveResourcePath,
            'recordResourceId': record.resourceId,
            'recordResourcePath': record.resourcePath,
            'resolvedTargetUrl': resolvedTargetUrl,
          },
        );
        if (_looksLikeQuarkNetdiskUrl(resolvedTargetUrl)) {
          return resolvedTargetUrl;
        }
      }
      return '';
    }

    return _resolveStrmTargetUrlSafely(
      source: source,
      resourcePath: resourcePath,
      sectionId: sectionId,
    );
  }

  Future<String> _resolveStrmTargetUrlSafely({
    required MediaSourceConfig source,
    required String resourcePath,
    required String sectionId,
  }) async {
    try {
      return await _webDavNasClient.resolveStrmTargetUrl(
        source: source,
        resourcePath: resourcePath,
        sectionId: sectionId,
      );
    } catch (error) {
      _logQuarkSyncDelete(
        'prepare.resolveTargetError',
        fields: {
          'sourceId': source.id,
          'resourcePath': resourcePath,
          'error': error,
        },
      );
      return '';
    }
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

    final candidates = <String>{};

    void addCandidate(String value) {
      final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (trimmed.isNotEmpty) {
        candidates.add(trimmed);
      }
    }

    addCandidate(rawRootName);
    addCandidate(rawRootName.replaceAll(RegExp(r'\{[^}]+\}'), ' '));
    addCandidate(rawRootName.replaceAll(RegExp(r'\[[^\]]+\]'), ' '));
    addCandidate(
      rawRootName
          .replaceAll(RegExp(r'\{[^}]+\}'), ' ')
          .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
          .replaceAll(RegExp(r'\(\d{4}\)'), ' '),
    );
    addCandidate(
      rawRootName
          .replaceAll(RegExp(r'\{[^}]+\}'), ' ')
          .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
          .replaceAll(RegExp(r'\(\d{4}\)'), ' ')
          .replaceAll(
            RegExp(r'\b(?:2160p|1080p|720p|4k|remux|web-dl|bluray)\b',
                caseSensitive: false),
            ' ',
          ),
    );

    return candidates.toList(growable: false);
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

  bool _looksLikeStrmResourcePath(String value) {
    return _uriPath(value).toLowerCase().endsWith('.strm');
  }

  bool _looksLikeQuarkNetdiskUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'pan.quark.cn' ||
        host == 'drive-pc.quark.cn' ||
        host == 'drive.quark.cn' ||
        host.endsWith('.quark.cn');
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
    return _parseSeasonNumberFromLabel(value) != null ||
        _looksLikeNumericTopicSeason(value);
  }

  int? _parseSeasonNumberFromLabel(String value) {
    final normalized = value.trim();
    for (final pattern in const [
      r'(?:^|[ ._\-])s(\d{1,2})(?:$|[ ._\-])',
      r'season[ ._\-]?(\d{1,2})',
      r'第(\d{1,2})季',
    ]) {
      final match =
          RegExp(pattern, caseSensitive: false).firstMatch(normalized);
      final parsed = int.tryParse(match?.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  bool _looksLikeNumericTopicSeason(String value) {
    return RegExp(r'^\s*\d{1,2}(?:[ ._\-]|$)').hasMatch(value);
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
  }) {
    final buffer = StringBuffer('[QuarkSyncDelete] $action');
    if (fields.isNotEmpty) {
      final normalizedFields = fields.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(' | ');
      buffer.write(' | $normalizedFields');
    }
    debugPrint(buffer.toString());
  }
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
