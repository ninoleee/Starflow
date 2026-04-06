import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
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
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  group('AppMediaRepository synced Quark delete', () {
    test(
        'deletes the matched Quark directory after deleting a WebDAV strm file',
        () async {
      const source = MediaSourceConfig(
        id: 'nas-main',
        name: '家庭 NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/',
        enabled: true,
      );
      final webDavClient = _RecordingWebDavNasClient(
        resolvedTargetUrl: 'https://pan.quark.cn/s/abc123',
      );
      final quarkClient = _RecordingQuarkSaveClient(
        directories: const [
          QuarkDirectoryEntry(
            fid: 'quark-dir-1',
            name: 'One Piece',
            path: '/保存目录/One Piece',
          ),
        ],
      );
      final cacheRepository = _RecordingLocalStorageCacheRepository();
      final indexer = _FakeNasMediaIndexer();
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'foo=bar',
                quarkSaveFolderId: 'folder-root',
                quarkSaveFolderPath: '/保存目录',
                syncDeleteQuarkEnabled: true,
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
                MockClient((request) async => http.Response('', 200))),
          ),
          webDavNasClientProvider.overrideWithValue(webDavClient),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
          nasMediaIndexerProvider.overrideWithValue(indexer),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      const resourcePath =
          'https://nas.example.com/dav/Shows/One%20Piece/Season%201/Episode%2001.strm';

      await repository.deleteResource(
        sourceId: source.id,
        resourcePath: resourcePath,
      );

      expect(webDavClient.deletedResourcePaths, [resourcePath]);
      expect(quarkClient.listParentFids, ['folder-root']);
      expect(quarkClient.deletedFids, ['quark-dir-1']);
      expect(indexer.removedScopes, [resourcePath]);
      expect(cacheRepository.clearedResources, hasLength(1));
      expect(cacheRepository.clearedResources.single.resourceId, resourcePath);
      expect(
          cacheRepository.clearedResources.single.resourcePath, resourcePath);
      expect(cacheRepository.clearedResources.single.treatAsScope, isFalse);
    });

    test('skips Quark deletion when the resolved strm target is not Quark',
        () async {
      const source = MediaSourceConfig(
        id: 'nas-main',
        name: '家庭 NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/',
        enabled: true,
      );
      final webDavClient = _RecordingWebDavNasClient(
        resolvedTargetUrl: 'https://media.example.com/stream.m3u8',
      );
      final quarkClient = _RecordingQuarkSaveClient(
        directories: const [
          QuarkDirectoryEntry(
            fid: 'quark-dir-1',
            name: 'One Piece',
            path: '/保存目录/One Piece',
          ),
        ],
      );
      final cacheRepository = _RecordingLocalStorageCacheRepository();
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'foo=bar',
                quarkSaveFolderId: 'folder-root',
                quarkSaveFolderPath: '/保存目录',
                syncDeleteQuarkEnabled: true,
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
                MockClient((request) async => http.Response('', 200))),
          ),
          webDavNasClientProvider.overrideWithValue(webDavClient),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
          nasMediaIndexerProvider.overrideWithValue(_FakeNasMediaIndexer()),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      await repository.deleteResource(
        sourceId: source.id,
        resourcePath:
            'https://nas.example.com/dav/Shows/One%20Piece/Season%201/Episode%2001.strm',
      );

      expect(quarkClient.listParentFids, isEmpty);
      expect(quarkClient.deletedFids, isEmpty);
    });

    test(
        'deleting a directory scope can still sync delete the matched Quark directory',
        () async {
      const source = MediaSourceConfig(
        id: 'nas-main',
        name: '家庭 NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/',
        enabled: true,
      );
      final webDavClient = _RecordingWebDavNasClient(
        resolvedTargetUrl: 'https://pan.quark.cn/s/series123',
      );
      final quarkClient = _RecordingQuarkSaveClient(
        directories: const [
          QuarkDirectoryEntry(
            fid: 'quark-dir-series',
            name: '请求救援',
            path: '/保存目录/请求救援',
          ),
        ],
      );
      final indexer = _FakeNasMediaIndexer(
        scopeRecords: [
          _scopeRecord(
            sourceId: source.id,
            resourceId:
                'https://nas.example.com/dav/movies/strm/quark/%E8%AF%B7%E6%B1%82%E6%95%91%E6%8F%B4/Send%20Help%20(2026).strm',
            resourcePath: '/movies/strm/quark/请求救援/Send Help (2026).strm',
            sectionId: 'https://nas.example.com/dav/movies/',
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
              networkStorage: const NetworkStorageConfig(
                quarkCookie: 'foo=bar',
                quarkSaveFolderId: 'folder-root',
                quarkSaveFolderPath: '/保存目录',
                syncDeleteQuarkEnabled: true,
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
                MockClient((request) async => http.Response('', 200))),
          ),
          webDavNasClientProvider.overrideWithValue(webDavClient),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
          nasMediaIndexerProvider.overrideWithValue(indexer),
          localStorageCacheRepositoryProvider
              .overrideWithValue(_RecordingLocalStorageCacheRepository()),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);

      await repository.deleteResource(
        sourceId: source.id,
        resourcePath: '/movies/strm/quark/请求救援',
      );

      expect(quarkClient.listParentFids, ['folder-root']);
      expect(quarkClient.deletedFids, ['quark-dir-series']);
    });
  });
}

class _RecordingWebDavNasClient extends WebDavNasClient {
  _RecordingWebDavNasClient({
    required this.resolvedTargetUrl,
  }) : super(MockClient((request) async => http.Response('', 200)));

