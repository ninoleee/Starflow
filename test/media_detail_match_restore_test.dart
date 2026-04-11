import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/details/application/detail_external_episode_variant_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('detail page restores cached multiple library match choices',
      (tester) async {
    const seedTarget = MediaDetailTarget(
      title: '测试影片',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '无',
      searchQuery: '测试影片',
      sourceName: '豆瓣',
    );
    const choiceA = MediaDetailTarget(
      title: '测试影片',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-A',
      searchQuery: '测试影片',
      sourceId: 'nas-a',
      itemId: 'movie-a',
      itemType: 'movie',
      sectionName: '版本A',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-A',
      playbackTarget: PlaybackTarget(
        title: '测试影片',
        sourceId: 'nas-a',
        streamUrl: 'https://example.com/movie-a.mkv',
        sourceName: 'nas-A',
        sourceKind: MediaSourceKind.nas,
        itemId: 'movie-a',
        itemType: 'movie',
      ),
    );
    const choiceB = MediaDetailTarget(
      title: '测试影片',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-B',
      searchQuery: '测试影片',
      sourceId: 'nas-b',
      itemId: 'movie-b',
      itemType: 'movie',
      sectionName: '版本B',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-B',
      playbackTarget: PlaybackTarget(
        title: '测试影片',
        sourceId: 'nas-b',
        streamUrl: 'https://example.com/movie-b.mkv',
        sourceName: 'nas-B',
        sourceKind: MediaSourceKind.nas,
        itemId: 'movie-b',
        itemType: 'movie',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _NoopMediaRepository(),
          ),
          localStorageCacheRepositoryProvider.overrideWithValue(
            _FakeRestoreCacheRepository(
              cachedState: const CachedDetailState(
                target: choiceB,
                libraryMatchChoices: [choiceA, choiceB],
                selectedLibraryMatchIndex: 1,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('播放版本'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    final labels = dropdown.items!
        .map((item) => (item.child as Text).data ?? '')
        .toList(growable: false);
    expect(dropdown.value, 1);
    expect(labels, contains('nas-A · 测试影片 · 版本A'));
    expect(labels, contains('nas-B · 测试影片 · 版本B'));
  });

  testWidgets(
      'detail page restores cached episode file variants as playable versions',
      (tester) async {
    const seedTarget = MediaDetailTarget(
      title: '第 1 集',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '无',
      searchQuery: '测试剧 第 1 集',
      sourceName: '豆瓣',
    );
    const choiceA = MediaDetailTarget(
      title: '第 1 集',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-A',
      searchQuery: '测试剧 第 1 集',
      sourceId: 'nas-a',
      itemId: 'episode-a',
      itemType: 'episode',
      sectionName: '版本A',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-A',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '第 1 集',
        sourceId: 'nas-a',
        streamUrl: 'https://example.com/show-s01e01-a.mkv',
        sourceName: 'nas-A',
        sourceKind: MediaSourceKind.nas,
        itemId: 'episode-a',
        itemType: 'episode',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    const choiceB = MediaDetailTarget(
      title: '第 1 集',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-B',
      searchQuery: '测试剧 第 1 集',
      sourceId: 'nas-b',
      itemId: 'episode-b',
      itemType: 'episode',
      sectionName: '版本B',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-B',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '第 1 集',
        sourceId: 'nas-b',
        streamUrl: 'https://example.com/show-s01e01-b.mkv',
        sourceName: 'nas-B',
        sourceKind: MediaSourceKind.nas,
        itemId: 'episode-b',
        itemType: 'episode',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _NoopMediaRepository(),
          ),
          localStorageCacheRepositoryProvider.overrideWithValue(
            _FakeRestoreCacheRepository(
              cachedState: const CachedDetailState(
                target: choiceB,
                libraryMatchChoices: [choiceA, choiceB],
                selectedLibraryMatchIndex: 1,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('播放版本'), findsOneWidget);
    expect(find.text('本地资源'), findsNothing);
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    final labels = dropdown.items!
        .map((item) => (item.child as Text).data ?? '')
        .toList(growable: false);
    expect(dropdown.value, 1);
    expect(labels, contains('nas-A · 第 1 集 · 版本A'));
    expect(labels, contains('nas-B · 第 1 集 · 版本B'));
  });

  testWidgets('detail page restores indexed episode file variants',
      (tester) async {
    const seedTarget = MediaDetailTarget(
      title: '第 1 集',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-A',
      searchQuery: '测试剧 第 1 集',
      sourceId: 'nas-a',
      itemId: 'episode-a',
      itemType: 'episode',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-A',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '第 1 集',
        sourceId: 'nas-a',
        streamUrl: 'https://example.com/show-s01e01-a.mkv',
        sourceName: 'nas-A',
        sourceKind: MediaSourceKind.nas,
        actualAddress: '/shows/测试剧/Season 1/第1集-A.mkv',
        itemId: 'episode-a',
        itemType: 'episode',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    const choiceA = seedTarget;
    const choiceB = MediaDetailTarget(
      title: '第 1 集',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-A',
      searchQuery: '测试剧 第 1 集',
      sourceId: 'nas-a',
      itemId: 'episode-b',
      itemType: 'episode',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-A',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '第 1 集',
        sourceId: 'nas-a',
        streamUrl: 'https://example.com/show-s01e01-b.mkv',
        sourceName: 'nas-A',
        sourceKind: MediaSourceKind.nas,
        actualAddress: '/shows/测试剧/Season 1/第1集-B.mkv',
        itemId: 'episode-b',
        itemType: 'episode',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    final settings = AppSettings.fromJson({
      'mediaSources': const [],
      'searchProviders': const [],
      'doubanAccount': const {'enabled': false},
      'homeModules': const [],
      'tmdbMetadataMatchEnabled': false,
      'wmdbMetadataMatchEnabled': false,
      'imdbRatingMatchEnabled': false,
      'detailAutoLibraryMatchEnabled': false,
    });
    final indexer = _buildNoopNasMediaIndexer(settings);
    addTearDown(indexer.dispose);
    final cacheRepository = _RecordingRestoreCacheRepository();
    final service = _FakeDetailExternalEpisodeVariantService(
      state: const DetailExternalEpisodeVariantState(
        choices: [choiceA, choiceB],
        selectedIndex: 1,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(settings),
          mediaRepositoryProvider.overrideWithValue(
            const _NoopMediaRepository(),
          ),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
          nasMediaIndexerProvider.overrideWithValue(indexer),
          detailExternalEpisodeVariantServiceProvider
              .overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('资源信息'), findsOneWidget);
    expect(find.text('播放版本'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    final labels = dropdown.items!
        .map((item) => (item.child as Text).data ?? '')
        .toList(growable: false);
    expect(dropdown.value, 1);
    expect(labels, contains('nas-A · 第1集-A.mkv'));
    expect(labels, contains('nas-A · 第1集-B.mkv'));
    expect(service.requestedTargets.single.itemId, 'episode-a');
    expect(cacheRepository.lastSavedState?.selectedLibraryMatchIndex, 1);
    expect(cacheRepository.lastSavedState?.libraryMatchChoices.length, 2);
  });

  testWidgets(
      'detail page merges matched resources with same-episode file variants',
      (tester) async {
    const seedTarget = MediaDetailTarget(
      title: '第 1 集',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '无',
      searchQuery: '测试剧 第 1 集',
      sourceName: '豆瓣',
    );
    const choiceA = MediaDetailTarget(
      title: '第 1 集',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-A',
      searchQuery: '测试剧 第 1 集',
      sourceId: 'nas-a',
      itemId: 'episode-a',
      itemType: 'episode',
      sectionName: '版本A',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-A',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '第 1 集',
        sourceId: 'nas-a',
        streamUrl: 'https://example.com/show-s01e01-a.mkv',
        sourceName: 'nas-A',
        sourceKind: MediaSourceKind.nas,
        actualAddress: '/shows/测试剧/Season 1/第1集-A.mkv',
        itemId: 'episode-a',
        itemType: 'episode',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    const choiceA2 = MediaDetailTarget(
      title: '第 1 集',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-A',
      searchQuery: '测试剧 第 1 集',
      sourceId: 'nas-a',
      itemId: 'episode-a-2',
      itemType: 'episode',
      sectionName: '版本A',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-A',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '第 1 集',
        sourceId: 'nas-a',
        streamUrl: 'https://example.com/show-s01e01-a-2.mkv',
        sourceName: 'nas-A',
        sourceKind: MediaSourceKind.nas,
        actualAddress: '/shows/测试剧/Season 1/第1集-A-备用.mkv',
        itemId: 'episode-a-2',
        itemType: 'episode',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    const choiceB = MediaDetailTarget(
      title: '第 1 集',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：WebDAV · nas-B',
      searchQuery: '测试剧 第 1 集',
      sourceId: 'nas-b',
      itemId: 'episode-b',
      itemType: 'episode',
      sectionName: '版本B',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-B',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '第 1 集',
        sourceId: 'nas-b',
        streamUrl: 'https://example.com/show-s01e01-b.mkv',
        sourceName: 'nas-B',
        sourceKind: MediaSourceKind.nas,
        actualAddress: '/shows-b/测试剧/Season 1/第1集-B.mkv',
        itemId: 'episode-b',
        itemType: 'episode',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    final settings = AppSettings.fromJson({
      'mediaSources': const [],
      'searchProviders': const [],
      'doubanAccount': const {'enabled': false},
      'homeModules': const [],
      'tmdbMetadataMatchEnabled': false,
      'wmdbMetadataMatchEnabled': false,
      'imdbRatingMatchEnabled': false,
      'detailAutoLibraryMatchEnabled': false,
    });
    final indexer = _buildNoopNasMediaIndexer(settings);
    addTearDown(indexer.dispose);
    final cacheRepository = _RecordingRestoreCacheRepository();
    await cacheRepository.saveDetailTarget(
      seedTarget: seedTarget,
      resolvedTarget: choiceA,
      libraryMatchChoices: const [choiceA, choiceB],
      selectedLibraryMatchIndex: 0,
    );
    final service = _FakeDetailExternalEpisodeVariantService(
      statesByItemId: {
        'episode-a': const DetailExternalEpisodeVariantState(
          choices: [choiceA, choiceA2],
          selectedIndex: 0,
        ),
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(settings),
          mediaRepositoryProvider.overrideWithValue(
            const _NoopMediaRepository(),
          ),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
          nasMediaIndexerProvider.overrideWithValue(indexer),
          detailExternalEpisodeVariantServiceProvider
              .overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('播放版本'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    final labels = dropdown.items!
        .map((item) => (item.child as Text).data ?? '')
        .toList(growable: false);
    expect(labels, contains('nas-A · 第1集-A.mkv'));
    expect(labels, contains('nas-A · 第1集-A-备用.mkv'));
    expect(labels, contains('nas-B · 第1集-B.mkv'));
    expect(cacheRepository.lastSavedState?.libraryMatchChoices.length, 3);
  });

  testWidgets(
      'detail page keeps series episode browser after restoring playable library choice',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const seedTarget = MediaDetailTarget(
      title: '测试剧',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '无',
      searchQuery: '测试剧',
      sourceId: 'emby-main',
      itemId: 'series-1',
      itemType: 'series',
      sectionId: 'shows',
      sectionName: '剧集',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
    );
    const choiceA = MediaDetailTarget(
      title: '测试剧',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：Emby · 客厅 Emby',
      searchQuery: '测试剧',
      sourceId: 'emby-main',
      itemId: 'episode-a',
      itemType: 'episode',
      sectionId: 'shows',
      sectionName: '版本A',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '测试剧',
        sourceId: 'emby-main',
        streamUrl: 'https://emby.example/Items/episode-a/stream.mkv',
        sourceName: '客厅 Emby',
        sourceKind: MediaSourceKind.emby,
        itemId: 'episode-a',
        itemType: 'episode',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    const choiceB = MediaDetailTarget(
      title: '测试剧',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：Emby · 客厅 Emby',
      searchQuery: '测试剧',
      sourceId: 'emby-main',
      itemId: 'episode-b',
      itemType: 'episode',
      sectionId: 'shows',
      sectionName: '版本B',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '测试剧',
        sourceId: 'emby-main',
        streamUrl: 'https://emby.example/Items/episode-b/stream.mkv',
        sourceName: '客厅 Emby',
        sourceKind: MediaSourceKind.emby,
        itemId: 'episode-b',
        itemType: 'episode',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _SeriesRestoreMediaRepository(),
          ),
          localStorageCacheRepositoryProvider.overrideWithValue(
            _FakeRestoreCacheRepository(
              cachedState: const CachedDetailState(
                target: choiceB,
                libraryMatchChoices: [choiceA, choiceB],
                selectedLibraryMatchIndex: 1,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('剧集'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('测试剧 第 1 集'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('测试剧 第 1 集'), findsOneWidget);
    expect(find.text('播放版本'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    final labels = dropdown.items!
        .map((item) => (item.child as Text).data ?? '')
        .toList(growable: false);
    expect(dropdown.value, 1);
    expect(labels, contains('客厅 Emby · 测试剧 · 版本A'));
    expect(labels, contains('客厅 Emby · 测试剧 · 版本B'));
  });

  testWidgets(
      'detail page restores series library match choices from real cache repository',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await SharedPreferences.getInstance();
    final cacheRepository =
        LocalStorageCacheRepository(sharedPreferences: prefs);

    const seedTarget = MediaDetailTarget(
      title: '测试剧',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '无',
      searchQuery: '测试剧',
      sourceId: 'emby-main',
      itemId: 'series-1',
      itemType: 'series',
      sectionId: 'shows',
      sectionName: '剧集',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
    );
    const choiceA = MediaDetailTarget(
      title: '测试剧',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：Emby · 客厅 Emby',
      searchQuery: '测试剧',
      sourceId: 'emby-main',
      itemId: 'episode-a',
      itemType: 'episode',
      sectionId: 'shows',
      sectionName: '版本A',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '测试剧',
        sourceId: 'emby-main',
        streamUrl: 'https://emby.example/Items/episode-a/stream.mkv',
        sourceName: '客厅 Emby',
        sourceKind: MediaSourceKind.emby,
        itemId: 'episode-a',
        itemType: 'episode',
        seriesId: 'series-1',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    const choiceB = MediaDetailTarget(
      title: '测试剧',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：Emby · 客厅 Emby',
      searchQuery: '测试剧',
      sourceId: 'emby-main',
      itemId: 'episode-b',
      itemType: 'episode',
      sectionId: 'shows',
      sectionName: '版本B',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '测试剧',
        sourceId: 'emby-main',
        streamUrl: 'https://emby.example/Items/episode-b/stream.mkv',
        sourceName: '客厅 Emby',
        sourceKind: MediaSourceKind.emby,
        itemId: 'episode-b',
        itemType: 'episode',
        seriesId: 'series-1',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );

    await cacheRepository.saveDetailTarget(
      seedTarget: seedTarget,
      resolvedTarget: choiceB,
      libraryMatchChoices: const [choiceA, choiceB],
      selectedLibraryMatchIndex: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _SeriesRestoreMediaRepository(),
          ),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('播放版本'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    final labels = dropdown.items!
        .map((item) => (item.child as Text).data ?? '')
        .toList(growable: false);
    expect(dropdown.value, 1);
    expect(labels, contains('客厅 Emby · 测试剧 · 版本A'));
    expect(labels, contains('客厅 Emby · 测试剧 · 版本B'));
  });

  testWidgets(
      'detail page restores single series resource state from cached episode target',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const seedTarget = MediaDetailTarget(
      title: '测试剧',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '无',
      searchQuery: '测试剧',
      sourceId: 'emby-main',
      itemId: 'series-1',
      itemType: 'series',
      sectionId: 'shows',
      sectionName: '剧集',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
    );
    const cachedEpisodeTarget = MediaDetailTarget(
      title: '测试剧',
      posterUrl: '',
      overview: '',
      year: 2026,
      availabilityLabel: '资源已就绪：Emby · 客厅 Emby',
      searchQuery: '测试剧',
      sourceId: 'emby-main',
      itemId: 'episode-a',
      itemType: 'episode',
      sectionId: 'shows',
      sectionName: '版本A',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
      seasonNumber: 1,
      episodeNumber: 1,
      playbackTarget: PlaybackTarget(
        title: '测试剧',
        sourceId: 'emby-main',
        streamUrl: 'https://emby.example/Items/episode-a/stream.mkv',
        sourceName: '客厅 Emby',
        sourceKind: MediaSourceKind.emby,
        itemId: 'episode-a',
        itemType: 'episode',
        seriesId: 'series-1',
        seriesTitle: '测试剧',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _SeriesRestoreMediaRepository(),
          ),
          localStorageCacheRepositoryProvider.overrideWithValue(
            _FakeRestoreCacheRepository(
              cachedState: const CachedDetailState(
                target: cachedEpisodeTarget,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('资源已就绪：Emby · 客厅 Emby'), findsOneWidget);
    expect(find.text('播放版本'), findsNothing);
  });

  testWidgets('detail page shows external-id reason as alternative ids',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': [
                {
                  'id': 'emby-main',
                  'name': 'Home Emby',
                  'kind': 'emby',
                  'endpoint': 'https://media.example.com',
                  'enabled': true,
                  'username': 'alice',
                  'accessToken': 'token-789',
                  'userId': 'user-123',
                  'deviceId': 'device-456',
                },
              ],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _SingleMatchMediaRepository(),
          ),
          localStorageCacheRepositoryProvider.overrideWithValue(
            _RecordingRestoreCacheRepository(),
          ),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(
            target: MediaDetailTarget(
              title: '测试影片',
              posterUrl: '',
              overview: '',
              year: 2026,
              availabilityLabel: '无',
              searchQuery: '测试影片',
              sourceName: '豆瓣',
              imdbId: 'tt1234567',
              tmdbId: '7654321',
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('匹配资源库'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.ancestor(
        of: find.text('匹配资源库'),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('按 IMDb ID / TMDB ID 匹配'), findsWidgets);
    expect(find.textContaining('按 IMDb ID + TMDB ID 匹配'), findsNothing);
  });

  testWidgets('detail page restores cached subtitle choice for playable target',
      (tester) async {
    const seedTarget = MediaDetailTarget(
      title: 'Planet Earth II',
      posterUrl: '',
      overview: '',
      year: 2016,
      availabilityLabel: '无',
      searchQuery: 'Planet Earth II',
      sourceName: '豆瓣',
    );
    const playableTarget = MediaDetailTarget(
      title: 'Planet Earth II',
      posterUrl: '',
      overview: '',
      year: 2016,
      availabilityLabel: '资源已就绪：Emby · 客厅 Emby',
      searchQuery: 'Planet Earth II',
      sourceId: 'emby-main',
      itemId: 'planet-earth-ii',
      itemType: 'episode',
      sourceKind: MediaSourceKind.emby,
      sourceName: '客厅 Emby',
      playbackTarget: PlaybackTarget(
        title: 'Planet Earth II',
        sourceId: 'emby-main',
        streamUrl: 'https://emby.example/Items/1/stream.mkv',
        sourceName: '客厅 Emby',
        sourceKind: MediaSourceKind.emby,
        itemId: 'planet-earth-ii',
        itemType: 'episode',
        seriesTitle: 'Planet Earth II',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    const subtitleChoice = CachedSubtitleSearchOption(
      result: SubtitleSearchResult(
        id: 'subtitle-1',
        source: OnlineSubtitleSource.assrt,
        providerLabel: 'ASSRT',
        title: 'Planet Earth II S01E01',
        version: 'WEB-DL',
        formatLabel: 'ASS',
        languageLabel: '中英双语',
        sourceLabel: 'ASSRT',
        publishDateLabel: '2024-01-01',
        downloadCount: 21,
        ratingLabel: '评分 9',
        downloadUrl: 'https://assrt.net/download/1/subtitle.ass',
        detailUrl: 'https://assrt.net/sub/1',
        packageName: 'Planet.Earth.II.ass',
        packageKind: SubtitlePackageKind.subtitleFile,
      ),
      selection: SubtitleSearchSelection(
        cachedPath: '/cache/subtitle-1',
        displayName: 'Planet Earth II',
        subtitleFilePath: '/cache/subtitle-1/Planet.Earth.II.ass',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
              'onlineSubtitleSources': ['assrt'],
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _NoopMediaRepository(),
          ),
          localStorageCacheRepositoryProvider.overrideWithValue(
            _FakeRestoreCacheRepository(
              cachedState: const CachedDetailState(
                target: playableTarget,
                subtitleSearchChoices: [subtitleChoice],
                selectedSubtitleSearchIndex: 0,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: seedTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('外挂字幕'), findsOneWidget);
    expect(find.textContaining('Planet Earth II S01E01'), findsOneWidget);
  });

  testWidgets('detail page auto searches subtitles for playable target',
      (tester) async {
    const playableTarget = MediaDetailTarget(
      title: 'Planet Earth II',
      posterUrl: '',
      overview: '',
      year: 2016,
      availabilityLabel: '资源已就绪：WebDAV · nas-A',
      searchQuery: 'Planet Earth II',
      sourceId: 'nas-a',
      itemId: 'planet-earth-ii-s01e01',
      itemType: 'episode',
      sourceKind: MediaSourceKind.nas,
      sourceName: 'nas-A',
      playbackTarget: PlaybackTarget(
        title: 'Planet Earth II',
        sourceId: 'nas-a',
        streamUrl: 'https://example.com/planet-earth-ii-s01e01.mkv',
        sourceName: 'nas-A',
        sourceKind: MediaSourceKind.nas,
        itemId: 'planet-earth-ii-s01e01',
        itemType: 'episode',
        seriesTitle: 'Planet Earth II',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    const subtitleResult = SubtitleSearchResult(
      id: 'subtitle-1',
      source: OnlineSubtitleSource.assrt,
      providerLabel: 'ASSRT',
      title: 'Planet Earth II S01E01',
      version: 'WEB-DL',
      formatLabel: 'ASS',
      languageLabel: '中英双语',
      sourceLabel: 'ASSRT',
      publishDateLabel: '2024-01-01',
      downloadCount: 21,
      ratingLabel: '评分 9',
      downloadUrl: 'https://assrt.net/download/1/subtitle.ass',
      detailUrl: 'https://assrt.net/sub/1',
      packageName: 'Planet.Earth.II.ass',
      packageKind: SubtitlePackageKind.subtitleFile,
    );
    final cacheRepository = _RecordingRestoreCacheRepository();
    final subtitleRepository = _FakeOnlineSubtitleRepository(
      results: const [subtitleResult],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'tmdbMetadataMatchEnabled': false,
              'wmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
              'detailAutoLibraryMatchEnabled': false,
              'onlineSubtitleSources': ['assrt'],
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            const _NoopMediaRepository(),
          ),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
          onlineSubtitleRepositoryProvider
              .overrideWithValue(subtitleRepository),
        ],
        child: const MaterialApp(
          home: MediaDetailPage(target: playableTarget),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(subtitleRepository.searchQueries, ['Planet Earth II S01E01']);
    expect(subtitleRepository.lastMaxResults, 10);
    expect(subtitleRepository.lastSources, [OnlineSubtitleSource.assrt]);
    expect(find.text('外挂字幕'), findsOneWidget);
    expect(find.text('不加载外挂字幕'), findsOneWidget);
    expect(cacheRepository.lastSavedState?.subtitleSearchChoices.length, 1);
    expect(cacheRepository.lastSavedState?.selectedSubtitleSearchIndex, -1);
  });
}

class _FakeRestoreCacheRepository extends LocalStorageCacheRepository {
  _FakeRestoreCacheRepository({required this.cachedState})
      : super(preferences: _MemoryPreferencesStore());

  final CachedDetailState? cachedState;

  @override
  Future<CachedDetailState?> loadDetailState(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) async {
    return cachedState;
  }

  @override
  Future<MediaDetailTarget?> loadDetailTarget(
      MediaDetailTarget seedTarget) async {
    return cachedState?.target;
  }
}

class _RecordingRestoreCacheRepository extends LocalStorageCacheRepository {
  _RecordingRestoreCacheRepository()
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
      MediaDetailTarget seedTarget) async {
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

class _FakeOnlineSubtitleRepository implements OnlineSubtitleRepository {
  _FakeOnlineSubtitleRepository({required this.results});

  final List<SubtitleSearchResult> results;
  final List<String> searchQueries = <String>[];
  List<OnlineSubtitleSource> lastSources = const [];
  int lastMaxResults = 0;

  @override
  Future<SubtitleDownloadResult> download(SubtitleSearchResult result) {
    throw UnimplementedError();
  }

  @override
  Future<List<SubtitleSearchResult>> search(
    String query, {
    List<OnlineSubtitleSource> sources = const [OnlineSubtitleSource.assrt],
    int maxResults = 0,
  }) async {
    searchQueries.add(query);
    lastSources = sources.toList(growable: false);
    lastMaxResults = maxResults;
    return results;
  }
}

NasMediaIndexer _buildNoopNasMediaIndexer(AppSettings settings) {
  return NasMediaIndexer(
    store: _NoopNasMediaIndexStore(),
    webDavNasClient: WebDavNasClient(
      MockClient((request) async => http.Response('', 500)),
    ),
    wmdbMetadataClient: WmdbMetadataClient(
      MockClient((request) async => http.Response('', 500)),
    ),
    tmdbMetadataClient: TmdbMetadataClient(
      MockClient((request) async => http.Response('', 500)),
    ),
    imdbRatingClient: ImdbRatingClient(
      MockClient((request) async => http.Response('', 500)),
    ),
    readSettings: () => settings,
    progressController: WebDavScrapeProgressController(),
  );
}

class _FakeDetailExternalEpisodeVariantService
    extends DetailExternalEpisodeVariantService {
  _FakeDetailExternalEpisodeVariantService({
    this.state,
    this.statesByItemId = const {},
  });

  final DetailExternalEpisodeVariantState? state;
  final Map<String, DetailExternalEpisodeVariantState?> statesByItemId;
  final List<MediaDetailTarget> requestedTargets = <MediaDetailTarget>[];

  @override
  Future<DetailExternalEpisodeVariantState?> loadChoices({
    required MediaDetailTarget target,
    required AppSettings settings,
    required NasMediaIndexer nasMediaIndexer,
    required EmbyApiClient embyApiClient,
  }) async {
    requestedTargets.add(target);
    return statesByItemId[target.itemId.trim()] ?? state;
  }
}

class _NoopNasMediaIndexStore implements NasMediaIndexStore {
  @override
  Future<void> clearAll() async {}

  @override
  Future<void> clearSource(String sourceId) async {}

  @override
  Future<LocalStorageCacheSummary> inspectSummary() async {
    return const LocalStorageCacheSummary(
      type: LocalStorageCacheType.nasMetadataIndex,
      entryCount: 0,
      totalBytes: 0,
    );
  }

  @override
  Future<List<NasMediaIndexRecord>> loadSourceRecords(String sourceId) async {
    return const [];
  }

  @override
  Future<NasMediaIndexSourceState?> loadSourceState(String sourceId) async {
    return null;
  }

  @override
  Future<void> replaceSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
  }) async {}

  @override
  Future<void> upsertSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
    bool clearMissingRecords = false,
  }) async {}
}

class _NoopMediaRepository implements MediaRepository {
  const _NoopMediaRepository();

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

class _SingleMatchMediaRepository implements MediaRepository {
  const _SingleMatchMediaRepository();

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
    if (kind != MediaSourceKind.emby || sourceId != 'emby-main') {
      return const <MediaCollection>[];
    }
    return const [
      MediaCollection(
        id: 'movies',
        title: '电影',
        sourceId: 'emby-main',
        sourceName: 'Home Emby',
        sourceKind: MediaSourceKind.emby,
      ),
    ];
  }

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    return const <MediaItem>[];
  }

  @override
  Future<List<MediaItem>> fetchLibrary({
    MediaSourceKind? kind,
    String? sourceId,
    String? sectionId,
    int limit = 200,
  }) async {
    if (kind != MediaSourceKind.emby ||
        sourceId != 'emby-main' ||
        sectionId != 'movies') {
      return const <MediaItem>[];
    }
    return [
      MediaItem(
        id: 'movie-1',
        title: '测试影片',
        overview: '',
        posterUrl: '',
        year: 2026,
        durationLabel: '120 分钟',
        genres: const [],
        itemType: 'movie',
        sectionId: 'movies',
        sectionName: '电影',
        sourceId: 'emby-main',
        sourceName: 'Home Emby',
        sourceKind: MediaSourceKind.emby,
        streamUrl: 'https://media.example.com/Items/1/stream.mkv',
        playbackItemId: 'movie-1',
        imdbId: 'tt1234567',
        tmdbId: '7654321',
        addedAt: DateTime.utc(2026, 4, 7),
      ),
    ];
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({
    MediaSourceKind? kind,
    int limit = 10,
  }) async {
    return const <MediaItem>[];
  }

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
    return const <MediaSourceConfig>[];
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

class _SeriesRestoreMediaRepository extends _NoopMediaRepository {
  const _SeriesRestoreMediaRepository();

  @override
  Future<List<MediaItem>> fetchChildren({
    required String sourceId,
    required String parentId,
    String sectionId = '',
    String sectionName = '',
    int limit = 200,
  }) async {
    if (sourceId != 'emby-main') {
      return const <MediaItem>[];
    }
    if (parentId == 'series-1') {
      return [
        MediaItem(
          id: 'season-1',
          title: '第 1 季',
          overview: '',
          posterUrl: '',
          year: 2026,
          durationLabel: '剧集',
          genres: const [],
          itemType: 'season',
          sectionId: 'shows',
          sectionName: '剧集',
          sourceId: 'emby-main',
          sourceName: '客厅 Emby',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          playbackItemId: '',
          seasonNumber: 1,
          addedAt: DateTime.utc(2026, 4, 7),
        ),
      ];
    }
    if (parentId == 'season-1') {
      return [
        MediaItem(
          id: 'episode-1',
          title: '测试剧 第 1 集',
          overview: '',
          posterUrl: '',
          year: 2026,
          durationLabel: '45 分钟',
          genres: const [],
          itemType: 'episode',
          sectionId: 'shows',
          sectionName: '剧集',
          sourceId: 'emby-main',
          sourceName: '客厅 Emby',
          sourceKind: MediaSourceKind.emby,
          streamUrl: 'https://emby.example/Items/episode-1/stream.mkv',
          playbackItemId: 'episode-1',
          seasonNumber: 1,
          episodeNumber: 1,
          addedAt: DateTime.utc(2026, 4, 7),
        ),
      ];
    }
    return const <MediaItem>[];
  }
}

class _MemoryPreferencesStore implements PreferencesStore {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<List<String>?> getStringList(String key) async =>
      (_values[key] as List<String>?)?.toList(growable: false);

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
    _values[key] = value.toList(growable: false);
  }
}
