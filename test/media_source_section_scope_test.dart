import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

void main() {
  group('AppMediaRepository section scope', () {
    test('only exposes selected collections for home editor and library',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: [
                const MediaSourceConfig(
                  id: 'emby-main',
                  name: '客厅 Emby',
                  kind: MediaSourceKind.emby,
                  endpoint: 'https://emby.example.com',
                  enabled: true,
                  username: 'alice',
                  accessToken: 'token',
                  userId: 'user-1',
                  featuredSectionIds: ['emby-movies'],
                ),
                const MediaSourceConfig(
                  id: 'nas-main',
                  name: '家庭 NAS',
                  kind: MediaSourceKind.nas,
                  endpoint: 'https://nas.example.com/dav/',
                  enabled: true,
                  libraryPath: 'https://nas.example.com/dav/Media/',
                  featuredSectionIds: [
                    'https://nas.example.com/dav/Media/Anime/'
                  ],
                ),
              ],
              searchProviders: const [],
              homeModules: const [],
            ),
          ),
          embyApiClientProvider.overrideWithValue(
            _FakeEmbyApiClient(
              collections: const [
                MediaCollection(
                  id: 'emby-movies',
                  title: '电影',
                  sourceId: 'emby-main',
                  sourceName: '客厅 Emby',
                  sourceKind: MediaSourceKind.emby,
                  subtitle: 'Movies',
                ),
                MediaCollection(
                  id: 'emby-tv',
                  title: '剧集',
                  sourceId: 'emby-main',
                  sourceName: '客厅 Emby',
                  sourceKind: MediaSourceKind.emby,
                  subtitle: 'Series',
                ),
              ],
              itemsBySection: {
                'emby-movies': [_item('emby-1', 'Interstellar', 'emby-movies')],
                'emby-tv': [_item('emby-2', 'Dark', 'emby-tv')],
              },
            ),
          ),
          webDavNasClientProvider.overrideWithValue(
            _FakeWebDavNasClient(
              collections: const [
                MediaCollection(
                  id: 'https://nas.example.com/dav/Media/Anime/',
                  title: 'Anime',
                  sourceId: 'nas-main',
                  sourceName: '家庭 NAS',
                  sourceKind: MediaSourceKind.nas,
                  subtitle: 'WebDAV 目录',
                ),
                MediaCollection(
                  id: 'https://nas.example.com/dav/Media/Docs/',
                  title: 'Docs',
                  sourceId: 'nas-main',
                  sourceName: '家庭 NAS',
                  sourceKind: MediaSourceKind.nas,
                  subtitle: 'WebDAV 目录',
                ),
              ],
              itemsBySection: {
                'https://nas.example.com/dav/Media/Anime/': [
                  _item(
                    'nas-1',
                    'One Piece',
                    'https://nas.example.com/dav/Media/Anime/',
                    sourceId: 'nas-main',
                    sourceName: '家庭 NAS',
                    sourceKind: MediaSourceKind.nas,
                  ),
                ],
                'https://nas.example.com/dav/Media/Docs/': [
                  _item(
                    'nas-2',
                    'Planet Earth',
                    'https://nas.example.com/dav/Media/Docs/',
                    sourceId: 'nas-main',
                    sourceName: '家庭 NAS',
                    sourceKind: MediaSourceKind.nas,
                  ),
                ],
              },
            ),
          ),
          nasMediaIndexStoreProvider.overrideWithValue(
            SembastNasMediaIndexStore(
              databaseOpener: () => databaseFactoryMemory.openDatabase(
                'media-source-section-scope-test-1',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      final collections = await repository.fetchCollections();
      final items = await repository.fetchLibrary();

      expect(
        collections.map((item) => item.id),
        orderedEquals([
          'emby-movies',
          'https://nas.example.com/dav/Media/Anime/',
        ]),
      );
      expect(
        items.map((item) => item.title),
        containsAll(<String>['Interstellar', 'One Piece']),
      );
      expect(
        items.map((item) => item.title),
        isNot(containsAll(<String>['Dark', 'Planet Earth'])),
      );
    });

    test(
        'does not fall back to all sections when saved scope no longer resolves',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              mediaSources: const [
                MediaSourceConfig(
                  id: 'nas-main',
                  name: '家庭 NAS',
                  kind: MediaSourceKind.nas,
                  endpoint: 'https://nas.example.com/dav/',
                  enabled: true,
                  libraryPath: 'https://nas.example.com/dav/Media/',
                  featuredSectionIds: [
                    'https://nas.example.com/dav/Media/Missing/'
                  ],
                ),
              ],
              searchProviders: const [],
              homeModules: const [],
            ),
          ),
          webDavNasClientProvider.overrideWithValue(
            _FakeWebDavNasClient(
              collections: const [
                MediaCollection(
                  id: 'https://nas.example.com/dav/Media/Anime/',
                  title: 'Anime',
                  sourceId: 'nas-main',
                  sourceName: '家庭 NAS',
                  sourceKind: MediaSourceKind.nas,
                  subtitle: 'WebDAV 目录',
                ),
              ],
              itemsBySection: {
                'https://nas.example.com/dav/Media/Anime/': [
                  _item(
                    'nas-1',
                    'One Piece',
                    'https://nas.example.com/dav/Media/Anime/',
                    sourceId: 'nas-main',
                    sourceName: '家庭 NAS',
                    sourceKind: MediaSourceKind.nas,
                  ),
                ],
              },
            ),
          ),
          nasMediaIndexStoreProvider.overrideWithValue(
            SembastNasMediaIndexStore(
              databaseOpener: () => databaseFactoryMemory.openDatabase(
                'media-source-section-scope-test-2',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(mediaRepositoryProvider);
      expect(await repository.fetchCollections(kind: MediaSourceKind.nas),
          isEmpty);
      expect(await repository.fetchLibrary(kind: MediaSourceKind.nas), isEmpty);
    });
  });
}

