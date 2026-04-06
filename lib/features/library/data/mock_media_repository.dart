import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
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
  ),
);

class AppMediaRepository implements MediaRepository {
  AppMediaRepository(
    this.ref,
    this._embyApiClient,
    this._webDavNasClient,
    this._nasMediaIndexer,
  );

  final Ref ref;
  final EmbyApiClient _embyApiClient;
  final WebDavNasClient _webDavNasClient;
  final NasMediaIndexer _nasMediaIndexer;

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

    await _webDavNasClient.deleteResource(
      source,
      resourcePath: normalizedResourcePath,
      sectionId: sectionId,
    );
    await _nasMediaIndexer.removeResourceScope(
      sourceId: normalizedSourceId,
      resourcePath: normalizedResourcePath,
    );
    await ref
        .read(localStorageCacheRepositoryProvider)
        .clearDetailCacheForSource(normalizedSourceId);
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
