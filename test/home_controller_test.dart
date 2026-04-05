import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  group('homeSectionsProvider', () {
    test('does not auto match Douban posters or resources on home', () async {
      final mediaRepository = _FakeMediaRepository(
        library: [
          MediaItem(
            id: 'emby-1',
            title: '美丽人生',
            overview: '来自 Emby 的条目',
            posterUrl: 'https://emby.example.com/poster.jpg',
            year: 1997,
            durationLabel: '116分钟',
            genres: const ['剧情'],
            sourceId: 'emby-main',
            sourceName: 'Home Emby',
            sourceKind: MediaSourceKind.emby,
            streamUrl: '',
            addedAt: DateTime(2026, 4, 4),
          ),
        ],
      );
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
              homeModules: [
                HomeModuleConfig.doubanInterest(DoubanInterestStatus.mark),
              ],
            ),
          ),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          discoveryRepositoryProvider.overrideWithValue(
            const _FakeDiscoveryRepository(
              entries: [
                DoubanEntry(
                  id: '1292063',
                  title: '美丽人生',
                  year: 1997,
                  posterUrl: '',
                  note: '圭多用幽默守护家人。',
                  ratingLabel: '豆瓣 9.6',
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sections = await container.read(homeSectionsProvider.future);
      expect(sections, hasLength(1));
      expect(sections.first.items.first.posterUrl, isEmpty);
      expect(sections.first.items.first.detailTarget.sourceId, isEmpty);
      expect(sections.first.items.first.detailTarget.itemId, isEmpty);
      expect(mediaRepository.fetchLibraryCallCount, 0);
      expect(mediaRepository.fetchRecentlyAddedCallCount, 0);
    });

    test('recently added uses repository recentlyAdded directly', () async {
      final mediaRepository = _FakeMediaRepository(
        library: [
          MediaItem(
            id: 'emby-1',
            title: '不应该读取整库',
            overview: '',
            posterUrl: '',
            year: 2026,
            durationLabel: '',
            genres: const [],
            sourceId: 'emby-main',
            sourceName: 'Home Emby',
            sourceKind: MediaSourceKind.emby,
            streamUrl: '',
            addedAt: DateTime(2026, 4, 1),
          ),
        ],
        recentlyAdded: [
          MediaItem(
            id: 'emby-2',
            title: '最近新增影片',
            overview: '',
            posterUrl: 'https://emby.example.com/recent.jpg',
            year: 2026,
            durationLabel: '',
            genres: const [],
            sourceId: 'emby-main',
            sourceName: 'Home Emby',
            sourceKind: MediaSourceKind.emby,
            streamUrl: '',
            addedAt: DateTime(2026, 4, 4),
          ),
        ],
      );
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
              homeModules: [
                HomeModuleConfig.recentlyAdded(),
                HomeModuleConfig.doubanInterest(DoubanInterestStatus.mark),
              ],
            ),
          ),
          mediaRepositoryProvider.overrideWithValue(mediaRepository),
          discoveryRepositoryProvider.overrideWithValue(
            const _FakeDiscoveryRepository(
              entries: [
                DoubanEntry(
                  id: '1295644',
                  title: '这个杀手不太冷',
                  year: 1994,
                  posterUrl: '',
                  note: '孤独杀手与少女之间的故事。',
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sections = await container.read(homeSectionsProvider.future);
      expect(sections, hasLength(2));
      expect(mediaRepository.fetchLibraryCallCount, 0);
      expect(mediaRepository.fetchRecentlyAddedCallCount, 1);
      expect(sections.first.items.first.title, '最近新增影片');
    });

    test('douban section exposes view-all target for title tap', () async {
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
              homeModules: [
                HomeModuleConfig.doubanInterest(DoubanInterestStatus.mark),
              ],
            ),
          ),
          mediaRepositoryProvider.overrideWithValue(
            _FakeMediaRepository(library: const []),
          ),
          discoveryRepositoryProvider.overrideWithValue(
            const _FakeDiscoveryRepository(
              entries: [
                DoubanEntry(
                  id: '1292052',
                  title: '肖申克的救赎',
                  year: 1994,
                  posterUrl: 'https://img.example.com/p.jpg',
                  note: '希望让人自由。',
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final section = await container.read(
        homeSectionProvider(
          container.read(appSettingsProvider).homeModules.first.id,
        ).future,
      );

      expect(section, isNotNull);
      expect(section!.viewAllTarget, isNotNull);
      expect(section.viewAllTarget!.routeName, 'home-module-list');
      expect(section.viewAllTarget!.extra, isA<HomeModuleConfig>());
    });
  });
}

class _FakeMediaRepository implements MediaRepository {
  _FakeMediaRepository({
    required this.library,
    List<MediaItem>? recentlyAdded,
  }) : recentlyAdded = recentlyAdded ?? library;

  final List<MediaItem> library;
  final List<MediaItem> recentlyAdded;
  int fetchLibraryCallCount = 0;
  int fetchRecentlyAddedCallCount = 0;

  @override
  Future<List<MediaCollection>> fetchCollections({
    MediaSourceKind? kind,
    String? sourceId,
  }) async {
    return const [];
  }

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
  Future<MediaItem?> findById(String id) async {
    return null;
  }

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    fetchLibraryCallCount += 1;
    return library.take(limit).toList();
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    fetchRecentlyAddedCallCount += 1;
    return recentlyAdded.take(limit).toList();
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

  @override
  Future<MediaItem?> matchTitle(String title) async {
    return null;
  }
}

class _FakeDiscoveryRepository implements DiscoveryRepository {
  const _FakeDiscoveryRepository({required this.entries});

  final List<DoubanEntry> entries;

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
    return entries;
  }
}
