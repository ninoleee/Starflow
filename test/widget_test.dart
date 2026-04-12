// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/details/presentation/widgets/detail_episode_browser.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/presentation/home_page.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

import 'package:starflow/app/app.dart';

void main() {
  testWidgets('renders Starflow shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StarflowApp()));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('正在唤醒你的片库'), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('renders media detail content', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: 'The Last of Us',
              posterUrl: '',
              overview: 'After a global pandemic, survivors keep moving.',
              year: 2023,
              durationLabel: '1h 20m',
              ratingLabels: ['IMDb 8.7'],
              genres: ['Drama'],
              directors: ['Craig Mazin'],
              actors: ['Pedro Pascal'],
              availabilityLabel: '资源已就绪：Emby · Home Emby',
              searchQuery: 'The Last of Us',
              playbackTarget: PlaybackTarget(
                title: 'The Last of Us',
                sourceId: 'emby-main',
                streamUrl: 'https://example.com/video.mp4',
                sourceName: 'Home Emby',
                sourceKind: MediaSourceKind.emby,
              ),
              itemId: 'series-1',
              sourceId: 'emby-main',
              itemType: 'Movie',
              sourceKind: MediaSourceKind.emby,
              sourceName: 'Home Emby',
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('The Last of Us'), findsAtLeastNWidgets(1));
    expect(
      find.text('After a global pandemic, survivors keep moving.'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('IMDb 8.7'), findsOneWidget);
    expect(find.text('立即播放'), findsOneWidget);
  });

  testWidgets(
      'overview detail auto refreshes metadata once and stores success marker',
      (WidgetTester tester) async {
    final cacheRepository = _RecordingDetailCacheRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': true,
              'tmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _FakeMediaRepository(library: []),
          ),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async {
                return http.Response(
                  jsonEncode({
                    'data': [
                      {
                        'type': 'movie',
                        'year': '2024',
                        'doubanRating': '8.8',
                        'doubanId': '123456',
                        'data': [
                          {
                            'lang': 'Cn',
                            'name': '示例电影',
                            'poster':
                                'https://img.wmdb.tv/movie/poster/example.jpg',
                            'genre': '剧情',
                            'description': '自动刷新后拿到的简介。',
                          },
                        ],
                      },
                    ],
                  }),
                  200,
                  headers: const {'content-type': 'application/json'},
                );
              }),
            ),
          ),
        ],
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: '示例电影',
              posterUrl: '',
              overview: '',
              year: 2024,
              availabilityLabel: '无',
              searchQuery: '示例电影',
              itemType: 'movie',
              sourceName: '豆瓣',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(cacheRepository.lastSavedState, isNotNull);
    expect(
      cacheRepository.lastSavedState?.metadataRefreshStatus,
      DetailMetadataRefreshStatus.succeeded,
    );
    expect(
      cacheRepository.lastSavedState?.target.posterUrl,
      'https://img.wmdb.tv/movie/poster/example.jpg',
    );
  });

  testWidgets('scraped overview detail does not auto refresh metadata on open',
      (WidgetTester tester) async {
    final cacheRepository = _RecordingDetailCacheRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': true,
              'tmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _FakeMediaRepository(library: []),
          ),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async {
                return http.Response(
                  jsonEncode({
                    'data': [
                      {
                        'type': 'movie',
                        'year': '2024',
                        'doubanRating': '8.8',
                        'doubanId': '123456',
                        'data': [
                          {
                            'lang': 'Cn',
                            'name': '示例电影',
                            'poster':
                                'https://img.wmdb.tv/movie/poster/example.jpg',
                            'genre': '剧情',
                            'description': '不应再次自动更新。',
                          },
                        ],
                      },
                    ],
                  }),
                  200,
                  headers: const {'content-type': 'application/json'},
                );
              }),
            ),
          ),
        ],
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: '示例电影',
              posterUrl: 'https://img.wmdb.tv/movie/poster/example.jpg',
              overview: '已有简介',
              year: 2024,
              ratingLabels: ['豆瓣 8.8'],
              genres: ['剧情'],
              availabilityLabel: '无',
              searchQuery: '示例电影',
              itemType: 'movie',
              tmdbId: '12345',
              sourceName: '豆瓣',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      cacheRepository.lastSavedState?.metadataRefreshStatus ??
          DetailMetadataRefreshStatus.never,
      DetailMetadataRefreshStatus.never,
    );
  });

  testWidgets('episode detail does not auto refresh metadata on open',
      (WidgetTester tester) async {
    final cacheRepository = _RecordingDetailCacheRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': true,
              'tmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _FakeMediaRepository(library: []),
          ),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async {
                return http.Response(
                  jsonEncode({
                    'data': [
                      {
                        'type': 'tv',
                        'year': '2024',
                        'doubanRating': '8.6',
                        'doubanId': '654321',
                        'data': [
                          {
                            'lang': 'Cn',
                            'name': '测试剧',
                            'poster': 'https://img.wmdb.tv/tv/poster/test.jpg',
                            'genre': '剧情',
                            'description': '不会被单集详情页自动写入缓存。',
                          },
                        ],
                      },
                    ],
                  }),
                  200,
                  headers: const {'content-type': 'application/json'},
                );
              }),
            ),
          ),
        ],
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: '第1集',
              posterUrl: '',
              overview: '',
              year: 2024,
              availabilityLabel: '无',
              searchQuery: '测试剧 第1集',
              itemType: 'episode',
              seasonNumber: 1,
              episodeNumber: 1,
              sourceName: '豆瓣',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      cacheRepository.lastSavedState?.metadataRefreshStatus ??
          DetailMetadataRefreshStatus.never,
      DetailMetadataRefreshStatus.never,
    );
  });

  testWidgets('strm detail shows strm path and playback size',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: 'STRM Movie',
              posterUrl: '',
              overview: '通过 STRM 直链播放。',
              year: 2026,
              durationLabel: '1h 42m',
              availabilityLabel: '资源已就绪：WebDAV · NAS',
              searchQuery: 'STRM Movie',
              playbackTarget: PlaybackTarget(
                title: 'STRM Movie',
                sourceId: 'nas-main',
                streamUrl: 'https://media.example.com/stream/movie.mkv',
                sourceName: 'NAS',
                sourceKind: MediaSourceKind.nas,
                actualAddress: '/Movies/STRM Movie.strm',
                itemId: 'movie-1',
                itemType: 'movie',
                container: 'strm',
                fileSizeBytes: 4294967296,
              ),
              itemId: 'movie-1',
              sourceId: 'nas-main',
              itemType: 'movie',
              resourcePath: '/Movies/STRM Movie.strm',
              sourceKind: MediaSourceKind.nas,
              sourceName: 'NAS',
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('地址'), findsOneWidget);
    expect(
      find.text('/Movies/STRM Movie.strm'),
      findsOneWidget,
    );
    expect(
      find.text('https://media.example.com/stream/movie.mkv'),
      findsNothing,
    );
    expect(find.text('4.00 GB'), findsOneWidget);
  });

  testWidgets(
      'home hero centers portrait fallback artwork on landscape screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const posterUrl = 'https://example.com/portrait-poster.jpg';
    const detailTarget = MediaDetailTarget(
      title: 'Portrait Hero',
      posterUrl: posterUrl,
      overview: '只有竖海报的 hero。',
      sourceName: 'NAS',
    );
    const heroSection = HomeSectionViewModel(
      id: 'hero-source',
      title: 'Hero Source',
      subtitle: '',
      emptyMessage: '',
      layout: HomeSectionLayout.posterRail,
      items: [
        HomeCardViewModel(
          id: 'hero-item-1',
          title: 'Portrait Hero',
          subtitle: '',
          posterUrl: posterUrl,
          detailTarget: detailTarget,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              homeModules: const [
                HomeModuleConfig(
                  id: HomeModuleConfig.heroModuleId,
                  type: HomeModuleType.hero,
                  title: 'Hero',
                  enabled: true,
                ),
                HomeModuleConfig(
                  id: 'test-module',
                  type: HomeModuleType.doubanList,
                  title: 'Test Module',
                  enabled: true,
                  doubanListUrl: 'https://example.com/list',
                ),
              ],
              homeHeroBackgroundEnabled: false,
            ),
          ),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => const HomeResolvedSectionsState(
              sections: [heroSection],
            ),
          ),
          homeSectionsProvider.overrideWith((ref) async => [heroSection]),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );

    await tester.pump();
    await tester.pump();

    final heroArtwork = tester.widget<AppNetworkImage>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is AppNetworkImage &&
                widget.url == posterUrl &&
                widget.fit == BoxFit.contain,
          )
          .first,
    );

    expect(heroArtwork.alignment, Alignment.center);
  });

  testWidgets('home page skips spacer for featured source module',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const heroTarget = MediaDetailTarget(
      title: 'Hero Show',
      posterUrl: 'https://example.com/hero.jpg',
      overview: 'Hero overview',
      year: 2026,
      sourceName: 'NAS',
    );
    const sectionTarget = MediaDetailTarget(
      title: 'Section Show',
      posterUrl: 'https://example.com/section.jpg',
      overview: 'Section overview',
      year: 2026,
      sourceName: 'NAS',
    );
    const featuredSection = HomeSectionViewModel(
      id: 'module-a',
      title: 'Module A',
      subtitle: '',
      emptyMessage: '',
      layout: HomeSectionLayout.posterRail,
      items: [
        HomeCardViewModel(
          id: 'hero-item',
          title: 'Hero Show',
          subtitle: '',
          posterUrl: 'https://example.com/hero.jpg',
          detailTarget: heroTarget,
        ),
      ],
    );
    const regularSection = HomeSectionViewModel(
      id: 'module-b',
      title: 'Module B',
      subtitle: '',
      emptyMessage: '',
      layout: HomeSectionLayout.posterRail,
      items: [
        HomeCardViewModel(
          id: 'section-item',
          title: 'Section Show',
          subtitle: '',
          posterUrl: 'https://example.com/section.jpg',
          detailTarget: sectionTarget,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              homeModules: const [
                HomeModuleConfig(
                  id: HomeModuleConfig.heroModuleId,
                  type: HomeModuleType.hero,
                  title: 'Hero',
                  enabled: true,
                ),
                HomeModuleConfig(
                  id: 'module-a',
                  type: HomeModuleType.doubanList,
                  title: 'Module A',
                  enabled: true,
                  doubanListUrl: 'https://example.com/a',
                ),
                HomeModuleConfig(
                  id: 'module-b',
                  type: HomeModuleType.doubanList,
                  title: 'Module B',
                  enabled: true,
                  doubanListUrl: 'https://example.com/b',
                ),
              ],
              homeHeroSourceModuleId: 'module-a',
              homeHeroBackgroundEnabled: false,
            ),
          ),
          homeSectionsProvider.overrideWith(
            (ref) async => [featuredSection, regularSection],
          ),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => const HomeResolvedSectionsState(
              sections: [featuredSection, regularSection],
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return switch (moduleId) {
              'module-a' => featuredSection,
              'module-b' => regularSection,
              _ => null,
            };
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Module A'), findsNothing);
    expect(find.text('Module B'), findsOneWidget);

    final moduleBTop = tester.getTopLeft(find.text('Module B')).dy;
    expect(moduleBTop, lessThan(465));
  });

  testWidgets(
      'episode detail overview keeps series title when file name is unavailable',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: '第1集 风暴前夜',
              posterUrl: '',
              overview: '这一集讲述主角行动前夜的准备与冲突。',
              year: 2026,
              durationLabel: '48m',
              availabilityLabel: '资源已就绪：WebDAV · NAS',
              searchQuery: '测试剧',
              playbackTarget: PlaybackTarget(
                title: '第1集 风暴前夜',
                sourceId: 'nas-main',
                streamUrl: 'https://example.com/show-s01e01.mp4',
                sourceName: 'NAS',
                sourceKind: MediaSourceKind.nas,
                itemType: 'episode',
                seriesTitle: '测试剧',
                seasonNumber: 1,
                episodeNumber: 1,
              ),
              itemId: 'episode-1',
              sourceId: 'nas-main',
              itemType: 'episode',
              seasonNumber: 1,
              episodeNumber: 1,
              sourceKind: MediaSourceKind.nas,
              sourceName: 'NAS',
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('测试剧'), findsAtLeastNWidgets(1));
    expect(find.text('第1集 风暴前夜'), findsNothing);
    expect(find.text('这一集讲述主角行动前夜的准备与冲突。'), findsOneWidget);
  });

  testWidgets('episode detail shows file name when episode overview is missing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: '第1集 风暴前夜',
              posterUrl: '',
              overview: '',
              year: 2026,
              durationLabel: '48m',
              availabilityLabel: '资源已就绪：WebDAV · NAS',
              searchQuery: '测试剧',
              playbackTarget: PlaybackTarget(
                title: '第1集 风暴前夜',
                sourceId: 'nas-main',
                streamUrl: 'https://example.com/show-s01e01.mp4',
                sourceName: 'NAS',
                sourceKind: MediaSourceKind.nas,
                itemType: 'episode',
                seriesTitle: '测试剧',
                seasonNumber: 1,
                episodeNumber: 1,
                actualAddress: '/shows/测试剧/Season 1/第1集 风暴前夜.mkv',
              ),
              itemId: 'episode-1',
              sourceId: 'nas-main',
              itemType: 'episode',
              seasonNumber: 1,
              episodeNumber: 1,
              resourcePath: '/shows/测试剧/Season 1/第1集 风暴前夜.mkv',
              sourceKind: MediaSourceKind.nas,
              sourceName: 'NAS',
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('第1集 风暴前夜'), findsNothing);
    expect(find.text('第1集 风暴前夜.mkv'), findsAtLeastNWidgets(1));
    expect(find.text('测试剧'), findsAtLeastNWidgets(1));
  });

  testWidgets('episode browser avoids reusing series overview for each episode',
      (WidgetTester tester) async {
    const seriesTarget = MediaDetailTarget(
      title: '测试剧',
      posterUrl: '',
      overview: '这是整部剧的总介绍。',
      itemId: 'series-1',
      sourceId: 'nas-main',
      itemType: 'series',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'NAS',
    );
    final episode = MediaItem(
      id: 'episode-1',
      title: '第1集 风暴前夜',
      overview: '这是整部剧的总介绍。',
      posterUrl: '',
      year: 2026,
      durationLabel: '48m',
      genres: const [],
      sourceId: 'nas-main',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      itemType: 'episode',
      streamUrl: '',
      seasonNumber: 1,
      episodeNumber: 1,
      fileSizeBytes: 1073741824,
      actualAddress: '/shows/测试剧/Season 1/第1集 风暴前夜.mkv',
      addedAt: DateTime(2026, 4, 11),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DetailEpisodeBrowser(
              seriesTarget: seriesTarget,
              groups: [
                DetailEpisodeGroup(
                  id: 'season-1',
                  title: '第 1 季',
                  seasonNumber: 1,
                  episodes: [episode],
                ),
              ],
              selectedGroupId: 'season-1',
              onSeasonSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('这是整部剧的总介绍。'), findsNothing);
    expect(find.text('第1集 风暴前夜 · 1.00 GB'), findsOneWidget);
    expect(find.textContaining('第1集 风暴前夜.mkv'), findsOneWidget);
  });
}

