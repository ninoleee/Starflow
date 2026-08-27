import 'dart:async';
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
import 'package:starflow/features/metadata/application/metadata_prefetch_concurrency_limiter.dart';
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

  test('NasMediaIndexer materializes Friends and Lu Yu real-world naming',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-real-world-series',
      name: 'WebDAV Real World Series',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSeriesTitleFilterKeywords: ['movies', 'strm', 'quark'],
    );
    final collection = MediaCollection(
      id: 'https://nas.example.com/movies/',
      title: 'movies',
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: [
        _episodeItem(
          id: 'friends-s08e06',
          path: '/movies/strm/quark/老友记/SE08/老友记.H265.1080P.SE08.06.(mkv).strm',
          title: '第 6 集',
          seasonNumber: 8,
          episodeNumber: 6,
        ),
        _episodeItem(
          id: 'friends-s02e03',
          path: '/movies/strm/quark/老友记/SE02/老友记.H265.1080P.SE02.03.(mkv).strm',
          title: '第 3 集',
          seasonNumber: 2,
          episodeNumber: 3,
        ),
        _episodeItem(
          id: 'luyu-19',
          path: '/movies/strm/quark/陈鲁豫/陈鲁豫 · 慢谈 #19 对话张泉灵/video.strm',
          title: '第 19 集',
          seasonNumber: 1,
          episodeNumber: 19,
        ),
        _episodeItem(
          id: 'luyu-02',
          path: '/movies/strm/quark/陈鲁豫/陈鲁豫 · 慢谈 #02 对话陈奕迅/video.strm',
          title: '第 2 集',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
        _episodeItem(
          id: 'brilliant-friend-s01e01',
          path:
              '/movies/strm/quark/我的天才女友/我的天才女友S1/我.的.天.才.女.友.S01E01.消失的娃娃.strm',
          title: '第 1 集',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'brilliant-friend-s02e02',
          path: '/movies/strm/quark/我的天才女友/我的天才女友S2/我.的.天.才.女.友.S02E02.strm',
          title: '第 2 集',
          seasonNumber: 2,
          episodeNumber: 2,
        ),
        _episodeItem(
          id: 'brilliant-friend-s03e08',
          path:
              '/movies/strm/quark/我的天才女友/我的天才女友S3 蓝光版/我的天才女友.Lamica.geniale.S03E08.1080p.strm',
          title: '第 8 集',
          seasonNumber: 3,
          episodeNumber: 8,
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

    await indexer.refreshSource(source, scopedCollections: [collection]);
    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(
      library.map((item) => item.title).toSet(),
      {'老友记', '陈鲁豫', '我的天才女友'},
    );

    final friends = library.singleWhere((item) => item.title == '老友记');
    final friendsSeasons = await indexer.loadChildren(
      source,
      parentId: friends.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(
      friendsSeasons.map((item) => item.seasonNumber).toSet(),
      {2, 8},
    );
    final friendsSeasonEight =
        friendsSeasons.singleWhere((item) => item.seasonNumber == 8);
    final friendsEpisodes = await indexer.loadChildren(
      source,
      parentId: friendsSeasonEight.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(friendsEpisodes.single.episodeNumber, 6);

    final luYu = library.singleWhere((item) => item.title == '陈鲁豫');
    final luYuSeasons = await indexer.loadChildren(
      source,
      parentId: luYu.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(luYuSeasons, hasLength(1));
    expect(luYuSeasons.single.seasonNumber, 1);
    final luYuEpisodes = await indexer.loadChildren(
      source,
      parentId: luYuSeasons.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(
      luYuEpisodes.map((item) => item.episodeNumber).toSet(),
      {2, 19},
    );

    final brilliantFriend =
        library.singleWhere((item) => item.title == '我的天才女友');
    final brilliantFriendSeasons = await indexer.loadChildren(
      source,
      parentId: brilliantFriend.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(
      brilliantFriendSeasons.map((item) => item.seasonNumber).toSet(),
      {1, 2, 3},
    );
  });

  test(
      'NasMediaIndexer merges duplicate same-episode files and exposes playable variants',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-duplicate-episodes',
      name: 'WebDAV Duplicate Episodes',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    const collection = MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-duplicate-episodes',
      sourceName: 'WebDAV Duplicate Episodes',
      sourceKind: MediaSourceKind.nas,
    );

    final client = _FakeWebDavNasClient(
      scannedItems: [
        _episodeItem(
          id: 'episode-a',
          path: '食贫道/Season 01/食贫道.S01E01.版本A.mkv',
          title: '第 1 集',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'episode-b',
          path: '食贫道/Season 01/食贫道.S01E01.版本B.mkv',
          title: '第 1 集',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'episode-c',
          path: '食贫道/Season 01/食贫道.S01E02.mkv',
          title: '第 2 集',
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
      limit: 50,
    );
    expect(library, hasLength(1));

    final seasons = await indexer.loadChildren(
      source,
      parentId: library.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(seasons, hasLength(1));
    expect(seasons.single.itemType, 'season');
    expect(seasons.single.seasonNumber, 1);

    final episodes = await indexer.loadChildren(
      source,
      parentId: seasons.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(episodes, hasLength(2));
    expect(
      episodes
          .where((item) => item.seasonNumber == 1 && item.episodeNumber == 1),
      hasLength(1),
    );

    final mergedEpisode = episodes.firstWhere(
      (item) => item.seasonNumber == 1 && item.episodeNumber == 1,
    );
    final variants = await indexer.loadEpisodeVariants(
      source,
      itemId: mergedEpisode.id,
      sectionId: collection.id,
      scopedCollections: [collection],
    );
    expect(variants, hasLength(2));
    expect(
      variants.map((item) => item.id),
      containsAll(<String>['episode-a', 'episode-b']),
    );
  });

  test(
      'NasMediaIndexer keeps upper and lower variety parts separate while preserving same-part variants',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-variety-split-parts',
      name: 'WebDAV Variety Split Parts',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    const collection = MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '综艺',
      sourceId: 'webdav-variety-split-parts',
      sourceName: 'WebDAV Variety Split Parts',
      sourceKind: MediaSourceKind.nas,
    );

    final client = _FakeWebDavNasClient(
      scannedItems: [
        _episodeItem(
          id: 'episode-upper-a',
          path: '乘风2026/Season 01/2026.04.03-第1期（上）.mkv',
          title: '2026.04.03-第1期（上）',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'episode-upper-b',
          path: '乘风2026/Season 01/2026.04.03-第1期（上）.备用.mkv',
          title: '2026.04.03-第1期（上）',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'episode-lower',
          path: '乘风2026/Season 01/2026.04.04-第1期（下）.mkv',
          title: '2026.04.04-第1期（下）',
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
      scopedCollections: [collection],
    );
    final library = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(library, hasLength(1));

    final seasons = await indexer.loadChildren(
      source,
      parentId: library.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(seasons, hasLength(1));

    final episodes = await indexer.loadChildren(
      source,
      parentId: seasons.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(episodes, hasLength(2));

    final upperEpisode = episodes.firstWhere(
      (item) => item.actualAddress.contains('（上）'),
    );
    final lowerEpisode = episodes.firstWhere(
      (item) => item.actualAddress.contains('（下）'),
    );

    final upperVariants = await indexer.loadEpisodeVariants(
      source,
      itemId: upperEpisode.id,
      sectionId: collection.id,
      scopedCollections: [collection],
    );
    expect(upperVariants, hasLength(2));
    expect(
      upperVariants.map((item) => item.id),
      containsAll(<String>['episode-upper-a', 'episode-upper-b']),
    );

    final lowerVariants = await indexer.loadEpisodeVariants(
      source,
      itemId: lowerEpisode.id,
      sectionId: collection.id,
      scopedCollections: [collection],
    );
    expect(lowerVariants, hasLength(1));
    expect(lowerVariants.single.id, 'episode-lower');
  });

  test(
      'NasMediaIndexer unwraps resolution folders before season folders and merges same-episode variants',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-resolution-wrapper-episodes',
      name: 'WebDAV Resolution Wrapper Episodes',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    const collection = MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-resolution-wrapper-episodes',
      sourceName: 'WebDAV Resolution Wrapper Episodes',
      sourceKind: MediaSourceKind.nas,
    );

    final client = _FakeWebDavNasClient(
      scannedItems: [
        _episodeItem(
          id: 'resolution-episode-a',
          path: '食贫道/2160p/Season 01/食贫道.S01E01.2160p.mkv',
          title: '第 1 集',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'resolution-episode-b',
          path: '食贫道/1080p/Season 01/食贫道.S01E01.1080p.mkv',
          title: '第 1 集',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _episodeItem(
          id: 'resolution-episode-c',
          path: '食贫道/2160p/Season 01/食贫道.S01E02.2160p.mkv',
          title: '第 2 集',
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
      limit: 50,
    );
    expect(library, hasLength(1));
    expect(library.single.title, '食贫道');

    final seasons = await indexer.loadChildren(
      source,
      parentId: library.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(seasons, hasLength(1));
    expect(seasons.single.seasonNumber, 1);

    final episodes = await indexer.loadChildren(
      source,
      parentId: seasons.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 50,
    );
    expect(episodes, hasLength(2));

    final mergedEpisode = episodes.firstWhere(
      (item) => item.seasonNumber == 1 && item.episodeNumber == 1,
    );
    final variants = await indexer.loadEpisodeVariants(
      source,
      itemId: mergedEpisode.id,
      sectionId: collection.id,
      scopedCollections: [collection],
    );
    expect(variants, hasLength(2));
    expect(
      variants.map((item) => item.id),
      containsAll(<String>['resolution-episode-a', 'resolution-episode-b']),
    );
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
          path:
              '怪奇物语/Stranger.Things.S04.2160p.NF.WEB-DL.x265.10bit.HDR/Stranger.Things.S04E01.2160p.NF.WEB-DL.x265.10bit.HDR.strm',
          title: 'Stranger.Things.S04E01.2160p.NF.WEB-DL.x265.10bit.HDR',
          itemType: 'episode',
          seasonNumber: 4,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'filtered-ep-2',
          path:
              '怪奇物语/Stranger.Things.S04.2160p.NF.WEB-DL.x265.10bit.HDR/Stranger.Things.S04E02.2160p.NF.WEB-DL.x265.10bit.HDR.strm',
          title: 'Stranger.Things.S04E02.2160p.NF.WEB-DL.x265.10bit.HDR',
          itemType: 'episode',
          seasonNumber: 4,
          episodeNumber: 2,
        ),
      ],
    );

    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: [source],
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

  test(
      'NasMediaIndexer falls back to child directory or file when filtered section root would be used as series title',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-filtered-section-root',
      name: 'WebDAV Filtered Section Root',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSeriesTitleFilterKeywords: ['movies'],
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/movies/',
      title: '电影',
      sourceId: 'webdav-filtered-section-root',
      sourceName: 'WebDAV Filtered Section Root',
      sourceKind: MediaSourceKind.nas,
    );

    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'filtered-root-ep-1',
          path: 'Season 1/让子弹飞 第01集.mkv',
          title: '让子弹飞 第01集',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ],
    );

    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: [source],
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
    expect(library.single.title, '让子弹飞');
    expect(library.single.title, isNot('movies'));
  });

  test(
      'NasMediaIndexer falls back to the deepest child directory when filtered section root has wrapper folders',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-filtered-section-wrapper',
      name: 'WebDAV Filtered Section Wrapper',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSeriesTitleFilterKeywords: ['movies'],
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/movies/',
      title: '电影',
      sourceId: 'webdav-filtered-section-wrapper',
      sourceName: 'WebDAV Filtered Section Wrapper',
      sourceKind: MediaSourceKind.nas,
    );

    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'filtered-wrapper-ep-1',
          path: 'strm/quark/圆桌派/Season 1/圆桌派 第01集.strm',
          title: '圆桌派 第01集',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ],
    );

    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: [source],
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
    expect(library.single.title, '圆桌派');
    expect(library.single.title, isNot('strm'));
    expect(library.single.title, isNot('quark'));
  });

  test(
      'NasMediaIndexer keeps resources visible when top-level filtered folder wraps the real series folder',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-filtered-top-wrapper',
      name: 'WebDAV Filtered Top Wrapper',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSeriesTitleFilterKeywords: ['strm'],
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/movies/',
      title: '电影',
      sourceId: 'webdav-filtered-top-wrapper',
      sourceName: 'WebDAV Filtered Top Wrapper',
      sourceKind: MediaSourceKind.nas,
    );

    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'filtered-top-wrapper-1',
          path: 'strm/quark/圆桌派/Season 1/圆桌派 第01集.strm',
          title: '圆桌派 第01集',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'filtered-top-wrapper-2',
          path: 'strm/quark/圆桌派/Season 1/圆桌派 第02集.strm',
          title: '圆桌派 第02集',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
      ],
    );

    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: [source],
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
    expect(library.single.title, '圆桌派');

    final children = await indexer.loadChildren(
      source,
      parentId: library.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(children, hasLength(1));
    expect(children.single.itemType, 'season');
    expect(children.single.seasonNumber, 1);

    final episodes = await indexer.loadChildren(
      source,
      parentId: children.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(episodes, hasLength(2));
    expect(episodes.every((item) => item.itemType == 'episode'), isTrue);
  });

  test(
      'NasMediaIndexer uses a composite season folder as structure root when its parent is filtered',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-filtered-composite-season-root',
      name: 'WebDAV Filtered Composite Season Root',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSeriesTitleFilterKeywords: ['strm', 'quark'],
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/movies/',
      title: '电影',
      sourceId: 'webdav-filtered-composite-season-root',
      sourceName: 'WebDAV Filtered Composite Season Root',
      sourceKind: MediaSourceKind.nas,
    );

    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'filtered-composite-season-1',
          path: 'strm/quark/十三邀 第九季/十三邀 第01集.strm',
          title: '十三邀 第01集',
          itemType: 'episode',
          seasonNumber: 9,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'filtered-composite-season-2',
          path: 'strm/quark/十三邀 第九季/十三邀 第02集.strm',
          title: '十三邀 第02集',
          itemType: 'episode',
          seasonNumber: 9,
          episodeNumber: 2,
        ),
      ],
    );

    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: [source],
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
    expect(library.single.title, '十三邀 第九季');
    expect(library.single.id, isNot(contains('quark')));

    final children = await indexer.loadChildren(
      source,
      parentId: library.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(children, hasLength(1));
    expect(children.single.itemType, 'season');
    expect(children.single.seasonNumber, 9);

    final episodes = await indexer.loadChildren(
      source,
      parentId: children.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(episodes, hasLength(2));
    expect(episodes.every((item) => item.itemType == 'episode'), isTrue);
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
    expect(records.single.manualMetadataLocked, isTrue);
  });

  test(
      'NasMediaIndexer skips automatic indexed enrichment after manual metadata management',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-manual-lock-skip',
      name: 'WebDAV Manual Lock Skip',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Movies/',
      enabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'movie-lock-skip-1',
          path: 'Movies/Lock.Skip.Movie.2024.mkv',
          title: 'Lock Skip Movie',
          itemType: 'movie',
          seasonNumber: 0,
          episodeNumber: 0,
        ),
      ],
    );
    var tmdbRequestCount = 0;
    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: [source],
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: true,
      tmdbReadAccessToken: 'tmdb-token',
      imdbRatingMatchEnabled: false,
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
      wmdbMetadataClient: WmdbMetadataClient(
        MockClient((request) async => http.Response('', 500)),
      ),
      tmdbMetadataClient: TmdbMetadataClient(
        MockClient((request) async {
          tmdbRequestCount += 1;
          return http.Response('Not found', 404);
        }),
      ),
      imdbRatingClient: ImdbRatingClient(
        MockClient((request) async => http.Response('', 500)),
      ),
      readSettings: () => settings,
      progressController: WebDavScrapeProgressController(),
    );

    await indexer.refreshSource(source);
    final library = await indexer.loadLibrary(source, limit: 20);
    final updatedTarget = await indexer.applyManualMetadata(
      target: MediaDetailTarget.fromMediaItem(library.single),
      searchQuery: '手动锁定标题',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.wmdb,
        mediaType: MetadataMediaType.movie,
        title: '手动锁定标题',
        imdbId: 'tt0133093',
      ),
    );

    expect(updatedTarget, isNotNull);
    expect(
      (await store.loadSourceRecords(source.id)).single.manualMetadataLocked,
      isTrue,
    );

    final enriched = await indexer.enrichDetailTargetMetadataIfNeeded(
      updatedTarget!,
    );

    expect(enriched, isNotNull);
    expect(tmdbRequestCount, 0);
    final records = await store.loadSourceRecords(source.id);
    expect(records.single.item.title, '手动锁定标题');
    expect(records.single.tmdbStatus, NasMetadataFetchStatus.never);
  });

  test(
      'NasMediaIndexer preserves manually managed metadata after source reindex',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-manual-lock-preserve',
      name: 'WebDAV Manual Lock Preserve',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Movies/',
      enabled: true,
    );
    final scannedItems = <_PendingTestItem>[
      const _PendingTestItem(
        id: 'movie-lock-preserve-1',
        path: 'Movies/Original.Movie.2024.mkv',
        title: 'Original Movie',
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
    final library = await indexer.loadLibrary(source, limit: 20);
    await indexer.applyManualMetadata(
      target: MediaDetailTarget.fromMediaItem(library.single),
      searchQuery: '手动保留标题',
      metadataMatch: const MetadataMatchResult(
        provider: MetadataMatchProvider.tmdb,
        mediaType: MetadataMediaType.movie,
        title: '手动保留标题',
        overview: '这是需要在重扫后保留的简介。',
        imdbId: 'tt1234567',
        tmdbId: '123456',
      ),
    );

    scannedItems[0] = const _PendingTestItem(
      id: 'movie-lock-preserve-1',
      path: 'Movies/Renamed.Movie.2024.mkv',
      title: 'Renamed Movie',
      itemType: 'movie',
      seasonNumber: 0,
      episodeNumber: 0,
    );

    await indexer.refreshSource(source, forceFullRescan: true);

    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(1));
    expect(records.single.manualMetadataLocked, isTrue);
    expect(records.single.item.title, '手动保留标题');
    expect(records.single.item.overview, '这是需要在重扫后保留的简介。');
    expect(records.single.resourcePath, 'Movies/Renamed.Movie.2024.mkv');
    expect(records.single.item.actualAddress, 'Movies/Renamed.Movie.2024.mkv');
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

  test(
      'NasMediaIndexer falls back to cached library items when external ids miss',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-match-cache-fallback',
      name: 'WebDAV Match Cache Fallback',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Movies/',
      enabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'movie-cache-fallback-1',
          path: 'Movies/Ma.Teng.Ni.Bie.Zou.2026.mkv',
          title: '马腾你别走',
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
    expect(client.scanCallCount, 1);

    final matches = await indexer.loadCachedLibraryMatchItems(
      source,
      imdbId: 'tt38820860',
    );

    expect(matches, hasLength(1));
    expect(matches.single.id, 'movie-cache-fallback-1');
    expect(matches.single.title, '马腾你别走');
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

    final refreshedLibrary = await indexer.loadLibrary(
      source,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(refreshedLibrary, hasLength(1));
    expect(refreshedLibrary.single.title, '迷失');
    expect(refreshedLibrary.single.itemType, 'series');

    final refreshedChildren = await indexer.loadChildren(
      source,
      parentId: refreshedLibrary.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(refreshedChildren, hasLength(1));
    expect(refreshedChildren.single.itemType, 'season');
    expect(refreshedChildren.single.seasonNumber, 1);

    final refreshedEpisodes = await indexer.loadChildren(
      source,
      parentId: refreshedChildren.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(refreshedEpisodes, hasLength(2));
    expect(
        refreshedEpisodes.every((item) => item.itemType == 'episode'), isTrue);
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
      'NasMediaIndexer invalidates cached scope when series title filter keywords change',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-scope-title-filter',
      name: 'WebDAV Scope Title Filter',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    const collection = MediaCollection(
      id: 'https://nas.example.com/movies/',
      title: 'Quark',
      sourceId: 'webdav-scope-title-filter',
      sourceName: 'WebDAV Scope Title Filter',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'scope-title-filter-1',
          path: 'strm/quark/食贫道/《电诈 摇滚 吴哥窟》.(mp4).strm',
          title: '《电诈 摇滚 吴哥窟》',
          itemType: 'episode',
          seasonNumber: 0,
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

    final initialState = await store.loadSourceState(source.id);
    expect(initialState, isNotNull);
    expect(initialState!.scopeKey, contains('title-filter:'));
    expect(initialState.scopeKey, isNot(contains('title-filter:strm,quark')));

    final updatedSource = source.copyWith(
      webDavSeriesTitleFilterKeywords: ['strm', 'quark'],
    );
    final staleLibrary = await indexer.loadLibrary(
      updatedSource,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(staleLibrary, isEmpty);

    await indexer.refreshSource(
      updatedSource,
      scopedCollections: [collection],
    );

    final refreshedLibrary = await indexer.loadLibrary(
      updatedSource,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(refreshedLibrary, hasLength(1));

    final refreshedState = await store.loadSourceState(source.id);
    expect(refreshedState, isNotNull);
    expect(refreshedState!.scopeKey, contains('title-filter:strm,quark'));
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
      'NasMediaIndexer keeps mixed-case resolution wrapper folders under the outer series title',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-pinzhuo-resolution-wrapper',
      name: 'WebDAV Pinzhuo Resolution Wrapper',
      kind: MediaSourceKind.nas,
      endpoint: 'https://webdav.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'pinzhuo-root',
          path:
              'strm/quark/拼桌/2025.2160p.WEB-DL.HQ.H265.10bit.DDP5.1&DTS5.1.(mkv).strm',
          title: '2025.2160p.WEB-DL.HQ.H265.10bit.DDP5.1&DTS5.1.(mkv)',
          itemType: '',
          seasonNumber: null,
          episodeNumber: null,
        ),
        _PendingTestItem(
          id: 'pinzhuo-hdr60',
          path:
              'strm/quark/拼桌/4K hDr60FpS高码率/2025.2160p.60FpS.HDR.WEB-DL.H265.DDP2.0.(mkv).strm',
          title: '2025.2160p.60FpS.HDR.WEB-DL.H265.DDP2.0.(mkv)',
          itemType: '',
          seasonNumber: null,
          episodeNumber: null,
        ),
        _PendingTestItem(
          id: 'pinzhuo-hqsdr',
          path: 'strm/quark/拼桌/4K HqSdR高码率/PINZHUO.(mp4).strm',
          title: 'PINZHUO.(mp4)',
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

    await indexer.refreshSource(source);
    final library = await indexer.loadLibrary(source, limit: 20);

    expect(library.map((item) => item.title), contains('拼桌'));
    expect(
        library.map((item) => item.title), isNot(contains('4K hDr60FpS高码率')));
    expect(library.map((item) => item.title), isNot(contains('4K HqSdR高码率')));
    expect(
      library.where((item) => item.title == '拼桌'),
      hasLength(1),
    );

    final series = library.singleWhere((item) => item.title == '拼桌');
    final seasons = await indexer.loadChildren(
      source,
      parentId: series.id,
      limit: 20,
    );
    expect(seasons, hasLength(1));
  });

  test(
      'NasMediaIndexer keeps year and quality-count folders under the outer series title',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-year-grouping-folders',
      name: 'WebDAV Year Grouping Folders',
      kind: MediaSourceKind.nas,
      endpoint: 'https://webdav.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'call-me-2025',
          path: 'strm/quark/披荆斩棘2026/2025/第01期.strm',
          title: '第01期',
          itemType: 'episode',
          seasonNumber: 2,
          episodeNumber: 1,
          imdbId: 'tt-year-bucket-must-not-promote',
        ),
        _PendingTestItem(
          id: 'call-me-2026',
          path: 'strm/quark/披荆斩棘2026/2026（4K）/第01期.strm',
          title: '第01期',
          itemType: 'episode',
          seasonNumber: 3,
          episodeNumber: 1,
        ),
        _PendingTestItem(
          id: 'call-me-4k-count',
          path: 'strm/quark/披荆斩棘2026/4K 12集/第03期.strm',
          title: '第03期',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 3,
        ),
        _PendingTestItem(
          id: 'top-level-year-title',
          path: '2025/第01集.strm',
          title: '第01集',
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

    await indexer.refreshSource(source);
    final library = await indexer.loadLibrary(source, limit: 20);

    expect(library, hasLength(2));
    expect(library.map((item) => item.itemType), everyElement('series'));
    expect(
      library.map((item) => item.title),
      containsAll(<String>['披荆斩棘2026', '2025']),
    );
    expect(
      library.where((item) => item.title == '披荆斩棘2026'),
      hasLength(1),
    );

    final series = library.singleWhere((item) => item.title == '披荆斩棘2026');
    final seasons = await indexer.loadChildren(
      source,
      parentId: series.id,
      limit: 20,
    );
    expect(
      seasons.map((item) => item.title),
      containsAll(<String>['第 1 季', '2025', '2026（4K）']),
    );
    expect(seasons.map((item) => item.title), isNot(contains('4K 12集')));
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

  test('NasMediaIndexer uses season number from single-season series title',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-single-season-title-hint',
      name: 'WebDAV Single Season Title Hint',
      kind: MediaSourceKind.nas,
      endpoint: 'https://webdav.example.com/shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final settings = SeedData.defaultSettings.copyWith(
      mediaSources: [source],
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    final indexedAt = DateTime.utc(2026, 4, 5, 12);
    final scopeKey =
        'root|${source.endpoint.trim()}|structure:${source.webDavStructureInferenceEnabled}|scrape:${source.webDavSidecarScrapingEnabled}|exclude:${source.normalizedWebDavExcludedPathKeywords.join(',')}|title-filter:${source.normalizedWebDavSeriesTitleFilterKeywords.join(',')}|special-filter:${source.normalizedWebDavSpecialEpisodeKeywords.join(',')}|extra-filter:${source.normalizedWebDavExtraKeywords.join(',')}|schema:webdav-v6';
    final record = NasMediaIndexRecord(
      id: NasMediaIndexRecord.buildRecordId(
        sourceId: source.id,
        resourceId: 'title-season-hint-1',
      ),
      sourceId: source.id,
      sectionId: '',
      sectionName: '',
      resourceId: 'title-season-hint-1',
      resourcePath: '繁城之下 第3季/Episode 01.strm',
      fingerprint: 'title-season-hint-1',
      fileSizeBytes: 1024,
      modifiedAt: indexedAt,
      indexedAt: indexedAt,
      scrapedAt: indexedAt,
      recognizedTitle: '繁城之下 第3季',
      searchQuery: '繁城之下 第3季',
      originalFileName: 'Episode 01.strm',
      parentTitle: '',
      recognizedYear: 0,
      recognizedItemType: 'episode',
      preferSeries: true,
      recognizedEpisodeNumber: 1,
      sidecarStatus: NasMetadataFetchStatus.never,
      wmdbStatus: NasMetadataFetchStatus.never,
      tmdbStatus: NasMetadataFetchStatus.never,
      imdbStatus: NasMetadataFetchStatus.never,
      item: MediaItem(
        id: 'title-season-hint-1',
        title: 'Episode 01',
        overview: '',
        posterUrl: '',
        year: 0,
        durationLabel: '剧集',
        genres: const [],
        itemType: 'episode',
        sectionId: '',
        sectionName: '',
        sourceId: source.id,
        sourceName: source.name,
        sourceKind: source.kind,
        streamUrl: 'https://media.example.com/title-season-hint-1.mkv',
        actualAddress: '繁城之下 第3季/Episode 01.strm',
        episodeNumber: 1,
        addedAt: indexedAt,
      ),
    );
    await store.replaceSourceRecords(
      sourceId: source.id,
      records: [record],
      state: NasMediaIndexSourceState(
        sourceId: 'webdav-single-season-title-hint',
        lastIndexedAt: DateTime.utc(2026, 4, 5, 12),
        recordCount: 1,
        scopeKey: scopeKey,
      ),
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: _FakeWebDavNasClient(scannedItems: const []),
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
    expect(series.title, '繁城之下 第3季');

    final seasons = await indexer.loadChildren(
      source,
      parentId: series.id,
      limit: 20,
    );
    expect(seasons, hasLength(1));
    expect(seasons.single.title, '第 3 季');
    expect(seasons.single.seasonNumber, 3);
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
      'NasMediaIndexer collapses movie version folders into one playable movie with variants',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-basterds-variants',
      name: 'WebDAV Movies',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    const collection = MediaCollection(
      id: 'https://nas.example.com/movies/strm/quark/',
      title: '电影',
      sourceId: 'webdav-basterds-variants',
      sourceName: 'WebDAV Movies',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'basterds-1080p',
          path: 'strm/quark/无耻混蛋/1080P.国英双语.双语特效字幕/无耻混蛋.2009.1080p.strm',
          title: '无耻混蛋',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
        ),
        _PendingTestItem(
          id: 'basterds-4k',
          path: 'strm/quark/无耻混蛋/4K.国英双语.双语特效字幕/无耻混蛋.2009.2160p.strm',
          title: '无耻混蛋',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
        ),
        _PendingTestItem(
          id: 'basterds-english',
          path: 'strm/quark/无耻混蛋/4K.英语.外挂简繁特效/无耻混蛋.2009.english.strm',
          title: '无耻混蛋',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
        ),
        _PendingTestItem(
          id: 'basterds-high-bitrate',
          path: 'strm/quark/无耻混蛋/4K.高码.国英双语.双语特效字幕/无耻混蛋.2009.high-bitrate.strm',
          title: '无耻混蛋',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
        ),
        _PendingTestItem(
          id: 'basterds-1080p-part2',
          path: 'strm/quark/无耻混蛋/1080P.国英双语.双语特效字幕/Disc 1/part-2.strm',
          title: '无耻混蛋',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
        ),
        _PendingTestItem(
          id: 'basterds-4k-part2',
          path: 'strm/quark/无耻混蛋/4K.国英双语.双语特效字幕/Remux/part-2.strm',
          title: '无耻混蛋',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
        ),
        _PendingTestItem(
          id: 'basterds-english-part2',
          path: 'strm/quark/无耻混蛋/4K.英语.外挂简繁特效/WEB/part-2.strm',
          title: '无耻混蛋',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
        ),
        _PendingTestItem(
          id: 'basterds-high-bitrate-part2',
          path: 'strm/quark/无耻混蛋/4K.高码.国英双语.双语特效字幕/BDMV/part-2.strm',
          title: '无耻混蛋',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
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
      scopedCollections: const [collection],
    );

    final library = await indexer.loadLibrary(
      source,
      scopedCollections: const [collection],
      limit: 20,
    );
    expect(library, hasLength(1));
    final movie = library.single;
    expect(movie.title, '无耻混蛋');
    expect(movie.itemType, 'movie');
    expect(movie.isPlayable, isTrue);

    final variants = await indexer.loadMovieVariants(
      source,
      itemId: movie.id,
      sectionId: movie.sectionId,
    );
    expect(variants, hasLength(8));
    expect(variants.every((item) => item.itemType == 'movie'), isTrue);
    expect(variants.every((item) => item.isPlayable), isTrue);
    expect(
      variants.map((item) => item.actualAddress),
      containsAll(<String>[
        'strm/quark/无耻混蛋/1080P.国英双语.双语特效字幕/无耻混蛋.2009.1080p.strm',
        'strm/quark/无耻混蛋/4K.国英双语.双语特效字幕/无耻混蛋.2009.2160p.strm',
        'strm/quark/无耻混蛋/4K.英语.外挂简繁特效/无耻混蛋.2009.english.strm',
        'strm/quark/无耻混蛋/4K.高码.国英双语.双语特效字幕/无耻混蛋.2009.high-bitrate.strm',
        'strm/quark/无耻混蛋/1080P.国英双语.双语特效字幕/Disc 1/part-2.strm',
        'strm/quark/无耻混蛋/4K.国英双语.双语特效字幕/Remux/part-2.strm',
        'strm/quark/无耻混蛋/4K.英语.外挂简繁特效/WEB/part-2.strm',
        'strm/quark/无耻混蛋/4K.高码.国英双语.双语特效字幕/BDMV/part-2.strm',
      ]),
    );
  });

  test(
      'NasMediaIndexer repairs cached series records when version folders become movie variants',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-basterds-migration',
      name: 'WebDAV Movies',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/',
      enabled: true,
      webDavStructureInferenceEnabled: false,
    );
    const paths = <String>[
      'strm/quark/无耻混蛋/1080P.国英双语.双语特效字幕/无耻混蛋.2009.1080p.strm',
      'strm/quark/无耻混蛋/4K.英语.外挂简繁特效/无耻混蛋.2009.english.strm',
    ];
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
    );
    NasMediaIndexer buildIndexer(List<_PendingTestItem> items) {
      return NasMediaIndexer(
        store: store,
        webDavNasClient: _FakeWebDavNasClient(scannedItems: items),
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

    final oldIndexer = buildIndexer([
      for (var index = 0; index < paths.length; index++)
        _PendingTestItem(
          id: 'basterds-migration-$index',
          path: paths[index],
          title: index == 0 ? '1080P.国英双语.双语特效字幕' : '4K.英语.外挂简繁特效',
          itemType: 'series',
          seasonNumber: 0,
          episodeNumber: null,
        ),
    ]);
    await oldIndexer.refreshSource(source);
    expect(
      (await store.loadSourceRecords(source.id))
          .every((record) => record.item.itemType == 'series'),
      isTrue,
    );

    final repairedIndexer = buildIndexer([
      for (var index = 0; index < paths.length; index++)
        _PendingTestItem(
          id: 'basterds-migration-$index',
          path: paths[index],
          title: '无耻混蛋',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
        ),
    ]);
    await repairedIndexer.refreshSource(source);

    final repairedRecords = await store.loadSourceRecords(source.id);
    expect(repairedRecords, hasLength(2));
    expect(
      repairedRecords.every(
        (record) =>
            record.item.itemType == 'movie' &&
            record.item.title == '无耻混蛋' &&
            record.item.seasonNumber == null &&
            record.fingerprint.contains('movie-version-v1:'),
      ),
      isTrue,
    );
    final library = await repairedIndexer.loadLibrary(source, limit: 20);
    expect(library, hasLength(1));
    expect(library.single.title, '无耻混蛋');
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
    expect(firstRecord.sidecarStatus, NasMetadataFetchStatus.noMatch);

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
    expect(episodes, hasLength(1));
    expect(episodes.single.itemType, 'season');
    expect(episodes.single.seasonNumber, 1);

    final seasonEpisodes = await indexer.loadChildren(
      source,
      parentId: episodes.single.id,
      sectionId: collection.id,
      scopedCollections: [collection],
      limit: 20,
    );
    expect(seasonEpisodes, hasLength(2));
    expect(seasonEpisodes.every((item) => item.itemType == 'episode'), isTrue);
  });

  test(
      'NasMediaIndexer reuses the series title for structure-inferred episode matching',
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
        _PendingTestItem(
          id: 'episode-online-2',
          path: 'Shows/Test Show/Season 01/Episode 02.strm',
          title: 'Episode 02',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 2,
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
    expect(lastWmdbQuery, 'Test Show');

    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(2));
    expect(
        records.every((record) => record.searchQuery == 'Test Show'), isTrue);
    expect(
      records.map((record) => record.item.title),
      containsAll(<String>['Episode 01', 'Episode 02']),
      reason:
          'Episode display title should not be overwritten by series match.',
    );
  });

  test(
      'NasMediaIndexer matches movie versions by the movie root instead of the file name',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-movie-root-query',
      name: 'WebDAV Movie Root Query',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/movies/',
      enabled: true,
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
          id: 'basterds-root-query',
          path:
              'movies/strm/quark/无耻混蛋/4K.英语.外挂简繁特效/Inglourious.Basterds.2009.2160p.iTunes.WEB-DL.DD5.1.H.265-SuperMiao.(mkv).strm',
          title:
              'Inglourious.Basterds.2009.2160p.iTunes.WEB-DL.DD5.1.H.265-SuperMiao',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
          year: 2009,
          hasSidecarMatch: false,
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
            '{"data":[{"name":"无耻混蛋","originalName":"无耻混蛋","type":"movie","year":"2009","doubanVotes":1000}]}',
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
    expect(lastWmdbQuery, '无耻混蛋');
    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(1));
    expect(records.single.searchQuery, '无耻混蛋');
  });

  test(
      'NasMediaIndexer deduplicates TMDB series lookup across inferred episodes',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-episode-tmdb-series-query',
      name: 'WebDAV Episode TMDB Series Query',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSidecarScrapingEnabled: true,
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: true,
      tmdbReadAccessToken: 'tmdb-token',
      imdbRatingMatchEnabled: false,
      taskMaxConcurrency: 2,
    );
    var tmdbSearchRequestCount = 0;
    var lastTmdbQuery = '';
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'tmdb-series-episode-1',
          path: 'Shows/Test Show/Season 01/Test.Show.S01E01.strm',
          title: 'Test Show S01E01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
          hasSidecarMatch: true,
        ),
        _PendingTestItem(
          id: 'tmdb-series-episode-2',
          path: 'Shows/Test Show/Season 01/Test.Show.S01E02.strm',
          title: 'Test Show S01E02',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 2,
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
        MockClient((request) async {
          tmdbSearchRequestCount += 1;
          lastTmdbQuery = request.url.queryParameters['query'] ?? '';
          return http.Response('{"results":[]}', 200);
        }),
      ),
      imdbRatingClient: ImdbRatingClient(
        MockClient((request) async => http.Response('', 500)),
      ),
      readSettings: () => settings,
      progressController: WebDavScrapeProgressController(),
    );

    await indexer.refreshSource(source);
    await _drainAsyncTasks(12);

    expect(tmdbSearchRequestCount, 1);
    expect(lastTmdbQuery, 'Test Show');
    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(2));
    expect(records.every((record) => record.tmdbStatus.hasAttempted), isTrue);
  });

  test(
      'NasMediaIndexer can scrape structure-inferred episodes with series title only',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-episode-series-level-query',
      name: 'WebDAV Episode Series Level Query',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
      webDavSidecarScrapingEnabled: true,
      webDavSeriesScrapeUsesDirectoryTitleOnly: true,
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
          id: 'episode-online-series-level-1',
          path: 'Shows/Test Show (2024)/Season 01/Episode 01.strm',
          title: 'Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
          year: 2024,
          hasSidecarMatch: true,
        ),
        _PendingTestItem(
          id: 'episode-online-series-level-2',
          path: 'Shows/Test Show (2024)/Season 02/Episode 01.strm',
          title: 'Episode 01',
          itemType: 'episode',
          seasonNumber: 2,
          episodeNumber: 1,
          year: 2025,
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
    expect(lastWmdbQuery, 'Test Show');

    final records = await store.loadSourceRecords(source.id);
    expect(records, hasLength(2));
    expect(
        records.every((record) => record.searchQuery == 'Test Show'), isTrue);
    expect(
      records.every((record) => record.item.title == 'Episode 01'),
      isTrue,
      reason:
          'Episode display title should still keep the original episode title.',
    );
  });

  test('force-full NAS enrichment bypasses background batch pacing', () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-force-full-maintenance-enrichment',
      name: 'WebDAV Force Full Maintenance Enrichment',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavSidecarScrapingEnabled: true,
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
      taskMaxConcurrency: 2,
      metadataPrefetchInitialBatchSize: 6,
      metadataPrefetchBatchDelayMs: 1000,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: List<_PendingTestItem>.generate(
        8,
        (index) => _PendingTestItem(
          id: 'maintenance-${index + 1}',
          path: 'Shows/Test Show/Episode ${index + 1}.mkv',
          title: 'Episode ${index + 1}',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: index + 1,
        ),
      ),
      scanResourceDelay: const Duration(milliseconds: 5),
    );
    final limiter = MetadataPrefetchConcurrencyLimiter();
    addTearDown(limiter.dispose);
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
      backgroundLimiter: limiter,
    );
    addTearDown(indexer.dispose);

    await indexer.refreshSource(source, forceFullRescan: true);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(
      client.scanResourceCallCount,
      8,
      reason:
          'Explicit rebuild enrichment should not wait for the one-second background batch timer.',
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
    expect(records.single.searchQuery, '圆桌派 Round Table');
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
    expect(firstRecord.wmdbStatus, NasMetadataFetchStatus.noMatch);

    await indexer.refreshSource(source, forceFullRescan: true);
    await _drainAsyncTasks();
    expect(
      wmdbRequestCount,
      1,
      reason:
          'Automatic rebuild should not retry WMDB matching after a recorded failure.',
    );
  });

  test('NasMediaIndexer keeps WMDB title matching without TMDB imdb-id lookup',
      () async {
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

    expect(tmdbFindRequests, 0);
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
      'NasMediaIndexer re-adds a WebDAV resource with the same id on a later incremental refresh',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-readd-same-id',
      name: 'WebDAV Readd Same Id',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
    );
    final scannedItems = <_PendingTestItem>[
      const _PendingTestItem(
        id: 'same-resource',
        path: 'Shows/食贫道/Season 01/食贫道.S01E01.mkv',
        title: '食贫道',
        itemType: 'episode',
        seasonNumber: 1,
        episodeNumber: 1,
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
      ['same-resource'],
    );

    scannedItems.clear();
    await indexer.refreshSource(source);
    await _drainAsyncTasks();
    expect(await store.loadSourceRecords(source.id), isEmpty);

    scannedItems.add(
      const _PendingTestItem(
        id: 'same-resource',
        path: 'Shows/食贫道/Season 01/食贫道.S01E01.mkv',
        title: '食贫道',
        itemType: 'episode',
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    );
    await indexer.refreshSource(source);
    await _drainAsyncTasks();
    expect(
      (await store.loadSourceRecords(source.id)).map((item) => item.resourceId),
      ['same-resource'],
    );
  });

  test(
      'NasMediaIndexer re-adds a WebDAV resource after local scope removal on incremental refresh',
      () async {
    final store = _MemoryNasMediaIndexStore();
    const source = MediaSourceConfig(
      id: 'webdav-readd-after-local-remove',
      name: 'WebDAV Readd After Local Remove',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
    );
    final scannedItems = <_PendingTestItem>[
      const _PendingTestItem(
        id: 'same-resource',
        path: 'Shows/食贫道/Season 01/食贫道.S01E01.mkv',
        title: '食贫道',
        itemType: 'episode',
        seasonNumber: 1,
        episodeNumber: 1,
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
      ['same-resource'],
    );

    await indexer.removeResourceScope(
      sourceId: source.id,
      resourcePath: 'Shows/食贫道',
    );
    expect(await store.loadSourceRecords(source.id), isEmpty);

    await indexer.refreshSource(source);
    await _drainAsyncTasks();
    expect(
      (await store.loadSourceRecords(source.id)).map((item) => item.resourceId),
      ['same-resource'],
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

  test('NasMediaIndexer keeps force rescan running during default cancellation',
      () async {
    final store = _MemoryNasMediaIndexStore();
    final source = const MediaSourceConfig(
      id: 'webdav-keep-force-refresh',
      name: 'WebDAV Keep Force Refresh',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/Shows/',
      enabled: true,
      webDavStructureInferenceEnabled: true,
    );
    final collection = const MediaCollection(
      id: 'https://nas.example.com/dav/Shows/',
      title: '剧集',
      sourceId: 'webdav-keep-force-refresh',
      sourceName: 'WebDAV Keep Force Refresh',
      sourceKind: MediaSourceKind.nas,
    );
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'keep-force-1',
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

    final rebuildFuture = indexer.refreshSource(
      source,
      scopedCollections: [collection],
      forceFullRescan: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await indexer.cancelAllRefreshTasks();
    await rebuildFuture;

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

  test('NasMediaIndexer applies enrichment concurrency to items', () async {
    final store = _MemoryNasMediaIndexStore();
    final releaseRequests = Completer<void>();
    final firstPairStarted = Completer<void>();
    var activeRequests = 0;
    var maxActiveRequests = 0;
    var requestCount = 0;
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'enrichment-concurrency-1',
          path: 'Movies/Concurrency One.mkv',
          title: 'Concurrency One',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
        ),
        _PendingTestItem(
          id: 'enrichment-concurrency-2',
          path: 'Movies/Concurrency Two.mkv',
          title: 'Concurrency Two',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
        ),
        _PendingTestItem(
          id: 'enrichment-concurrency-3',
          path: 'Movies/Concurrency Three.mkv',
          title: 'Concurrency Three',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
        ),
      ],
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: true,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
      taskMaxConcurrency: 2,
    );
    final indexer = NasMediaIndexer(
      store: store,
      webDavNasClient: client,
      wmdbMetadataClient: WmdbMetadataClient(
        MockClient((request) async {
          requestCount += 1;
          activeRequests += 1;
          if (activeRequests > maxActiveRequests) {
            maxActiveRequests = activeRequests;
          }
          if (activeRequests == 2 && !firstPairStarted.isCompleted) {
            firstPairStarted.complete();
          }
          await releaseRequests.future;
          activeRequests -= 1;
          return http.Response(
            '{"data":[{"name":"Concurrency Match","type":"movie","year":"2024","doubanVotes":1000}]}',
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
    const source = MediaSourceConfig(
      id: 'webdav-enrichment-concurrency',
      name: 'WebDAV Enrichment Concurrency',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/enrichment-concurrency/',
      enabled: true,
      webDavSidecarScrapingEnabled: false,
    );

    await indexer.refreshSource(source);
    await firstPairStarted.future.timeout(const Duration(seconds: 1));

    expect(maxActiveRequests, 2);
    expect(requestCount, 2);

    releaseRequests.complete();
    await _waitUntil(() async {
      final records = await store.loadSourceRecords(source.id);
      return records.length == 3 &&
          records.every((record) => record.wmdbStatus.hasAttempted);
    });

    expect(requestCount, 3);
    expect(maxActiveRequests, 2);
  });

  test('NasMediaIndexer enforces source refresh concurrency budget', () async {
    final store = _MemoryNasMediaIndexStore();
    final gateOne = Completer<void>();
    final gateTwo = Completer<void>();
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'concurrency-item',
          path: 'Movie/Example.mkv',
          title: 'Example',
          itemType: 'movie',
          seasonNumber: null,
          episodeNumber: null,
        ),
      ],
      onScanDelay: (callIndex) async {
        if (callIndex == 1) {
          await gateOne.future;
        } else if (callIndex == 2) {
          await gateTwo.future;
        }
      },
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
      taskMaxConcurrency: 1,
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
    const sourceA = MediaSourceConfig(
      id: 'webdav-concurrency-source-a',
      name: 'WebDAV Concurrency Source A',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/concurrency/a/',
      enabled: true,
      webDavSidecarScrapingEnabled: false,
    );
    const sourceB = MediaSourceConfig(
      id: 'webdav-concurrency-source-b',
      name: 'WebDAV Concurrency Source B',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/concurrency/b/',
      enabled: true,
      webDavSidecarScrapingEnabled: false,
    );

    final firstRefresh = indexer.refreshSource(sourceA);
    await Future<void>.delayed(Duration.zero);
    final secondRefresh = indexer.refreshSource(sourceB);
    await Future<void>.delayed(Duration.zero);
    expect(client.scanCallCount, 1);
    gateOne.complete();
    await Future<void>.delayed(Duration.zero);
    await firstRefresh;
    await Future<void>.delayed(Duration.zero);
    expect(client.scanCallCount, 2);
    gateTwo.complete();
    await secondRefresh;
  });

  test('NasMediaIndexer respects collection refresh concurrency budget',
      () async {
    final store = _MemoryNasMediaIndexStore();
    var currentConcurrent = 0;
    var maxConcurrent = 0;
    final client = _FakeWebDavNasClient(
      scannedItems: const [
        _PendingTestItem(
          id: 'collection-item',
          path: 'Series/Season 01/Episode 01.mkv',
          title: 'Episode 01',
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ],
      onScanDelay: (_) async =>
          Future<void>.delayed(Duration(milliseconds: 30)),
      onScanEnter: (_) {
        currentConcurrent += 1;
        if (currentConcurrent > maxConcurrent) {
          maxConcurrent = currentConcurrent;
        }
      },
      onScanExit: (_) {
        currentConcurrent -= 1;
      },
    );
    final settings = SeedData.defaultSettings.copyWith(
      wmdbMetadataMatchEnabled: false,
      tmdbMetadataMatchEnabled: false,
      imdbRatingMatchEnabled: false,
      taskMaxConcurrency: 2,
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
    const source = MediaSourceConfig(
      id: 'webdav-concurrent-collections',
      name: 'WebDAV Concurrent Collections',
      kind: MediaSourceKind.nas,
      endpoint: 'https://nas.example.com/dav/concurrent/',
      enabled: true,
      webDavSidecarScrapingEnabled: false,
    );
    final collections = List.generate(
      3,
      (index) => MediaCollection(
        id: 'https://nas.example.com/dav/concurrent/section-${index + 1}',
        title: 'Section ${index + 1}',
        sourceId: source.id,
        sourceName: source.name,
        sourceKind: source.kind,
      ),
    );

    await indexer.refreshSource(
      source,
      scopedCollections: collections,
    );

    expect(maxConcurrent, 2);
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
    this.year = 0,
    this.hasSidecarMatch = true,
  });

  final String id;
  final String path;
  final String title;
  final String itemType;
  final int? seasonNumber;
  final int? episodeNumber;
  final String imdbId;
  final int year;
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
    this.onScanDelay,
    this.onScanEnter,
    this.onScanExit,
  }) : super(MockClient((request) async => http.Response('', 200)));

  final List<_PendingTestItem> scannedItems;
  final Duration scanDelay;
  final Duration scanResourceDelay;
  final Map<String, _PendingTestItem> scanResourceOverrides;
  final Set<String> missingScanResourceIds;
  final Future<void> Function(int callIndex)? onScanDelay;
  final void Function(int callIndex)? onScanEnter;
  final void Function(int callIndex)? onScanExit;
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
    final callIndex = scanCallCount;
    resetCachesCalls.add(resetCaches);
    onScanEnter?.call(callIndex);
    try {
      if (onScanDelay != null) {
        await onScanDelay!(callIndex);
      } else if (scanDelay > Duration.zero) {
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
    } finally {
      onScanExit?.call(callIndex);
    }
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
        year: item.year,
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

Future<void> _waitUntil(
  FutureOr<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!await predicate()) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException('Timed out waiting for asynchronous index work.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
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
  Future<List<NasMediaIndexRecord>> loadSourceRecords(
    String sourceId, {
    String sectionId = '',
  }) async {
    final records = _records[sourceId] ?? const <NasMediaIndexRecord>[];
    final normalizedSectionId = sectionId.trim();
    if (normalizedSectionId.isEmpty) {
      return records;
    }
    return records
        .where((record) => record.sectionId == normalizedSectionId)
        .toList(growable: false);
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

  @override
  Future<void> upsertSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> records,
    required NasMediaIndexSourceState state,
    bool clearMissingRecords = false,
  }) async {
    if (clearMissingRecords) {
      _records[sourceId] = records;
    } else {
      final existing = _records[sourceId] ?? const <NasMediaIndexRecord>[];
      final merged = <String, NasMediaIndexRecord>{
        for (final record in existing) record.id: record,
      };
      for (final record in records) {
        merged[record.id] = record;
      }
      _records[sourceId] = merged.values.toList(growable: false);
    }
    _states[sourceId] = state;
  }

  @override
  Future<void> patchSourceRecords({
    required String sourceId,
    required List<NasMediaIndexRecord> upsertedRecords,
    required List<String> deletedRecordIds,
    required NasMediaIndexSourceState state,
  }) async {
    final merged = <String, NasMediaIndexRecord>{
      for (final record in _records[sourceId] ?? const <NasMediaIndexRecord>[])
        record.id: record,
    };
    for (final recordId in deletedRecordIds) {
      merged.remove(recordId);
    }
    for (final record in upsertedRecords) {
      merged[record.id] = record;
    }
    _records[sourceId] = merged.values.toList(growable: false);
    _states[sourceId] = state;
  }
}
