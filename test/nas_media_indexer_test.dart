import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
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

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
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

  test(
      'NasMediaIndexer stops upward structure series inference at filtered folders',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-filtered-series',
      name: 'WebDAV Filtered Series',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSeriesTitleFilterKeywords: ['2160p'],
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/dav/shows/',
      title: '剧集',
      sourceId: 'webdav-filtered-series',
      sourceName: 'WebDAV Filtered Series',
      sourceKind: MediaSourceKind.nas,
    );

    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'filtered-ep-1',
          path: '怪奇物语/Stranger.Things.S04.2160p.NF.WEB-DL.x265.10bit.HDR/Stranger.Things.S04E01.2160p.NF.WEB-DL.x265.10bit.HDR.strm',
          title:
              'Stranger.Things.S04E01.2160p.NF.WEB-DL.x265.10bit.HDR',
          itemType: 'episode',
          seasonNumber: 4,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'filtered-ep-2',
          path: '怪奇物语/Stranger.Things.S04.2160p.NF.WEB-DL.x265.10bit.HDR/Stranger.Things.S04E02.2160p.NF.WEB-DL.x265.10bit.HDR.strm',
          title:
              'Stranger.Things.S04E02.2160p.NF.WEB-DL.x265.10bit.HDR',
          itemType: 'episode',
          seasonNumber: 4,
          episodeNumber: 2,
        ),
      ],
    );

    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: const [source],
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

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
    );
    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 20,
    );

    expect(library, hasLength(1));
    expect(library.single.itemType, 'series');
    expect(library.single.title, 'Stranger Things');
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

    await indexer.refreshSource(source);
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
        tmdbId: '603',
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
    expect(records.single.item.tmdbId, '603');
    expect(records.single.item.ratingLabels, contains('豆瓣 9.1'));
    expect(records.single.searchQuery, '黑客帝国');
    expect(records.single.wmdbMatched, isTrue);
    expect(records.single.wmdbStatus, NasMetadataFetchStatus.succeeded);
  });

  test('NasMediaIndexer reuses indexed cache for WebDAV id matching', () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-match-cache',
      name: 'WebDAV Match Cache',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Movies/',
      enabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'movie-cache-1',
          path: 'Movies/Dune.Part.Two.2024.2160p.mkv',
          title: 'Dune: Part Two',
          itemType: 'movie',
          seasonNumber: 0,
          episodeNumber: 0,
          imdbId: 'tt15239678',
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

    await indexer.refreshSource(source);
    expect(client.scanCallCount, 1);

    final matches = await indexer.loadCachedLibraryMatchItems(
      source,
      imdbId: 'tt15239678',
    );

    expect(matches, hasLength(1));
    expect(matches.single.id, 'movie-cache-1');
    expect(matches.single.imdbId, 'tt15239678');
    expect(client.scanCallCount, 1);
  });

  test('NasMediaIndexer manual metadata overwrites existing movie metadata',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-movie-overwrite',
      name: 'WebDAV Movie Overwrite',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Movies/',
      enabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'movie-overwrite-1',
          path: 'Movies/Old.Movie.2000.1080p.mkv',
          title: 'Old Movie',
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

    await indexer.refreshSource(source);
    final library = await indexer.loadLibrary(source, limit: 20);
    final seedTarget = MediaDetailTarget.fromMediaItem(library.single);

    await indexer.applyManualMetadata(
      target: seedTarget,
      searchQuery: '旧标题',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.tmdb,
        title: '旧标题',
        originalTitle: 'Old Title',
        posterUrl: 'https://img.example.com/old-poster.jpg',
        backdropUrl: 'https://img.example.com/old-backdrop.jpg',
        logoUrl: 'https://img.example.com/old-logo.png',
        bannerUrl: 'https://img.example.com/old-banner.jpg',
        extraBackdropUrls: ['https://img.example.com/old-extra.jpg'],
        overview: '旧简介',
        year: 2001,
        durationLabel: '1h 30m',
        genres: ['旧类型'],
        directors: ['旧导演'],
        actors: ['旧演员'],
        ratingLabels: ['TMDB 6.0'],
        imdbId: 'tt0000001',
        tmdbId: '1001',
      ),
    );

    final updatedTarget = await indexer.applyManualMetadata(
      target: seedTarget,
      searchQuery: '新标题',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.tmdb,
        title: '新标题',
        originalTitle: 'New Title',
        posterUrl: 'https://img.example.com/new-poster.jpg',
        backdropUrl: 'https://img.example.com/new-backdrop.jpg',
        logoUrl: 'https://img.example.com/new-logo.png',
        bannerUrl: 'https://img.example.com/new-banner.jpg',
        extraBackdropUrls: ['https://img.example.com/new-extra.jpg'],
        overview: '新简介',
        year: 2002,
        durationLabel: '2h 05m',
        genres: ['新类型'],
        directors: ['新导演'],
        actors: ['新演员'],
        ratingLabels: ['TMDB 8.0'],
        imdbId: 'tt0000002',
        tmdbId: '2002',
      ),
    );

    expect(updatedTarget, isNotNull);
    final records = await store.loadSourceRecords(source.id);
    expect(records.single.item.title, '新标题');
    expect(records.single.item.originalTitle, 'New Title');
    expect(records.single.item.posterUrl,
        'https://img.example.com/new-poster.jpg');
    expect(
      records.single.item.backdropUrl,
      'https://img.example.com/new-backdrop.jpg',
    );
    expect(records.single.item.logoUrl, 'https://img.example.com/new-logo.png');
    expect(records.single.item.bannerUrl,
        'https://img.example.com/new-banner.jpg');
    expect(
      records.single.item.extraBackdropUrls,
      ['https://img.example.com/new-extra.jpg'],
    );
    expect(records.single.item.overview, '新简介');
    expect(records.single.item.year, 2002);
    expect(records.single.item.durationLabel, '2h 05m');
    expect(records.single.item.genres, ['新类型']);
    expect(records.single.item.directors, ['新导演']);
    expect(records.single.item.actors, ['新演员']);
    expect(records.single.item.imdbId, 'tt0000002');
    expect(records.single.item.tmdbId, '2002');
    expect(records.single.searchQuery, '新标题');
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

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
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
        tmdbId: '4607',
      ),
    );

    expect(updatedTarget, isNotNull);
    expect(updatedTarget!.itemType, 'series');
    expect(updatedTarget.title, '迷失');
    expect(updatedTarget.imdbId, 'tt0411008');
    expect(updatedTarget.tmdbId, '4607');
    expect(updatedTarget.ratingLabels, contains('豆瓣 8.9'));

    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(2));
    expect(
        records.every((record) => record.item.imdbId == 'tt0411008'), isTrue);
    expect(records.every((record) => record.item.tmdbId == '4607'), isTrue);
    expect(records.every((record) => record.parentTitle == '迷失'), isTrue);
    expect(
      records.map((record) => record.item.title),
      containsAll(['Pilot (1)', 'Pilot (2)']),
    );
  });

  test(
      'NasMediaIndexer manual metadata overwrites existing synthetic series metadata',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-series-overwrite',
      name: 'WebDAV Series Overwrite',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-series-overwrite',
      sourceName: 'WebDAV Series Overwrite',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: [
        _episodeItem(
          id: 'series-overwrite-ep-1',
          path: 'Dark/Season 01/Episode 01.mkv',
          title: 'Secrets',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'series-overwrite-ep-2',
          path: 'Dark/Season 01/Episode 02.mkv',
          title: 'Lies',
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

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
    );
    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 20,
    );
    final series = library.single;
    final seedTarget = MediaDetailTarget.fromMediaItem(series);

    await indexer.applyManualMetadata(
      target: seedTarget,
      searchQuery: '暗黑',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.tmdb,
        title: '暗黑',
        posterUrl: 'https://img.example.com/dark-old-poster.jpg',
        backdropUrl: 'https://img.example.com/dark-old-backdrop.jpg',
        logoUrl: 'https://img.example.com/dark-old-logo.png',
        bannerUrl: 'https://img.example.com/dark-old-banner.jpg',
        extraBackdropUrls: ['https://img.example.com/dark-old-extra.jpg'],
        overview: '旧剧集简介',
        year: 2017,
        durationLabel: '45m / 集',
        genres: ['悬疑'],
        directors: ['旧导演'],
        actors: ['旧演员'],
        imdbId: 'tt5753856',
        tmdbId: '70523',
      ),
    );

    final updatedTarget = await indexer.applyManualMetadata(
      target: seedTarget,
      searchQuery: '暗黑 新',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.tmdb,
        title: '暗黑 新',
        posterUrl: 'https://img.example.com/dark-new-poster.jpg',
        backdropUrl: 'https://img.example.com/dark-new-backdrop.jpg',
        logoUrl: 'https://img.example.com/dark-new-logo.png',
        bannerUrl: 'https://img.example.com/dark-new-banner.jpg',
        extraBackdropUrls: ['https://img.example.com/dark-new-extra.jpg'],
        overview: '新剧集简介',
        year: 2020,
        durationLabel: '50m / 集',
        genres: ['科幻'],
        directors: ['新导演'],
        actors: ['新演员'],
        imdbId: 'tt9999999',
        tmdbId: '99999',
      ),
    );

    expect(updatedTarget, isNotNull);
    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(2));
    expect(records.every((record) => record.parentTitle == '暗黑 新'), isTrue);
    expect(records.every((record) => record.item.overview == '新剧集简介'), isTrue);
    expect(
      records.every(
        (record) =>
            record.item.posterUrl ==
            'https://img.example.com/dark-new-poster.jpg',
      ),
      isTrue,
    );
    expect(
      records.every(
        (record) =>
            record.item.backdropUrl ==
            'https://img.example.com/dark-new-backdrop.jpg',
      ),
      isTrue,
    );
    expect(
      records.every(
        (record) =>
            record.item.logoUrl == 'https://img.example.com/dark-new-logo.png',
      ),
      isTrue,
    );
    expect(
      records.every(
        (record) =>
            record.item.bannerUrl ==
            'https://img.example.com/dark-new-banner.jpg',
      ),
      isTrue,
    );
    expect(
      records.every(
        (record) =>
            record.item.extraBackdropUrls.first ==
            'https://img.example.com/dark-new-extra.jpg',
      ),
      isTrue,
    );
    expect(records.every((record) => record.item.year == 2020), isTrue);
    expect(
      records.every((record) => record.item.durationLabel == '50m / 集'),
      isTrue,
    );
    expect(records.every((record) => record.item.genres.join('|') == '科幻'),
        isTrue);
    expect(
      records.every((record) => record.item.directors.join('|') == '新导演'),
      isTrue,
    );
    expect(records.every((record) => record.item.actors.join('|') == '新演员'),
        isTrue);
    expect(
        records.every((record) => record.item.imdbId == 'tt9999999'), isTrue);
    expect(records.every((record) => record.item.tmdbId == '99999'), isTrue);
    expect(records.every((record) => record.searchQuery == '暗黑 新'), isTrue);
  });

  test(
      'NasMediaIndexer scopes synthetic manual metadata writes to the current directory path',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-series-scope',
      name: 'WebDAV Series Scope',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-series-scope',
      sourceName: 'WebDAV Series Scope',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: [
        _episodeItem(
          id: 'scope-ep-1',
          path: 'Lost/Season 01/Episode 01.mkv',
          title: 'Pilot (1)',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'scope-ep-2',
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

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
    );
    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(library, hasLength(1));
    final series = library.single;

    final updatedTarget = await indexer.applyManualMetadata(
      target: MediaDetailTarget.fromMediaItem(series).copyWith(
        resourcePath: 'https://nas.example.com/dav/Shows/Lost/Season 01',
      ),
      searchQuery: '迷失 第一季',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.tmdb,
        title: '迷失 第一季',
        originalTitle: 'Lost',
        overview: '第一季手动索引简介。',
        year: 2004,
        genres: ['剧情'],
        actors: ['马修·福克斯'],
        imdbId: 'tt0411008',
        tmdbId: '4607',
      ),
    );

    expect(updatedTarget, isNotNull);
    expect(updatedTarget!.resourcePath,
        'https://nas.example.com/dav/Shows/Lost/Season 01');

    final records = await store.loadSourceRecords(source.id);
    final seasonOne =
        records.firstWhere((record) => record.resourceId == 'scope-ep-1');
    final seasonTwo =
        records.firstWhere((record) => record.resourceId == 'scope-ep-2');
    expect(seasonOne.item.imdbId, 'tt0411008');
    expect(seasonOne.item.tmdbId, '4607');
    expect(seasonOne.item.overview, '第一季手动索引简介。');
    expect(seasonOne.parentTitle, '迷失 第一季');
    expect(seasonTwo.item.imdbId, isEmpty);
    expect(seasonTwo.item.tmdbId, isEmpty);
    expect(seasonTwo.item.overview, isEmpty);
    expect(seasonTwo.parentTitle, 'Lost');
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

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
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

    await indexer.refreshSource(source);
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
    expect(seasons.map((item) => item.seasonNumber), containsAll([7, 11]));
  });

  test(
      'NasMediaIndexer preserves numeric season folders and treats root files as specials',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-bare-numeric-seasons',
      name: 'WebDAV Bare Numeric Seasons',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-bare-numeric-seasons',
      sourceName: 'WebDAV Bare Numeric Seasons',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'food-bare-0',
          path: '食贫道/吴哥窟.(mp4).strm',
          title: '吴哥窟',
          itemType: '',
          seasonNumber: null,
          episodeNumber: null,
        ),
        _PendingTestItem(
          id: 'food-bare-1',
          path: '食贫道/6./深层目录/第01集.(mp4).strm',
          title: '第01集',
          itemType: '',
          seasonNumber: null,
          episodeNumber: null,
        ),
        _PendingTestItem(
          id: 'food-bare-2',
          path: '食贫道/12./更深/目录/第02集.(mp4).strm',
          title: '第02集',
          itemType: '',
          seasonNumber: null,
          episodeNumber: null,
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

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
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
    expect(seasons.map((item) => item.seasonNumber), containsAll([0, 6, 12]));
    expect(seasons.firstWhere((item) => item.seasonNumber == 0).title, '特别篇');
    expect(seasons.firstWhere((item) => item.seasonNumber == 6).title, '6.');
    expect(seasons.firstWhere((item) => item.seasonNumber == 12).title, '12.');
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

    await indexer.refreshSource(source);
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

  test(
      'NasMediaIndexer ignores wrapper folders nested under a season when deriving series title',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-show-root-wrapper-season',
      name: 'WebDAV Show Root Wrapper Season',
      kind: MediaSourceKind.nas,
      endpoint: 'https://webdav.example.com/shows/繁城之下/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'show-root-wrapper-1',
          path: 'Season 1/分段版 特效中字/Episode 01.strm',
          title: 'Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'show-root-wrapper-2',
          path: 'Season 1/分段版 特效中字/Episode 02.strm',
          title: 'Episode 02',
          itemType: 'episode',
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

    await indexer.refreshSource(source);
    final library = await indexer.loadLibrary(source, limit: 20);
    expect(library, hasLength(1));
    final series = library.single;
    expect(series.itemType, 'series');
    expect(series.title, '繁城之下');

    final seasons = await indexer.loadChildren(
      source,
      parentId: series.id,
      limit: 20,
    );
    expect(seasons, hasLength(1));
    expect(seasons.single.title, '第 1 季');
    expect(seasons.single.seasonNumber, 1);
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

    await indexer.refreshSource(source);
    final library = await indexer.loadLibrary(source, limit: 20);
    expect(library, hasLength(1));
    final movie = library.single;
    expect(movie.itemType, 'movie');
    expect(movie.streamUrl, isNotEmpty);
    expect(movie.title, '星球大战：最后的绝地武士 2160p remux (2017)');
  });

  test(
      'NasMediaIndexer manual movie metadata converts misgrouped single-resource series back to movie',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-manual-movie-fix',
      name: 'WebDAV Manual Movie Fix',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'manual-movie-1',
          path: 'Movies/Misclassified Movie/Misclassified.Movie.2024.mkv',
          title: 'Misclassified Movie',
          itemType: '',
          seasonNumber: null,
          episodeNumber: null,
          hasSidecarMatch: false,
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

    await indexer.refreshSource(source);
    final initialLibrary = await indexer.loadLibrary(source, limit: 20);
    expect(initialLibrary, hasLength(1));
    expect(initialLibrary.single.itemType, 'series');

    final updatedTarget = await indexer.applyManualMetadata(
      target: MediaDetailTarget.fromMediaItem(initialLibrary.single),
      searchQuery: '修正后的电影',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.tmdb,
        mediaType: MetadataMediaType.movie,
        title: '修正后的电影',
        originalTitle: 'Misclassified Movie',
        imdbId: 'tt9900001',
        tmdbId: '99001',
      ),
    );

    expect(updatedTarget, isNotNull);
    expect(updatedTarget!.itemType, 'movie');

    final library = await indexer.loadLibrary(source, limit: 20);
    expect(library, hasLength(1));
    expect(library.single.itemType, 'movie');
    expect(library.single.title, '修正后的电影');

    final records = await store.loadSourceRecords(source.id);
    expect(records.single.item.itemType, 'movie');
    expect(records.single.recognizedItemType, 'movie');
    expect(records.single.preferSeries, isFalse);
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
      'NasMediaIndexer force rescan cancels in-flight incremental background enrichment and restarts refresh',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-force-priority',
      name: 'WebDAV Force Priority',
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
          id: 'force-1',
          path: 'Shows/Test Show/Test Episode 01.mkv',
          title: 'Test Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
          hasSidecarMatch: true,
        ),
      ],
      scanResourceDelay: const Duration(milliseconds: 180),
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
    await indexer.refreshSource(source, forceFullRescan: true);
    await _drainAsyncTasks();

    expect(client.scanCallCount, 2);
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
      'NasMediaIndexer incremental refresh rescans while background enrichment is still running',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-refresh-during-background',
      name: 'WebDAV Refresh During Background',
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
    final scannedItems = <_PendingTestItem>[
      const _PendingTestItem(
        id: 'background-1',
        path: 'Shows/Test Show/Episode 01.strm',
        title: 'Episode 01',
        itemType: 'episode',
        seasonNumber: 1,
        episodeNumber: 1,
        hasSidecarMatch: false,
      ),
    ];
    final client = _FakeWebDavNasClient(
      scannedItems: scannedItems,
      scanResourceDelay: const Duration(milliseconds: 120),
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
    await Future<void>.delayed(const Duration(milliseconds: 10));

    scannedItems.add(
      const _PendingTestItem(
        id: 'background-2',
        path: 'Shows/Test Show/Episode 02.strm',
        title: 'Episode 02',
        itemType: 'episode',
        seasonNumber: 1,
        episodeNumber: 2,
        hasSidecarMatch: false,
      ),
    );

    await indexer.refreshSource(source);
    await _drainAsyncTasks();

    final records = await store.loadSourceRecords(source.id);
    expect(
      records.map((record) => record.resourceId),
      containsAll(<String>['background-1', 'background-2']),
    );
  });

  test(
      'NasMediaIndexer skips repeat sidecar scraping after an automatic failure',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-sidecar-failed-once',
      name: 'WebDAV Sidecar Failed Once',
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
          id: 'sidecar-fail-1',
          path: 'Shows/Test Show/Test Episode 01.mkv',
          title: 'Test Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
          hasSidecarMatch: false,
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
    expect(client.scanResourceCallCount, 1);

    final firstRecord = (await store.loadSourceRecords(source.id)).single;
    expect(firstRecord.sidecarStatus, NasMetadataFetchStatus.failed);

    await indexer.refreshSource(source, forceFullRescan: true);
    await _drainAsyncTasks();
    expect(
      client.scanResourceCallCount,
      1,
      reason:
          'Automatic rebuild should not retry sidecar scraping after a recorded failure.',
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
      'NasMediaIndexer uses series title plus file title for structure-inferred episode matching',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-episode-online-query',
      name: 'WebDAV Episode Online Query',
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
    var lastWmdbQuery = '';
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'episode-online-1',
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
          lastWmdbQuery = request.url.queryParameters['q'] ?? '';
          return http.Response(
            '{"data":[{"name":"Test Show","type":"series","year":"2024","doubanVotes":1000}]}',
            200,
          );
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

    expect(wmdbRequestCount, 1);
    expect(lastWmdbQuery, 'Test Show Episode 01');

    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(1));
    expect(records.single.searchQuery, 'Test Show Episode 01');
    expect(
      records.single.item.title,
      'Episode 01',
      reason:
          'Episode display title should not be overwritten by series match.',
    );
  });

  test(
      'NasMediaIndexer strips embedded external id tags from grouped series titles',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-round-table-tags',
      name: 'WebDAV Round Table',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/strm/115/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSidecarScrapingEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/movies/strm/115/',
      title: 'Round Table',
      sourceId: 'webdav-round-table-tags',
      sourceName: 'WebDAV Round Table',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'round-table-1',
          path:
              '圆桌派.Round Table (2016) {tmdbid-95903}/Season 1/圆桌派.Round Table (2016) S01E01.师徒.{tmdbid-95903}.strm',
          title: '师徒',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
          hasSidecarMatch: true,
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

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
    );
    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(library, hasLength(1));
    expect(library.single.title, '圆桌派 Round Table');

    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(1));
    expect(records.single.recognizedTitle, '圆桌派 Round Table');
    expect(records.single.parentTitle, '圆桌派 Round Table');
    expect(records.single.searchQuery, '圆桌派 Round Table 师徒');
  });

  test('NasMediaIndexer skips repeat WMDB matching after an automatic failure',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-wmdb-failed-once',
      name: 'WebDAV WMDB Failed Once',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
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
          id: 'wmdb-fail-1',
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
          return http.Response('{"data":[]}', 200);
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
    expect(wmdbRequestCount, 1);

    final firstRecord = (await store.loadSourceRecords(source.id)).single;
    expect(firstRecord.wmdbStatus, NasMetadataFetchStatus.failed);

    await indexer.refreshSource(source, forceFullRescan: true);
    await _drainAsyncTasks();
    expect(
      wmdbRequestCount,
      1,
      reason:
          'Automatic rebuild should not retry WMDB matching after a recorded failure.',
    );
  });

  test('NasMediaIndexer prioritizes imdb id for TMDB indexing', () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-imdb-priority',
      name: 'WebDAV IMDb Priority',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Movies/',
      enabled: true,
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: true,
      tmdbMetadataMatchEnabled: true,
      tmdbReadAccessToken: 'tmdb-token',
      imdbRatingMatchEnabled: false,
    );
    var tmdbFindRequests = 0;
    var wmdbSearchRequests = 0;
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'movie-imdb-1',
          path: 'Movies/The.Matrix.tt0133093.mkv',
          title: 'The Matrix',
          itemType: 'movie',
          seasonNumber: 0,
          episodeNumber: 0,
          imdbId: 'tt0133093',
        ),
      ],
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
      wmdbMetadataClient: WmdbMetadataClient(
        MockClient((request) async {
          wmdbSearchRequests += 1;
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'data': [
                    {
                      'name': '黑客帝国',
                    },
                  ],
                  'imdbId': 'tt0133093',
                  'year': '1999',
                },
              ],
            }),
            200,
          );
        }),
      ),
      tmdbMetadataClient: TmdbMetadataClient(
        MockClient((request) async {
          if (request.url.path == '/3/find/tt0133093') {
            tmdbFindRequests += 1;
            return http.Response(
              jsonEncode({
                'movie_results': [
                  {
                    'id': 603,
                    'title': 'The Matrix',
                    'original_title': 'The Matrix',
                    'release_date': '1999-03-31',
                    'popularity': 88.0,
                  },
                ],
                'tv_results': const [],
              }),
              200,
            );
          }
          if (request.url.path == '/3/movie/603') {
            return http.Response(
              jsonEncode({
                'id': 603,
                'title': '黑客帝国',
                'original_title': 'The Matrix',
                'overview': '一名黑客发现世界的真实面貌。',
                'poster_path': '/poster.jpg',
                'release_date': '1999-03-31',
                'runtime': 136,
                'genres': const [],
                'credits': {
                  'cast': const [],
                  'crew': const [],
                },
                'external_ids': {
                  'imdb_id': 'tt0133093',
                },
              }),
              200,
            );
          }
          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      ),
      imdbRatingClient: ImdbRatingClient(
        MockClient((request) async => http.Response('', 500)),
      ),
      readSettings: () => settings,
      progressController: WebDavScrapeProgressController(),
    );

    await indexer.refreshSource(source);
    await _drainAsyncTasks();

    expect(tmdbFindRequests, 1);
    expect(wmdbSearchRequests, 1);

    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(1));
    expect(records.single.item.imdbId, 'tt0133093');
  });

  test(
      'NasMediaIndexer removes records missing from an incremental WebDAV refresh',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-remove-missing',
      name: 'WebDAV Remove Missing',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Movies/',
      enabled: true,
    );
    final scannedItems = <_PendingTestItem>[
      const _PendingTestItem(
        id: 'keep-1',
        path: 'Movies/Keep.mkv',
        title: 'Keep',
        itemType: 'movie',
        seasonNumber: 0,
        episodeNumber: 0,
      ),
      const _PendingTestItem(
        id: 'delete-1',
        path: 'Movies/Delete.mkv',
        title: 'Delete',
        itemType: 'movie',
        seasonNumber: 0,
        episodeNumber: 0,
      ),
    ];
    final client = _FakeWebDavNasClient(scannedItems: scannedItems);
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

    await indexer.refreshSource(source);
    await _drainAsyncTasks();
    expect(
      (await store.loadSourceRecords(source.id)).map((item) => item.resourceId),
      ['keep-1', 'delete-1'],
    );

    scannedItems.removeWhere((item) => item.id == 'delete-1');

    await indexer.refreshSource(source);
    await _drainAsyncTasks();
    expect(
      (await store.loadSourceRecords(source.id)).map((item) => item.resourceId),
      ['keep-1'],
    );
  });

  test(
      'NasMediaIndexer removes records deleted between index and background enrichment',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-remove-during-enrichment',
      name: 'WebDAV Remove During Enrichment',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavSidecarScrapingEnabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'gone-later',
          path: 'Shows/Test/Test Episode 01.strm',
          title: 'Test Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
          hasSidecarMatch: false,
        ),
      ],
      missingScanResourceIds: const {'gone-later'},
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

    await indexer.refreshSource(source);
    await _drainAsyncTasks();

    final records = await store.loadSourceRecords(source.id);
    expect(records, isEmpty);
  });

  test('NasMediaIndexer cancels existing refresh tasks before a new rebuild',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-cancel-refresh',
      name: 'WebDAV Cancel Refresh',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-cancel-refresh',
      sourceName: 'WebDAV Cancel Refresh',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'cancel-1',
          path: '食贫道/6./第01集.strm',
          title: '第01集',
          itemType: '',
          seasonNumber: null,
          episodeNumber: null,
        ),
      ],
      scanDelay: const Duration(milliseconds: 80),
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

    final firstRefresh = indexer.refreshSource(
      source,
      scopedCollections: [collection],
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await indexer.cancelAllRefreshTasks();
    await firstRefresh;

    expect(await store.loadSourceRecords(source.id), isEmpty);

    await indexer.refreshSource(
      source,
      scopedCollections: [collection],
      forceFullRescan: true,
    );

    final records = await store.loadSourceRecords(source.id);
    expect(records, isNotEmpty);
  });

  test('NasMediaIndexer resets WebDAV scan caches only once for scoped scans',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-reset-caches-once',
      name: 'WebDAV Reset Caches Once',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
    );
    final collections = const [
      MediaCollection(
        id: 'https://nas.example.com/dav/Shows/A/',
        title: 'A',
        sourceId: 'webdav-reset-caches-once',
        sourceName: 'WebDAV Reset Caches Once',
        sourceKind: MediaSourceKind.nas,
      ),
      MediaCollection(
        id: 'https://nas.example.com/dav/Shows/B/',
        title: 'B',
        sourceId: 'webdav-reset-caches-once',
        sourceName: 'WebDAV Reset Caches Once',
        sourceKind: MediaSourceKind.nas,
      ),
    ];
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'reset-cache-1',
          path: 'Shows/Test Show/Test Episode 01.mkv',
          title: 'Test Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
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

    await indexer.refreshSource(
      source,
      scopedCollections: collections,
      forceFullRescan: true,
    );

    expect(client.resetCachesCalls, [true, false]);
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
  final int? seasonNumber;
  final int? episodeNumber;
  final String imdbId;
  final bool hasSidecarMatch;
}

