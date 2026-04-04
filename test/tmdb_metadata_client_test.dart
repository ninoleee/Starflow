import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';

void main() {
  group('TmdbMetadataClient', () {
    test('maps movie metadata from search and details response', () async {
      final client = TmdbMetadataClient(
        MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer tmdb-token');

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
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'title': '黑客帝国',
                  'overview': '一名黑客发现世界的真实面貌。',
                  'poster_path': '/matrix-detail.jpg',
                  'release_date': '1999-03-31',
                  'runtime': 136,
                  'genres': [
                    {'name': '动作'},
                    {'name': '科幻'},
                  ],
                  'credits': {
                    'cast': [
                      {'name': 'Keanu Reeves'},
                      {'name': 'Carrie-Anne Moss'},
                    ],
                    'crew': [
                      {
                        'name': 'Lana Wachowski',
                        'job': 'Director',
                        'department': 'Directing',
                      },
                      {
                        'name': 'Lilly Wachowski',
                        'job': 'Director',
                        'department': 'Directing',
                      },
                    ],
                  },
                  'external_ids': {'imdb_id': 'tt0133093'},
                }),
              ),
              200,
            );
          }

          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      );

      final result = await client.matchTitle(
        query: 'The.Matrix.1999.1080p.BluRay',
        readAccessToken: 'tmdb-token',
        year: 1999,
      );

      expect(result, isNotNull);
      expect(result!.title, '黑客帝国');
      expect(
        result.posterUrl,
        'https://image.tmdb.org/t/p/w500/matrix-detail.jpg',
      );
      expect(result.overview, '一名黑客发现世界的真实面貌。');
      expect(result.year, 1999);
      expect(result.durationLabel, '2h 16m');
      expect(result.genres, ['动作', '科幻']);
      expect(result.directors, ['Lana Wachowski', 'Lilly Wachowski']);
      expect(result.actors, ['Keanu Reeves', 'Carrie-Anne Moss']);
      expect(result.imdbId, 'tt0133093');
    });

    test('prefers tv result when series is requested', () async {
      final client = TmdbMetadataClient(
        MockClient((request) async {
          if (request.url.path == '/3/search/multi') {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'id': 11,
                    'media_type': 'movie',
                    'title': 'The Last of Us',
                    'original_title': 'The Last of Us',
                    'overview': '',
                    'release_date': '2023-01-10',
                    'popularity': 20.0,
                  },
                  {
                    'id': 100088,
                    'media_type': 'tv',
                    'name': 'The Last of Us',
                    'original_name': 'The Last of Us',
                    'overview': '',
                    'first_air_date': '2023-01-15',
                    'popularity': 99.0,
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.path == '/3/tv/100088') {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'name': '最后生还者',
                  'overview': '末日世界里，Joel 和 Ellie 一路求生。',
                  'first_air_date': '2023-01-15',
                  'episode_run_time': [55],
                  'genres': [
                    {'name': '剧情'},
                  ],
                  'created_by': [
                    {'name': 'Craig Mazin'},
                  ],
                  'aggregate_credits': {
                    'cast': [
                      {'name': 'Pedro Pascal'},
                      {'name': 'Bella Ramsey'},
                    ],
                    'crew': const [],
                  },
                  'external_ids': {'imdb_id': 'tt3581920'},
                }),
              ),
              200,
            );
          }

          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      );

      final result = await client.matchTitle(
        query: 'The Last of Us',
        readAccessToken: 'tmdb-token',
        year: 2023,
        preferSeries: true,
      );

      expect(result, isNotNull);
      expect(result!.title, '最后生还者');
      expect(result.durationLabel, '55m / 集');
      expect(result.directors, ['Craig Mazin']);
      expect(result.actors, ['Pedro Pascal', 'Bella Ramsey']);
      expect(result.imdbId, 'tt3581920');
    });
  });
}
