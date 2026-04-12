import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppMediaRepository synced Quark delete', () {
    test(
        'deletes the matched Quark directory after deleting a file inside the selected WebDAV scope',
        () async {
      const source = MediaSourceConfig(
        id: 'nas-main',
        name: '家庭 NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/',
        enabled: true,
      );
      final webDavClient = _RecordingWebDavNasClient();
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
      final playbackRepository = _RecordingPlaybackMemoryRepository();
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
                syncDeleteQuarkWebDavDirectories: [
                  NetworkStorageWebDavDirectory(
                    sourceId: 'nas-main',
                    sourceName: '家庭 NAS',
                    directoryId: 'https://nas.example.com/dav/Shows/',
                    directoryLabel: 'nas.example.com/dav/Shows/',
                  ),
                ],
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider.overrideWithValue(webDavClient),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
          nasMediaIndexerProvider.overrideWithValue(indexer),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
          playbackMemoryRepositoryProvider
              .overrideWithValue(playbackRepository),
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
        cacheRepository.clearedResources.single.resourcePath,
        resourcePath,
      );
      expect(cacheRepository.clearedResources.single.treatAsScope, isFalse);
      expect(playbackRepository.clearedResources, hasLength(1));
      expect(
          playbackRepository.clearedResources.single.resourceId, resourcePath);
      expect(
        playbackRepository.clearedResources.single.resourcePath,
        resourcePath,
      );
      expect(playbackRepository.clearedResources.single.treatAsScope, isFalse);
    });

    test(
        'skips Quark deletion when the deleted path is outside the selected WebDAV scope',
        () async {
      const source = MediaSourceConfig(
        id: 'nas-main',
        name: '家庭 NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/',
        enabled: true,
      );
      final webDavClient = _RecordingWebDavNasClient();
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
                syncDeleteQuarkWebDavDirectories: [
                  NetworkStorageWebDavDirectory(
                    sourceId: 'nas-main',
                    sourceName: '家庭 NAS',
                    directoryId: 'https://nas.example.com/dav/Movies/',
                    directoryLabel: 'nas.example.com/dav/Movies/',
                  ),
                ],
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
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
      final webDavClient = _RecordingWebDavNasClient();
      final quarkClient = _RecordingQuarkSaveClient(
        directories: const [
          QuarkDirectoryEntry(
            fid: 'quark-dir-series',
            name: '请求救援',
            path: '/保存目录/请求救援',
          ),
        ],
      );
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
                syncDeleteQuarkWebDavDirectories: [
                  NetworkStorageWebDavDirectory(
                    sourceId: 'nas-main',
                    sourceName: '家庭 NAS',
                    directoryId:
                        'https://nas.example.com/dav/movies/strm/quark/',
                    directoryLabel: 'nas.example.com/dav/movies/strm/quark/',
                  ),
                ],
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
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

    test(
        'can still match selected WebDAV scope by source name when source id changed',
        () async {
      const source = MediaSourceConfig(
        id: 'media-source-1775415208787',
        name: 'nas',
        kind: MediaSourceKind.nas,
        endpoint: 'https://webdav.nux.ink/',
        enabled: true,
      );
      final webDavClient = _RecordingWebDavNasClient();
      final quarkClient = _RecordingQuarkSaveClient(
        directories: const [
          QuarkDirectoryEntry(
            fid: 'quark-dir-mitang',
            name: '密探',
            path: '/来自：分享/密探',
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
                quarkSaveFolderPath: '/来自：分享',
                syncDeleteQuarkEnabled: true,
                syncDeleteQuarkWebDavDirectories: [
                  NetworkStorageWebDavDirectory(
                    sourceId: 'media-source-old',
                    sourceName: 'nas',
                    directoryId:
                        'https://webdav.nux.ink/home/AL123456/movies/strm/quark/',
                    directoryLabel:
                        'webdav.nux.ink/home/AL123456/movies/strm/quark/',
                  ),
                ],
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider.overrideWithValue(webDavClient),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
          nasMediaIndexerProvider.overrideWithValue(_FakeNasMediaIndexer()),
          localStorageCacheRepositoryProvider
              .overrideWithValue(_RecordingLocalStorageCacheRepository()),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);

      await repository.deleteResource(
        sourceId: source.id,
        resourcePath: '/movies/strm/quark/密探',
      );

      expect(quarkClient.listParentFids, ['folder-root']);
      expect(quarkClient.deletedFids, ['quark-dir-mitang']);
    });

    test(
        'deletes indexed Quark scope paths from browse pages and clears local index',
        () async {
      const source = MediaSourceConfig(
        id: 'quark-main',
        name: 'Quark Drive',
        kind: MediaSourceKind.quark,
        endpoint: 'root-folder',
        libraryPath: '/影视',
        enabled: true,
      );
      final quarkClient = _RecordingQuarkSaveClient(
        directories: const [],
        resolvedDirectoriesByPath: const {
          '/影视/圆桌派': QuarkDirectoryEntry(
            fid: 'series-dir',
            name: '圆桌派',
            path: '/影视/圆桌派',
          ),
        },
      );
      final cacheRepository = _RecordingLocalStorageCacheRepository();
      final playbackRepository = _RecordingPlaybackMemoryRepository();
      final indexer = _FakeNasMediaIndexer(
        scopeRecordsByPath: {
          '/影视/圆桌派': [
            _quarkIndexRecord(
              source: source,
              fid: 'episode-1',
              path: '/影视/圆桌派/Season 1/S01E01.mp4',
            ),
            _quarkIndexRecord(
              source: source,
              fid: 'episode-2',
              path: '/影视/圆桌派/Season 1/S01E02.mp4',
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
                quarkCookie: 'foo=bar',
              ),
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider
              .overrideWithValue(_RecordingWebDavNasClient()),
          quarkSaveClientProvider.overrideWithValue(quarkClient),
          nasMediaIndexerProvider.overrideWithValue(indexer),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
          playbackMemoryRepositoryProvider
              .overrideWithValue(playbackRepository),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);

      await repository.deleteResource(
        sourceId: source.id,
        resourcePath: '/影视/圆桌派',
      );

      expect(quarkClient.deletedFids, ['series-dir']);
      expect(indexer.removedScopes, ['/影视/圆桌派']);
      expect(cacheRepository.clearedResources, hasLength(1));
      expect(cacheRepository.clearedResources.single.resourceId, isEmpty);
      expect(
        cacheRepository.clearedResources.single.resourcePath,
        '/影视/圆桌派',
      );
      expect(cacheRepository.clearedResources.single.treatAsScope, isTrue);
      expect(playbackRepository.clearedResources, hasLength(1));
      expect(playbackRepository.clearedResources.single.resourceId, isEmpty);
      expect(
        playbackRepository.clearedResources.single.resourcePath,
        '/影视/圆桌派',
      );
      expect(playbackRepository.clearedResources.single.treatAsScope, isTrue);
    });

    test(
        'incremental refresh clears removed indexed resources from cache and playback memory',
        () async {
      const source = MediaSourceConfig(
        id: 'nas-refresh-remove',
        name: '家庭 NAS',
        kind: MediaSourceKind.nas,
        endpoint: 'https://nas.example.com/dav/',
        enabled: true,
      );
      final keepRecord = _nasIndexRecord(
        source: source,
        resourceId: 'keep-1',
        path: '/movies/Keep.mkv',
      );
      final removedRecord = _nasIndexRecord(
        source: source,
        resourceId: 'removed-1',
        path: '/movies/Removed.mkv',
      );
      final cacheRepository = _RecordingLocalStorageCacheRepository();
      final playbackRepository = _RecordingPlaybackMemoryRepository();
      final indexer = _FakeNasMediaIndexer(
        sourceRecordsBySource: {
          source.id: [keepRecord, removedRecord],
        },
        sourceRecordsAfterRefreshBySource: {
          source.id: [keepRecord],
        },
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [source],
              searchProviders: const [],
              homeModules: const [],
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async => http.Response('', 200)),
            ),
          ),
          webDavNasClientProvider
              .overrideWithValue(_RecordingWebDavNasClient()),
          quarkSaveClientProvider.overrideWithValue(
            _RecordingQuarkSaveClient(directories: const []),
          ),
          nasMediaIndexerProvider.overrideWithValue(indexer),
          localStorageCacheRepositoryProvider
              .overrideWithValue(cacheRepository),
          playbackMemoryRepositoryProvider
              .overrideWithValue(playbackRepository),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      await repository.refreshSource(sourceId: source.id);

      expect(indexer.refreshedSources, [source.id]);
      expect(cacheRepository.clearedResources, hasLength(1));
      expect(cacheRepository.clearedResources.single.resourceId, 'removed-1');
      expect(
        cacheRepository.clearedResources.single.resourcePath,
        '/movies/Removed.mkv',
      );
      expect(playbackRepository.clearedResources, hasLength(1));
      expect(
          playbackRepository.clearedResources.single.resourceId, 'removed-1');
      expect(
        playbackRepository.clearedResources.single.resourcePath,
        '/movies/Removed.mkv',
      );
    });
  });
}

NasMediaIndexRecord _nasIndexRecord({
  required MediaSourceConfig source,
  required String resourceId,
  required String path,
}) {
  final fileName = path.split('/').last;
  final item = MediaItem(
    id: resourceId,
    title: fileName,
    overview: '',
    posterUrl: '',
    year: 0,
    durationLabel: '文件',
    genres: const [],
    itemType: 'movie',
    sourceId: source.id,
    sourceName: source.name,
    sourceKind: source.kind,
    streamUrl: '',
    actualAddress: path,
    playbackItemId: resourceId,
    addedAt: DateTime(2026, 4, 12),
  );
  return NasMediaIndexRecord(
    id: NasMediaIndexRecord.buildRecordId(
      sourceId: source.id,
      resourceId: resourceId,
    ),
    sourceId: source.id,
    sectionId: '',
    sectionName: '',
    resourceId: resourceId,
    resourcePath: path,
    fingerprint: 'fp-$resourceId',
    fileSizeBytes: 0,
    modifiedAt: DateTime(2026, 4, 12),
    indexedAt: DateTime(2026, 4, 12),
    scrapedAt: DateTime(2026, 4, 12),
    recognizedTitle: fileName,
    searchQuery: fileName,
    originalFileName: fileName,
    parentTitle: 'movies',
    recognizedYear: 0,
    recognizedItemType: item.itemType,
    preferSeries: false,
    sidecarStatus: NasMetadataFetchStatus.never,
    wmdbStatus: NasMetadataFetchStatus.never,
    tmdbStatus: NasMetadataFetchStatus.never,
    imdbStatus: NasMetadataFetchStatus.never,
    item: item,
  );
}

NasMediaIndexRecord _quarkIndexRecord({
  required MediaSourceConfig source,
  required String fid,
  required String path,
}) {
  final resourceId = Uri(
    scheme: 'quark',
    host: 'entry',
    path: '/$fid',
    queryParameters: {
      'path': path,
      'parentFid': 'parent-$fid',
    },
  ).toString();
  final item = MediaItem(
    id: resourceId,
    title: path.split('/').last,
    overview: '',
    posterUrl: '',
    year: 0,
    durationLabel: '文件',
    genres: const [],
    itemType: 'episode',
    sourceId: source.id,
    sourceName: source.name,
    sourceKind: source.kind,
    streamUrl: '',
    actualAddress: path,
    playbackItemId: fid,
    addedAt: DateTime(2026, 4, 11),
  );
  return NasMediaIndexRecord(
    id: NasMediaIndexRecord.buildRecordId(
      sourceId: source.id,
      resourceId: resourceId,
    ),
    sourceId: source.id,
    sectionId: '',
    sectionName: '',
    resourceId: resourceId,
    resourcePath: path,
    fingerprint: 'fp-$fid',
    fileSizeBytes: 0,
    modifiedAt: DateTime(2026, 4, 11),
    indexedAt: DateTime(2026, 4, 11),
    scrapedAt: DateTime(2026, 4, 11),
    recognizedTitle: item.title,
    searchQuery: item.title,
    originalFileName: item.title,
    parentTitle: '圆桌派',
    recognizedYear: 0,
    recognizedItemType: item.itemType,
    preferSeries: true,
    sidecarStatus: NasMetadataFetchStatus.never,
    wmdbStatus: NasMetadataFetchStatus.never,
    tmdbStatus: NasMetadataFetchStatus.never,
    imdbStatus: NasMetadataFetchStatus.never,
    item: item,
  );
}

class _RecordingWebDavNasClient extends WebDavNasClient {
  _RecordingWebDavNasClient()
      : super(MockClient((request) async => http.Response('', 200)));

  final List<String> deletedResourcePaths = <String>[];

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
    this.resolvedDirectoriesByPath = const {},
  }) : super(MockClient((request) async => http.Response('', 200)));

  final List<QuarkDirectoryEntry> directories;
  final Map<String, QuarkDirectoryEntry> resolvedDirectoriesByPath;
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

  @override
  Future<QuarkDirectoryEntry?> resolveDirectoryByPath({
    required String cookie,
    required String path,
  }) async {
    return resolvedDirectoriesByPath[normalizeQuarkDirectoryPath(path)];
  }
}

