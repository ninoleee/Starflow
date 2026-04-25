import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/application/empty_library_auto_rebuild_scheduler.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/quark_external_storage_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

class AppMediaQueryService {
  static const Duration _embyAutoRefreshInterval = Duration(hours: 24);

  AppMediaQueryService({
    required this.ref,
    required EmbyApiClient embyApiClient,
    required WebDavNasClient webDavNasClient,
    required NasMediaIndexer nasMediaIndexer,
    required QuarkExternalStorageClient quarkExternalStorageClient,
  })  : _embyApiClient = embyApiClient,
        _webDavNasClient = webDavNasClient,
        _nasMediaIndexer = nasMediaIndexer,
        _quarkExternalStorageClient = quarkExternalStorageClient,
        _emptyLibraryAutoRebuildScheduler = EmptyLibraryAutoRebuildScheduler();

  final Ref ref;
  final EmbyApiClient _embyApiClient;
  final WebDavNasClient _webDavNasClient;
  final NasMediaIndexer _nasMediaIndexer;
  final QuarkExternalStorageClient _quarkExternalStorageClient;
  final EmptyLibraryAutoRebuildScheduler _emptyLibraryAutoRebuildScheduler;
  final Map<String, Future<void>> _embyRefreshFutures =
      <String, Future<void>>{};
  final Map<String, _CachedEmbyLibraryMatchIndex> _embyLibraryMatchIndexes =
      <String, _CachedEmbyLibraryMatchIndex>{};

