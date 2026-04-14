import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/metadata/data/metadata_match_resolver.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

AppSettings _resolverSettings({
  MetadataMatchProvider priority = MetadataMatchProvider.tmdb,
}) {
  return AppSettings(
    mediaSources: const [],
    searchProviders: const [],
    doubanAccount: const DoubanAccountConfig(enabled: false),
    homeModules: const [
      HomeModuleConfig(
        id: HomeModuleConfig.heroModuleId,
        type: HomeModuleType.hero,
        title: 'Hero',
        enabled: true,
      ),
    ],
    tmdbMetadataMatchEnabled: true,
    wmdbMetadataMatchEnabled: true,
    metadataMatchPriority: priority,
    tmdbReadAccessToken: 'tmdb-token',
  );
}

void main() {
  group('MetadataMatchResolver', () {
    test('falls back to wmdb when tmdb detail enrichment fails', () async {
      final resolver = MetadataMatchResolver(
        tmdbMetadataClient: TmdbMetadataClient(
          MockClient((request) async {
            if (request.url.path == '/3/search/multi') {
              return http.Response(
                jsonEncode({
                  'results': [
                    {
                      'id': 603,
                      'media_type': 'movie',
                      'title': 'The Matrix',
                      'original_title': 'The Matrix',
                      'overview': '',
                      'poster_path': '/matrix-search.jpg',
                      'release_date': '1999-03-30',
                      'popularity': 88.0,
                    },
                  ],
                }),
                200,
              );
            }
            if (request.url.path == '/3/movie/603') {
              return http.Response('boom', 500);
            }
            throw UnsupportedError('Unexpected TMDB request: ${request.url}');
          }),
        ),
        wmdbMetadataClient: WmdbMetadataClient(
          MockClient((request) async {
            expect(request.url.path, '/api/v1/movie/search');
            expect(request.url.queryParameters['q'], 'The Matrix');
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'data': [
                    {
                      'originalName': '黑客帝国',
                      'alias': 'The Matrix',
                      'year': '1999',
                      'type': 'Movie',
                      'imdbId': 'tt0133093',
                      'tmdbId': '603',
                      'doubanId': '1291843',
                      'data': [
                        {
                          'poster':
                              'https://img.wmdb.tv/movie/poster/matrix.jpg',
                          'name': '黑客帝国',
                          'description': '欢迎来到真实世界。',
                          'genre': '动作/科幻',
                          'lang': 'Cn',
                        },
                      ],
                    },
                  ],
                }),
              ),
              200,
            );
          }),
        ),
      );

      final match = await resolver.match(
        settings: _resolverSettings(),
        request: const MetadataMatchRequest(
          query: 'The Matrix',
          year: 1999,
        ),
      );

      expect(match, isNotNull);
      expect(match!.provider, MetadataMatchProvider.wmdb);
      expect(match.title, '黑客帝国');
      expect(match.tmdbId, '603');
    });

    test('falls back to tmdb imdb lookup after wmdb returns no match',
        () async {
      final resolver = MetadataMatchResolver(
        tmdbMetadataClient: TmdbMetadataClient(
          MockClient((request) async {
            if (request.url.path == '/3/find/tt0133093') {
              return http.Response(
                jsonEncode({
                  'movie_results': [
                    {
                      'id': 603,
                      'title': 'The Matrix',
                      'original_title': 'The Matrix',
                      'poster_path': '/matrix-find.jpg',
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
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'title': '黑客帝国',
                    'overview': '一名黑客发现世界的真实面貌。',
                    'poster_path': '/matrix-detail.jpg',
                    'release_date': '1999-03-31',
                    'runtime': 136,
                    'genres': const [],
                    'credits': {
                      'cast': const [],
                      'crew': const [],
                    },
                    'external_ids': {'imdb_id': 'tt0133093'},
                  }),
                ),
                200,
              );
            }
            throw UnsupportedError('Unexpected TMDB request: ${request.url}');
          }),
        ),
        wmdbMetadataClient: WmdbMetadataClient(
          MockClient((request) async {
            expect(request.url.path, '/api/v1/movie/search');
            return http.Response.bytes(
              utf8.encode(jsonEncode({'data': const []})),
              200,
            );
          }),
        ),
      );

      final match = await resolver.match(
        settings: _resolverSettings(priority: MetadataMatchProvider.wmdb),
        request: const MetadataMatchRequest(
          query: '黑客帝国',
          imdbId: 'tt0133093',
          year: 1999,
        ),
      );

      expect(match, isNotNull);
      expect(match!.provider, MetadataMatchProvider.tmdb);
      expect(match.imdbId, 'tt0133093');
      expect(match.tmdbId, '603');
      expect(match.title, '黑客帝国');
    });
  });
}
