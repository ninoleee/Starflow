import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/domain/library_collection_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/library_collection_page.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('library items provider no longer rebuilds for cache scope updates',
      () async {
    final mediaRepository = _CountingMediaRepository(
      library: [
        MediaItem(
          id: 'movie-1',
          title: 'Original Title',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Living Room',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '100',
          addedAt: DateTime(2026, 4, 12),
        ),
      ],
    );
    final cacheRepository = _MutableLocalStorageCacheRepository();
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            performanceLiveItemHeroOverlayEnabled: true,
          ),
        ),
        mediaRepositoryProvider.overrideWithValue(mediaRepository),
        localStorageCacheRepositoryProvider.overrideWithValue(cacheRepository),
        isTelevisionProvider.overrideWithValue(const AsyncData(false)),
      ],
    );
    addTearDown(container.dispose);

    final initialItems = await container.read(
      libraryItemsProvider(LibraryFilter.all).future,
    );
    expect(initialItems.single.title, 'Original Title');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);

    final revisionNotifier =
        container.read(localStorageDetailCacheChangeProvider.notifier);
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'other-source'},
          lookupKeys: {'tmdb|movie|404'},
        ),
      ),
    );

    final unchangedItems = await container.read(
      libraryItemsProvider(LibraryFilter.all).future,
    );
    expect(unchangedItems.single.title, 'Original Title');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);

    cacheRepository.targetsByLookupKey['library|emby-main|movie-1'] =
        const MediaDetailTarget(
      title: 'Cached Title',
      posterUrl: 'https://cache.example.com/poster.jpg',
      overview: 'Cached overview',
      sourceId: 'emby-main',
      itemId: 'movie-1',
      itemType: 'movie',
      sourceKind: MediaSourceKind.emby,
      sourceName: 'Living Room',
    );
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'emby-main'},
          lookupKeys: {'library|emby-main|movie-1'},
        ),
      ),
    );

    final updatedItems = await container.read(
      libraryItemsProvider(LibraryFilter.all).future,
    );
    expect(updatedItems.single.title, 'Original Title');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);
  });

  test(
      'pruneRetainedVisiblePageCacheEntries keeps only current scope neighbors',
      () {
    const first = LibraryVisiblePageRequest(
      filter: LibraryFilter.all,
      page: 0,
      pageSize: 24,
    );
    const second = LibraryVisiblePageRequest(
      filter: LibraryFilter.all,
      page: 1,
      pageSize: 24,
    );
    const third = LibraryVisiblePageRequest(
      filter: LibraryFilter.all,
      page: 2,
      pageSize: 24,
    );
    const fourth = LibraryVisiblePageRequest(
      filter: LibraryFilter.all,
      page: 3,
      pageSize: 24,
    );
    const otherFilter = LibraryVisiblePageRequest(
      filter: LibraryFilter.nas,
      page: 1,
      pageSize: 24,
    );
    final entries = <LibraryVisiblePageRequest, String>{
      first: 'first',
      second: 'second',
      third: 'third',
      fourth: 'fourth',
      otherFilter: 'other',
    };

    pruneRetainedVisiblePageCacheEntries(
      entries: entries,
      currentRequest: second,
      pageOf: (request) => request.page,
      isSameScope: (entry, currentRequest) =>
          entry.filter == currentRequest.filter &&
          entry.pageSize == currentRequest.pageSize,
    );

    expect(entries.keys, unorderedEquals([first, second, third]));
  });

  test('library visible page provider stays stable across cache updates',
      () async {
    final mediaRepository = _CountingMediaRepository(
      library: [
        MediaItem(
          id: 'movie-1',
          title: 'Page 1',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Living Room',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '101',
          addedAt: DateTime(2026, 4, 12),
        ),
        MediaItem(
          id: 'movie-2',
          title: 'Page 2',
          overview: '',
          posterUrl: '',
          year: 2025,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Living Room',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '102',
          addedAt: DateTime(2026, 4, 12),
        ),
      ],
    );
    final cacheRepository = _MutableLocalStorageCacheRepository();
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            performanceLiveItemHeroOverlayEnabled: true,
          ),
        ),
        mediaRepositoryProvider.overrideWithValue(mediaRepository),
        localStorageCacheRepositoryProvider.overrideWithValue(cacheRepository),
        isTelevisionProvider.overrideWithValue(const AsyncData(false)),
      ],
    );
    addTearDown(container.dispose);

    final request = const LibraryVisiblePageRequest(
      filter: LibraryFilter.all,
      page: 0,
      pageSize: 1,
    );
    final initialPage = await container.read(
      libraryVisiblePageItemsProvider(request).future,
    );
    expect(initialPage.totalItems, 2);
    expect(initialPage.items.single.title, 'Page 1');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);

    final revisionNotifier =
        container.read(localStorageDetailCacheChangeProvider.notifier);
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'emby-main'},
          lookupKeys: {'library|emby-main|movie-2'},
        ),
      ),
    );

    final offPageUpdate = await container.read(
      libraryVisiblePageItemsProvider(request).future,
    );
    expect(offPageUpdate.items.single.title, 'Page 1');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);

    cacheRepository.targetsByLookupKey['library|emby-main|movie-1'] =
        const MediaDetailTarget(
      title: 'Page 1 Cached',
      posterUrl: '',
      overview: '',
      sourceId: 'emby-main',
      itemId: 'movie-1',
      itemType: 'movie',
      sourceKind: MediaSourceKind.emby,
      sourceName: 'Living Room',
    );
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'emby-main'},
          lookupKeys: {'library|emby-main|movie-1'},
        ),
      ),
    );

    final onPageUpdate = await container.read(
      libraryVisiblePageItemsProvider(request).future,
    );
    expect(onPageUpdate.items.single.title, 'Page 1');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);
  });

  test(
      'library visible page provider returns a static cached snapshot when runtime overlay updates are disabled',
      () async {
    final mediaRepository = _CountingMediaRepository(
      library: [
        MediaItem(
          id: 'movie-1',
          title: 'Page 1',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Living Room',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '101',
          addedAt: DateTime(2026, 4, 12),
        ),
        MediaItem(
          id: 'movie-2',
          title: 'Page 2',
          overview: '',
          posterUrl: '',
          year: 2025,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Living Room',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '102',
          addedAt: DateTime(2026, 4, 12),
        ),
      ],
    );
    final cacheRepository = _MutableLocalStorageCacheRepository();
    cacheRepository.targetsByLookupKey['library|emby-main|movie-1'] =
        const MediaDetailTarget(
      title: 'Page 1 Cached',
      posterUrl: '',
      overview: '',
      sourceId: 'emby-main',
      itemId: 'movie-1',
      itemType: 'movie',
      sourceKind: MediaSourceKind.emby,
      sourceName: 'Living Room',
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            performanceLiveItemHeroOverlayEnabled: false,
          ),
        ),
        mediaRepositoryProvider.overrideWithValue(mediaRepository),
        localStorageCacheRepositoryProvider.overrideWithValue(cacheRepository),
        isTelevisionProvider.overrideWithValue(const AsyncData(false)),
      ],
    );
    addTearDown(container.dispose);

    final request = const LibraryVisiblePageRequest(
      filter: LibraryFilter.all,
      page: 0,
      pageSize: 1,
    );
    final initialPage = await container.read(
      libraryVisiblePageItemsProvider(request).future,
    );
    expect(initialPage.totalItems, 2);
    expect(initialPage.items.single.title, 'Page 1 Cached');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);

    cacheRepository.targetsByLookupKey['library|emby-main|movie-1'] =
        const MediaDetailTarget(
      title: 'Page 1 Cached Updated',
      posterUrl: '',
      overview: '',
      sourceId: 'emby-main',
      itemId: 'movie-1',
      itemType: 'movie',
      sourceKind: MediaSourceKind.emby,
      sourceName: 'Living Room',
    );
    final revisionNotifier =
        container.read(localStorageDetailCacheChangeProvider.notifier);
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'emby-main'},
          lookupKeys: {'library|emby-main|movie-1'},
        ),
        changedFields: {
          LocalStorageDetailCacheChangedField.summary,
        },
      ),
    );

    final stablePage = await container.read(
      libraryVisiblePageItemsProvider(request).future,
    );
    expect(stablePage.items.single.title, 'Page 1 Cached');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);
  });

  test('library cached detail target provider updates only the targeted item',
      () async {
    final mediaRepository = _CountingMediaRepository(
      library: [
        MediaItem(
          id: 'movie-1',
          title: 'Page 1',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Living Room',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '101',
          addedAt: DateTime(2026, 4, 12),
        ),
        MediaItem(
          id: 'movie-2',
          title: 'Page 2',
          overview: '',
          posterUrl: '',
          year: 2025,
          durationLabel: '',
          genres: const [],
          sourceId: 'emby-main',
          sourceName: 'Living Room',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          tmdbId: '102',
          addedAt: DateTime(2026, 4, 12),
        ),
      ],
    );
    final cacheRepository = _MutableLocalStorageCacheRepository();
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            performanceLiveItemHeroOverlayEnabled: true,
          ),
        ),
        mediaRepositoryProvider.overrideWithValue(mediaRepository),
        localStorageCacheRepositoryProvider.overrideWithValue(cacheRepository),
        isTelevisionProvider.overrideWithValue(const AsyncData(false)),
      ],
    );
    addTearDown(container.dispose);

    final request = const LibraryVisiblePageRequest(
      filter: LibraryFilter.all,
      page: 0,
      pageSize: 1,
    );
    final page = await container.read(
      libraryVisiblePageItemsProvider(request).future,
    );
    final seedItem = page.items.single;
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);

    final overlayRequest = LibraryItemOverlayRequest(seedItem);
    final initialResolved = mergeLibraryItemWithCachedDetails(
      item: seedItem,
      cachedTarget: container.read(
        libraryCachedDetailTargetProvider(overlayRequest),
      ),
    );
    expect(initialResolved.title, 'Page 1');

    final revisionNotifier =
        container.read(localStorageDetailCacheChangeProvider.notifier);
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'emby-main'},
          lookupKeys: {'library|emby-main|movie-2'},
        ),
      ),
    );

    final stillUnchanged = mergeLibraryItemWithCachedDetails(
      item: seedItem,
      cachedTarget: container.read(
        libraryCachedDetailTargetProvider(overlayRequest),
      ),
    );
    expect(stillUnchanged.title, 'Page 1');
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);

    cacheRepository.targetsByLookupKey['library|emby-main|movie-1'] =
        const MediaDetailTarget(
      title: 'Page 1 Cached',
      posterUrl: '',
      overview: '',
      sourceId: 'emby-main',
      itemId: 'movie-1',
      itemType: 'movie',
      sourceKind: MediaSourceKind.emby,
      sourceName: 'Living Room',
    );
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'emby-main'},
          lookupKeys: {'library|emby-main|movie-1'},
        ),
        changedFields: {
          LocalStorageDetailCacheChangedField.summary,
        },
      ),
    );

    final updated = mergeLibraryItemWithCachedDetails(
      item: seedItem,
      cachedTarget: container.read(
        libraryCachedDetailTargetProvider(overlayRequest),
      ),
    );
    expect(updated.title, 'Page 1 Cached');
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);
  });

  test(
      'library cached detail target provider skips runtime overlay when disabled',
      () async {
    final cacheRepository = _MutableLocalStorageCacheRepository();
    cacheRepository.targetsByLookupKey['library|emby-main|movie-1'] =
        const MediaDetailTarget(
      title: 'Page 1 Cached',
      posterUrl: '',
      overview: '',
      sourceId: 'emby-main',
      itemId: 'movie-1',
      itemType: 'movie',
      sourceKind: MediaSourceKind.emby,
      sourceName: 'Living Room',
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            performanceLiveItemHeroOverlayEnabled: false,
          ),
        ),
        localStorageCacheRepositoryProvider.overrideWithValue(cacheRepository),
        isTelevisionProvider.overrideWithValue(const AsyncData(false)),
      ],
    );
    addTearDown(container.dispose);

    final seedItem = MediaItem(
      id: 'movie-1',
      title: 'Page 1',
      overview: '',
      posterUrl: '',
      year: 2024,
      durationLabel: '',
      genres: const [],
      sourceId: 'emby-main',
      sourceName: 'Living Room',
      sourceKind: MediaSourceKind.emby,
      streamUrl: '',
      tmdbId: '101',
      addedAt: DateTime(2026, 4, 12),
    );

    final overlayRequest = LibraryItemOverlayRequest(seedItem);
    final initialResolved = mergeLibraryItemWithCachedDetails(
      item: seedItem,
      cachedTarget: container.read(
        libraryCachedDetailTargetProvider(overlayRequest),
      ),
    );
    expect(initialResolved.title, 'Page 1');

    final revisionNotifier =
        container.read(localStorageDetailCacheChangeProvider.notifier);
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'emby-main'},
          lookupKeys: {'library|emby-main|movie-1'},
        ),
        changedFields: {
          LocalStorageDetailCacheChangedField.summary,
        },
      ),
    );

    final stillStatic = mergeLibraryItemWithCachedDetails(
      item: seedItem,
      cachedTarget: container.read(
        libraryCachedDetailTargetProvider(overlayRequest),
      ),
    );
    expect(stillStatic.title, 'Page 1');
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);
  });

  test(
      'library collection visible page provider ignores off-page cache updates',
      () async {
    final mediaRepository = _CountingMediaRepository(
      library: [
        MediaItem(
          id: 'episode-1',
          title: 'Episode 1',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'nas-main',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
          streamUrl: '',
          itemType: 'episode',
          sectionId: 'season-1',
          addedAt: DateTime(2026, 4, 12),
        ),
        MediaItem(
          id: 'episode-2',
          title: 'Episode 2',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'nas-main',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
          streamUrl: '',
          itemType: 'episode',
          sectionId: 'season-1',
          addedAt: DateTime(2026, 4, 12),
        ),
      ],
    );
    final cacheRepository = _MutableLocalStorageCacheRepository();
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            performanceLiveItemHeroOverlayEnabled: true,
          ),
        ),
        mediaRepositoryProvider.overrideWithValue(mediaRepository),
        localStorageCacheRepositoryProvider.overrideWithValue(cacheRepository),
        isTelevisionProvider.overrideWithValue(const AsyncData(false)),
      ],
    );
    addTearDown(container.dispose);

    const request = LibraryCollectionVisiblePageRequest(
      target: LibraryCollectionTarget(
        title: 'Season 1',
        sourceId: 'nas-main',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
        sectionId: 'season-1',
      ),
      page: 0,
      pageSize: 1,
    );

    final initialPage = await container.read(
      libraryCollectionVisiblePageItemsProvider(request).future,
    );
    expect(initialPage.totalItems, 2);
    expect(initialPage.items.single.title, 'Episode 1');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);

    final revisionNotifier =
        container.read(localStorageDetailCacheChangeProvider.notifier);
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'nas-main'},
          lookupKeys: {'library|nas-main|episode-2'},
        ),
      ),
    );

    final offPageUpdate = await container.read(
      libraryCollectionVisiblePageItemsProvider(request).future,
    );
    expect(offPageUpdate.items.single.title, 'Episode 1');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 0);
  });

  test(
      'library collection visible page provider returns a static cached snapshot when runtime overlay updates are disabled',
      () async {
    final mediaRepository = _CountingMediaRepository(
      library: [
        MediaItem(
          id: 'episode-1',
          title: 'Episode 1',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'nas-main',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
          streamUrl: '',
          itemType: 'episode',
          sectionId: 'season-1',
          addedAt: DateTime(2026, 4, 12),
        ),
        MediaItem(
          id: 'episode-2',
          title: 'Episode 2',
          overview: '',
          posterUrl: '',
          year: 2024,
          durationLabel: '',
          genres: const [],
          sourceId: 'nas-main',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
          streamUrl: '',
          itemType: 'episode',
          sectionId: 'season-1',
          addedAt: DateTime(2026, 4, 12),
        ),
      ],
    );
    final cacheRepository = _MutableLocalStorageCacheRepository();
    cacheRepository.targetsByLookupKey['library|nas-main|episode-1'] =
        const MediaDetailTarget(
      title: 'Episode 1 Cached',
      posterUrl: '',
      overview: '',
      sourceId: 'nas-main',
      itemId: 'episode-1',
      itemType: 'episode',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'NAS',
    );
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          const AppSettings(
            mediaSources: [],
            searchProviders: [],
            doubanAccount: DoubanAccountConfig(enabled: false),
            homeModules: [],
            performanceLiveItemHeroOverlayEnabled: false,
          ),
        ),
        mediaRepositoryProvider.overrideWithValue(mediaRepository),
        localStorageCacheRepositoryProvider.overrideWithValue(cacheRepository),
        isTelevisionProvider.overrideWithValue(const AsyncData(false)),
      ],
    );
    addTearDown(container.dispose);

    const request = LibraryCollectionVisiblePageRequest(
      target: LibraryCollectionTarget(
        title: 'Season 1',
        sourceId: 'nas-main',
        sourceName: 'NAS',
        sourceKind: MediaSourceKind.nas,
        sectionId: 'season-1',
      ),
      page: 0,
      pageSize: 1,
    );

    final initialPage = await container.read(
      libraryCollectionVisiblePageItemsProvider(request).future,
    );
    expect(initialPage.totalItems, 2);
    expect(initialPage.items.single.title, 'Episode 1 Cached');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);

    cacheRepository.targetsByLookupKey['library|nas-main|episode-1'] =
        const MediaDetailTarget(
      title: 'Episode 1 Cached Updated',
      posterUrl: '',
      overview: '',
      sourceId: 'nas-main',
      itemId: 'episode-1',
      itemType: 'episode',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'NAS',
    );
    final revisionNotifier =
        container.read(localStorageDetailCacheChangeProvider.notifier);
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'nas-main'},
          lookupKeys: {'library|nas-main|episode-1'},
        ),
        changedFields: {
          LocalStorageDetailCacheChangedField.summary,
        },
      ),
    );

    final stablePage = await container.read(
      libraryCollectionVisiblePageItemsProvider(request).future,
    );
    expect(stablePage.items.single.title, 'Episode 1 Cached');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);
  });
}

