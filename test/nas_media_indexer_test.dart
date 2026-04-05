import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';

void main() {
  test('NasMediaIndexer groups WebDAV episodes into series and seasons',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-tv',
      name: 'WebDAV TV',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-tv',
      sourceName: 'WebDAV TV',
      sourceKind: MediaSourceKind.nas,
    );

    final client = _FakeWebDavNasClient(
      scannedItems: [
        _episodeItem(
          id: 'ep-1',
          path: 'Lost/Season 01/Episode 01.mkv',
          title: 'Pilot (1)',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'ep-2',
          path: 'Lost/Season 02/Episode 01.mkv',
          title: 'Man of Science, Man of Faith',
          seasonNumber: 2,
          episodeNumber: 1,
        ),
      ],
    );

    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );

    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(library, hasLength(1));
    final series = library.single;
    expect(series.itemType, 'series');
    expect(series.title, 'Lost');

    final seasons = await indexer.loadChildren(
      source,
      parentId: series.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(seasons, hasLength(2));
    expect(seasons.every((item) => item.itemType == 'season'), isTrue);
    expect(seasons.map((item) => item.seasonNumber), containsAll([1, 2]));

    final seasonTwo = seasons.firstWhere((item) => item.seasonNumber == 2);
    final episodes = await indexer.loadChildren(
      source,
      parentId: seasonTwo.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(episodes, hasLength(1));
    expect(episodes.single.itemType, 'episode');
    expect(episodes.single.title, 'Man of Science, Man of Faith');
    expect(episodes.single.seasonNumber, 2);
    expect(episodes.single.episodeNumber, 1);
  });

  test('NasMediaIndexer writes manual metadata matches back into local index',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-movie',
      name: 'WebDAV Movie',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Movies/',
      enabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'movie-1',
          path: 'Movies/The.Matrix.1999.1080p.mkv',
          title: 'The Matrix',
          itemType: 'movie',
          seasonNumber: 0,
          episodeNumber: 0,
        ),
      ],
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    final library = await indexer.loadLibrary(source, limit: 20);
    expect(library, hasLength(1));
    expect(library.single.title, 'The Matrix');

    final updatedTarget = await indexer.applyManualMetadata(
      target: MediaDetailTarget.fromMediaItem(library.single),
      searchQuery: '黑客帝国',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.wmdb,
        title: '黑客帝国',
        originalTitle: 'The Matrix',
        overview: '这是手动写回到本地索引的简介。',
        year: 1999,
        genres: ['科幻', '动作'],
        directors: ['莉莉·沃卓斯基'],
        actors: ['基努·里维斯'],
        ratingLabels: ['豆瓣 9.1'],
        doubanId: '1291843',
        imdbId: 'tt0133093',
      ),
    );

    expect(updatedTarget, isNotNull);
    expect(updatedTarget!.title, '黑客帝国');
    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(1));
    expect(records.single.item.title, '黑客帝国');
    expect(records.single.item.overview, '这是手动写回到本地索引的简介。');
    expect(records.single.item.doubanId, '1291843');
    expect(records.single.item.imdbId, 'tt0133093');
    expect(records.single.item.ratingLabels, contains('豆瓣 9.1'));
    expect(records.single.searchQuery, '黑客帝国');
    expect(records.single.wmdbMatched, isTrue);
  });

  test('NasMediaIndexer applies manual metadata to synthetic series targets',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-series',
      name: 'WebDAV Series',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-series',
      sourceName: 'WebDAV Series',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: [
        _episodeItem(
          id: 'series-ep-1',
          path: 'Lost/Season 01/Episode 01.mkv',
          title: 'Pilot (1)',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'series-ep-2',
          path: 'Lost/Season 01/Episode 02.mkv',
          title: 'Pilot (2)',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
      ],
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(library, hasLength(1));
    final series = library.single;
    expect(series.itemType, 'series');

    final updatedTarget = await indexer.applyManualMetadata(
      target: MediaDetailTarget.fromMediaItem(series),
      searchQuery: '迷失',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.tmdb,
        title: '迷失',
        originalTitle: 'Lost',
        overview: '一架客机坠毁后，幸存者在神秘岛屿上求生。',
        year: 2004,
        genres: ['剧情', '悬疑'],
        directors: ['J·J·艾布拉姆斯'],
        actors: ['马修·福克斯'],
        ratingLabels: ['豆瓣 8.9'],
        imdbId: 'tt0411008',
      ),
    );

    expect(updatedTarget, isNotNull);
    expect(updatedTarget!.itemType, 'series');
    expect(updatedTarget.title, '迷失');
    expect(updatedTarget.imdbId, 'tt0411008');
    expect(updatedTarget.ratingLabels, contains('豆瓣 8.9'));

    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(2));
    expect(
        records.every((record) => record.item.imdbId == 'tt0411008'), isTrue);
    expect(records.every((record) => record.parentTitle == '迷失'), isTrue);
    expect(
      records.map((record) => record.item.title),
      containsAll(['Pilot (1)', 'Pilot (2)']),
    );
  });

  test(
      'NasMediaIndexer keeps structure-inferred documentary folders grouped under one series',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-doc-series',
      name: 'WebDAV Docs',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/strm/quark/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/movies/strm/quark/',
      title: 'Quark',
      sourceId: 'webdav-doc-series',
      sourceName: 'WebDAV Docs',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'food-0',
          path: '食贫道/《电诈 摇滚 吴哥窟》.(mp4).strm',
          title: '《电诈 摇滚 吴哥窟》',
          itemType: 'episode',
          seasonNumber: 0,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'food-1',
          path: '食贫道/1.日本/食贫道 东瀛大宝荐 迷失东京.(mp4).strm',
          title: '食贫道 东瀛大宝荐 迷失东京',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'food-2',
          path: '食贫道/2.巴以/食贫道 巴以观察.(mp4).strm',
          title: '食贫道 巴以观察',
          itemType: 'episode',
          seasonNumber: 2,
          episodeNumber: 1,
        ),
      ],
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(library, hasLength(1));
    final series = library.single;
    expect(series.itemType, 'series');
    expect(series.title, '食贫道');

    final seasons = await indexer.loadChildren(
      source,
      parentId: series.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(seasons.map((item) => item.seasonNumber), containsAll([0, 1, 2]));
    expect(seasons.firstWhere((item) => item.seasonNumber == 0).title, '特别篇');
    expect(seasons.firstWhere((item) => item.seasonNumber == 1).title, '1.日本');
    expect(seasons.firstWhere((item) => item.seasonNumber == 2).title, '2.巴以');
  });

  test(
      'NasMediaIndexer resolves series root past wrapper folders for season directories',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-wrapper-series',
      name: 'WebDAV Wrapper Series',
      kind: MediaSourceKind.nas,
      endpoint: 'https://webdav.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'food-wrapper-1',
          path: 'strm/quark/食贫道/11.日本（12月更新-日本战后八十年）/【4K】战 后 八 十 年.(mp4).strm',
          title: '【4K】战 后 八 十 年',
          itemType: 'episode',
          seasonNumber: 11,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'food-wrapper-2',
          path: 'strm/quark/食贫道/7.黄粱一梦（你还好吗，美国）/黄 粱 一 梦.(mp4).strm',
          title: '黄 粱 一 梦',
          itemType: 'episode',
          seasonNumber: 7,
          episodeNumber: 1,
        ),
      ],
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    final library = await indexer.loadLibrary(source, limit: 20);
    expect(library, hasLength(1));
    final series = library.single;
    expect(series.itemType, 'series');
    expect(series.title, '食贫道');

    final seasons = await indexer.loadChildren(
      source,
      parentId: series.id,
      limit: 20,
    );
    expect(seasons, hasLength(2));
    expect(
      seasons.map((item) => item.title),
      containsAll([
        '11.日本（12月更新-日本战后八十年）',
        '7.黄粱一梦（你还好吗，美国）',
      ]),
    );
  });

  test(
      'NasMediaIndexer keeps imdb-tagged WebDAV episodes under structure root series grouping',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-wrapper-imdb-series',
      name: 'WebDAV Wrapper IMDb Series',
      kind: MediaSourceKind.nas,
      endpoint: 'https://webdav.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'food-wrapper-imdb-1',
          path: 'strm/quark/食贫道/11.日本（12月更新-日本战后八十年）/【4K】战 后 八 十 年.(mp4).strm',
          title: '【4K】战 后 八 十 年',
          itemType: 'episode',
          seasonNumber: 11,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'food-wrapper-imdb-2',
          path: 'strm/quark/食贫道/7.黄粱一梦（你还好吗，美国）/黄 粱 一 梦.(mp4).strm',
          title: '黄 粱 一 梦',
          itemType: 'episode',
          seasonNumber: 7,
          episodeNumber: 2,
          imdbId: 'tt0025880',
        ),
      ],
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    final library = await indexer.loadLibrary(source, limit: 20);
    expect(library, hasLength(1));
    final series = library.single;
    expect(series.itemType, 'series');
    expect(series.title, '食贫道');

    final seasons = await indexer.loadChildren(
      source,
      parentId: series.id,
      limit: 20,
    );
    expect(seasons, hasLength(2));
    expect(seasons.map((item) => item.seasonNumber), containsAll([7, 11]));
    expect(
      seasons.map((item) => item.title),
      containsAll([
        '11.日本（12月更新-日本战后八十年）',
        '7.黄粱一梦（你还好吗，美国）',
      ]),
    );
  });

  test('NasMediaIndexer keeps single-file movie folders as playable movies',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-starwars',
      name: 'WebDAV StarWars',
      kind: MediaSourceKind.nas,
      endpoint: 'https://webdav.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'starwars-1',
          path:
              'strm/quark/星球大战：最后的绝地武士 2160p remux (2017)/星球大战：最后的绝地武士 2160p remux (2017).(mkv).strm',
          title: '星球大战：最后的绝地武士 2160p remux (2017)',
          itemType: 'movie',
          seasonNumber: 0,
          episodeNumber: 0,
        ),
      ],
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    final library = await indexer.loadLibrary(source, limit: 20);
    expect(library, hasLength(1));
    final movie = library.single;
    expect(movie.itemType, 'movie');
    expect(movie.streamUrl, isNotEmpty);
    expect(movie.title, '星球大战：最后的绝地武士 2160p remux (2017)');
  });

  test(
      'NasMediaIndexer does not start duplicate NAS refresh while one is active',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-dedupe',
      name: 'WebDAV Dedupe',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'dedupe-1',
          path: 'Shows/Test Episode 01.mkv',
          title: 'Test Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ],
      scanDelay: const Duration(milliseconds: 120),
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    await Future.wait([
      indexer.refreshSource(source),
      indexer.refreshSource(source),
    ]);

    expect(client.scanCallCount, 1);
  });

  test(
      'NasMediaIndexer incremental refresh only enriches changed or missing-metadata items',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-incremental',
      name: 'WebDAV Incremental',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavSidecarScrapingEnabled: true,
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'incremental-1',
          path: 'Shows/Test Show/Test Episode 01.mkv',
          title: 'Test Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
          hasSidecarMatch: true,
        ),
      ],
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    await indexer.refreshSource(source);
    await _drainAsyncTasks();
    expect(client.scanCallCount, 1);
    expect(client.scanResourceCallCount, 1);

    await indexer.refreshSource(source);
    await _drainAsyncTasks();
    expect(client.scanCallCount, 2);
    expect(
      client.scanResourceCallCount,
      1,
      reason:
          'Second incremental refresh should not re-read sidecar for unchanged items.',
    );
  });

  test(
      'NasMediaIndexer keeps structure-inferred episode grouping after background sidecar enrichment',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-structure-merge',
      name: 'WebDAV Structure Merge',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSidecarScrapingEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-structure-merge',
      sourceName: 'WebDAV Structure Merge',
      sourceKind: MediaSourceKind.nas,
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'mystery-1',
          path: 'Shows/9号秘事 (2014)/Season 01/Episode 01.strm',
          title: 'Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
          hasSidecarMatch: true,
        ),
        _PendingTestItem(
          id: 'mystery-2',
          path: 'Shows/9号秘事 (2014)/Season 01/Episode 02.strm',
          title: 'Episode 02',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 2,
          hasSidecarMatch: true,
        ),
      ],
      scanResourceOverrides: const {
        'mystery-1': _PendingTestItem(
          id: 'mystery-1',
          path: 'Shows/9号秘事 (2014)/Season 01/Episode 01.strm',
          title: '9号秘事',
          itemType: '',
          seasonNumber: 0,
          episodeNumber: 0,
          hasSidecarMatch: true,
        ),
        'mystery-2': _PendingTestItem(
          id: 'mystery-2',
          path: 'Shows/9号秘事 (2014)/Season 01/Episode 02.strm',
          title: '9号秘事',
          itemType: '',
          seasonNumber: 0,
          episodeNumber: 0,
          hasSidecarMatch: true,
        ),
      },
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
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

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
    );
    await _drainAsyncTasks();

    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(library, hasLength(1));
    expect(library.single.itemType, 'series');
    expect(library.single.title, contains('9号秘事'));

    final episodes = await indexer.loadChildren(
      source,
      parentId: library.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(episodes, hasLength(2));
    expect(episodes.every((item) => item.itemType == 'episode'), isTrue);
  });

  test(
      'NasMediaIndexer skips per-file online matching for structure-inferred episodes',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-episode-online-skip',
      name: 'WebDAV Episode Online Skip',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSidecarScrapingEnabled: true,
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: true,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    var wmdbRequestCount = 0;
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'skip-online-1',
          path: 'Shows/Test Show/Season 01/Episode 01.strm',
          title: 'Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
          hasSidecarMatch: true,
        ),
      ],
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
      wmdbMetadataClient: WmdbMetadataClient(
        MockClient((request) async {
          wmdbRequestCount += 1;
          return http.Response('', 500);
        }),
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

    await indexer.refreshSource(source);
    await _drainAsyncTasks();

    expect(wmdbRequestCount, 0);
  });
}

