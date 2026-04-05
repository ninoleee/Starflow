import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';

void main() {
  group('WmdbMetadataClient', () {
    test('maps direct douban id lookup', () async {
      final client = WmdbMetadataClient(
        MockClient((request) async {
          expect(request.url.path, '/movie/api');
          expect(request.url.queryParameters['id'], '1428581');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {
                    'poster': 'https://img.wmdb.tv/movie/poster/sample.jpg',
                    'name': '天书奇谭',
                    'genre': '动画/奇幻',
                    'description': '袁公偷偷把天书带到人间。',
                    'lang': 'Cn',
                  },
                ],
                'actor': [
                  {
                    'data': [
                      {'name': '刘风', 'lang': 'Cn'},
                    ],
                  },
                ],
                'director': [
                  {
                    'data': [
                      {'name': '钱运达', 'lang': 'Cn'},
                    ],
                  },
                ],
                'originalName': '天书奇谭',
                'imdbId': 'tt6035092',
                'tmdbId': '135130',
                'imdbRating': '7.4',
                'year': '1983',
                'duration': 5340,
                'doubanId': '1428581',
                'doubanRating': '9.2',
              }),
            ),
            200,
          );
        }),
      );

      final result = await client.matchByDoubanId(doubanId: '1428581');
      expect(result, isNotNull);
      expect(result!.title, '天书奇谭');
      expect(result.posterUrl, 'https://img.wmdb.tv/movie/poster/sample.jpg');
      expect(result.year, 1983);
      expect(result.durationLabel, '1h 29m');
      expect(result.directors, ['钱运达']);
      expect(result.actors, ['刘风']);
      expect(result.ratingLabels, ['豆瓣 9.2', 'IMDb 7.4']);
      expect(result.doubanId, '1428581');
      expect(result.imdbId, 'tt6035092');
    });

    test('maps search lookup and prefers best title match', () async {
      final client = WmdbMetadataClient(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/movie/search');
          expect(request.url.queryParameters['q'], '英雄本色');
          expect(request.url.queryParameters['actor'], '周润发');
          expect(request.url.queryParameters['year'], '1986');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {
                    'originalName': '英雄本色',
                    'alias': 'A Better Tomorrow / Gangland Boss',
                    'year': '1986',
                    'type': 'Movie',
                    'imdbId': 'tt0092263',
                    'doubanId': '1297574',
                    'doubanRating': '8.7',
                    'duration': 5700,
                    'data': [
                      {
                        'poster': 'https://img.wmdb.tv/movie/poster/hero.jpg',
                        'name': '英雄本色',
                        'genre': '剧情/动作/犯罪',
                        'description': '宋子豪和 Mark 情同手足。',
                        'lang': 'Cn',
                      },
                    ],
                    'director': [
                      {
                        'data': [
                          {'name': '吴宇森', 'lang': 'Cn'},
                        ],
                      },
                    ],
                    'actor': [
                      {
                        'data': [
                          {'name': '周润发', 'lang': 'Cn'},
                        ],
                      },
                      {
                        'data': [
                          {'name': '张国荣', 'lang': 'Cn'},
                        ],
                      },
                    ],
                  },
                  {
                    'originalName': '无关影片',
                    'year': '1990',
                    'type': 'Movie',
                    'data': [
                      {
                        'poster': 'https://img.wmdb.tv/movie/poster/other.jpg',
                        'name': '无关影片',
                        'genre': '剧情',
                        'description': '',
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
      );

      final result = await client.matchTitle(
        query: '英雄本色',
        year: 1986,
        actors: const ['周润发'],
      );
      expect(result, isNotNull);
      expect(result!.title, '英雄本色');
      expect(result.posterUrl, 'https://img.wmdb.tv/movie/poster/hero.jpg');
      expect(result.genres, ['剧情', '动作', '犯罪']);
      expect(result.directors, ['吴宇森']);
      expect(result.actors, ['周润发', '张国荣']);
      expect(result.titlesForMatching, contains('A Better Tomorrow'));
    });

    test('falls back to 豆瓣 0 when wmdb does not return douban rating',
        () async {
      final client = WmdbMetadataClient(
        MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {
                    'poster': 'https://img.wmdb.tv/movie/poster/sample.jpg',
                    'name': '无名之辈',
                    'genre': '剧情',
                    'description': '小人物故事。',
                    'lang': 'Cn',
                  },
                ],
                'originalName': '无名之辈',
                'imdbId': 'tt9378778',
                'tmdbId': '543320',
                'year': '2018',
                'duration': 6480,
                'doubanId': '27110296',
                'imdbRating': '6.6',
              }),
            ),
            200,
          );
        }),
      );

      final result = await client.matchByDoubanId(doubanId: '27110296');
      expect(result, isNotNull);
      expect(result!.ratingLabels, ['豆瓣 0', 'IMDb 6.6']);
    });

    test('reuses identical lookups from in-memory cache', () async {
      final gate = Completer<void>();
      var requestCount = 0;
      final client = WmdbMetadataClient(
        MockClient((request) async {
          requestCount += 1;
          await gate.future;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {
                    'originalName': '英雄本色',
                    'year': '1986',
                    'type': 'Movie',
                    'data': [
                      {
                        'poster': 'https://img.wmdb.tv/movie/poster/hero.jpg',
                        'name': '英雄本色',
                        'genre': '剧情/动作/犯罪',
                        'description': '宋子豪和 Mark 情同手足。',
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
      );

      final first = client.matchTitle(query: '英雄本色', year: 1986);
      final second = client.matchTitle(query: '英雄本色', year: 1986);
      await Future<void>.delayed(Duration.zero);
      gate.complete();

      await Future.wait([first, second]);
      await client.matchTitle(query: '英雄本色', year: 1986);

      expect(requestCount, 1);
    });
  });
}
