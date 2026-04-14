import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'home section provider stays stable across cache writes until an explicit refresh boundary',
      () async {
    final discoveryRepository = _CountingDiscoveryRepository(
      entries: const [
        DoubanEntry(
          id: '1292052',
          title: '肖申克的救赎',
          year: 1994,
          posterUrl: '',
          note: '希望让人自由。',
          subjectType: 'movie',
        ),
      ],
    );
    final cacheRepository = _MutableLocalStorageCacheRepository();
    final module = HomeModuleConfig.doubanInterest(DoubanInterestStatus.mark);
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(
          AppSettings(
            mediaSources: const [],
            searchProviders: const [],
            doubanAccount: const DoubanAccountConfig(
              enabled: true,
              userId: 'demo-user',
            ),
            homeModules: [module],
          ),
        ),
        mediaRepositoryProvider.overrideWithValue(
          _NoopMediaRepository(),
        ),
        discoveryRepositoryProvider.overrideWithValue(discoveryRepository),
        localStorageCacheRepositoryProvider.overrideWithValue(cacheRepository),
      ],
    );
    addTearDown(container.dispose);

    final initialSection = await container.read(
      homeSectionProvider(module.id).future,
    );
    expect(initialSection, isNotNull);
    expect(initialSection!.items.single.title, '肖申克的救赎');
    expect(container.read(homeSectionsProvider), [initialSection]);
    expect(discoveryRepository.fetchEntriesCallCount, 1);
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

    final unchangedSection = await container.read(
      homeSectionProvider(module.id).future,
    );
    expect(unchangedSection, isNotNull);
    expect(unchangedSection!.items.single.title, '肖申克的救赎');
    expect(container.read(homeSectionsProvider), [unchangedSection]);
    expect(discoveryRepository.fetchEntriesCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);

    cacheRepository.targetsByLookupKey['douban|movie|1292052'] =
        const MediaDetailTarget(
      title: '肖申克的救赎（缓存）',
      posterUrl: 'https://cache.example.com/poster.jpg',
      overview: '缓存的详情信息',
      doubanId: '1292052',
      itemType: 'movie',
      sourceId: 'emby-main',
      itemId: 'movie-1',
      sourceKind: MediaSourceKind.emby,
      sourceName: 'Living Room',
    );
    revisionNotifier.apply(
      const LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {'emby-main'},
          lookupKeys: {'douban|movie|1292052'},
        ),
      ),
    );

    final updatedSection = await container.read(
      homeSectionProvider(module.id).future,
    );
    expect(updatedSection, isNotNull);
    expect(updatedSection!.items.single.title, '肖申克的救赎');
    expect(container.read(homeSectionsProvider), [updatedSection]);
    expect(discoveryRepository.fetchEntriesCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);

    container.read(homeMetadataAutoRefreshRevisionProvider.notifier).state++;

    final refreshedSection = await container.read(
      homeSectionProvider(module.id).future,
    );
    expect(refreshedSection, isNotNull);
    expect(refreshedSection!.items.single.title, '肖申克的救赎（缓存）');
    expect(container.read(homeSectionsProvider), [refreshedSection]);
    expect(discoveryRepository.fetchEntriesCallCount, 1);
    expect(cacheRepository.loadDetailTargetsBatchCallCount, 2);
  });
}

class _CountingDiscoveryRepository implements DiscoveryRepository {
  _CountingDiscoveryRepository({
    required this.entries,
  });

  final List<DoubanEntry> entries;
  int fetchEntriesCallCount = 0;

  @override
  Future<List<DoubanCarouselEntry>> fetchCarouselItems() async {
    return const [];
  }

  @override
  Future<List<DoubanEntry>> fetchEntries(
    HomeModuleConfig module, {
    int page = 1,
    int? pageSize,
  }) async {
    fetchEntriesCallCount += 1;
    return entries;
  }
}

class _NoopMediaRepository implements MediaRepository {
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
    return const [];
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    return const [];
  }

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
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