MediaItem _item(
  String id,
  String title,
  String sectionId, {
  String sourceId = 'emby-main',
  String sourceName = '客厅 Emby',
  MediaSourceKind sourceKind = MediaSourceKind.emby,
}) {
  return MediaItem(
    id: id,
    title: title,
    overview: '',
    posterUrl: '',
    year: 0,
    durationLabel: '',
    genres: const [],
    sectionId: sectionId,
    sectionName: sectionId,
    sourceId: sourceId,
    sourceName: sourceName,
    sourceKind: sourceKind,
    streamUrl: 'https://stream.example.com/$id',
    addedAt: DateTime.utc(2026, 4, 4),
  );
}

class _FakeEmbyApiClient extends EmbyApiClient {
  _FakeEmbyApiClient({
    required this.collections,
    required this.itemsBySection,
  }) : super(MockClient((request) async => http.Response('', 200)));

  final List<MediaCollection> collections;
  final Map<String, List<MediaItem>> itemsBySection;

  @override
  Future<List<MediaCollection>> fetchCollections(
      MediaSourceConfig source) async {
    return collections;
  }

  @override
  Future<List<MediaItem>> fetchLibrary(
    MediaSourceConfig source, {
    int limit = 200,
    String? sectionId,
    String sectionName = '',
  }) async {
    if (sectionId?.trim().isNotEmpty == true) {
      return itemsBySection[sectionId] ?? const [];
    }
    return itemsBySection.values.expand((items) => items).toList();
  }
}

class _FakeWebDavNasClient extends WebDavNasClient {
  _FakeWebDavNasClient({
    required this.collections,
    required this.itemsBySection,
  }) : super(MockClient((request) async => http.Response('', 200)));

  final List<MediaCollection> collections;
  final Map<String, List<MediaItem>> itemsBySection;

  @override
  Future<List<MediaCollection>> fetchCollections(
    MediaSourceConfig source, {
    String? directoryId,
  }) async {
    return collections;
  }

  @override
  Future<List<MediaItem>> fetchLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
  }) async {
    if (sectionId?.trim().isNotEmpty == true) {
      return itemsBySection[sectionId] ?? const [];
    }
    return itemsBySection.values.expand((items) => items).toList();
  }

  @override
  Future<List<WebDavScannedItem>> scanLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    String sectionName = '',
    int limit = 200,
    bool? loadSidecarMetadata,
    bool resetCaches = true,
    bool Function()? shouldCancel,
  }) async {
    final items = sectionId?.trim().isNotEmpty == true
        ? (itemsBySection[sectionId] ?? const <MediaItem>[])
        : itemsBySection.values.expand((entries) => entries).toList();
    return items
        .take(limit)
        .map(
          (item) => WebDavScannedItem(
            resourceId: item.id,
            fileName: item.actualAddress.trim().isNotEmpty
                ? item.actualAddress.split('/').last
                : '${item.title}.strm',
            actualAddress: item.actualAddress.trim().isNotEmpty
                ? item.actualAddress
                : '${item.sectionName}/${item.title}.strm',
            sectionId: item.sectionId,
            sectionName: item.sectionName,
            streamUrl: item.streamUrl,
            streamHeaders: item.streamHeaders,
            addedAt: item.addedAt,
            modifiedAt: item.addedAt,
            fileSizeBytes: 0,
            metadataSeed: WebDavMetadataSeed(
              title: item.title,
              overview: item.overview,
              posterUrl: item.posterUrl,
              posterHeaders: item.posterHeaders,
              backdropUrl: item.backdropUrl,
              backdropHeaders: item.backdropHeaders,
              logoUrl: item.logoUrl,
              logoHeaders: item.logoHeaders,
              bannerUrl: item.bannerUrl,
              bannerHeaders: item.bannerHeaders,
              extraBackdropUrls: item.extraBackdropUrls,
              extraBackdropHeaders: item.extraBackdropHeaders,
              year: item.year,
              durationLabel:
                  item.durationLabel.trim().isEmpty ? '文件' : item.durationLabel,
              genres: item.genres,
              directors: item.directors,
              actors: item.actors,
              itemType: item.itemType,
              seasonNumber: item.seasonNumber,
              episodeNumber: item.episodeNumber,
              imdbId: item.imdbId,
              container: item.container,
              videoCodec: item.videoCodec,
              audioCodec: item.audioCodec,
              width: item.width,
              height: item.height,
              bitrate: item.bitrate,
              hasSidecarMatch: item.title.trim().isNotEmpty,
            ),
          ),
        )
        .toList(growable: false);
  }
}