class _FakeNasMediaIndexer extends NasMediaIndexer {
  _FakeNasMediaIndexer({
    Map<String, NasMediaIndexRecord> recordsByResourceId = const {},
    Map<String, List<NasMediaIndexRecord>> scopeRecordsByPath = const {},
    Map<String, List<NasMediaIndexRecord>> sourceRecordsBySource = const {},
    Map<String, List<NasMediaIndexRecord>> sourceRecordsAfterRefreshBySource =
        const {},
  })  : _recordsByResourceId = recordsByResourceId,
        _scopeRecordsByPath = scopeRecordsByPath,
        _sourceRecordsBySource = {
          for (final entry in sourceRecordsBySource.entries)
            entry.key: List<NasMediaIndexRecord>.from(entry.value),
        },
        _sourceRecordsAfterRefreshBySource = sourceRecordsAfterRefreshBySource,
        super(
          store: SembastNasMediaIndexStore(
            databaseOpener: () => databaseFactoryMemory.openDatabase(
              'media-repository-delete-sync-quark-test',
            ),
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

  final Map<String, NasMediaIndexRecord> _recordsByResourceId;
  final Map<String, List<NasMediaIndexRecord>> _scopeRecordsByPath;
  final Map<String, List<NasMediaIndexRecord>> _sourceRecordsBySource;
  final Map<String, List<NasMediaIndexRecord>>
      _sourceRecordsAfterRefreshBySource;
  final List<String> removedScopes = <String>[];
  final List<String> refreshedSources = <String>[];

  @override
  Future<NasMediaIndexRecord?> loadRecord({
    required String sourceId,
    required String resourceId,
  }) async {
    return _recordsByResourceId[resourceId];
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
    return _scopeRecordsByPath[resourcePath] ?? const <NasMediaIndexRecord>[];
  }

  @override
  Future<List<NasMediaIndexRecord>> loadSourceRecords(String sourceId) async {
    return _sourceRecordsBySource[sourceId] ?? const <NasMediaIndexRecord>[];
  }

  @override
  Future<void> clearSource(String sourceId) async {
    _sourceRecordsBySource[sourceId] = const <NasMediaIndexRecord>[];
  }

  @override
  Future<void> refreshSource(
    MediaSourceConfig source, {
    List<MediaCollection>? scopedCollections,
    int limitPerCollection = 200,
    bool forceFullRescan = false,
  }) async {
    refreshedSources.add(source.id);
    final nextRecords = _sourceRecordsAfterRefreshBySource[source.id];
    if (nextRecords != null) {
      _sourceRecordsBySource[source.id] =
          List<NasMediaIndexRecord>.from(nextRecords);
    }
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

class _RecordingPlaybackMemoryRepository extends PlaybackMemoryRepository {
  _RecordingPlaybackMemoryRepository();

  final List<_ClearedResourceRequest> clearedResources =
      <_ClearedResourceRequest>[];

  @override
  Future<void> clearEntriesForResource({
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
