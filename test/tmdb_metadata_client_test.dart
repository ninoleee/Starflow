import 'dart:async';
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
                  'production_companies': [
                    {
                      'name': 'Warner Bros.',
                      'logo_path': '/warner.png',
                    },
                  ],
                  'credits': {
                    'cast': [
                      {
                        'name': 'Keanu Reeves',
                        'profile_path': '/keanu.jpg',
                      },
                      {
                        'name': 'Carrie-Anne Moss',
                        'profile_path': '/carrie.jpg',
                      },
                    ],
                    'crew': [
                      {
                        'name': 'Lana Wachowski',
                        'job': 'Director',
                        'department': 'Directing',
                        'profile_path': '/lana.jpg',
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
      expect(result.directorProfiles.first.name, 'Lana Wachowski');
      expect(
        result.directorProfiles.first.avatarUrl,
        'https://image.tmdb.org/t/p/w185/lana.jpg',
      );
      expect(result.platforms, ['Warner Bros.']);
      expect(result.platformProfiles.first.name, 'Warner Bros.');
      expect(
        result.platformProfiles.first.avatarUrl,
        'https://image.tmdb.org/t/p/w300/warner.png',
      );
      expect(result.actors, ['Keanu Reeves', 'Carrie-Anne Moss']);
      expect(result.actorProfiles.first.name, 'Keanu Reeves');
      expect(
        result.actorProfiles.first.avatarUrl,
        'https://image.tmdb.org/t/p/w185/keanu.jpg',
      );
      expect(result.imdbId, 'tt0133093');
      expect(result.tmdbId, 603);
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
                    {
                      'name': 'Craig Mazin',
                      'profile_path': '/craig.jpg',
                    },
                  ],
                  'production_companies': [
                    {
                      'name': 'Sony Pictures Television',
                      'logo_path': '/sony-tv.png',
                    },
                  ],
                  'networks': [
                    {
                      'name': 'HBO',
                      'logo_path': '/hbo.png',
                    },
                  ],
                  'aggregate_credits': {
                    'cast': [
                      {
                        'name': 'Pedro Pascal',
                        'profile_path': '/pedro.jpg',
                      },
                      {
                        'name': 'Bella Ramsey',
                        'profile_path': '/bella.jpg',
                      },
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
      expect(result.directorProfiles.first.name, 'Craig Mazin');
      expect(
        result.directorProfiles.first.avatarUrl,
        'https://image.tmdb.org/t/p/w185/craig.jpg',
      );
      expect(result.platforms, ['Sony Pictures Television']);
      expect(result.platformProfiles.first.name, 'Sony Pictures Television');
      expect(
        result.platformProfiles.first.avatarUrl,
        'https://image.tmdb.org/t/p/w300/sony-tv.png',
      );
      expect(result.actors, ['Pedro Pascal', 'Bella Ramsey']);
      expect(result.actorProfiles.first.name, 'Pedro Pascal');
      expect(
        result.actorProfiles.first.avatarUrl,
        'https://image.tmdb.org/t/p/w185/pedro.jpg',
      );
      expect(result.imdbId, 'tt3581920');
      expect(result.tmdbId, 100088);
    });

    test('reuses identical lookups from in-memory cache', () async {
      final searchGate = Completer<void>();
      var searchRequests = 0;
      var detailRequests = 0;
      final client = TmdbMetadataClient(
        MockClient((request) async {
          if (request.url.path == '/3/search/multi') {
            searchRequests += 1;
            await searchGate.future;
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
            detailRequests += 1;
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

          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      );

      final first = client.matchTitle(
        query: 'The Matrix',
        readAccessToken: 'tmdb-token',
        year: 1999,
      );
      final second = client.matchTitle(
        query: 'The Matrix',
        readAccessToken: 'tmdb-token',
        year: 1999,
      );
      await Future<void>.delayed(Duration.zero);
      searchGate.complete();

      final results = await Future.wait([first, second]);
      final cached = await client.matchTitle(
        query: 'The Matrix',
        readAccessToken: 'tmdb-token',
        year: 1999,
      );

      expect(results.first, isNotNull);
      expect(results.last, isNotNull);
      expect(cached, isNotNull);
      expect(searchRequests, 1);
      expect(detailRequests, 1);
    });

    test('matches TMDB details by imdb id before title search', () async {
      var findRequests = 0;
      var detailRequests = 0;
      final client = TmdbMetadataClient(
        MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer tmdb-token');
          if (request.url.path == '/3/find/tt0133093') {
            findRequests += 1;
            expect(request.url.queryParameters['external_source'], 'imdb_id');
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
            detailRequests += 1;
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

          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      );

      final result = await client.matchByImdbId(
        imdbId: 'tt0133093',
        readAccessToken: 'tmdb-token',
      );

      expect(result, isNotNull);
      expect(result!.title, '黑客帝国');
      expect(result.imdbId, 'tt0133093');
      expect(result.tmdbId, 603);
      expect(findRequests, 1);
      expect(detailRequests, 1);
    });

    test('returns no match when details lookup fails after search hit',
        () async {
      final client = TmdbMetadataClient(
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

          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      );

      final result = await client.matchTitle(
        query: 'The Matrix',
        readAccessToken: 'tmdb-token',
        year: 1999,
      );

      expect(result, isNull);
    });

    test('fetches related credits for actor and director entries', () async {
      final client = TmdbMetadataClient(
        MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer tmdb-token');

          if (request.url.path == '/3/search/person') {
            expect(request.url.queryParameters['query'], 'Christopher Nolan');
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'id': 99,
                    'name': 'Christopher Nolan Fan',
                    'profile_path': '/fan.jpg',
                    'known_for_department': 'Acting',
                    'popularity': 1.0,
                  },
                  {
                    'id': 525,
                    'name': 'Christopher Nolan',
                    'profile_path': '/nolan.jpg',
                    'known_for_department': 'Directing',
                    'popularity': 25.0,
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.path == '/3/person/525/combined_credits') {
            return http.Response(
              jsonEncode({
                'cast': [
                  {
                    'id': 27205,
                    'media_type': 'movie',
                    'title': 'Inception',
                    'original_title': 'Inception',
                    'poster_path': '/inception.jpg',
                    'backdrop_path': '/inception-bg.jpg',
                    'overview': 'Dreams within dreams.',
                    'release_date': '2010-07-16',
                    'vote_average': 8.3,
                    'vote_count': 32000,
                    'character': 'Cobb',
                    'popularity': 50.0,
                  },
                  {
                    'id': 27205,
                    'media_type': 'movie',
                    'title': 'Inception',
                    'original_title': 'Inception',
                    'poster_path': '/duplicate.jpg',
                    'release_date': '2010-07-16',
                    'character': 'Duplicate',
                    'popularity': 10.0,
                  },
                ],
                'crew': [
                  {
                    'id': 157336,
                    'media_type': 'movie',
                    'title': 'Interstellar',
                    'original_title': 'Interstellar',
                    'poster_path': '/interstellar.jpg',
                    'backdrop_path': '/interstellar-bg.jpg',
                    'overview': 'Space exploration.',
                    'release_date': '2014-11-07',
                    'vote_average': 8.4,
                    'vote_count': 28000,
                    'job': 'Director',
                    'department': 'Directing',
                    'popularity': 80.0,
                  },
                  {
                    'id': 49026,
                    'media_type': 'movie',
                    'title': 'The Dark Knight Rises',
                    'original_title': 'The Dark Knight Rises',
                    'poster_path': '/tdkr.jpg',
                    'release_date': '2012-07-20',
                    'job': 'Producer',
                    'department': 'Production',
                    'popularity': 70.0,
                  },
                ],
              }),
              200,
            );
          }

          throw UnsupportedError('Unexpected request: ${request.url}');
        }),
      );

      final actorCredits = await client.fetchPersonCredits(
        name: 'Christopher Nolan',
        avatarUrl: 'https://image.tmdb.org/t/p/w185/nolan.jpg',
        role: TmdbPersonCreditsRole.actor,
        readAccessToken: 'tmdb-token',
      );
      final directorCredits = await client.fetchPersonCredits(
        name: 'Christopher Nolan',
        avatarUrl: 'https://image.tmdb.org/t/p/w185/nolan.jpg',
        role: TmdbPersonCreditsRole.director,
        readAccessToken: 'tmdb-token',
      );

      expect(actorCredits, hasLength(1));
      expect(actorCredits.first.title, 'Inception');
      expect(actorCredits.first.subtitle, '饰 Cobb');
      expect(actorCredits.first.ratingLabels, ['TMDB 8.3']);

      expect(directorCredits, hasLength(1));
      expect(directorCredits.first.title, 'Interstellar');
      expect(directorCredits.first.subtitle, '导演');
      expect(
        directorCredits.first.posterUrl,
        'https://image.tmdb.org/t/p/w500/interstellar.jpg',
      );
    });
  });
}
