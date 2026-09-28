import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/discovery/domain/douban_browse_models.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/discovery/presentation/douban_browse_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  testWidgets('disabled discovery does not issue requests', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var requests = 0;
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
          mediaSources: [],
          searchProviders: [],
          homeModules: [],
          doubanAccount: DoubanAccountConfig(enabled: false))),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider
          .overrideWithValue(DoubanApiClient(MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }))),
    ], child: const MaterialApp(home: DoubanBrowsePage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('豆瓣模块已关闭'), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('poster year badge and pagination follow the last grid row',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: true),
      )),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider.overrideWithValue(DoubanApiClient(MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'items': [
              {
                'id': '123',
                'title': '测试电影',
                'type': 'movie',
                'year': '2023',
                'rating': {'value': 8.6, 'count': 200},
              }
            ],
            'total': 1,
          })),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ))),
    ], child: const MaterialApp(home: DoubanBrowsePage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    final poster = tester.widget<MediaPosterTile>(find.byType(MediaPosterTile));
    expect(poster.imageTopLeftBadgeText, '2023');
    expect(poster.imageTopRightBadgeText, '电影');
    expect(poster.imageBadgeText, '豆瓣 8.6');
    expect(poster.imageBottomRightBadgeText, '☆200');
    expect(poster.subtitle, isEmpty);
    expect(tester.getTopLeft(find.text('2023')).dy,
        lessThan(tester.getTopLeft(find.text('☆200')).dy));
    expect(tester.getTopLeft(find.text('电影').last).dy,
        lessThan(tester.getTopLeft(find.text('豆瓣 8.6')).dy));
    expect(tester.getTopLeft(find.text('☆200')).dx,
        greaterThan(tester.getTopLeft(find.text('豆瓣 8.6')).dx));
    final grid = find.byType(GridView);
    final pager = find.byTooltip('上一页');
    await tester.ensureVisible(pager);
    await tester.pumpAndSettle();
    final gap = tester.getTopLeft(pager).dy - tester.getBottomLeft(grid).dy;
    expect(gap, inInclusiveRange(12, 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact poster badges fit without overlap', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 140,
              child: MediaPosterTile(
                title: '影片',
                subtitle: '',
                posterUrl: '',
                imageTopLeftBadgeText: '2023',
                imageTopRightBadgeText: '电视剧',
                imageBadgeText: '豆瓣 9.6',
                imageBottomRightBadgeText: '☆9.9万',
                onTap: _noop,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.text('☆9.9万')).dx,
        greaterThan(tester.getTopLeft(find.text('豆瓣 9.6')).dx));
    final left = tester.getRect(find.text('豆瓣 9.6'));
    final right = tester.getRect(find.text('☆9.9万'));
    expect(left.right, lessThanOrEqualTo(right.left));
  });

  testWidgets(
      'rating count menu filters candidates and keeps year all selectable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final starts = <String>[];
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: true),
      )),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider.overrideWithValue(DoubanApiClient(MockClient(
        (request) async {
          starts.add(request.url.queryParameters['start']!);
          final start = request.url.queryParameters['start']!;
          return http.Response.bytes(
              utf8.encode(jsonEncode({
                'items': start == '0'
                    ? [
                        {
                          'id': '1',
                          'title': '热门',
                          'type': 'movie',
                          'year': '2024',
                          'rating': {'count': 12000}
                        },
                        {
                          'id': '2',
                          'title': '冷门',
                          'type': 'movie',
                          'year': '2023',
                          'rating': {'count': 200}
                        },
                      ]
                    : const [],
                'total': 2,
              })),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8'
              });
        },
      ))),
    ], child: const MaterialApp(home: DoubanBrowsePage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('年份: 全部'));
    await tester.pumpAndSettle();
    expect(find.text('全部'), findsWidgets);
    await tester.tap(find.text('全部').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('年份: 全部'), findsOneWidget);

    await tester.tap(find.textContaining('点评: 不限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 万以上'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('热门'), findsOneWidget);
    expect(find.text('冷门'), findsNothing);
    expect(starts, ['0', '0']);
  });

  testWidgets(
      'rating count results paginate across more than one candidate page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _RatingCountApiClient();
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: true),
      )),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider.overrideWithValue(api),
    ], child: const MaterialApp(home: DoubanBrowsePage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('点评: 不限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 万以上'));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('作品1'), findsOneWidget);
    expect(find.text('作品21'), findsNothing);
    expect(api.browseStarts, ['0']);
    expect(api.candidateRequests, 1);

    await tester.dragUntilVisible(
      find.byTooltip('下一页'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('作品21'), findsOneWidget);
    expect(find.text('作品1'), findsNothing);
    expect(api.browseStarts, ['0']);
    expect(api.candidateRequests, 1);
  });

  testWidgets(
      'changing sort requests a fresh page and keeps its selected label',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sorts = <String>[];
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
          mediaSources: [],
          searchProviders: [],
          homeModules: [],
          doubanAccount: DoubanAccountConfig(enabled: true))),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider
          .overrideWithValue(DoubanApiClient(MockClient((request) async {
        sorts.add(request.url.queryParameters['sort']!);
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'items': [
                {
                  'id': '123',
                  'title': '测试电影',
                  'type': 'movie',
                  'year': '2023',
                  'rating': {'value': 8.6, 'count': 200}
                }
              ],
              'total': 1,
              'sorts': [
                {'name': 'T', 'checked': true}
              ],
            })),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }))),
    ], child: const MaterialApp(home: DoubanBrowsePage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(sorts, ['S']);
    expect(find.textContaining('第 1 页'), findsOneWidget);
    await tester.tap(find.textContaining('排序: 高分优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('近期热度').last);
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(sorts, ['S', 'U']);
    expect(find.textContaining('排序: 近期热度'), findsOneWidget);
    expect(find.textContaining('第 1 页'), findsOneWidget);
  });

  testWidgets('failed next page leaves the current page visible',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final starts = <String>[];
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: true),
      )),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider
          .overrideWithValue(DoubanApiClient(MockClient((request) async {
        final start = request.url.queryParameters['start']!;
        starts.add(start);
        if (start == '20') return http.Response('failure', 503);
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'items': [
                {'id': '123', 'title': '第一页影片', 'type': 'movie', 'year': '2023'}
              ],
              'total': 40,
            })),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }))),
    ], child: const MaterialApp(home: DoubanBrowsePage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 页'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('下一页'));
    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(starts, ['0', '20']);
    expect(find.textContaining('第 1 页'), findsOneWidget);
    expect(find.textContaining('请求失败'), findsOneWidget);
  });

  testWidgets('series and variety display separate genre tags', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tags = <String>[];
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: true),
      )),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider.overrideWithValue(DoubanApiClient(MockClient(
        (request) async {
          tags.add(request.url.queryParameters['tags']!);
          return http.Response.bytes(
              utf8.encode(jsonEncode({
                'items': [],
                'total': 0,
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
                        'tags': ['悬疑']
                      },
                      {
                        'text': '综艺',
                        'tags': ['真人秀']
                      },
                    ]
                  }
                ]
              })),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8'
              });
        },
      ))),
    ], child: const MaterialApp(home: DoubanBrowsePage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('电视剧'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(tags, ['', '电视剧']);
    await tester.tap(find.textContaining('类型: 全部'));
    await tester.pumpAndSettle();
    expect(find.text('悬疑'), findsOneWidget);
    expect(find.text('类型'), findsNothing);
    expect(find.text('综艺'), findsOneWidget);
    await tester.tap(find.text('悬疑'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(tags.last, '电视剧,悬疑');
    await tester.pumpAndSettle();
    await tester.tap(find.text('综艺'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(tags.last, '综艺');
    await tester.tap(find.textContaining('类型: 全部'));
    await tester.pumpAndSettle();
    expect(find.text('真人秀'), findsOneWidget);
    expect(find.text('悬疑'), findsNothing);
    await tester.tap(find.text('真人秀'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(tags.last, '综艺,真人秀');
  });

  testWidgets('returning to a cached page restores its earlier IDs',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final starts = <String>[];
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: true),
      )),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider.overrideWithValue(DoubanApiClient(MockClient(
        (request) async {
          final start = request.url.queryParameters['start']!;
          starts.add(start);
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'items': start == '0'
                  ? [
                      {'id': '1', 'title': '首屏作品', 'type': 'movie'}
                    ]
                  : [
                      {'id': '1', 'title': '首屏作品', 'type': 'movie'},
                      {'id': '2', 'title': '次页作品', 'type': 'movie'},
                      {'id': '2', 'title': '次页作品', 'type': 'movie'},
                    ],
              'total': 41,
            })),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        },
      ))),
    ], child: const MaterialApp(home: DoubanBrowsePage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('下一页'));
    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('次页作品'), findsOneWidget);
    expect(find.text('首屏作品'), findsNothing);
    await tester.ensureVisible(find.byTooltip('上一页'));
    await tester.tap(find.byTooltip('上一页'));
    await tester.pumpAndSettle();
    expect(find.text('首屏作品'), findsOneWidget);
    expect(starts, ['0', '20']);
  });

  testWidgets('rapid sort changes only request the final pending selection',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final first = Completer<http.Response>();
    final sorts = <String>[];
    http.Response page() => http.Response.bytes(
          utf8.encode(jsonEncode({'items': [], 'total': 0})),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
    await tester.pumpWidget(ProviderScope(overrides: [
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: true),
      )),
      isTelevisionProvider.overrideWith((ref) => false),
      doubanApiClientProvider.overrideWithValue(DoubanApiClient(MockClient(
        (request) {
          sorts.add(request.url.queryParameters['sort']!);
          return sorts.length == 1 ? first.future : Future.value(page());
        },
      ))),
    ], child: const MaterialApp(home: DoubanBrowsePage())));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(sorts, ['S']);
    await tester.tap(find.textContaining('排序: 高分优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('近期热度').last);
    await tester.pump();
    await tester.tap(find.textContaining('排序: 近期热度'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首映时间').last);
    await tester.pump();
    expect(sorts, ['S']);
    first.complete(page());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(sorts, ['S', 'R']);
    expect(find.textContaining('排序: 首映时间'), findsOneWidget);
  });
}

void _noop() {}

class _RatingCountApiClient extends DoubanApiClient {
  _RatingCountApiClient()
      : super(MockClient((_) async => http.Response('{}', 200)));

  final browseStarts = <String>[];
  int candidateRequests = 0;

  @override
  Future<DoubanBrowsePageData> fetchBrowsePage(
    DoubanBrowseQuery query, {
    int start = 0,
  }) async {
    browseStarts.add('$start');
    final entries = start == 0
        ? List.generate(
            20,
            (index) => DoubanEntry(
              id: '${index + 1}',
              title: '作品${index + 1}',
              year: 0,
              posterUrl: '',
              note: '',
              ratingLabel: '',
              ratingCount: 12000,
              subjectType: 'movie',
            ),
          )
        : <DoubanEntry>[];
    return DoubanBrowsePageData(
      entries: entries,
      start: start,
      rawCount: entries.length,
      total: 20,
    );
  }

  @override
  Future<List<DoubanEntry>> fetchBrowseEntries(
    DoubanBrowseQuery query, {
    required int minimumRatingCount,
    int requestLimit = 50,
  }) async {
    candidateRequests++;
    return List.generate(
      40,
      (index) => DoubanEntry(
        id: '${index + 1}',
        title: '作品${index + 1}',
        year: 0,
        posterUrl: '',
        note: '',
        ratingLabel: '',
        ratingCount: 12000,
        subjectType: 'movie',
      ),
    );
  }
}