class _FakeMediaRepository implements MediaRepository {
  const _FakeMediaRepository({required this.library});

  final List<MediaItem> library;

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
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    return library.take(limit).toList();
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

class _RecordingDetailCacheRepository extends LocalStorageCacheRepository {
  _RecordingDetailCacheRepository()
      : super(preferences: _MemoryPreferencesStore());

  CachedDetailState? lastSavedState;

  @override
  Future<CachedDetailState?> loadDetailState(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) async {
    return lastSavedState;
  }

  @override
  Future<MediaDetailTarget?> loadDetailTarget(
    MediaDetailTarget seedTarget,
  ) async {
    return lastSavedState?.target;
  }

  @override
  Future<void> saveDetailTarget({
    required MediaDetailTarget seedTarget,
    required MediaDetailTarget resolvedTarget,
    DetailMetadataRefreshStatus? metadataRefreshStatus,
    List<MediaDetailTarget>? libraryMatchChoices,
    int? selectedLibraryMatchIndex,
    List<CachedSubtitleSearchOption>? subtitleSearchChoices,
    int? selectedSubtitleSearchIndex,
  }) async {
    final existing = lastSavedState;
    lastSavedState = CachedDetailState(
      target: resolvedTarget,
      libraryMatchChoices:
          libraryMatchChoices ?? existing?.libraryMatchChoices ?? const [],
      selectedLibraryMatchIndex:
          selectedLibraryMatchIndex ?? existing?.selectedLibraryMatchIndex ?? 0,
      subtitleSearchChoices:
          subtitleSearchChoices ?? existing?.subtitleSearchChoices ?? const [],
      selectedSubtitleSearchIndex: selectedSubtitleSearchIndex ??
          existing?.selectedSubtitleSearchIndex ??
          -1,
      metadataRefreshStatus: metadataRefreshStatus ??
          existing?.metadataRefreshStatus ??
          DetailMetadataRefreshStatus.never,
    );
  }
}

class _MemoryPreferencesStore implements PreferencesStore {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<String?> getString(String key) async {
    final value = _values[key];
    return value is String ? value : null;
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    final value = _values[key];
    return value is List<String> ? value : null;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _values[key] = List<String>.from(value);
  }
}