  Future<List<MediaSourceConfig>> fetchSources() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _enabledSources;
  }

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

    return collections.expand((item) => item).toList(growable: false);
  }

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
    final sourceResults = await Future.wait(
      sources.map(
        (source) => _fetchLibraryForSource(
          source,
          sectionId: sectionId,
          limit: limit,
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

  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    final items = await fetchLibrary(kind: kind, limit: limit);
    return items.take(limit).toList();
  }

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
    if (source == null) {
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

  Future<MediaItem?> findById(String id) async {
    final matches = (await fetchLibrary()).where((item) => item.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  Future<MediaItem?> matchTitle(String title) async {
    final library = await fetchLibrary(limit: 2000);
    return matchMediaItemByTitles(library, titles: [title]);
  }

  Future<List<MediaItem>> loadCachedEmbyLibraryMatchItems(
    MediaSourceConfig source, {
    Iterable<String> titles = const <String>[],
    int year = 0,
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
    int limit = 2000,
  }) async {
    if (source.kind != MediaSourceKind.emby || !source.hasActiveSession) {
      return const <MediaItem>[];
    }
    final snapshot = await _loadCachedEmbySnapshot(source);
    final items = _mergedVisibleCachedEmbyItems(source, snapshot);
    if (items.isEmpty) {
      return const <MediaItem>[];
    }

    final normalizedSourceId = source.id.trim();
    final currentRevision = snapshot.refreshedAt?.microsecondsSinceEpoch ?? 0;
    final cachedIndex = _embyLibraryMatchIndexes[normalizedSourceId];
    final index = cachedIndex == null ||
            cachedIndex.revision != currentRevision ||
            cachedIndex.itemCount != items.length
        ? (_embyLibraryMatchIndexes[normalizedSourceId] =
            _CachedEmbyLibraryMatchIndex(
            revision: currentRevision,
            index: _EmbyLibraryMatchIndex(items),
            itemCount: items.length,
          ))
        : cachedIndex;
    final matched = index.index.lookup(
      titles: titles,
      year: year,
      doubanId: doubanId,
      imdbId: imdbId,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      wikidataId: wikidataId,
    );
    final resolved = matched.isEmpty ? items : matched;
    return resolved.take(limit).toList(growable: false);
  }

  List<MediaSourceConfig> get _enabledSources {
    return ref
        .read(appSettingsProvider)
        .mediaSources
        .where((item) => item.enabled)
        .toList();
  }

  Future<void> refreshEmbySourceCache(MediaSourceConfig source) async {
    final normalizedSourceId = source.id.trim();
    if (source.kind != MediaSourceKind.emby ||
        normalizedSourceId.isEmpty ||
        !source.hasActiveSession) {
      return;
    }

    final existing = _embyRefreshFutures[normalizedSourceId];
    if (existing != null) {
      return existing;
    }

    final refreshFuture = _refreshEmbySourceCacheInternal(source);
    _embyRefreshFutures[normalizedSourceId] = refreshFuture;
    try {
      await refreshFuture;
    } finally {
      _embyRefreshFutures.remove(normalizedSourceId);
    }
  }

  Future<CachedEmbyLibrarySnapshot> _loadCachedEmbySnapshot(
    MediaSourceConfig source,
  ) async {
    final cacheRepository = ref.read(localStorageCacheRepositoryProvider);
    var snapshot = await cacheRepository.loadEmbyLibrarySnapshot(source.id);
    if (_shouldAutoRefreshEmbySource(source, snapshot)) {
      try {
        await refreshEmbySourceCache(source);
      } catch (_) {
        // Keep the cached snapshot empty and rely on manual refresh next.
      }
      snapshot = await cacheRepository.loadEmbyLibrarySnapshot(source.id);
    }
    return snapshot;
  }

  bool _shouldAutoRefreshEmbySource(
    MediaSourceConfig source,
    CachedEmbyLibrarySnapshot snapshot,
  ) {
    if (source.kind != MediaSourceKind.emby || !source.hasActiveSession) {
      return false;
    }
    if (snapshot.hasData) {
      return false;
    }
    final refreshedAt = snapshot.refreshedAt;
    if (refreshedAt == null) {
      return true;
    }
    return DateTime.now().difference(refreshedAt) >= _embyAutoRefreshInterval;
  }

  Future<void> _refreshEmbySourceCacheInternal(MediaSourceConfig source) async {
    final cacheRepository = ref.read(localStorageCacheRepositoryProvider);
    final refreshedAt = DateTime.now();
    var collections = const <MediaCollection>[];
    var fallbackItems = const <MediaItem>[];
    var itemsBySection = const <String, List<MediaItem>>{};

    try {
      collections = await _embyApiClient.fetchCollections(source);
      final sectionItems = await Future.wait(
        collections.map((collection) async {
          final items = await _loadEmbySectionItems(
            source,
            collection: collection,
          );
          return MapEntry(collection.id.trim(), items);
        }),
      );
      itemsBySection = Map<String, List<MediaItem>>.unmodifiable(
        <String, List<MediaItem>>{
          for (final entry in sectionItems)
            if (entry.key.isNotEmpty) entry.key: entry.value,
        },
      );

      if (!source.hasExplicitNoSectionsSelected) {
        fallbackItems = _mergeAndSortEmbyItems(
          _resolveVisibleEmbyItemsBySection(
            source,
            itemsBySection,
          ).values,
        );
        if (fallbackItems.isEmpty) {
          fallbackItems = await _loadEmbyRootLibraryFallback(source);
        }
      }
    } catch (_) {
      rethrow;
    } finally {
      _embyLibraryMatchIndexes.remove(source.id.trim());
      await cacheRepository.saveEmbyLibrarySnapshot(
        sourceId: source.id,
        refreshedAt: refreshedAt,
        collections: collections,
        fallbackItems: fallbackItems
            .map(_stripArtworkForEmbyCache)
            .toList(growable: false),
        itemsBySection: itemsBySection.map(
          (key, value) => MapEntry(
            key,
            value.map(_stripArtworkForEmbyCache).toList(growable: false),
          ),
        ),
      );
    }
  }

  Future<List<MediaItem>> _loadEmbySectionItems(
    MediaSourceConfig source, {
    required MediaCollection collection,
  }) async {
    try {
      return await _embyApiClient.fetchLibrary(
        source,
        limit: 200,
        sectionId: collection.id,
        sectionName: collection.title,
      );
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  Future<List<MediaItem>> _loadEmbyRootLibraryFallback(
    MediaSourceConfig source,
  ) async {
    try {
      return await _embyApiClient.fetchLibrary(
        source,
        limit: 200,
      );
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  List<MediaCollection> _applyCollectionSelection(
    MediaSourceConfig source,
    List<MediaCollection> collections,
  ) {
    if (source.hasExplicitNoSectionsSelected) {
      return const <MediaCollection>[];
    }
    final selectedIds = source.selectedSectionIds;
    if (selectedIds.isEmpty) {
      return collections;
    }
    return collections
        .where((collection) => selectedIds.contains(collection.id))
        .toList(growable: false);
  }

  List<MediaItem> _resolveCachedEmbyItems(
    MediaSourceConfig source,
    CachedEmbyLibrarySnapshot snapshot, {
    String? sectionId,
    required int limit,
  }) {
    final normalizedSectionId = sectionId?.trim() ?? '';
    if (normalizedSectionId.isNotEmpty) {
      final scopedItems = snapshot.itemsBySection[normalizedSectionId];
      final resolved = scopedItems == null || scopedItems.isEmpty
          ? snapshot.fallbackItems
              .where((item) => item.sectionId == normalizedSectionId)
              .toList(growable: false)
          : scopedItems;
      return _rehydrateCachedEmbyItems(
        source,
        resolved.take(limit),
      );
    }

    final resolved = _mergedVisibleCachedEmbyItems(source, snapshot);
    return resolved.take(limit).toList(growable: false);
  }

  List<MediaItem> _mergedVisibleCachedEmbyItems(
    MediaSourceConfig source,
    CachedEmbyLibrarySnapshot snapshot,
  ) {
    final visibleItemsBySection = _resolveVisibleEmbyItemsBySection(
      source,
      snapshot.itemsBySection,
    );
    final resolved = visibleItemsBySection.isEmpty
        ? snapshot.fallbackItems
        : _mergeAndSortEmbyItems(visibleItemsBySection.values);
    return _rehydrateCachedEmbyItems(source, resolved);
  }

  Map<String, List<MediaItem>> _resolveVisibleEmbyItemsBySection(
    MediaSourceConfig source,
    Map<String, List<MediaItem>> itemsBySection,
  ) {
    if (itemsBySection.isEmpty) {
      return const <String, List<MediaItem>>{};
    }
    if (source.hasExplicitNoSectionsSelected) {
      return const <String, List<MediaItem>>{};
    }
    final selectedIds = source.selectedSectionIds;
    if (selectedIds.isEmpty) {
      return itemsBySection;
    }
    return <String, List<MediaItem>>{
      for (final entry in itemsBySection.entries)
        if (selectedIds.contains(entry.key)) entry.key: entry.value,
    };
  }

  List<MediaItem> _mergeAndSortEmbyItems(
    Iterable<List<MediaItem>> groups,
  ) {
    final mergedById = <String, MediaItem>{};
    for (final group in groups) {
      for (final item in group) {
        final itemId = item.id.trim();
        if (itemId.isEmpty) {
          continue;
        }
        final existing = mergedById[itemId];
        if (existing == null || item.addedAt.isAfter(existing.addedAt)) {
          mergedById[itemId] = item;
        }
      }
    }
    final merged = mergedById.values.toList(growable: false)
      ..sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return merged;
  }

  MediaItem _stripArtworkForEmbyCache(MediaItem item) {
    return item.copyWith(
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
    );
  }

  List<MediaItem> _rehydrateCachedEmbyItems(
    MediaSourceConfig source,
    Iterable<MediaItem> items,
  ) {
    return items
        .map((item) => _rehydrateCachedEmbyItem(source, item))
        .toList(growable: false);
  }

  MediaItem _rehydrateCachedEmbyItem(
    MediaSourceConfig source,
    MediaItem item,
  ) {
    if (item.posterUrl.trim().isNotEmpty || item.id.trim().isEmpty) {
      return item;
    }
    final baseUri = _resolvePreferredEmbyBaseUri(source);
    if (baseUri == null) {
      return item;
    }
    return item.copyWith(
      posterUrl: EmbyApiClient.buildPosterUri(
        baseUri: baseUri,
        itemId: item.id,
        imageTag: '',
        accessToken: source.accessToken,
      ).toString(),
      posterHeaders: const <String, String>{},
    );
  }

  Uri? _resolvePreferredEmbyBaseUri(MediaSourceConfig source) {
    final candidates = EmbyApiClient.candidateBaseUris(source.endpoint);
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.last;
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
      final snapshot = await _loadCachedEmbySnapshot(source);
      collections = snapshot.collections;
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
    return _applyCollectionSelection(source, collections);
  }

  Future<_SourceFetchResult> _fetchLibraryForSource(
    MediaSourceConfig source, {
    required String? sectionId,
    required int limit,
  }) async {
    try {
      final hasScopedSections = _hasScopedSections(source);
      if (source.kind == MediaSourceKind.emby) {
        if (!source.hasActiveSession) {
          return const _SourceFetchResult(items: <MediaItem>[]);
        }
        final snapshot = await _loadCachedEmbySnapshot(source);
        return _SourceFetchResult(
          items: _resolveCachedEmbyItems(
            source,
            snapshot,
            sectionId: sectionId,
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

        final libraryItems = await _loadNasLibraryWithAutoRebuild(
          source,
          limit: limit,
        );
        return _SourceFetchResult(items: libraryItems);
      }

      return const _SourceFetchResult(items: <MediaItem>[]);
    } catch (error, stackTrace) {
      return _SourceFetchResult(
        items: const <MediaItem>[],
        error: error,
        stackTrace: stackTrace,
      );
    }
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

class _EmbyLibraryMatchIndex {
  _EmbyLibraryMatchIndex(List<MediaItem> items) {
    for (final item in items) {
      _indexItem(item);
    }
  }

  final Map<String, List<MediaItem>> _byLookupKey = <String, List<MediaItem>>{};

  List<MediaItem> lookup({
    Iterable<String> titles = const <String>[],
    int year = 0,
    String doubanId = '',
    String imdbId = '',
    String tmdbId = '',
    String tvdbId = '',
    String wikidataId = '',
  }) {
    final matchedById = <String, MediaItem>{};

    void collect(String key) {
      final lookupKey = key.trim();
      if (lookupKey.isEmpty) {
        return;
      }
      final items = _byLookupKey[lookupKey];
      if (items == null) {
        return;
      }
      for (final item in items) {
        final itemId = item.id.trim();
        if (itemId.isEmpty) {
          continue;
        }
        matchedById[itemId] = item;
      }
    }

    collect('douban|${doubanId.trim()}');
    collect('imdb|${imdbId.trim().toLowerCase()}');
    collect('tmdb|${tmdbId.trim()}');
    collect('tvdb|${tvdbId.trim()}');
    collect('wikidata|${wikidataId.trim().toUpperCase()}');
    if (matchedById.isNotEmpty) {
      return matchedById.values.toList(growable: false);
    }

    for (final title in titles) {
      final normalizedTitle = _normalizeEmbyMatchText(title);
      if (normalizedTitle.isEmpty) {
        continue;
      }
      if (year > 0) {
        collect('title|$normalizedTitle|$year');
      }
      collect('title|$normalizedTitle');
      final originalNormalizedTitle = _normalizeEmbyMatchText(title);
      if (originalNormalizedTitle.isNotEmpty) {
        collect('title-original|$originalNormalizedTitle');
      }
    }
    return matchedById.values.toList(growable: false);
  }

  void _indexItem(MediaItem item) {
    void addKey(String key) {
      final lookupKey = key.trim();
      final itemId = item.id.trim();
      if (lookupKey.isEmpty || itemId.isEmpty) {
        return;
      }
      (_byLookupKey[lookupKey] ??= <MediaItem>[]).add(item);
    }

    final doubanId = item.doubanId.trim();
    if (doubanId.isNotEmpty) {
      addKey('douban|$doubanId');
    }
    final imdbId = item.imdbId.trim().toLowerCase();
    if (imdbId.isNotEmpty) {
      addKey('imdb|$imdbId');
    }
    final tmdbId = item.tmdbId.trim();
    if (tmdbId.isNotEmpty) {
      addKey('tmdb|$tmdbId');
    }
    final tvdbId = item.tvdbId.trim();
    if (tvdbId.isNotEmpty) {
      addKey('tvdb|$tvdbId');
    }
    final wikidataId = item.wikidataId.trim().toUpperCase();
    if (wikidataId.isNotEmpty) {
      addKey('wikidata|$wikidataId');
    }

    for (final title in <String>{
      item.title.trim(),
      item.originalTitle.trim(),
      item.sortTitle.trim(),
    }) {
      final normalizedTitle = _normalizeEmbyMatchText(title);
      if (normalizedTitle.isEmpty) {
        continue;
      }
      addKey('title|$normalizedTitle');
      if (item.year > 0) {
        addKey('title|$normalizedTitle|${item.year}');
      }
      addKey('title-original|$normalizedTitle');
    }
  }
}

class _CachedEmbyLibraryMatchIndex {
  const _CachedEmbyLibraryMatchIndex({
    required this.revision,
    required this.index,
    required this.itemCount,
  });

  final int revision;
  final _EmbyLibraryMatchIndex index;
  final int itemCount;
}

String _normalizeEmbyMatchText(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  return normalized.replaceAll(
    RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'),
    '',
  );
}
