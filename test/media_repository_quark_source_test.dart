import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/quark_external_storage_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppMediaRepository Quark source', () {
    test('lists collections and video items from a configured quark source',
        () async {
      const source = MediaSourceConfig(
        id: 'quark-main',
        name: 'Quark Drive',
        kind: MediaSourceKind.quark,
        endpoint: 'root-folder',
        libraryPath: '/影视',
        enabled: true,
      );
      final quarkClient = _FakeQuarkSaveClient(
        entriesByParentFid: {
          'root-folder': [
            QuarkFileEntry(
              fid: 'series-dir',
              name: 'Series',
              path: '/Series',
              isDirectory: true,
            ),
            QuarkFileEntry(
              fid: 'movie-file',
              name: 'Movie.2024.mkv',
              path: '/Movie.2024.mkv',
              isDirectory: false,
              sizeBytes: 2147483648,
              updatedAt: DateTime(2026, 4, 9, 10),
              category: 'video',
              extension: 'mkv',
            ),
            QuarkFileEntry(
              fid: 'notes-file',
              name: 'notes.txt',
              path: '/影视/notes.txt',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 9, 9),
              category: 'doc',
              extension: 'txt',
            ),
          ],
          'series-dir': [
            QuarkFileEntry(
              fid: 'episode-file',
              name: 'The.Show.S01E01.mkv',
              path: '/The.Show.S01E01.mkv',
              isDirectory: false,
              sizeBytes: 1073741824,
              updatedAt: DateTime(2026, 4, 8, 20),
              category: 'video',
              extension: 'mkv',
            ),
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'kps=test; sign=test;',
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider.overrideWithValue(
            WebDavNasClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          nasMediaIndexStoreProvider.overrideWithValue(
            SembastNasMediaIndexStore(
              databaseOpener: () => databaseFactoryMemory.openDatabase(
                'media-repository-quark-source-test-1',
              ),
            ),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          imdbRatingClientProvider.overrideWithValue(
            ImdbRatingClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      final collections =
          await repository.fetchCollections(sourceId: source.id);
      final items =
          await repository.fetchLibrary(sourceId: source.id, limit: 10);

      expect(collections, hasLength(1));
      expect(collections.single.id, 'series-dir');
      expect(collections.single.title, 'Series');
      expect(collections.single.subtitle, '/影视/Series');

      expect(items, hasLength(2));
      expect(items.first.sourceKind, MediaSourceKind.quark);
      expect(items.first.playbackItemId, 'movie-file');
      expect(items.first.fileSizeBytes, 2147483648);
      expect(items.first.title, contains('Movie'));

      final series = items.singleWhere((item) => item.itemType == 'series');
      final seasons = await repository.fetchChildren(
        sourceId: source.id,
        parentId: series.id,
        limit: 10,
      );
      expect(seasons, hasLength(1));
      expect(seasons.single.itemType, 'season');
      expect(seasons.single.seasonNumber, 1);

      final children = await repository.fetchChildren(
        sourceId: source.id,
        parentId: seasons.single.id,
        limit: 10,
      );
      final episode =
          children.singleWhere((item) => item.playbackItemId == 'episode-file');
      expect(episode.itemType, 'episode');
      expect(episode.seasonNumber, 1);
      expect(episode.episodeNumber, 1);
      expect(episode.actualAddress, '/影视/Series/The.Show.S01E01.mkv');
    });

    test('rebuilds quark series from flattened child paths', () async {
      const source = MediaSourceConfig(
        id: 'quark-main',
        name: 'Quark Drive',
        kind: MediaSourceKind.quark,
        endpoint: 'root-folder',
        libraryPath: '/影视',
        enabled: true,
        webDavStructureInferenceEnabled: true,
      );
      final quarkClient = _FakeQuarkSaveClient(
        entriesByParentFid: {
          'root-folder': [
            QuarkFileEntry(
              fid: 'round-table-dir',
              name: '圆桌派',
              path: '/圆桌派',
              isDirectory: true,
            ),
          ],
          'round-table-dir': [
            QuarkFileEntry(
              fid: 'round-table-episode-1',
              name: '圆桌派.S01E01.师徒.mp4',
              path: '/圆桌派.S01E01.师徒.mp4',
              isDirectory: false,
              sizeBytes: 1024,
              updatedAt: DateTime(2026, 4, 10, 9),
              category: 'video',
              extension: 'mp4',
            ),
            QuarkFileEntry(
              fid: 'round-table-episode-2',
              name: '圆桌派.S01E02.离谱.mp4',
              path: '/圆桌派.S01E02.离谱.mp4',
              isDirectory: false,
              sizeBytes: 1024,
              updatedAt: DateTime(2026, 4, 10, 8),
              category: 'video',
              extension: 'mp4',
            ),
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'kps=test; sign=test;',
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider.overrideWithValue(
            WebDavNasClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          nasMediaIndexStoreProvider.overrideWithValue(
            SembastNasMediaIndexStore(
              databaseOpener: () => databaseFactoryMemory.openDatabase(
                'media-repository-quark-source-test-4',
              ),
            ),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          imdbRatingClientProvider.overrideWithValue(
            ImdbRatingClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      var library =
          await repository.fetchLibrary(sourceId: source.id, limit: 10);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (library.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        library = await repository.fetchLibrary(sourceId: source.id, limit: 10);
      }

      expect(library, hasLength(1));
      expect(library.single.itemType, 'series');
      expect(library.single.title, '圆桌派');

      final seasons = await repository.fetchChildren(
        sourceId: source.id,
        parentId: library.single.id,
        limit: 10,
      );
      expect(seasons, hasLength(1));
      expect(seasons.single.itemType, 'season');
      expect(seasons.single.seasonNumber, 1);

      final children = await repository.fetchChildren(
        sourceId: source.id,
        parentId: seasons.single.id,
        limit: 10,
      );
      expect(children, hasLength(2));
      expect(children.every((item) => item.itemType == 'episode'), isTrue);
      expect(
        children.map((item) => item.actualAddress),
        everyElement(startsWith('/影视/圆桌派/')),
      );
    });

    test('does not scan an unconfigured quark source', () async {
      const source = MediaSourceConfig(
        id: 'quark-main',
        name: 'Quark Drive',
        kind: MediaSourceKind.quark,
        endpoint: '',
        libraryPath: '',
        enabled: true,
      );
      final quarkClient = _FakeQuarkSaveClient(
        entriesByParentFid: {
          '0': [
            QuarkFileEntry(
              fid: 'movie-file',
              name: 'Movie.2024.mkv',
              path: '/Movie.2024.mkv',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 9, 10),
              category: 'video',
              extension: 'mkv',
            ),
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'kps=test; sign=test;',
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider.overrideWithValue(
            WebDavNasClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          nasMediaIndexStoreProvider.overrideWithValue(
            SembastNasMediaIndexStore(
              databaseOpener: () => databaseFactoryMemory.openDatabase(
                'media-repository-quark-source-test-2',
              ),
            ),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          imdbRatingClientProvider.overrideWithValue(
            ImdbRatingClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      final collections =
          await repository.fetchCollections(sourceId: source.id);
      final items =
          await repository.fetchLibrary(sourceId: source.id, limit: 10);

      expect(collections, isEmpty);
      expect(items, isEmpty);
      expect(quarkClient.listedParentFids, isEmpty);
    });

    test('reports progress while refreshing a quark source', () async {
      const source = MediaSourceConfig(
        id: 'quark-main',
        name: 'Quark Drive',
        kind: MediaSourceKind.quark,
        endpoint: 'root-folder',
        libraryPath: '/影视',
        enabled: true,
      );
      final gate = Completer<void>();
      final quarkClient = _BlockingQuarkSaveClient(
        gate: gate,
        entriesByParentFid: {
          'root-folder': [
            QuarkFileEntry(
              fid: 'movie-file',
              name: 'Movie.2024.mkv',
              path: '/影视/Movie.2024.mkv',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 21),
              category: 'video',
              extension: 'mkv',
            ),
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'kps=test; sign=test;',
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider.overrideWithValue(
            WebDavNasClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          nasMediaIndexStoreProvider.overrideWithValue(
            SembastNasMediaIndexStore(
              databaseOpener: () => databaseFactoryMemory.openDatabase(
                'media-repository-quark-source-test-3',
              ),
            ),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          imdbRatingClientProvider.overrideWithValue(
            ImdbRatingClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      final refreshFuture = repository.refreshSource(sourceId: source.id);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final progressState = container.read(webDavScrapeProgressProvider);
      expect(progressState.containsKey(source.id), isTrue);
      expect(progressState[source.id]?.stage, WebDavScrapeStage.scanning);

      gate.complete();
      await refreshFuture;
      await _waitUntil(
        () => !container.read(webDavScrapeProgressProvider).containsKey(
              source.id,
            ),
      );
    });

    test('cancels in-flight refresh safely when container is disposed',
        () async {
      const source = MediaSourceConfig(
        id: 'quark-main',
        name: 'Quark Drive',
        kind: MediaSourceKind.quark,
        endpoint: 'root-folder',
        libraryPath: '/影视',
        enabled: true,
        webDavSidecarScrapingEnabled: true,
      );
      final gate = Completer<void>();
      final quarkClient = _BlockingQuarkSaveClient(
        gate: gate,
        entriesByParentFid: {
          'root-folder': [
            QuarkFileEntry(
              fid: 'movie-file',
              name: 'Movie.2024.mkv',
              path: '/影视/Movie.2024.mkv',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 21),
              category: 'video',
              extension: 'mkv',
            ),
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'kps=test; sign=test;',
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider.overrideWithValue(
            WebDavNasClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          nasMediaIndexStoreProvider.overrideWithValue(
            SembastNasMediaIndexStore(
              databaseOpener: () => databaseFactoryMemory.openDatabase(
                'media-repository-quark-source-test-5',
              ),
            ),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          imdbRatingClientProvider.overrideWithValue(
            ImdbRatingClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
        ],
      );

      final repository = container.read(mediaRepositoryProvider);
      final refreshFuture = repository.refreshSource(sourceId: source.id);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      container.dispose();
      gate.complete();

      await expectLater(refreshFuture, completes);
    });

    test('uses shared scan-stage season rules for quark topic folders',
        () async {
      const source = MediaSourceConfig(
        id: 'quark-main',
        name: 'Quark Drive',
        kind: MediaSourceKind.quark,
        endpoint: 'root-folder',
        libraryPath: '/影视',
        enabled: true,
        webDavStructureInferenceEnabled: true,
      );
      final quarkClient = _FakeQuarkSaveClient(
        entriesByParentFid: {
          'food-dao-dir': [
            QuarkFileEntry(
              fid: 'food-special',
              name: '《电诈 摇滚 吴哥窟》.mp4',
              path: '/《电诈 摇滚 吴哥窟》.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 10),
              category: 'video',
              extension: 'mp4',
            ),
            QuarkFileEntry(
              fid: 'food-season-1-dir',
              name: '1.日本',
              path: '/1.日本',
              isDirectory: true,
            ),
            QuarkFileEntry(
              fid: 'food-season-2-dir',
              name: '2.巴以',
              path: '/2.巴以',
              isDirectory: true,
            ),
          ],
          'food-season-1-dir': [
            QuarkFileEntry(
              fid: 'food-season-1-ep-1',
              name: '食贫道 东瀛大宝荐 迷失东京.mp4',
              path: '/食贫道 东瀛大宝荐 迷失东京.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 9),
              category: 'video',
              extension: 'mp4',
            ),
          ],
          'food-season-2-dir': [
            QuarkFileEntry(
              fid: 'food-season-2-ep-1',
              name: '食贫道 巴以观察.mp4',
              path: '/食贫道 巴以观察.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 8),
              category: 'video',
              extension: 'mp4',
            ),
          ],
        },
      );
      final client = QuarkExternalStorageClient(
        quarkSaveClient: quarkClient,
        readSettings: () => SeedData.defaultSettings.copyWith(
          networkStorage: const NetworkStorageConfig(
            quarkCookie: 'kps=test; sign=test;',
          ),
        ),
      );

      final items = await client.scanLibrary(
        source,
        sectionId: 'food-dao-dir',
        sectionName: '食贫道',
        limit: 20,
      );

      expect(items, hasLength(3));
      expect(
        items.map((item) => item.metadataSeed.seasonNumber),
        containsAll([0, 1, 2]),
      );
      expect(
        items.every((item) => item.metadataSeed.itemType == 'episode'),
        isTrue,
      );
    });

    test('routes keyword-matched quark special folders into season zero',
        () async {
      const source = MediaSourceConfig(
        id: 'quark-specials',
        name: 'Quark Variety Specials',
        kind: MediaSourceKind.quark,
        endpoint: 'variety-root',
        libraryPath: '/综艺',
        enabled: true,
        webDavStructureInferenceEnabled: true,
      );
      final quarkClient = _FakeQuarkSaveClient(
        entriesByParentFid: {
          'variety-root': [
            QuarkFileEntry(
              fid: 'regular-dir',
              name: '正片',
              path: '/正片',
              isDirectory: true,
            ),
            QuarkFileEntry(
              fid: 'special-dir',
              name: '先导片',
              path: '/先导片',
              isDirectory: true,
            ),
          ],
          'regular-dir': [
            QuarkFileEntry(
              fid: 'regular-episode',
              name: '节目 第1期.mp4',
              path: '/节目 第1期.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 9),
              category: 'video',
              extension: 'mp4',
            ),
          ],
          'special-dir': [
            QuarkFileEntry(
              fid: 'special-episode',
              name: '节目 开场先导片.mp4',
              path: '/节目 开场先导片.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 10),
              category: 'video',
              extension: 'mp4',
            ),
          ],
        },
      );
      final client = QuarkExternalStorageClient(
        quarkSaveClient: quarkClient,
        readSettings: () => SeedData.defaultSettings.copyWith(
          networkStorage: const NetworkStorageConfig(
            quarkCookie: 'kps=test; sign=test;',
          ),
        ),
      );

      final items = await client.scanLibrary(
        source,
        sectionId: 'variety-root',
        sectionName: '节目',
        limit: 20,
      );

      expect(items, hasLength(2));
      expect(items.every((item) => item.metadataSeed.itemType == 'episode'),
          isTrue);

      final regularEpisode =
          items.firstWhere((item) => item.playbackItemId == 'regular-episode');
      expect(regularEpisode.metadataSeed.seasonNumber, 1);

      final specialEpisode =
          items.firstWhere((item) => item.playbackItemId == 'special-episode');
      expect(specialEpisode.metadataSeed.seasonNumber, 0);
    });

    test('routes built-in quark variety special keywords into season zero',
        () async {
      const source = MediaSourceConfig(
        id: 'quark-builtin-specials',
        name: 'Quark Builtin Specials',
        kind: MediaSourceKind.quark,
        endpoint: 'variety-builtin-root',
        libraryPath: '/综艺',
        enabled: true,
        webDavStructureInferenceEnabled: true,
      );
      final quarkClient = _FakeQuarkSaveClient(
        entriesByParentFid: {
          'variety-builtin-root': [
            QuarkFileEntry(
              fid: 'regular-dir',
              name: '正片',
              path: '/正片',
              isDirectory: true,
            ),
            QuarkFileEntry(
              fid: 'special-dir',
              name: '训练室',
              path: '/训练室',
              isDirectory: true,
            ),
          ],
          'regular-dir': [
            QuarkFileEntry(
              fid: 'regular-episode',
              name: '节目 第1期.mp4',
              path: '/节目 第1期.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 9),
              category: 'video',
              extension: 'mp4',
            ),
          ],
          'special-dir': [
            QuarkFileEntry(
              fid: 'special-episode',
              name: '节目 训练室全纪录.mp4',
              path: '/节目 训练室全纪录.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 10),
              category: 'video',
              extension: 'mp4',
            ),
          ],
        },
      );
      final client = QuarkExternalStorageClient(
        quarkSaveClient: quarkClient,
        readSettings: () => SeedData.defaultSettings.copyWith(
          networkStorage: const NetworkStorageConfig(
            quarkCookie: 'kps=test; sign=test;',
          ),
        ),
      );

      final items = await client.scanLibrary(
        source,
        sectionId: 'variety-builtin-root',
        sectionName: '节目',
        limit: 20,
      );

      expect(items, hasLength(2));
      final specialEpisode =
          items.firstWhere((item) => item.playbackItemId == 'special-episode');
      expect(specialEpisode.metadataSeed.seasonNumber, 0);
    });

    test('keeps variety specials separated instead of merging them away',
        () async {
      const source = MediaSourceConfig(
        id: 'quark-variety-merge-guard',
        name: 'Quark Variety Merge Guard',
        kind: MediaSourceKind.quark,
        endpoint: 'variety-merge-root',
        libraryPath: '/综艺',
        enabled: true,
        webDavStructureInferenceEnabled: true,
      );
      final quarkClient = _FakeQuarkSaveClient(
        entriesByParentFid: {
          'variety-merge-root': [
            QuarkFileEntry(
              fid: 'ride-the-wind-dir',
              name: '乘风2026',
              path: '/乘风2026',
              isDirectory: true,
            ),
          ],
          'ride-the-wind-dir': [
            QuarkFileEntry(
              fid: 'episode-main-a',
              name: '2026.04.03-第1期（上）.mp4',
              path: '/2026.04.03-第1期（上）.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 3, 20),
              category: 'video',
              extension: 'mp4',
            ),
            QuarkFileEntry(
              fid: 'episode-main-b',
              name: '2026.04.04-第1期（下）.mp4',
              path: '/2026.04.04-第1期（下）.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 4, 20),
              category: 'video',
              extension: 'mp4',
            ),
            QuarkFileEntry(
              fid: 'episode-special-linkup',
              name: '2026.03.28-乘风亲友连麦大会第1期.mp4',
              path: '/2026.03.28-乘风亲友连麦大会第1期.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 3, 28, 20),
              category: 'video',
              extension: 'mp4',
            ),
            QuarkFileEntry(
              fid: 'episode-special-extra',
              name: '2026.04.01-加更版第1期.mp4',
              path: '/2026.04.01-加更版第1期.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 1, 20),
              category: 'video',
              extension: 'mp4',
            ),
            QuarkFileEntry(
              fid: 'episode-special-pilot',
              name: '2026.04.02-先导片.mp4',
              path: '/2026.04.02-先导片.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 2, 20),
              category: 'video',
              extension: 'mp4',
            ),
            QuarkFileEntry(
              fid: 'episode-special-stage-1',
              name: '2026.04.04-舞台纯享版第1期.mp4',
              path: '/2026.04.04-舞台纯享版第1期.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 4, 21),
              category: 'video',
              extension: 'mp4',
            ),
            QuarkFileEntry(
              fid: 'episode-special-stage-2',
              name: '2026.04.11-舞台纯享版第2期.mp4',
              path: '/2026.04.11-舞台纯享版第2期.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 11, 20),
              category: 'video',
              extension: 'mp4',
            ),
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'kps=test; sign=test;',
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider.overrideWithValue(
            WebDavNasClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          nasMediaIndexStoreProvider.overrideWithValue(
            SembastNasMediaIndexStore(
              databaseOpener: () => databaseFactoryMemory.openDatabase(
                'media-repository-quark-source-test-merge-guard',
              ),
            ),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          imdbRatingClientProvider.overrideWithValue(
            ImdbRatingClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      var library =
          await repository.fetchLibrary(sourceId: source.id, limit: 10);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (library.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        library = await repository.fetchLibrary(sourceId: source.id, limit: 10);
      }

      expect(library, hasLength(1));
      expect(library.single.title, '乘风2026');

      final seasons = await repository.fetchChildren(
        sourceId: source.id,
        parentId: library.single.id,
        limit: 10,
      );
      expect(
        seasons
            .where((item) => item.itemType == 'season')
            .map((item) => item.seasonNumber),
        containsAll(<int?>[0, 1]),
      );

      final specialsSeason =
          seasons.firstWhere((item) => item.seasonNumber == 0);
      final regularSeason =
          seasons.firstWhere((item) => item.seasonNumber == 1);

      final specials = await repository.fetchChildren(
        sourceId: source.id,
        parentId: specialsSeason.id,
        limit: 20,
      );
      expect(
          specials.where((item) => item.itemType == 'episode'), hasLength(5));
      expect(
        specials.map((item) => item.actualAddress),
        containsAll(<String>[
          '/综艺/乘风2026/2026.03.28-乘风亲友连麦大会第1期.mp4',
          '/综艺/乘风2026/2026.04.01-加更版第1期.mp4',
          '/综艺/乘风2026/2026.04.02-先导片.mp4',
          '/综艺/乘风2026/2026.04.04-舞台纯享版第1期.mp4',
          '/综艺/乘风2026/2026.04.11-舞台纯享版第2期.mp4',
        ]),
      );

      final regularEpisodes = await repository.fetchChildren(
        sourceId: source.id,
        parentId: regularSeason.id,
        limit: 20,
      );
      expect(
        regularEpisodes.where((item) => item.itemType == 'episode'),
        hasLength(2),
      );
      expect(
        regularEpisodes.map((item) => item.actualAddress),
        containsAll(<String>[
          '/综艺/乘风2026/2026.04.03-第1期（上）.mp4',
          '/综艺/乘风2026/2026.04.04-第1期（下）.mp4',
        ]),
      );
    });

    test('routes keyword-matched quark extras into season zero', () async {
      const source = MediaSourceConfig(
        id: 'quark-extras',
        name: 'Quark Variety Extras',
        kind: MediaSourceKind.quark,
        endpoint: 'variety-extra-root',
        libraryPath: '/综艺',
        enabled: true,
        webDavStructureInferenceEnabled: true,
      );
      final quarkClient = _FakeQuarkSaveClient(
        entriesByParentFid: {
          'variety-extra-root': [
            QuarkFileEntry(
              fid: 'regular-dir',
              name: '正片',
              path: '/正片',
              isDirectory: true,
            ),
            QuarkFileEntry(
              fid: 'extra-dir',
              name: '花絮',
              path: '/花絮',
              isDirectory: true,
            ),
          ],
          'regular-dir': [
            QuarkFileEntry(
              fid: 'regular-episode',
              name: '节目 第1期.mp4',
              path: '/节目 第1期.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 9),
              category: 'video',
              extension: 'mp4',
            ),
          ],
          'extra-dir': [
            QuarkFileEntry(
              fid: 'extra-episode',
              name: '节目 采访.mp4',
              path: '/节目 采访.mp4',
              isDirectory: false,
              updatedAt: DateTime(2026, 4, 10, 10),
              category: 'video',
              extension: 'mp4',
            ),
          ],
        },
      );
      final client = QuarkExternalStorageClient(
        quarkSaveClient: quarkClient,
        readSettings: () => SeedData.defaultSettings.copyWith(
          networkStorage: const NetworkStorageConfig(
            quarkCookie: 'kps=test; sign=test;',
          ),
        ),
      );

      final items = await client.scanLibrary(
        source,
        sectionId: 'variety-extra-root',
        sectionName: '节目',
        limit: 20,
      );

      expect(items, hasLength(2));
      final regularEpisode =
          items.firstWhere((item) => item.playbackItemId == 'regular-episode');
      expect(regularEpisode.metadataSeed.seasonNumber, 1);
      final extraEpisode =
          items.firstWhere((item) => item.playbackItemId == 'extra-episode');
      expect(extraEpisode.metadataSeed.seasonNumber, 0);
    });
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(step);
  }
  if (!condition()) {
    throw TimeoutException('Condition not satisfied within $timeout.');
  }
}

class _FakeQuarkSaveClient extends QuarkSaveClient {
  _FakeQuarkSaveClient({
    required this.entriesByParentFid,
  }) : super(MockClient((request) async => http.Response('', 200)));

  final Map<String, List<QuarkFileEntry>> entriesByParentFid;
  final List<String> listedParentFids = <String>[];

  @override
  Future<List<QuarkFileEntry>> listEntries({
    required String cookie,
    String parentFid = '0',
  }) async {
    listedParentFids.add(parentFid);
    return entriesByParentFid[parentFid] ?? const <QuarkFileEntry>[];
  }

  @override
  Future<List<QuarkDirectoryEntry>> listDirectories({
    required String cookie,
    String parentFid = '0',
  }) async {
    final entries = await listEntries(
      cookie: cookie,
      parentFid: parentFid,
    );
    return entries
        .where((item) => item.isDirectory)
        .map(QuarkDirectoryEntry.fromFileEntry)
        .whereType<QuarkDirectoryEntry>()
        .toList(growable: false);
  }
}

class _BlockingQuarkSaveClient extends _FakeQuarkSaveClient {
  _BlockingQuarkSaveClient({
    required super.entriesByParentFid,
    required this.gate,
  });

  final Completer<void> gate;

  @override
  Future<List<QuarkFileEntry>> listEntries({
    required String cookie,
    String parentFid = '0',
  }) async {
    if (!gate.isCompleted) {
      await gate.future;
    }
    return super.listEntries(
      cookie: cookie,
      parentFid: parentFid,
    );
  }
}
