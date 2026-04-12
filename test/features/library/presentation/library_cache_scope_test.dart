import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'library items provider ignores unrelated cache scope updates and keeps seed fetch warm',
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
          ),
        ),
        mediaRepositoryProvider.overrideWithValue(mediaRepository),
        localStorageCacheRepositoryProvider.overrideWithValue(cacheRepository),
      ],
    );
    addTearDown(container.dispose);

    final initialItems = await container.read(
      libraryItemsProvider(LibraryFilter.all).future,
    );
    expect(initialItems.single.title, 'Original Title');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);

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
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);

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
    expect(updatedItems.single.title, 'Cached Title');
    expect(mediaRepository.fetchLibraryCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 2);
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
}