class _CountingMediaRepository implements MediaRepository {
  _CountingMediaRepository({
    required this.library,
  });

  final List<MediaItem> library;
  int fetchLibraryCallCount = 0;

  @override
  Future<void> cancelActiveWebDavRefreshes({
    bool includeForceFull = false,
  }) async {}

  @override
  Future<void> deleteResource({
    required String sourceId,
    required String resourcePath,
    String sectionId = '',
  }) async {}

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    return const [];
  }

  @override
  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async {
    return const [];
  }

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    fetchLibraryCallCount += 1;
    return library.take(limit).toList(growable: false);
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    return const [];
  }

  @override
  Future<MediaItem?> findById(String id) async {
    return null;
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    return null;
  }

  @override
  Future<void> refreshSource({
    required String sourceId,
    bool forceFullRescan = false,
  }) async {}

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
    return const [];
  }
}

class _MutableLocalStorageCacheRepository extends LocalStorageCacheRepository {
  final Map<String, MediaDetailTarget> targetsByLookupKey =
      <String, MediaDetailTarget>{};
  int loadDetailTargetsBatchCallCount = 0;

  @override
  Future<void> primeDetailPayload() async {}

  @override
  Future<List<MediaDetailTarget?>> loadDetailTargetsBatch(
    Iterable<MediaDetailTarget> seedTargets,
  ) async {
    loadDetailTargetsBatchCallCount += 1;
    return seedTargets.map((seedTarget) {
      for (final lookupKey
          in LocalStorageCacheRepository.buildLookupKeys(seedTarget)) {
        final cachedTarget = targetsByLookupKey[lookupKey];
        if (cachedTarget != null) {
          return cachedTarget;
        }
      }
      return null;
    }).toList(growable: false);
  }

  @override
  MediaDetailTarget? peekDetailTarget(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) {
    for (final lookupKey
        in LocalStorageCacheRepository.buildLookupKeys(seedTarget)) {
      final cachedTarget = targetsByLookupKey[lookupKey];
      if (cachedTarget != null) {
        return cachedTarget;
      }
    }
    return null;
  }
}