class _ResolvedSeedData {
  const _ResolvedSeedData({
    required this.itemType,
    required this.seasonNumber,
    required this.episodeNumber,
  });

  final String itemType;
  final int? seasonNumber;
  final int? episodeNumber;
}

class _FakeWebDavNasClient extends WebDavNasClient {
  _FakeWebDavNasClient({
    required this.scannedItems,
    this.scanDelay = Duration.zero,
    this.scanResourceDelay = Duration.zero,
    this.scanResourceOverrides = const {},
    this.missingScanResourceIds = const {},
  }) : super(MockClient((request) async => http.Response('', 200)));

  final List<_PendingTestItem> scannedItems;
  final Duration scanDelay;
  final Duration scanResourceDelay;
  final Map<String, _PendingTestItem> scanResourceOverrides;
  final Set<String> missingScanResourceIds;
  final List<bool> resetCachesCalls = <bool>[];
  int scanCallCount = 0;
  int scanResourceCallCount = 0;

  @override
  Future<List<WebDavScannedItem>> scanLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
    bool? loadSidecarMetadata,
    bool resolvePlayableStreams = true,
    bool resetCaches = true,
    bool Function()? shouldCancel,
  }) async {
    scanCallCount += 1;
    resetCachesCalls.add(resetCaches);
    if (scanDelay > Duration.zero) {
      await Future<void>.delayed(scanDelay);
    }
    return scannedItems
        .take(limit)
        .map(
          (item) => _buildScannedItem(
            source: source,
            item: item,
            sectionId: sectionId ?? source.endpoint,
            sectionName: sectionName.isEmpty ? '剧集' : sectionName,
            loadSidecarMetadata: loadSidecarMetadata,
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
    bool resolvePlayableStreams = true,
    bool Function()? shouldCancel,
  }) async {
    scanResourceCallCount += 1;
    if (scanResourceDelay > Duration.zero) {
      await Future<void>.delayed(scanResourceDelay);
    }
    if (missingScanResourceIds.contains(resourceId)) {
      return null;
    }
    final override = scanResourceOverrides[resourceId];
    final matched = override == null
        ? scannedItems.where((item) => item.id == resourceId)
        : [override];
    if (matched.isEmpty) {
      return null;
    }
    final item = matched.first;
    return _buildScannedItem(
      source: source,
      item: item,
      sectionId: sectionId,
      sectionName: sectionName.isEmpty ? '剧集' : sectionName,
      loadSidecarMetadata: loadSidecarMetadata,
    );
  }

  WebDavScannedItem _buildScannedItem({
    required MediaSourceConfig source,
    required _PendingTestItem item,
    required String sectionId,
    required String sectionName,
    required bool? loadSidecarMetadata,
  }) {
    final resolvedSeed = _resolveSeedData(source, item);
    return WebDavScannedItem(
      resourceId: item.id,
      fileName: item.path.split('/').last,
      actualAddress: item.path,
      sectionId: sectionId,
      sectionName: sectionName,
      streamUrl: 'https://media.example.com/${item.id}.mkv',
      streamHeaders: const {},
      addedAt: DateTime.utc(2026, 4, 5, 12, resolvedSeed.episodeNumber ?? 0),
      modifiedAt: DateTime.utc(2026, 4, 5, 12, resolvedSeed.episodeNumber ?? 0),
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
        itemType: resolvedSeed.itemType,
        seasonNumber: resolvedSeed.seasonNumber,
        episodeNumber: resolvedSeed.episodeNumber,
        imdbId: item.imdbId,
        tmdbId: '',
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

  _ResolvedSeedData _resolveSeedData(
    MediaSourceConfig source,
    _PendingTestItem item,
  ) {
    final explicitItemType = item.itemType.trim();
    final explicitSeasonNumber = item.seasonNumber;
    final explicitEpisodeNumber = item.episodeNumber;
    if (!source.webDavStructureInferenceEnabled) {
      return _ResolvedSeedData(
        itemType: explicitItemType,
        seasonNumber: explicitSeasonNumber,
        episodeNumber: explicitEpisodeNumber,
      );
    }

    final segments = item.path
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final directorySegments = segments.length > 1
        ? segments.sublist(0, segments.length - 1)
        : const <String>[];
    final inferredSeasonNumber =
        explicitSeasonNumber ?? _inferSeasonNumber(directorySegments);
    final inferredEpisodeNumber = explicitEpisodeNumber ??
        _inferEpisodeNumber(segments.isEmpty ? '' : segments.last);
    final inferredItemType = explicitItemType.isNotEmpty
        ? explicitItemType
        : ((inferredSeasonNumber != null || inferredEpisodeNumber != null)
            ? 'episode'
            : '');
    return _ResolvedSeedData(
      itemType: inferredItemType,
      seasonNumber: inferredSeasonNumber,
      episodeNumber: inferredEpisodeNumber,
    );
  }

  int? _inferSeasonNumber(List<String> directories) {
    if (directories.length <= 1) {
      return directories.isNotEmpty ? 0 : null;
    }
    for (var index = directories.length - 1; index >= 0; index--) {
      final segment = directories[index];
      final numberedSeason =
          RegExp(r'^(\d{1,3})\s*\.[^/]*$').firstMatch(segment);
      if (numberedSeason != null) {
        return int.tryParse(numberedSeason.group(1) ?? '');
      }
      final namedSeason =
          RegExp(r'^(?:season|s)\s*0*(\d{1,3})$', caseSensitive: false)
              .firstMatch(segment);
      if (namedSeason != null) {
        return int.tryParse(namedSeason.group(1) ?? '');
      }
    }
    return 0;
  }

  int? _inferEpisodeNumber(String fileName) {
    final normalized = fileName.trim();
    final chineseEpisode = RegExp(r'第\s*0*(\d{1,4})\s*[集话]').firstMatch(
      normalized,
    );
    if (chineseEpisode != null) {
      return int.tryParse(chineseEpisode.group(1) ?? '');
    }
    final englishEpisode =
        RegExp(r'\b(?:ep|episode)[ ._-]*0*(\d{1,4})\b', caseSensitive: false)
            .firstMatch(normalized);
    if (englishEpisode != null) {
      return int.tryParse(englishEpisode.group(1) ?? '');
    }
    return null;
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
  Future<void> clearAll() async {
    _records.clear();
    _states.clear();
  }

  @override
  Future<void> clearSource(String sourceId) async {
    _records.remove(sourceId);
    _states.remove(sourceId);
  }

  @override
  Future<LocalStorageCacheSummary> inspectSummary() async {
    final recordList = _records.values.expand((items) => items).toList();
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.nasMetadataIndex,
      entryCount: recordList.length,
      totalBytes: utf8
          .encode(
            jsonEncode(recordList.map((record) => record.toJson()).toList()),
          )
          .length,
    );
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
