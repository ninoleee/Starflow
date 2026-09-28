import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/discovery/data/douban_browse_repository.dart';
import 'package:starflow/features/discovery/domain/douban_browse_models.dart';

void main() {
  test('year choices step by one, five, then ten years', () {
    final years = doubanBrowseYearOptions(currentYear: 2026);
    expect(years.take(7), [2026, 2025, 2024, 2023, 2022, 2021, 2020]);
    expect(years.skip(7).take(4), [2015, 2010, 2005, 2000]);
    expect(years.skip(11).take(3), [1990, 1980, 1970]);
    expect(years.last, 1890);
    expect(years.toSet().length, years.length);
    expect(
        doubanBrowseYearOptions(currentYear: 2026, selectedYear: 1997)
            .where((year) => year == 1997),
        [1997]);
  });

  test('encodes combined filters and parses a browse page', () async {
    var requests = 0;
    final api = DoubanApiClient(MockClient((request) async {
      requests++;
      expect(request.url.path, '/rexxar/api/v2/movie/recommend');
      expect(request.url.queryParameters['tags'], '科幻,美国,2023');
      expect(jsonDecode(request.url.queryParameters['selected_categories']!),
          {'类型': '科幻', '地区': '美国'});
      expect(request.url.queryParameters['score_range'], '8,10');
      expect(request.url.queryParameters['sort'], 'S');
      expect(request.url.queryParameters['start'], '0');
      expect(request.headers.containsKey('Cookie'), false);
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'items': [
              {
                'id': '123',
                'title': '测试电影',
                'type': 'movie',
                'year': '2023',
                'pic': {'normal': '//img.doubanio.com/poster.jpg'},
                'rating': {'value': 8.5, 'count': 360},
                'card_subtitle': '2024 / 中国大陆 / 惊悚 / 犯罪',
              },
              {'id': '456', 'title': '电视剧', 'type': 'tv'},
            ],
            'total': 32,
            'recommend_categories': [
              {
                'type': '类型',
                'data': [
                  {'text': '全部'},
                  {'text': '科幻'}
                ]
              },
              {
                'type': '地区',
                'data': [
                  {'text': '美国'}
                ]
              },
            ],
          })),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }));
    final query =
        DoubanBrowseQuery(year: 2023, region: '美国', genre: '科幻', minRating: 8);
    final repo = DoubanBrowseRepository(api);
    final page = await repo.fetch(query);
    final again = await repo.fetch(query);
    expect(requests, 1);
    expect(identical(page, again), true);
    expect(page.rawCount, 2);
    expect(page.total, 32);
    expect(page.entries, hasLength(1));
    expect(page.entries.single.ratingLabel, '豆瓣 8.5');
    expect(page.entries.single.ratingCount, 360);
    expect(page.entries.single.note, isEmpty);
    expect(page.entries.single.genres, ['惊悚', '犯罪']);
    expect(
        page.entries.single.posterUrl, 'https://img.doubanio.com/poster.jpg');
    expect(page.genres, ['科幻']);
    expect(page.regions, ['美国']);
  });

  test('tv pagination uses raw offset and supports manual refresh', () async {
    var requests = 0;
    final api = DoubanApiClient(MockClient((request) async {
      requests++;
      expect(request.url.path, '/rexxar/api/v2/tv/recommend');
      expect(request.url.queryParameters['start'], '20');
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'items': [
              {'id': '234', 'title': '剧集', 'type': 'tv', 'year': '2020'}
            ],
            'total': 21,
          })),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    }));
    final repo = DoubanBrowseRepository(api);
    final query = DoubanBrowseQuery(category: DoubanBrowseCategory.series);
    final page = await repo.fetch(query, start: 20);
    expect(page.hasNext, false);
    expect(page.entries.single.subjectType, 'tv');
    await repo.fetch(query, start: 20, refresh: true);
    expect(requests, 2);
  });

  test('invalidating a query drops all pages and rejects late cache writes',
      () async {
    final staleResponse = Completer<http.Response>();
    final freshResponse = Completer<http.Response>();
    var requests = 0;
    http.Response page(String title) => http.Response.bytes(
          utf8.encode(jsonEncode({
            'items': [
              {'id': title, 'title': title, 'type': 'movie'}
            ],
            'total': 40,
          })),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
    final api = DoubanApiClient(MockClient((request) {
      requests++;
      expect(request.url.queryParameters['start'], '20');
      return requests == 1 ? staleResponse.future : freshResponse.future;
    }));
    final repo = DoubanBrowseRepository(api);
    const query = DoubanBrowseQuery();

    final stalePage = repo.fetch(query, start: 20);
    repo.invalidateQuery(query);
    final freshPage = repo.fetch(query, start: 20);

    staleResponse.complete(page('stale'));
    await stalePage;
    freshResponse.complete(page('fresh'));
    final fresh = await freshPage;

    expect(fresh.entries.single.title, 'fresh');
    expect((await repo.fetch(query, start: 20)).entries.single.title, 'fresh');
    expect(requests, 2);
  });

  for (final category in [
    DoubanBrowseCategory.series,
    DoubanBrowseCategory.variety,
  ]) {
    test('${category.label} uses its form and genre tags', () async {
      final api = DoubanApiClient(MockClient((request) async {
        expect(request.url.path, '/rexxar/api/v2/tv/recommend');
        expect(jsonDecode(request.url.queryParameters['selected_categories']!),
            {'类型': category.tvTag});
        expect(request.url.queryParameters['tags'],
            '${category.tvTag},${category == DoubanBrowseCategory.series ? '悬疑' : '真人秀'}');
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'items': [
                {'id': '234', 'title': '节目', 'type': 'tv'}
              ],
              'recommend_categories': [
                {
                  'type': '类型',
                  'data': [
                    {
                      'text': '类型',
                      'tags': ['不限类型']
                    },
                    {
                      'text': '电视剧',
                      'tags': ['悬疑', '科幻']
                    },
                    {
                      'text': '综艺',
                      'tags': ['真人秀', '脱口秀']
                    },
                  ]
                }
              ]
            })),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }));
      final page = await api.fetchBrowsePage(DoubanBrowseQuery(
          category: category,
          genre: category == DoubanBrowseCategory.series ? '悬疑' : '真人秀'));
      expect(
          page.genres,
          category == DoubanBrowseCategory.series
              ? ['悬疑', '科幻']
              : ['真人秀', '脱口秀']);
    });
  }

  test('invalid payload fails rather than claiming no results', () async {
    final api = DoubanApiClient(MockClient(
        (request) async => http.Response('<html>verify</html>', 200)));
    await expectLater(api.fetchBrowsePage(const DoubanBrowseQuery()),
        throwsA(isA<DoubanApiException>()));
  });

  test('invalid conditions fail before network', () async {
    final api = DoubanApiClient(
        MockClient((request) async => http.Response('{}', 200)));
    await expectLater(
        api.fetchBrowsePage(const DoubanBrowseQuery(minRating: 11)),
        throwsFormatException);
    await expectLater(
        api.fetchBrowsePage(const DoubanBrowseQuery(), start: -20),
        throwsFormatException);
  });
}