  final String resolvedTargetUrl;
  final List<String> deletedResourcePaths = <String>[];

  @override
  Future<String> resolveStrmTargetUrl({
    required MediaSourceConfig source,
    required String resourcePath,
    String sectionId = '',
  }) async {
    return resolvedTargetUrl;
  }

  @override
  Future<void> deleteResource(
    MediaSourceConfig source, {
    required String resourcePath,
    String sectionId = '',
  }) async {
    deletedResourcePaths.add(resourcePath);
  }
}

class _RecordingQuarkSaveClient extends QuarkSaveClient {
  _RecordingQuarkSaveClient({
    required this.directories,
  }) : super(MockClient((request) async => http.Response('', 200)));

  final List<QuarkDirectoryEntry> directories;
  final List<String> listParentFids = <String>[];
  final List<String> deletedFids = <String>[];

  @override
  Future<List<QuarkDirectoryEntry>> listDirectories({
    required String cookie,
    String parentFid = '0',
  }) async {
    listParentFids.add(parentFid);
    return directories;
  }

  @override
  Future<QuarkDeleteResult> deleteEntries({
    required String cookie,
    required List<String> fids,
  }) async {
    deletedFids.addAll(fids);
    return QuarkDeleteResult(
      taskId: 'delete-task',
      deletedCount: fids.length,
      finished: true,
    );
  }
}

class _FakeNasMediaIndexer extends NasMediaIndexer {
  _FakeNasMediaIndexer({
    this.scopeRecords = const [],
  }) : super(
          store: SembastNasMediaIndexStore(
            databaseOpener: () => databaseFactoryMemory.openDatabase(
              'media-repository-delete-sync-quark-test',
            ),
          ),
          webDavNasClient: WebDavNasClient(
              MockClient((request) async => http.Response('', 200))),
          wmdbMetadataClient: WmdbMetadataClient(
              MockClient((request) async => http.Response('', 200))),
          tmdbMetadataClient: TmdbMetadataClient(
              MockClient((request) async => http.Response('', 200))),
          imdbRatingClient: ImdbRatingClient(
              MockClient((request) async => http.Response('', 200))),
          readSettings: () => SeedData.defaultSettings,
          progressController: WebDavScrapeProgressController(),
        );

  final List<String> removedScopes = <String>[];
  final List<NasMediaIndexRecord> scopeRecords;

  @override
  Future<NasMediaIndexRecord?> loadRecord({
    required String sourceId,
    required String resourceId,
  }) async {
    return null;
  }

  @override
  Future<void> removeResourceScope({
    required String sourceId,
    required String resourcePath,
  }) async {
    removedScopes.add(resourcePath);
  }

  @override
  Future<List<NasMediaIndexRecord>> loadRecordsInScope({
    required String sourceId,
    required String resourcePath,
  }) async {
    return scopeRecords;
  }
}

class _RecordingLocalStorageCacheRepository
    extends LocalStorageCacheRepository {
  _RecordingLocalStorageCacheRepository();

  final List<_ClearedResourceRequest> clearedResources =
      <_ClearedResourceRequest>[];

  @override
  Future<void> clearDetailCacheForResource({
    required String sourceId,
    String resourceId = '',
    required String resourcePath,
    bool treatAsScope = false,
  }) async {
    clearedResources.add(
      _ClearedResourceRequest(
        sourceId: sourceId,
        resourceId: resourceId,
        resourcePath: resourcePath,
        treatAsScope: treatAsScope,
      ),
    );
  }
}

class _ClearedResourceRequest {
  const _ClearedResourceRequest({
    required this.sourceId,
    required this.resourceId,
    required this.resourcePath,
    required this.treatAsScope,
  });

  final String sourceId;
  final String resourceId;
  final String resourcePath;
  final bool treatAsScope;
}

NasMediaIndexRecord _scopeRecord({
  required String sourceId,
  required String resourceId,
  required String resourcePath,
  required String sectionId,
}) {
  return NasMediaIndexRecord(
    id: NasMediaIndexRecord.buildRecordId(
      sourceId: sourceId,
      resourceId: resourceId,
    ),
    sourceId: sourceId,
    sectionId: sectionId,
    sectionName: 'movies',
    resourceId: resourceId,
    resourcePath: resourcePath,
    fingerprint: 'fingerprint',
    fileSizeBytes: 0,
    modifiedAt: DateTime.utc(2026, 4, 7),
    indexedAt: DateTime.utc(2026, 4, 7),
    scrapedAt: DateTime.utc(2026, 4, 7),
    recognizedTitle: '请求救援',
    searchQuery: '请求救援',
    originalFileName: 'Send Help (2026).strm',
    parentTitle: '请求救援',
    recognizedYear: 2026,
    recognizedItemType: 'movie',
    preferSeries: false,
    sidecarStatus: NasMetadataFetchStatus.never,
    wmdbStatus: NasMetadataFetchStatus.never,
    tmdbStatus: NasMetadataFetchStatus.never,
    imdbStatus: NasMetadataFetchStatus.never,
    item: MediaItem(
      id: resourceId,
      title: '请求救援',
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '文件',
      genres: const [],
      sectionId: sectionId,
      sectionName: 'movies',
      sourceId: sourceId,
      sourceName: '家庭 NAS',
      sourceKind: MediaSourceKind.nas,
      streamUrl: resourceId,
      actualAddress: resourcePath,
      addedAt: DateTime.utc(2026, 4, 7),
    ),
  );
}
