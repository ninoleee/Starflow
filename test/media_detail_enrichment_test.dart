import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('enrichedDetailTargetProvider', () {
    test('keeps detail target unchanged when auto enrichment is disabled',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': false,
              'tmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
            }),
          ),
          mediaRepositoryProvider.overrideWithValue(
            _FakeMediaRepository(
              library: [
                MediaItem(
                  id: 'emby-1',
                  title: '美丽人生',
                  overview: '来自 Emby 的条目',
                  posterUrl: 'https://emby.example.com/poster.jpg',
                  year: 1997,
                  durationLabel: '116分钟',
                  genres: const ['剧情'],
                  sourceId: 'emby-main',
                  sourceName: 'Home Emby',
                  sourceKind: MediaSourceKind.emby,
                  streamUrl: '',
                  playbackItemId: 'emby-1',
                  addedAt: DateTime(2026, 4, 4),
                ),
              ],
            ),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async {
                throw TestFailure('关闭自动补全时不应请求元数据：${request.url}');
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      const target = MediaDetailTarget(
        title: '美丽人生',
        posterUrl: '',
        overview: '',
        year: 1997,
        ratingLabels: ['豆瓣 9.6'],
        availabilityLabel: '无',
        searchQuery: '美丽人生',
        sourceName: '豆瓣',
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      expect(resolved.sourceId, isEmpty);
      expect(resolved.itemId, isEmpty);
      expect(resolved.playbackTarget, isNull);
      expect(resolved.posterUrl, isEmpty);
      expect(resolved.ratingLabels, ['豆瓣 9.6']);
    });

    test('normalizes duplicate rating labels already present on detail target',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': false,
              'tmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      const target = MediaDetailTarget(
        title: '美丽人生',
        posterUrl: '',
        overview: '',
        year: 1997,
        ratingLabels: ['豆瓣 9.6', '豆瓣9.6', 'IMDb 8.6'],
        availabilityLabel: '无',
        searchQuery: '美丽人生',
        sourceName: '豆瓣',
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      expect(resolved.ratingLabels, ['豆瓣 9.6', 'IMDb 8.6']);
    });

    test('dedupes provider ratings when current target merges with cache',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': false,
              'tmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      const seedTarget = MediaDetailTarget(
        title: '美丽人生',
        posterUrl: '',
        overview: '',
        year: 1997,
        ratingLabels: ['豆瓣 9.6'],
        availabilityLabel: '无',
        searchQuery: '美丽人生',
        sourceName: '豆瓣',
      );
      final cachedTarget = seedTarget.copyWith(
        ratingLabels: const ['豆瓣9.6', 'TMDB 8.3'],
      );

      await container
          .read(localStorageCacheRepositoryProvider)
          .saveDetailTarget(
            seedTarget: seedTarget,
            resolvedTarget: cachedTarget,
          );

      final resolved = await container.read(
        enrichedDetailTargetProvider(seedTarget).future,
      );

      expect(resolved.ratingLabels, ['豆瓣 9.6', 'TMDB 8.3']);
    });

    test('resolves Emby playback details for existing matched target',
        () async {
      final container = ProviderContainer(
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
            }),
          ),
          embyApiClientProvider.overrideWithValue(
            EmbyApiClient(
              MockClient((request) async {
                if (request.url.path == '/Items/emby-1/PlaybackInfo') {
                  return http.Response(
                    jsonEncode({
                      'PlaySessionId': 'play-session-1',
                      'MediaSources': [
                        {
                          'Id': 'media-source-2',
                          'Container': 'mkv',
                          'Size': 25769803776,
                          'Bitrate': 28400000,
                          'Width': 3840,
                          'Height': 2160,
                          'DirectStreamUrl':
                              '/Videos/emby-1/stream.mp4?static=true&MediaSourceId=media-source-2',
                          'AddApiKeyToDirectStreamUrl': true,
                          'MediaStreams': [
                            {
                              'Type': 'Video',
                              'Codec': 'hevc',
                              'Width': 3840,
                              'Height': 2160,
                              'BitRate': 25200000,
                            },
                            {
                              'Type': 'Audio',
                              'Codec': 'truehd',
                              'BitRate': 3200000,
                            },
                          ],
                        },
                      ],
                    }),
                    200,
                  );
                }
                return http.Response('Not found', 404);
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final target = MediaDetailTarget.fromMediaItem(
        MediaItem(
          id: 'emby-1',
          title: '美丽人生',
          overview: '来自 Emby 的条目',
          posterUrl: 'https://emby.example.com/poster.jpg',
          year: 1997,
          durationLabel: '116分钟',
          genres: const ['剧情'],
          sourceId: 'emby-main',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
          streamUrl: '',
          playbackItemId: 'emby-1',
          preferredMediaSourceId: 'media-source-2',
          addedAt: DateTime(2026, 4, 4),
        ),
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      final playback = resolved.playbackTarget;
      expect(playback, isNotNull);
      expect(playback!.streamUrl, contains('/Videos/emby-1/stream.mp4'));
      expect(playback.formatLabel, 'MKV · HEVC · TrueHD');
      expect(playback.fileSizeLabel, '24.0 GB');
      expect(playback.resolutionLabel, '3840x2160');
    });

    test('resolves Quark playback url for existing matched target', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': [
                {
                  'id': 'quark-main',
                  'name': 'Quark Drive',
                  'kind': 'quark',
                  'endpoint': '0',
                  'libraryPath': '/',
                  'enabled': true,
                },
              ],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'networkStorage': const {
                'quarkCookie': 'kps=test; sign=test;',
              },
            }),
          ),
          quarkSaveClientProvider.overrideWithValue(
            QuarkSaveClient(
              MockClient((request) async {
                expect(request.url.path, '/1/clouddrive/file/download');
                return http.Response(
                  jsonEncode({
                    'code': 0,
                    'data': {
                      'download_list': [
                        {
                          'fid': 'quark-file-1',
                          'download_url':
                              'https://download.example.com/quark-file-1.mkv',
                          'size': 3221225472,
                        },
                      ],
                    },
                  }),
                  200,
                  headers: const {
                    'set-cookie': '__puus=abc; Path=/',
                  },
                );
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final target = MediaDetailTarget.fromMediaItem(
        MediaItem(
          id: 'quark://entry/quark-file-1',
          title: '请求救援 S01E01',
          overview: '来自夸克的条目',
          posterUrl: '',
          year: 2025,
          durationLabel: '剧集',
          genres: const ['剧情'],
          sourceId: 'quark-main',
          sourceName: 'Quark Drive',
          sourceKind: MediaSourceKind.quark,
          streamUrl: '',
          playbackItemId: 'quark-file-1',
          container: 'mkv',
          fileSizeBytes: 3221225472,
          addedAt: DateTime(2026, 4, 4),
        ),
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      final playback = resolved.playbackTarget;
      expect(playback, isNotNull);
      expect(
        playback!.streamUrl,
        'https://download.example.com/quark-file-1.mkv',
      );
      expect(playback.formatLabel, 'MKV');
      expect(playback.fileSizeLabel, '3.00 GB');
      expect(playback.headers['Cookie'], contains('kps=test'));
      expect(playback.headers['Cookie'], contains('__puus=abc'));
    });

    test('prefers cached local resource state for douban detail target',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': false,
              'tmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      const seedTarget = MediaDetailTarget(
        title: '天书奇谭',
        posterUrl: '',
        overview: '',
        year: 1983,
        availabilityLabel: '无',
        searchQuery: '天书奇谭',
        doubanId: '1428581',
        sourceName: '豆瓣',
      );
      final cachedTarget = seedTarget.copyWith(
        availabilityLabel: '资源已就绪：WebDAV · nas',
        sourceKind: MediaSourceKind.nas,
        sourceName: 'nas',
        sourceId: 'media-source-1775415208787',
        itemId: 'nas-item-1',
        resourcePath: '/movies/天书奇谭 (1983).strm',
        playbackTarget: const PlaybackTarget(
          title: '天书奇谭',
          sourceId: 'media-source-1775415208787',
          streamUrl: 'https://webdav.example.com/movies/天书奇谭.mkv',
          sourceName: 'nas',
          sourceKind: MediaSourceKind.nas,
          actualAddress: '/movies/天书奇谭 (1983).strm',
          itemId: 'nas-item-1',
          itemType: 'movie',
        ),
      );

      await container
          .read(localStorageCacheRepositoryProvider)
          .saveDetailTarget(
            seedTarget: seedTarget,
            resolvedTarget: cachedTarget,
          );

      final resolved = await container.read(
        enrichedDetailTargetProvider(seedTarget).future,
      );

      expect(resolved.availabilityLabel, '资源已就绪：WebDAV · nas');
      expect(resolved.sourceKind, MediaSourceKind.nas);
      expect(resolved.sourceName, 'nas');
      expect(resolved.sourceId, 'media-source-1775415208787');
      expect(resolved.itemId, 'nas-item-1');
      expect(resolved.playbackTarget, isNotNull);
      expect(
        resolved.playbackTarget!.streamUrl,
        'https://webdav.example.com/movies/天书奇谭.mkv',
      );
    });

    test('prefers cached series context for matched douban detail target',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': false,
              'tmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      const seedTarget = MediaDetailTarget(
        title: '9号秘事',
        posterUrl: '',
        overview: '',
        year: 2014,
        availabilityLabel: '无',
        searchQuery: '9号秘事',
        itemType: 'movie',
        doubanId: '25897385',
        sourceName: '豆瓣',
      );
      final cachedTarget = seedTarget.copyWith(
        availabilityLabel: '已匹配：WebDAV · nas',
        sourceKind: MediaSourceKind.nas,
        sourceName: 'nas',
        sourceId: 'media-source-1775415208787',
        itemId: 'webdav-series|inside-no-9',
        itemType: 'series',
        sectionName: '剧集',
      );

      await container
          .read(localStorageCacheRepositoryProvider)
          .saveDetailTarget(
            seedTarget: seedTarget,
            resolvedTarget: cachedTarget,
          );

      final resolved = await container.read(
        enrichedDetailTargetProvider(seedTarget).future,
      );

      expect(resolved.itemType, 'series');
      expect(resolved.isSeries, isTrue);
      expect(resolved.sourceId, 'media-source-1775415208787');
      expect(resolved.itemId, 'webdav-series|inside-no-9');
      expect(resolved.sectionName, '剧集');
    });

    test('prefers cached availability when current target only has playback',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': false,
              'tmdbMetadataMatchEnabled': false,
              'imdbRatingMatchEnabled': false,
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      const seedTarget = MediaDetailTarget(
        title: '天书奇谭',
        posterUrl: '',
        overview: '',
        year: 1983,
        availabilityLabel: '无',
        searchQuery: '天书奇谭',
        doubanId: '1428581',
        sourceName: '豆瓣',
        playbackTarget: PlaybackTarget(
          title: '天书奇谭',
          sourceId: 'media-source-1775415208787',
          streamUrl: 'https://webdav.example.com/movies/天书奇谭.mkv',
          sourceName: 'nas',
          sourceKind: MediaSourceKind.nas,
          actualAddress: '/movies/天书奇谭 (1983).strm',
          itemId: 'nas-item-1',
          itemType: 'movie',
        ),
      );
      final cachedTarget = seedTarget.copyWith(
        availabilityLabel: '资源已就绪：WebDAV · nas',
        sourceKind: MediaSourceKind.nas,
        sourceName: 'nas',
        sourceId: 'media-source-1775415208787',
        itemId: 'nas-item-1',
        resourcePath: '/movies/天书奇谭 (1983).strm',
      );

      await container
          .read(localStorageCacheRepositoryProvider)
          .saveDetailTarget(
            seedTarget: seedTarget,
            resolvedTarget: cachedTarget,
          );

      final resolved = await container.read(
        enrichedDetailTargetProvider(seedTarget).future,
      );

      expect(resolved.availabilityLabel, '资源已就绪：WebDAV · nas');
      expect(resolved.sourceName, 'nas');
      expect(resolved.sourceKind, MediaSourceKind.nas);
    });

    test('auto enriches douban detail with imdb rating and ids', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': true,
              'tmdbMetadataMatchEnabled': true,
              'tmdbReadAccessToken': 'tmdb-token',
            }),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async {
                expect(request.url.path, '/movie/api');
                expect(request.url.queryParameters['id'], '1428581');
                return http.Response(
                  jsonEncode({
                    'data': [
                      {
                        'poster': 'https://img.wmdb.tv/poster.jpg',
                        'name': '天书奇谭',
                        'genre': '动画/奇幻',
                        'description': '袁公偷偷把天书带到人间。',
                        'lang': 'Cn',
                      },
                    ],
                    'originalName': '天书奇谭',
                    'imdbId': 'tt6035092',
                    'imdbRating': '7.4',
                    'doubanId': '1428581',
                    'year': '1983',
                  }),
                  200,
                  headers: const {'content-type': 'application/json'},
                );
              }),
            ),
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
              MockClient((request) async {
                if (request.url.path == '/3/search/multi') {
                  return http.Response(
                    jsonEncode({
                      'results': [
                        {
                          'id': 135130,
                          'media_type': 'movie',
                          'title': '天书奇谭',
                          'original_title': '天书奇谭',
                          'overview': '袁公偷偷把天书带到人间。',
                          'poster_path': '/poster.jpg',
                          'release_date': '1983-01-01',
                          'popularity': 8.0,
                        },
                      ],
                    }),
                    200,
                    headers: const {'content-type': 'application/json'},
                  );
                }
                if (request.url.path == '/3/movie/135130') {
                  return http.Response(
                    jsonEncode({
                      'id': 135130,
                      'title': '天书奇谭',
                      'original_title': '天书奇谭',
                      'overview': '袁公偷偷把天书带到人间。',
                      'poster_path': '/poster.jpg',
                      'release_date': '1983-01-01',
                      'runtime': 89,
                      'genres': [
                        {'name': 'Animation'},
                      ],
                      'credits': {
                        'cast': const [],
                        'crew': const [],
                      },
                      'external_ids': {
                        'imdb_id': 'tt6035092',
                      },
                    }),
                    200,
                    headers: const {'content-type': 'application/json'},
                  );
                }
                return http.Response('Not found', 404);
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      const target = MediaDetailTarget(
        title: '天书奇谭',
        posterUrl: '',
        overview: '',
        year: 1983,
        availabilityLabel: '无',
        searchQuery: '天书奇谭',
        doubanId: '1428581',
        sourceName: '豆瓣',
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      expect(resolved.imdbId, 'tt6035092');
      expect(resolved.ratingLabels, contains('IMDb 7.4'));
    });

    test('auto enriches non-douban detail with wmdb ratings and ids', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': true,
              'imdbRatingMatchEnabled': true,
            }),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async {
                expect(request.url.path, '/api/v1/movie/search');
                expect(request.url.queryParameters['q'], '美丽人生');
                expect(request.url.queryParameters['year'], '1997');
                return http.Response(
                  jsonEncode({
                    'data': [
                      {
                        'data': [
                          {
                            'poster':
                                'https://img.wmdb.tv/movie/poster/life.jpg',
                            'name': '美丽人生',
                            'genre': '剧情/喜剧',
                            'description': '圭多用幽默守护家人。',
                            'lang': 'Cn',
                          },
                        ],
                        'originalName': 'La vita e bella',
                        'imdbId': 'tt0118799',
                        'tmdbId': '637',
                        'doubanId': '1292063',
                        'doubanRating': '9.6',
                        'imdbRating': '8.6',
                        'year': '1997',
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
      );
      addTearDown(container.dispose);

      const target = MediaDetailTarget(
        title: '美丽人生',
        posterUrl: 'https://emby.example.com/poster.jpg',
        overview: '来自本地媒体库的简介',
        year: 1997,
        availabilityLabel: '无',
        searchQuery: '美丽人生',
        sourceId: 'emby-main',
        sourceName: 'Home Emby',
        sourceKind: MediaSourceKind.emby,
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      expect(resolved.doubanId, '1292063');
      expect(resolved.imdbId, 'tt0118799');
      expect(resolved.ratingLabels, contains('豆瓣 9.6'));
      expect(resolved.ratingLabels, contains('IMDb 8.6'));
      expect(resolved.posterUrl, 'https://emby.example.com/poster.jpg');
      expect(resolved.overview, '来自本地媒体库的简介');
    });

    test('auto enrich prioritizes tmdb imdb-id lookup before title search',
        () async {
      var wmdbRequests = 0;
      var tmdbFindRequests = 0;
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': true,
              'tmdbMetadataMatchEnabled': true,
              'tmdbReadAccessToken': 'tmdb-token',
              'imdbRatingMatchEnabled': false,
            }),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async {
                wmdbRequests += 1;
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
          ),
          tmdbMetadataClientProvider.overrideWithValue(
            TmdbMetadataClient(
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
          ),
        ],
      );
      addTearDown(container.dispose);

      const target = MediaDetailTarget(
        title: 'The Matrix',
        posterUrl: '',
        overview: '',
        year: 1999,
        availabilityLabel: '无',
        searchQuery: 'The Matrix',
        imdbId: 'tt0133093',
        sourceId: 'emby-main',
        sourceName: 'Home Emby',
        sourceKind: MediaSourceKind.emby,
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      expect(resolved.imdbId, 'tt0133093');
      expect(tmdbFindRequests, 1);
      expect(wmdbRequests, 1);
    });

    test('keeps existing douban label when wmdb also returns douban rating',
        () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson({
              'mediaSources': const [],
              'searchProviders': const [],
              'doubanAccount': const {'enabled': false},
              'homeModules': const [],
              'wmdbMetadataMatchEnabled': true,
              'imdbRatingMatchEnabled': true,
            }),
          ),
          wmdbMetadataClientProvider.overrideWithValue(
            WmdbMetadataClient(
              MockClient((request) async {
                return http.Response(
                  jsonEncode({
                    'data': [
                      {
                        'data': [
                          {
                            'poster':
                                'https://img.wmdb.tv/movie/poster/life.jpg',
                            'name': '美丽人生',
                            'genre': '剧情/喜剧',
                            'description': '圭多用幽默守护家人。',
                            'lang': 'Cn',
                          },
                        ],
                        'originalName': 'La vita e bella',
                        'imdbId': 'tt0118799',
                        'tmdbId': '637',
                        'doubanId': '1292063',
                        'doubanRating': '9.6',
                        'imdbRating': '8.6',
                        'year': '1997',
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
      );
      addTearDown(container.dispose);

      const target = MediaDetailTarget(
        title: '美丽人生',
        posterUrl: '',
        overview: '',
        year: 1997,
        ratingLabels: ['豆瓣 9.5'],
        availabilityLabel: '无',
        searchQuery: '美丽人生',
        sourceName: '豆瓣',
      );

      final resolved = await container.read(
        enrichedDetailTargetProvider(target).future,
      );

      expect(resolved.ratingLabels, contains('豆瓣 9.5'));
      expect(resolved.ratingLabels, isNot(contains('豆瓣 9.6')));
      expect(resolved.ratingLabels, contains('IMDb 8.6'));
      expect(resolved.imdbId, 'tt0118799');
    });
  });
}

class _FakeMediaRepository implements MediaRepository {
  const _FakeMediaRepository({required this.library});

  final List<MediaItem> library;

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
  Future<MediaItem?> findById(String id) async {
    return null;
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
  Future<void> cancelActiveWebDavRefreshes({
    bool includeForceFull = false,
  }) async {}

  @override
  Future<void> refreshSource({
    required String sourceId,
    bool forceFullRescan = false,
  }) async {}

  @override
  Future<List<MediaSourceConfig>> fetchSources() async {
    return const [];
  }

  @override
  Future<MediaItem?> matchTitle(String title) async {
    return null;
  }

  @override
  Future<void> deleteResource({
    required String sourceId,
    required String resourcePath,
    String sectionId = '',
  }) async {}
}
