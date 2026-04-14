import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/mock_discovery_repository.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});

  group('home controller abstractions', () {
    test('exposes home feed repository and page controller providers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(homeFeedRepositoryProvider),
          isA<HomeFeedRepository>());
      expect(container.read(homePageControllerProvider),
          isA<HomePageController>());
    });

    test('HomePageController resolveSectionStates keeps order and filters null',
        () {
      final controller = HomePageController();
      final modules = [
        const HomeModuleConfig(
          id: 'module-a',
          type: HomeModuleType.recentlyAdded,
          title: '最近新增',
          enabled: true,
        ),
        const HomeModuleConfig(
          id: 'module-b',
          type: HomeModuleType.recentPlayback,
          title: '最近播放',
          enabled: true,
        ),
        const HomeModuleConfig(
          id: 'module-c',
          type: HomeModuleType.doubanInterest,
          title: '想看',
          enabled: true,
        ),
      ];
      const sectionA = HomeSectionViewModel(
        id: 'module-a',
        title: 'A',
        subtitle: '',
        emptyMessage: '无',
        layout: HomeSectionLayout.posterRail,
      );
      const sectionC = HomeSectionViewModel(
        id: 'module-c',
        title: 'C',
        subtitle: '',
        emptyMessage: '无',
        layout: HomeSectionLayout.posterRail,
      );

      final state = controller.resolveSectionStates(
        enabledModules: modules,
        loadSectionState: (module) {
          return switch (module.id) {
            'module-a' => const AsyncData(sectionA),
            'module-c' => const AsyncData(sectionC),
            _ => const AsyncData(null),
          };
        },
      );

      expect(state.sections.map((item) => item.id).toList(growable: false), [
        'module-a',
        'module-c',
      ]);
    });

    test('resolveSectionStates exposes resolved sections list', () {
      final controller = HomePageController();
      const modules = [
        HomeModuleConfig(
          id: 'module-a',
          type: HomeModuleType.recentlyAdded,
          title: '最近新增',
          enabled: true,
        )
      ];
      const section = HomeSectionViewModel(
        id: 'module-a',
        title: 'A',
        subtitle: '',
        emptyMessage: '无',
        layout: HomeSectionLayout.posterRail,
      );

      final state = controller.resolveSectionStates(
        enabledModules: modules,
        loadSectionState: (_) => const AsyncData(section),
      );

      expect(state.sections, [section]);
    });

    test('resolveSectionStates reuses previous state when snapshots unchanged',
        () {
      final controller = HomePageController();
      const modules = [
        HomeModuleConfig(
          id: 'module-a',
          type: HomeModuleType.recentlyAdded,
          title: '最近新增',
          enabled: true,
        ),
      ];
      const section = HomeSectionViewModel(
        id: 'module-a',
        title: 'A',
        subtitle: '',
        emptyMessage: '无',
        layout: HomeSectionLayout.posterRail,
      );

      final first = controller.resolveSectionStates(
        enabledModules: modules,
        loadSectionState: (_) => const AsyncData(section),
      );
      final second = controller.resolveSectionStates(
        enabledModules: modules,
        loadSectionState: (_) => const AsyncData(section),
      );

      expect(identical(first, second), isTrue);
      expect(identical(first.sections, second.sections), isTrue);
      expect(first.hasPendingSections, isFalse);
    });

    testWidgets('refreshHomeModules bumps home refresh revisions', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                final metadataRevision =
                    ref.watch(homeMetadataAutoRefreshRevisionProvider);
                final explicitRevision =
                    ref.watch(homeExplicitRefreshRevisionProvider);
                return Column(
                  children: [
                    Text(
                      'metadata:$metadataRevision',
                      textDirection: TextDirection.ltr,
                    ),
                    Text(
                      'explicit:$explicitRevision',
                      textDirection: TextDirection.ltr,
                    ),
                    TextButton(
                      onPressed: () => refreshHomeModules(ref),
                      child: const Text('refresh'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('metadata:1'), findsOneWidget);
      expect(find.text('explicit:0'), findsOneWidget);

      await tester.tap(find.text('refresh'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      expect(find.text('metadata:2'), findsOneWidget);
      expect(find.text('explicit:1'), findsOneWidget);
    });
  });

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

      final sections = await _readResolvedHomeSections(container);
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
      final cacheRepository = _FakeLocalStorageCacheRepository();
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
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
        ],
      );
      addTearDown(container.dispose);

      final sections = await _readResolvedHomeSections(container);
      expect(sections, hasLength(2));
      expect(mediaRepository.fetchLibraryCallCount, 0);
      expect(mediaRepository.fetchRecentlyAddedCallCount, 1);
      expect(sections.first.items.first.title, '最近新增影片');
      expect(cacheRepository.loadDetailTargetsBatchCallCount, greaterThan(0));
      expect(cacheRepository.loadDetailTargetCallCount, 0);
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

    test('recent playback module reads recent playback memory directly',
        () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final playbackMemoryRepository =
          PlaybackMemoryRepository(sharedPreferences: prefs);
      final target = const PlaybackTarget(
        title: '最近播放影片',
        sourceId: 'webdav-main',
        streamUrl: 'https://media.example.com/recent-play.mkv',
        sourceName: '家庭影音库',
        sourceKind: MediaSourceKind.nas,
        itemId: 'recent-1',
        itemType: 'movie',
        year: 2025,
      );
      await playbackMemoryRepository.saveProgress(
        target: target,
        position: const Duration(minutes: 27, seconds: 15),
        duration: const Duration(hours: 1, minutes: 42),
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
                HomeModuleConfig.recentPlayback(),
              ],
            ),
          ),
          mediaRepositoryProvider.overrideWithValue(
            _FakeMediaRepository(library: const []),
          ),
          playbackMemoryRepositoryProvider.overrideWithValue(
            playbackMemoryRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      final sections = await _readResolvedHomeSections(container);
      expect(sections, hasLength(1));
      expect(sections.first.title, '最近播放');
      expect(sections.first.items, hasLength(1));
      expect(sections.first.items.first.title, '最近播放影片');
      expect(sections.first.items.first.subtitle, contains('27:15 / 1:42:00'));
    });

    test('recent playback module shows series title instead of episode title',
        () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final playbackMemoryRepository =
          PlaybackMemoryRepository(sharedPreferences: prefs);
      final target = const PlaybackTarget(
        title: '第 2 集',
        sourceId: 'webdav-main',
        streamUrl: 'https://media.example.com/episode-2.mkv',
        sourceName: '家庭影音库',
        sourceKind: MediaSourceKind.nas,
        itemId: 'episode-2',
        itemType: 'episode',
        year: 2025,
        seriesId: 'series-1',
        seriesTitle: '人生切割术',
        seasonNumber: 1,
        episodeNumber: 2,
      );
      await playbackMemoryRepository.saveProgress(
        target: target,
        position: const Duration(minutes: 12, seconds: 8),
        duration: const Duration(minutes: 48),
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
                HomeModuleConfig.recentPlayback(),
              ],
            ),
          ),
          mediaRepositoryProvider.overrideWithValue(
            _FakeMediaRepository(library: const []),
          ),
          playbackMemoryRepositoryProvider.overrideWithValue(
            playbackMemoryRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      final sections = await _readResolvedHomeSections(container);
      expect(sections, hasLength(1));
      expect(sections.first.items, hasLength(1));
      expect(sections.first.items.first.title, '人生切割术');
      expect(sections.first.items.first.subtitle, contains('S01E02'));
      expect(sections.first.items.first.detailTarget.itemType, 'series');
      expect(sections.first.items.first.detailTarget.itemId, 'series-1');
      expect(
        sections.first.items.first.detailTarget.playbackTarget?.title,
        '第 2 集',
      );
    });

    test('recent playback module collapses multiple episode records per series',
        () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final playbackMemoryRepository =
          PlaybackMemoryRepository(sharedPreferences: prefs);
      await playbackMemoryRepository.saveProgress(
        target: const PlaybackTarget(
          title: '第 1 集',
          sourceId: 'webdav-main',
          streamUrl: 'https://media.example.com/episode-1.mkv',
          sourceName: '家庭影音库',
          sourceKind: MediaSourceKind.nas,
          itemId: 'episode-1',
          itemType: 'episode',
          year: 2025,
          seriesId: 'series-1',
          seriesTitle: '人生切割术',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        position: const Duration(minutes: 8),
        duration: const Duration(minutes: 48),
      );
      await playbackMemoryRepository.saveProgress(
        target: const PlaybackTarget(
          title: '孤注一掷',
          sourceId: 'webdav-main',
          streamUrl: 'https://media.example.com/movie.mkv',
          sourceName: '家庭影音库',
          sourceKind: MediaSourceKind.nas,
          itemId: 'movie-1',
          itemType: 'movie',
          year: 2023,
        ),
        position: const Duration(minutes: 16),
        duration: const Duration(hours: 1, minutes: 57),
      );
      await playbackMemoryRepository.saveProgress(
        target: const PlaybackTarget(
          title: '第 2 集',
          sourceId: 'webdav-main',
          streamUrl: 'https://media.example.com/episode-2.mkv',
          sourceName: '家庭影音库',
          sourceKind: MediaSourceKind.nas,
          itemId: 'episode-2',
          itemType: 'episode',
          year: 2025,
          seriesId: 'series-1',
          seriesTitle: '人生切割术',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 48),
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
                HomeModuleConfig.recentPlayback(),
              ],
            ),
          ),
          mediaRepositoryProvider.overrideWithValue(
            _FakeMediaRepository(library: const []),
          ),
          playbackMemoryRepositoryProvider.overrideWithValue(
            playbackMemoryRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      final sections = await _readResolvedHomeSections(container);
      expect(sections, hasLength(1));
      expect(sections.first.items, hasLength(2));
      expect(sections.first.items.first.title, '人生切割术');
      expect(sections.first.items.first.subtitle, contains('S01E02'));
      expect(sections.first.items.last.title, '孤注一掷');
    });

    test('recent playback module prefers associated series metadata', () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final playbackMemoryRepository =
          PlaybackMemoryRepository(sharedPreferences: prefs);
      await playbackMemoryRepository.saveProgress(
        target: const PlaybackTarget(
          title: '第 2 集',
          sourceId: 'webdav-main',
          streamUrl: 'https://media.example.com/episode-2.mkv',
          sourceName: '家庭影音库',
          sourceKind: MediaSourceKind.nas,
          itemId: 'episode-2',
          itemType: 'episode',
          year: 2025,
          seriesId: 'series-1',
          seriesTitle: '人生切割术',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 48),
      );
      final cacheRepository = _FakeLocalStorageCacheRepository(
        target: MediaDetailTarget(
          title: '人生切割术（已关联）',
          posterUrl: 'https://cache.example.com/severance.jpg',
          overview: '已关联的剧集信息',
          year: 2025,
          availabilityLabel: '资源已就绪：WebDAV · 家庭影音库',
          searchQuery: '人生切割术',
          sourceKind: MediaSourceKind.nas,
          sourceName: '家庭影音库',
          sourceId: 'webdav-main',
          itemId: 'series-1',
          itemType: 'series',
          playbackTarget: const PlaybackTarget(
            title: '第 2 集',
            sourceId: 'webdav-main',
            streamUrl: 'https://media.example.com/episode-2.mkv',
            sourceName: '家庭影音库',
            sourceKind: MediaSourceKind.nas,
            itemId: 'episode-2',
            itemType: 'episode',
            seriesId: 'series-1',
            seriesTitle: '人生切割术（已关联）',
            seasonNumber: 1,
            episodeNumber: 2,
          ),
        ),
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
                HomeModuleConfig.recentPlayback(),
              ],
            ),
          ),
          mediaRepositoryProvider.overrideWithValue(
            _FakeMediaRepository(library: const []),
          ),
          playbackMemoryRepositoryProvider.overrideWithValue(
            playbackMemoryRepository,
          ),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
        ],
      );
      addTearDown(container.dispose);

      final sections = await _readResolvedHomeSections(container);
      expect(sections, hasLength(1));
      expect(sections.first.items, hasLength(1));
      expect(sections.first.items.first.title, '人生切割术（已关联）');
      expect(
        sections.first.items.first.posterUrl,
        'https://cache.example.com/severance.jpg',
      );
      expect(sections.first.items.first.detailTarget.itemType, 'series');
      expect(sections.first.items.first.detailTarget.itemId, 'series-1');
      expect(cacheRepository.loadDetailTargetsBatchCallCount, greaterThan(0));
      expect(cacheRepository.loadDetailTargetCallCount, 0);
    });

    test('douban section prefers cached poster from detail cache', () async {
      final cacheRepository = _FakeLocalStorageCacheRepository(
        target: MediaDetailTarget(
          title: '美丽人生',
          posterUrl: 'https://cache.example.com/beautiful-life.jpg',
          overview: '缓存海报',
          year: 1997,
          availabilityLabel: '资源已就绪：WebDAV · nas',
          searchQuery: '美丽人生',
          sourceKind: MediaSourceKind.nas,
          sourceName: 'nas',
          sourceId: 'media-source-1',
          itemId: 'nas-item-1',
          itemType: 'movie',
          resourcePath: '/movies/美丽人生 (1997).mkv',
          doubanId: '1292063',
          playbackTarget: const PlaybackTarget(
            title: '美丽人生',
            sourceId: 'media-source-1',
            streamUrl: 'https://webdav.example.com/life-is-beautiful.mkv',
            sourceName: 'nas',
            sourceKind: MediaSourceKind.nas,
            itemId: 'nas-item-1',
            itemType: 'movie',
          ),
        ),
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
          mediaRepositoryProvider.overrideWithValue(
            _FakeMediaRepository(library: const []),
          ),
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
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
        ],
      );
      addTearDown(container.dispose);

      final sections = await _readResolvedHomeSections(container);
      expect(sections, hasLength(1));
      expect(
        sections.first.items.first.posterUrl,
        'https://cache.example.com/beautiful-life.jpg',
      );
      expect(
        sections.first.items.first.detailTarget.posterUrl,
        'https://cache.example.com/beautiful-life.jpg',
      );
      expect(
        sections.first.items.first.detailTarget.availabilityLabel,
        '资源已就绪：WebDAV · nas',
      );
      expect(sections.first.items.first.detailTarget.sourceName, 'nas');
      expect(
          sections.first.items.first.detailTarget.sourceId, 'media-source-1');
      expect(sections.first.items.first.detailTarget.itemId, 'nas-item-1');
      expect(sections.first.items.first.detailTarget.playbackTarget, isNotNull);
      expect(cacheRepository.loadDetailTargetsBatchCallCount, greaterThan(0));
      expect(cacheRepository.loadDetailTargetCallCount, 0);
    });
  });

  group('HomeFeedRepository applyCachedSection', () {
    test('reuses poster rail section when cache overlay is unchanged',
        () async {
      const section = HomeSectionViewModel(
        id: 'module-a',
        title: '最近新增',
        subtitle: '',
        emptyMessage: '无',
        layout: HomeSectionLayout.posterRail,
        items: [
          HomeCardViewModel(
            id: 'movie-1',
            title: 'Original Title',
            subtitle: '2024',
            posterUrl: '',
            detailTarget: MediaDetailTarget(
              title: 'Original Title',
              posterUrl: '',
              overview: '',
              sourceId: 'emby-main',
              itemId: 'movie-1',
              itemType: 'movie',
            ),
          ),
        ],
      );
      final cacheRepository = _FakeLocalStorageCacheRepository();

      final resolved = await const HomeFeedRepository().applyCachedSection(
        section: section,
        localStorageCacheRepository: cacheRepository,
      );

      expect(identical(resolved, section), isTrue);
      expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);
    });

    test('reuses carousel section when cache overlay is unchanged', () async {
      const section = HomeSectionViewModel(
        id: 'module-b',
        title: '豆瓣轮播',
        subtitle: '',
        emptyMessage: '无',
        layout: HomeSectionLayout.carousel,
        carouselItems: [
          HomeCarouselItemViewModel(
            id: 'douban-1',
            title: 'Movie',
            subtitle: '2024',
            imageUrl: '',
            detailTarget: MediaDetailTarget(
              title: 'Movie',
              posterUrl: '',
              overview: '',
              doubanId: '1292052',
              itemType: 'movie',
            ),
          ),
        ],
      );
      final cacheRepository = _FakeLocalStorageCacheRepository();

      final resolved = await const HomeFeedRepository().applyCachedSection(
        section: section,
        localStorageCacheRepository: cacheRepository,
      );

      expect(identical(resolved, section), isTrue);
      expect(cacheRepository.loadDetailTargetsBatchCallCount, 1);
    });
  });
}

