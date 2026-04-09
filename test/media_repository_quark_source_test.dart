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
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
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
              path: '/影视/Series',
              isDirectory: true,
            ),
            QuarkFileEntry(
              fid: 'movie-file',
              name: 'Movie.2024.mkv',
              path: '/影视/Movie.2024.mkv',
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
              path: '/影视/Series/The.Show.S01E01.mkv',
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
          nasMediaIndexerProvider
              .overrideWithValue(_buildNoopNasMediaIndexer()),
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

      final episode =
          items.singleWhere((item) => item.playbackItemId == 'episode-file');
      expect(episode.itemType, 'episode');
      expect(episode.seasonNumber, 1);
      expect(episode.episodeNumber, 1);
      expect(episode.actualAddress, '/影视/Series/The.Show.S01E01.mkv');
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
          nasMediaIndexerProvider
              .overrideWithValue(_buildNoopNasMediaIndexer()),
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
  });
}

NasMediaIndexer _buildNoopNasMediaIndexer() {
  return NasMediaIndexer(
    store: SembastNasMediaIndexStore(
      databaseOpener: () => databaseFactoryMemory
          .openDatabase('media-repository-quark-source-test'),
    ),
    webDavNasClient: WebDavNasClient(
      MockClient((request) async => http.Response('', 200)),
    ),
    wmdbMetadataClient: WmdbMetadataClient(
      MockClient((request) async => http.Response('', 200)),
    ),
    tmdbMetadataClient: TmdbMetadataClient(
      MockClient((request) async => http.Response('', 200)),
    ),
    imdbRatingClient: ImdbRatingClient(
      MockClient((request) async => http.Response('', 200)),
    ),
    readSettings: () => SeedData.defaultSettings,
    progressController: WebDavScrapeProgressController(),
  );
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
