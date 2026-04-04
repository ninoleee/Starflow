import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';

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

    test('falls back to user views when root items query is empty', () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          expect(request.headers['X-Emby-Token'], 'token-789');

          if (request.url.path == '/Users/user-123/Items' &&
              !request.url.queryParameters.containsKey('ParentId')) {
            return http.Response(jsonEncode({'Items': []}), 200);
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
      expect(
        items.first.streamUrl,
        'https://media.example.com/Videos/movie-1/stream.mkv?static=true&MediaSourceId=media-source-1&api_key=token-789',
      );
      expect(items.first.directors, ['Denis Villeneuve']);
      expect(items.first.actors, ['Timothee Chalamet', 'Zendaya']);
    });

    test('returns browseable folder items for emby sections', () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'shows-view') {
            expect(request.url.queryParameters['Recursive'], isNull);
            expect(
              request.url.queryParameters['IncludeItemTypes'],
              contains('Series'),
            );
            expect(request.url.queryParameters['Filters'], isNull);
            expect(request.url.queryParameters['MediaTypes'], isNull);

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
      expect(items.first.sectionId, 'shows-view');
      expect(items.first.sectionName, '剧集');
      expect(items.first.streamUrl, isEmpty);
      expect(items.first.streamHeaders, isEmpty);
      expect(
        items.first.posterUrl,
        'https://media.example.com/Items/series-1/Images/Primary?maxHeight=720&quality=90&tag=poster-series-1&api_key=token-789',
      );
    });

    test('falls back to recursive playable query when section browse is empty',
        () async {
      final client = EmbyApiClient(
        MockClient((request) async {
          if (request.url.path == '/Users/user-123/Items' &&
              request.url.queryParameters['ParentId'] == 'shows-view' &&
              request.url.queryParameters['Recursive'] == null) {
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
      expect(
        items.first.streamUrl,
        'https://media.example.com/Videos/episode-1/stream.mp4?static=true&MediaSourceId=media-source-2&api_key=token-789',
      );
    });
  });
}