Future<List<HomeSectionViewModel>> _readResolvedHomeSections(
  ProviderContainer container,
) async {
  final modules = container.read(homeEnabledModulesProvider);
  await Future.wait(
    modules
        .map((module) => container.read(homeSectionProvider(module.id).future)),
  );
  return container.read(homeSectionsProvider);
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
  Future<void> cancelActiveWebDavRefreshes({
    bool includeForceFull = false,
  }) async {}

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

  @override
  Future<void> deleteResource({
    required String sourceId,
    required String resourcePath,
    String sectionId = '',
  }) async {}
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

class _FakeLocalStorageCacheRepository extends LocalStorageCacheRepository {
  _FakeLocalStorageCacheRepository({this.target});

  final MediaDetailTarget? target;
  int loadDetailTargetCallCount = 0;
  int loadDetailTargetsBatchCallCount = 0;
  List<MediaDetailTarget> lastBatchSeedTargets = const [];

  @override
  Future<MediaDetailTarget?> loadDetailTarget(
    MediaDetailTarget seedTarget,
  ) async {
    loadDetailTargetCallCount += 1;
    return target;
  }

  @override
  Future<List<MediaDetailTarget?>> loadDetailTargetsBatch(
    Iterable<MediaDetailTarget> seedTargets,
  ) async {
    loadDetailTargetsBatchCallCount += 1;
    lastBatchSeedTargets = seedTargets.toList(growable: false);
    return List<MediaDetailTarget?>.filled(
      lastBatchSeedTargets.length,
      target,
      growable: false,
    );
  }
}
