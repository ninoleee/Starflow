import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  group('EmbyApiClient helpers', () {
    test('adds /emby fallback when endpoint is bare host', () {
      final candidates = EmbyApiClient.candidateBaseUris(
        'https://media.example.com',
      );

      expect(
        candidates.map((item) => item.toString()),
        [
          'https://media.example.com',
          'https://media.example.com/emby',
        ],
      );
    });

    test('builds direct stream uri with media source and token', () {
      final uri = EmbyApiClient.buildDirectStreamUri(
        baseUri: Uri.parse('https://media.example.com/emby'),
        itemId: 'item-123',
        container: 'mkv',
        mediaSourceId: 'source-456',
        accessToken: 'token-789',
      );

      expect(
        uri.toString(),
        'https://media.example.com/emby/Videos/item-123/stream.mkv?static=true&MediaSourceId=source-456&api_key=token-789',
      );
    });

    test('formats runtime ticks as hour-minute label', () {
      expect(
        EmbyApiClient.formatRunTimeTicks(54000000000),
        '1h 30m',
      );
    });

    test('aggregates library content from user views first', () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          expect(request.headers['X-Emby-Token'], 'token-789');

          if (request.url.path == '/Users/user-123/Items' &&
              !request.url.queryParameters.containsKey('ParentId')) {
            return http.Response('Unexpected root recursive request', 500);
          }

          if (request.url.path == '/Users/user-123/Views') {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'movies-view',
                    'CollectionType': 'movies',
                  },
                  {
                    'Id': 'shows-view',
                    'CollectionType': 'tvshows',
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'movies-view') {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'movie-1',
                    'Name': 'Dune: Part Two',
                    'Overview': 'Sci-fi epic',
                    'ProductionYear': 2024,
                    'DateCreated': '2026-04-01T12:00:00.0000000Z',
                    'Genres': ['Sci-Fi'],
                    'People': [
                      {'Name': 'Denis Villeneuve', 'Type': 'Director'},
                      {'Name': 'Timothee Chalamet', 'Type': 'Actor'},
                      {'Name': 'Zendaya', 'Type': 'Actor'},
                    ],
                    'ImageTags': {'Primary': 'poster-1'},
                    'MediaSources': [
                      {
                        'Id': 'media-source-1',
                        'Container': 'mkv',
                      },
                    ],
                    'RunTimeTicks': 99600000000,
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'shows-view') {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'episode-1',
                    'Name': 'The Last of Us S01E01',
                    'Overview': 'Pilot episode',
                    'ProductionYear': 2023,
                    'DateCreated': '2026-03-15T08:00:00.0000000Z',
                    'Genres': ['Drama'],
                    'People': [
                      {'Name': 'Craig Mazin', 'Type': 'Director'},
                      {'Name': 'Pedro Pascal', 'Type': 'Actor'},
                    ],
                    'ImageTags': {'Primary': 'poster-2'},
                    'MediaSources': [
                      {
                        'Id': 'media-source-2',
                        'Container': 'mp4',
                      },
                    ],
                    'UserData': {
                      'PlayedPercentage': 37.5,
                    },
                    'RunTimeTicks': 48600000000,
                  },
                ],
              }),
              200,
            );
          }

          return http.Response('Not found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'emby-main',
          name: 'Home Emby',
          kind: MediaSourceKind.emby,
          endpoint: 'https://media.example.com',
          enabled: true,
          username: 'alice',
          accessToken: 'token-789',
          userId: 'user-123',
          deviceId: 'device-456',
        ),
      );

      expect(items, hasLength(2));
      expect(items.map((item) => item.id), ['movie-1', 'episode-1']);
      expect(
        items.first.posterUrl,
        'https://media.example.com/Items/movie-1/Images/Primary?maxHeight=720&quality=90&tag=poster-1&api_key=token-789',
      );
      expect(items.first.streamUrl, isEmpty);
      expect(items.first.playbackItemId, 'movie-1');
      expect(items.first.preferredMediaSourceId, 'media-source-1');
      expect(items.first.isPlayable, isTrue);
      expect(items.first.directors, ['Denis Villeneuve']);
      expect(items.first.actors, ['Timothee Chalamet', 'Zendaya']);
      expect(items.last.playbackProgress, closeTo(0.375, 0.0001));
    });

    test('prefers nested series over recursive episodes for tv sections',
        () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          if (request.url.path.endsWith('/Users/user-123/Items')) {
            if (request.url.queryParameters['ParentId'] == 'shows-view' &&
                request.url.queryParameters['Recursive'] == 'false') {
              expect(request.url.queryParameters['Recursive'], 'false');
              expect(request.url.queryParameters['IncludeItemTypes'], isNull);

              return http.Response(
                jsonEncode({
                  'Items': [
                    {
                      'Id': 'folder-us',
                      'Name': 'United States',
                      'Type': 'Folder',
                      'IsFolder': true,
                      'Overview': 'Region folder',
                      'ProductionYear': 0,
                      'DateCreated': '2026-03-15T08:00:00.0000000Z',
                      'Genres': [],
                      'ImageTags': {'Primary': 'poster-folder-us'},
                    },
                  ],
                }),
                200,
              );
            }

            if (request.url.queryParameters['ParentId'] == 'folder-us' &&
                request.url.queryParameters['Recursive'] == 'false') {
              return http.Response(
                jsonEncode({
                  'Items': [
                    {
                      'Id': 'series-1',
                      'Name': 'The Last of Us',
                      'Type': 'Series',
                      'IsFolder': true,
                      'Overview': 'Post-apocalyptic drama',
                      'ProductionYear': 2023,
                      'DateCreated': '2026-03-15T08:00:00.0000000Z',
                      'Genres': ['Drama'],
                      'ImageTags': {'Primary': 'poster-series-1'},
                    },
                  ],
                }),
                200,
              );
            }

            if (request.url.queryParameters['Recursive'] == 'true') {
              return http.Response('Unexpected recursive request', 500);
            }
          }

          return http.Response('Not found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'emby-main',
          name: 'Home Emby',
          kind: MediaSourceKind.emby,
          endpoint: 'https://media.example.com',
          enabled: true,
          username: 'alice',
          accessToken: 'token-789',
          userId: 'user-123',
          deviceId: 'device-456',
        ),
        sectionId: 'shows-view',
        sectionName: '剧集',
      );

      expect(items, hasLength(1));
      expect(items.first.id, 'series-1');
      expect(items.first.sectionId, 'shows-view');
      expect(items.first.sectionName, '剧集');
      expect(items.first.itemType, 'Series');
      expect(items.first.streamUrl, isEmpty);
      expect(
        items.first.posterUrl,
        'https://media.example.com/Items/series-1/Images/Primary?maxHeight=720&quality=90&tag=poster-series-1&api_key=token-789',
      );
    });

    test('walks deeper grouped folders before falling back to recursive query',
        () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          if (request.url.path.endsWith('/Users/user-123/Items')) {
            if (request.url.queryParameters['ParentId'] == 'shows-view' &&
                request.url.queryParameters['Recursive'] == 'false') {
              return http.Response(
                jsonEncode({
                  'Items': [
                    {
                      'Id': 'folder-country',
                      'Name': 'United States',
                      'Type': 'Folder',
                      'IsFolder': true,
                      'DateCreated': '2026-03-15T08:00:00.0000000Z',
                    },
                  ],
                }),
                200,
              );
            }

            if (request.url.queryParameters['ParentId'] == 'folder-country' &&
                request.url.queryParameters['Recursive'] == 'false') {
              return http.Response(
                jsonEncode({
                  'Items': [
                    {
                      'Id': 'folder-network',
                      'Name': 'HBO',
                      'Type': 'Folder',
                      'IsFolder': true,
                      'DateCreated': '2026-03-15T08:00:00.0000000Z',
                    },
                  ],
                }),
                200,
              );
            }

            if (request.url.queryParameters['ParentId'] == 'folder-network' &&
                request.url.queryParameters['Recursive'] == 'false') {
              return http.Response(
                jsonEncode({
                  'Items': [
                    {
                      'Id': 'folder-drama',
                      'Name': 'Drama',
                      'Type': 'Folder',
                      'IsFolder': true,
                      'DateCreated': '2026-03-15T08:00:00.0000000Z',
                    },
                  ],
                }),
                200,
              );
            }

            if (request.url.queryParameters['ParentId'] == 'folder-drama' &&
                request.url.queryParameters['Recursive'] == 'false') {
              return http.Response(
                jsonEncode({
                  'Items': [
                    {
                      'Id': 'series-1',
                      'Name': 'The Last of Us',
                      'Type': 'Series',
                      'IsFolder': true,
                      'Overview': 'Post-apocalyptic drama',
                      'ProductionYear': 2023,
                      'DateCreated': '2026-03-15T08:00:00.0000000Z',
                      'ImageTags': {'Primary': 'poster-series-1'},
                    },
                  ],
                }),
                200,
              );
            }

            if (request.url.queryParameters['Recursive'] == 'true') {
              return http.Response('Unexpected recursive request', 500);
            }
          }

          return http.Response('Not found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'emby-main',
          name: 'Home Emby',
          kind: MediaSourceKind.emby,
          endpoint: 'https://media.example.com',
          enabled: true,
          username: 'alice',
          accessToken: 'token-789',
          userId: 'user-123',
          deviceId: 'device-456',
        ),
        sectionId: 'shows-view',
        sectionName: '剧集',
      );

      expect(items, hasLength(1));
      expect(items.first.id, 'series-1');
      expect(items.first.itemType, 'Series');
    });

    test(
        'falls back to recursive playable query when grouped folders do not resolve to series',
        () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'shows-view' &&
              request.url.queryParameters['Recursive'] == 'false') {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'folder-us',
                    'Name': 'United States',
                    'Type': 'Folder',
                    'IsFolder': true,
                    'Overview': 'Region folder',
                    'ProductionYear': 0,
                    'DateCreated': '2026-03-15T08:00:00.0000000Z',
                    'Genres': [],
                    'ImageTags': {'Primary': 'poster-folder-us'},
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'folder-us' &&
              request.url.queryParameters['Recursive'] == 'false') {
            return http.Response(jsonEncode({'Items': []}), 200);
          }

          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'shows-view' &&
              request.url.queryParameters['Recursive'] == 'true') {
            expect(
              request.url.queryParameters['IncludeItemTypes'],
              'Movie,Episode,Video',
            );
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'episode-1',
                    'Name': 'The Last of Us S01E01',
                    'Type': 'Episode',
                    'MediaType': 'Video',
                    'Overview': 'Pilot episode',
                    'ProductionYear': 2023,
                    'DateCreated': '2026-03-15T08:00:00.0000000Z',
                    'Genres': ['Drama'],
                    'ImageTags': {'Primary': 'poster-2'},
                    'MediaSources': [
                      {
                        'Id': 'media-source-2',
                        'Container': 'mp4',
                      },
                    ],
                    'RunTimeTicks': 48600000000,
                  },
                ],
              }),
              200,
            );
          }

          return http.Response('Not found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'emby-main',
          name: 'Home Emby',
          kind: MediaSourceKind.emby,
          endpoint: 'https://media.example.com',
          enabled: true,
          username: 'alice',
          accessToken: 'token-789',
          userId: 'user-123',
          deviceId: 'device-456',
        ),
        sectionId: 'shows-view',
        sectionName: '剧集',
      );

      expect(items, hasLength(1));
      expect(items.first.id, 'episode-1');
      expect(items.first.streamUrl, isEmpty);
      expect(items.first.playbackItemId, 'episode-1');
      expect(items.first.preferredMediaSourceId, 'media-source-2');
      expect(items.first.isPlayable, isTrue);
    });

    test('returns nested episodes when seasons are the deepest content nodes',
        () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'shows-view' &&
              request.url.queryParameters['Recursive'] == 'false') {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'folder-archive',
                    'Name': 'Archive',
                    'Type': 'Folder',
                    'IsFolder': true,
                    'DateCreated': '2026-03-15T08:00:00.0000000Z',
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'folder-archive' &&
              request.url.queryParameters['Recursive'] == 'false') {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'season-1',
                    'Name': 'Season 1',
                    'Type': 'Season',
                    'IsFolder': true,
                    'DateCreated': '2026-03-15T08:00:00.0000000Z',
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'season-1' &&
              request.url.queryParameters['Recursive'] == 'false') {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'episode-1',
                    'Name': 'Pilot',
                    'Type': 'Episode',
                    'MediaType': 'Video',
                    'Overview': 'Pilot episode',
                    'ProductionYear': 2023,
                    'DateCreated': '2026-03-15T08:00:00.0000000Z',
                    'ImageTags': {'Primary': 'poster-2'},
                    'MediaSources': [
                      {
                        'Id': 'media-source-2',
                        'Container': 'mp4',
                      },
                    ],
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.queryParameters['Recursive'] == 'true') {
            return http.Response('Unexpected recursive request', 500);
          }

          return http.Response('Not found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'emby-main',
          name: 'Home Emby',
          kind: MediaSourceKind.emby,
          endpoint: 'https://media.example.com',
          enabled: true,
          username: 'alice',
          accessToken: 'token-789',
          userId: 'user-123',
          deviceId: 'device-456',
        ),
        sectionId: 'shows-view',
        sectionName: '剧集',
      );

      expect(items, hasLength(1));
      expect(items.first.id, 'episode-1');
      expect(items.first.playbackItemId, 'episode-1');
      expect(items.first.isPlayable, isTrue);
    });

    test('keeps series items when section already returns content nodes',
        () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'shows-view' &&
              request.url.queryParameters['Recursive'] == 'false') {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'series-1',
                    'Name': 'The Last of Us',
                    'Type': 'Series',
                    'IsFolder': true,
                    'Overview': 'Post-apocalyptic drama',
                    'ProductionYear': 2023,
                    'DateCreated': '2026-03-15T08:00:00.0000000Z',
                    'Genres': ['Drama'],
                    'ImageTags': {'Primary': 'poster-series-1'},
                  },
                ],
              }),
              200,
            );
          }

          return http.Response('Not found', 404);
        }),
      );

      final items = await client.fetchLibrary(
        const MediaSourceConfig(
          id: 'emby-main',
          name: 'Home Emby',
          kind: MediaSourceKind.emby,
          endpoint: 'https://media.example.com',
          enabled: true,
          username: 'alice',
          accessToken: 'token-789',
          userId: 'user-123',
          deviceId: 'device-456',
        ),
        sectionId: 'shows-view',
        sectionName: '剧集',
      );

      expect(items, hasLength(1));
      expect(items.first.id, 'series-1');
      expect(items.first.itemType, 'Series');
      expect(items.first.isFolder, isTrue);
      expect(items.first.streamUrl, isEmpty);
    });

    test('resolves playback info into the final stream target', () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          if (request.url.path == '/Items/episode-1/PlaybackInfo') {
            expect(request.url.queryParameters['UserId'], 'user-123');
            expect(request.url.queryParameters['IsPlayback'], 'true');
            expect(
                request.url.queryParameters['MediaSourceId'], 'media-source-2');

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
                        '/Videos/episode-1/stream.mp4?static=true&MediaSourceId=media-source-2',
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
                    'RequiredHttpHeaders': {
                      'X-Test-Header': 'value-1',
                    },
                  },
                ],
              }),
              200,
            );
          }

          return http.Response('Not found', 404);
        }),
      );

      final target = await client.resolvePlaybackTarget(
        source: const MediaSourceConfig(
          id: 'emby-main',
          name: 'Home Emby',
          kind: MediaSourceKind.emby,
          endpoint: 'https://media.example.com',
          enabled: true,
          username: 'alice',
          accessToken: 'token-789',
          userId: 'user-123',
          deviceId: 'device-456',
        ),
        target: const PlaybackTarget(
          title: 'Pilot',
          sourceId: 'emby-main',
          streamUrl: '',
          sourceName: 'Home Emby',
          sourceKind: MediaSourceKind.emby,
          itemId: 'episode-1',
          preferredMediaSourceId: 'media-source-2',
        ),
      );

      final resolvedUri = Uri.parse(target.streamUrl);
      expect(resolvedUri.path, '/Videos/episode-1/stream.mp4');
      expect(resolvedUri.queryParameters['MediaSourceId'], 'media-source-2');
      expect(resolvedUri.queryParameters['api_key'], 'token-789');
      expect(target.headers['X-Test-Header'], 'value-1');
      expect(target.headers['X-Emby-Token'], 'token-789');
      expect(target.container, 'mkv');
      expect(target.videoCodec, 'hevc');
      expect(target.audioCodec, 'truehd');
      expect(target.width, 3840);
      expect(target.height, 2160);
      expect(target.bitrate, 28400000);
      expect(target.fileSizeBytes, 25769803776);
    });
  });
}