_PendingTestItem _episodeItem({
  required String id,
  required String path,
  required String title,
  required int seasonNumber,
  required int episodeNumber,
}) {
  return _PendingTestItem(
    id: id,
    path: path,
    title: title,
    itemType: 'episode',
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );
}

class _PendingTestItem {
  const _PendingTestItem({
    required this.id,
    required this.path,
    required this.title,
    required this.itemType,
    required this.seasonNumber,
    required this.episodeNumber,
    this.imdbId = '',
    this.hasSidecarMatch = true,
  });

  final String id;
  final String path;
  final String title;
  final String itemType;
  final int seasonNumber;
  final int episodeNumber;
  final String imdbId;
  final bool hasSidecarMatch;
}

class _FakeWebDavNasClient extends WebDavNasClient {
  _FakeWebDavNasClient({
    required this.scannedItems,
    this.scanDelay = Duration.zero,
    this.scanResourceOverrides = const {},
  }) : super(MockClient((request) async => http.Response('', 200)));

  final List<_PendingTestItem> scannedItems;
  final Duration scanDelay;
  final Map<String, _PendingTestItem> scanResourceOverrides;
  int scanCallCount = 0;
  int scanResourceCallCount = 0;

  @override
  Future<List<WebDavScannedItem>> scanLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
    bool? loadSidecarMetadata,
    bool resetCaches = true,
  }) async {
    scanCallCount += 1;
    if (scanDelay > Duration.zero) {
      await Future<void>.delayed(scanDelay);
    }
    return scannedItems
        .take(limit)
        .map(
          (item) => WebDavScannedItem(
            resourceId: item.id,
            fileName: item.path.split('/').last,
            actualAddress: item.path,
            sectionId: sectionId ?? source.endpoint,
            sectionName: sectionName.isEmpty ? '剧集' : sectionName,
            streamUrl: 'https://media.example.com/${item.id}.mkv',
            streamHeaders: const {},
            addedAt: DateTime.utc(2026, 4, 5, 12, item.episodeNumber),
            modifiedAt: DateTime.utc(2026, 4, 5, 12, item.episodeNumber),
            fileSizeBytes: 1024,
            metadataSeed: WebDavMetadataSeed(
              title: item.title,
              overview: '',
              posterUrl: '',
              posterHeaders: const {},
              backdropUrl: '',
              backdropHeaders: const {},
              logoUrl: '',
              logoHeaders: const {},
              bannerUrl: '',
              bannerHeaders: const {},
              extraBackdropUrls: const [],
              extraBackdropHeaders: const {},
              year: 0,
              durationLabel: '剧集',
              genres: const [],
              directors: const [],
              actors: const [],
              itemType: item.itemType,
              seasonNumber: item.seasonNumber,
              episodeNumber: item.episodeNumber,
              imdbId: item.imdbId,
              container: 'mkv',
              videoCodec: '',
              audioCodec: '',
              width: null,
              height: null,
              bitrate: null,
              hasSidecarMatch:
                  loadSidecarMetadata == true ? item.hasSidecarMatch : false,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<WebDavScannedItem?> scanResource(
    MediaSourceConfig source, {
    required String resourceId,
    required String sectionId,
    required String sectionName,
    bool? loadSidecarMetadata,
  }) async {
    scanResourceCallCount += 1;
    final override = scanResourceOverrides[resourceId];
    final matched = override == null
        ? scannedItems.where((item) => item.id == resourceId)
        : [override];
    if (matched.isEmpty) {
      return null;
    }
    final item = matched.first;
    return WebDavScannedItem(
      resourceId: item.id,
      fileName: item.path.split('/').last,
      actualAddress: item.path,
      sectionId: sectionId,
      sectionName: sectionName.isEmpty ? '剧集' : sectionName,
      streamUrl: 'https://media.example.com/${item.id}.mkv',
      streamHeaders: const {},
      addedAt: DateTime.utc(2026, 4, 5, 12, item.episodeNumber),
      modifiedAt: DateTime.utc(2026, 4, 5, 12, item.episodeNumber),
      fileSizeBytes: 1024,
      metadataSeed: WebDavMetadataSeed(
        title: item.title,
        overview: '',
        posterUrl: '',
        posterHeaders: const {},
        backdropUrl: '',
        backdropHeaders: const {},
        logoUrl: '',
        logoHeaders: const {},
        bannerUrl: '',
        bannerHeaders: const {},
        extraBackdropUrls: const [],
        extraBackdropHeaders: const {},
        year: 0,
        durationLabel: '剧集',
        genres: const [],
        directors: const [],
        actors: const [],
        itemType: item.itemType,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        imdbId: item.imdbId,
        container: 'mkv',
        videoCodec: '',
        audioCodec: '',
        width: null,
        height: null,
        bitrate: null,
        hasSidecarMatch:
            loadSidecarMetadata == true ? item.hasSidecarMatch : false,
      ),
    );
  }
}

Future<void> _drainAsyncTasks([int turns = 6]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _MemoryNasMediaIndexStore implements NasMediaIndexStore {
  final Map<String, List<NasMediaIndexRecord>> _records =
      <String, List<NasMediaIndexRecord>>{};
  final Map<String, NasMediaIndexSourceState> _states =
      <String, NasMediaIndexSourceState>{};

  @override
  Future<void> clearSource(String sourceId) async {
    _records.remove(sourceId);
    _states.remove(sourceId);
  }

  @override
  Future<NasMediaIndexSourceState?> loadSourceState(String sourceId) async {
    return _states[sourceId];
  }

  @override
  Future<List<NasMediaIndexRecord>> loadSourceRecords(String sourceId) async {
    return _records[sourceId] ?? const [];
  }

  @override
  Future<void> replaceSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
  }) async {
    _records[sourceId] = records;
    _states[sourceId] = state;
  }
}
