import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/mock_search_repository.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

http.Response _response(Object value) => http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      200,
      headers: {'content-type': 'application/json'},
    );

http.Response _valid115() => _response({
      'state': true,
      'data': {
        'count': 1,
        'list': [
          {'fid': '1'}
        ]
      },
    });

Future<void> _pumpSearch(
  WidgetTester tester, {
  required SearchRepository repository,
  required Cloud115SaveClient cloud115,
  required QuarkSaveClient quark,
  String cookie115 = 'UID=test;',
  bool multipleProviders = false,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      isTelevisionProvider.overrideWith((ref) => false),
      searchRepositoryProvider.overrideWithValue(repository),
      cloud115SaveClientProvider.overrideWithValue(cloud115),
      quarkSaveClientProvider.overrideWithValue(quark),
      appSettingsProvider.overrideWithValue(AppSettings(
        mediaSources: const [],
        doubanAccount: const DoubanAccountConfig(enabled: false),
        homeModules: const [],
        searchProviders: [
          const SearchProviderConfig(
            id: 'online',
            name: 'Online',
            kind: SearchProviderKind.panSou,
            endpoint: 'https://example.test',
            enabled: true,
            allowedCloudTypes: ['quark', '115'],
          ),
          if (multipleProviders)
            const SearchProviderConfig(
              id: 'second',
              name: 'Second',
              kind: SearchProviderKind.cloudSaver,
              endpoint: 'https://second.test',
              enabled: true,
              allowedCloudTypes: ['quark', '115'],
            ),
        ],
        taskMaxConcurrency: 1,
        networkStorage: NetworkStorageConfig(
          cloud115Cookie: cookie115,
          quarkCookie: 'kps=test;',
        ),
      )),
    ],
    child: const MaterialApp(home: SearchPage(initialQuery: 'old')),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  testWidgets('Quark variants from multiple providers validate only once',
      (tester) async {
    final secondProvider = Completer<SearchFetchResult>();
    final pending = Completer<http.Response>();
    var tokenRequests = 0;
    var detailRequests = 0;
    await _pumpSearch(
      tester,
      multipleProviders: true,
      repository: _ProviderSearchRepository(secondProvider.future, [
        _result('first', 'https://pan.quark.cn/s/AbC123')
            .copyWith(password: 'abcd'),
      ]),
      cloud115: Cloud115SaveClient(MockClient((_) async => fail('Not 115'))),
      quark: QuarkSaveClient(MockClient((request) {
        if (request.url.path.endsWith('/token')) {
          tokenRequests++;
          final body = jsonDecode(request.body) as Map;
          expect(body['pwd_id'], 'AbC123');
          expect(body['passcode'], 'abcd');
          return Future.value(_response({
            'code': 0,
            'data': {'stoken': 'test'}
          }));
        }
        detailRequests++;
        return pending.future;
      })),
    );
    secondProvider.complete(SearchFetchResult(items: [
      _result('second', 'http://pan.quark.cn/s/AbC123/?pwd=abcd&from=search'),
      _result('third', 'https://pan.quark.cn/s/AbC123?utm_source=pansou'),
    ], filteredCount: 0));
    await tester.pump();
    pending.complete(_response({
      'code': 0,
      'data': {
        'list': [
          {'fid': '1'}
        ]
      }
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(tokenRequests, 1);
    expect(detailRequests, 1);
    expect(find.text('资源 first'), findsOneWidget);
    expect(find.text('资源 second'), findsNothing);
    expect(find.textContaining('结果 1 条 · 过滤 2 条'), findsOneWidget);
  });

  for (final alreadyFinished in [false, true]) {
    testWidgets(
        'Quark duplicate fills missing passcode, finished=$alreadyFinished',
        (tester) async {
      final secondProvider = Completer<SearchFetchResult>();
      final pending = Completer<http.Response>();
      final passcodes = <String>[];
      await _pumpSearch(
        tester,
        multipleProviders: true,
        repository: _ProviderSearchRepository(secondProvider.future, [
          _result('first', 'https://pan.quark.cn/s/abc'),
        ]),
        cloud115: Cloud115SaveClient(MockClient((_) async => fail('Not 115'))),
        quark: QuarkSaveClient(MockClient((request) {
          if (request.url.path.endsWith('/token')) {
            final passcode =
                (jsonDecode(request.body) as Map)['passcode'] as String;
            passcodes.add(passcode);
            return passcode.isEmpty
                ? pending.future
                : Future.value(_response({
                    'code': 0,
                    'data': {'stoken': 'test'}
                  }));
          }
          return Future.value(_response({
            'code': 0,
            'data': {
              'list': [
                {'fid': '1'}
              ]
            }
          }));
        })),
      );
      expect(passcodes, ['']);
      final invalid = _response({'code': 41001, 'message': '提取码错误'});
      if (alreadyFinished) {
        pending.complete(invalid);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
      }
      secondProvider.complete(SearchFetchResult(items: [
        _result('second', 'http://pan.quark.cn/s/abc?from=search')
            .copyWith(password: 'abcd'),
      ], filteredCount: 0));
      await tester.pump();
      if (!alreadyFinished) pending.complete(invalid);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(passcodes, ['', 'abcd']);
      expect(find.text('资源 first'), findsOneWidget);
      expect(find.text('资源 second'), findsNothing);
      expect(find.text('提取码 abcd'), findsOneWidget);
      expect(find.textContaining('结果 1 条 · 过滤 1 条'), findsOneWidget);
    });
  }

  for (final alreadyFinished in [false, true]) {
    testWidgets(
        'later provider fills missing code, validation finished=$alreadyFinished',
        (tester) async {
      final secondProvider = Completer<SearchFetchResult>();
      final firstValidation = Completer<http.Response>();
      final codes = <String>[];
      await _pumpSearch(
        tester,
        multipleProviders: true,
        repository: _ProviderSearchRepository(secondProvider.future, [
          _result('first', 'https://115.com/s/abc'),
        ]),
        quark: QuarkSaveClient(MockClient((_) async => fail('Not Quark'))),
        cloud115: Cloud115SaveClient(MockClient((request) {
          final code = request.url.queryParameters['receive_code']!;
          codes.add(code);
          return code.isEmpty
              ? firstValidation.future
              : Future.value(_valid115());
        })),
      );
      expect(codes, ['']);
      final invalid = _response({'state': false, 'error': '接收码错误'});
      if (alreadyFinished) {
        firstValidation.complete(invalid);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
      }
      secondProvider.complete(SearchFetchResult(items: [
        _result('later', 'https://115cdn.com/s/abc?password=abcd'),
      ], filteredCount: 0));
      await tester.pump();
      if (!alreadyFinished) firstValidation.complete(invalid);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(codes, ['', 'abcd']);
      expect(find.text('资源 first'), findsOneWidget);
      expect(find.text('资源 later'), findsNothing);
      expect(find.text('提取码 abcd'), findsOneWidget);
      expect(find.textContaining('结果 1 条 · 过滤 1 条'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  }

  testWidgets('same-share aliases from multiple providers validate only once',
      (tester) async {
    final secondProvider = Completer<SearchFetchResult>();
    final pending = Completer<http.Response>();
    var validations = 0;
    await _pumpSearch(
      tester,
      multipleProviders: true,
      repository: _ProviderSearchRepository(secondProvider.future, [
        _result('first', 'https://115.com/s/abc?password=abcd'),
      ]),
      quark: QuarkSaveClient(MockClient((_) async => fail('Not Quark'))),
      cloud115: Cloud115SaveClient(MockClient((request) {
        validations++;
        return pending.future;
      })),
    );
    secondProvider.complete(SearchFetchResult(items: [
      _result('second', 'https://115cdn.com/s/abc?password=abcd'),
      _result('third', 'https://anxia.com/s/abc?password=abcd&from=search'),
    ], filteredCount: 0));
    await tester.pump();
    pending.complete(_valid115());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(validations, 1);
    expect(find.text('资源 first'), findsOneWidget);
    expect(find.text('资源 second'), findsNothing);
    expect(find.textContaining('结果 1 条 · 过滤 2 条'), findsOneWidget);
  });

  testWidgets('115 and Quark share concurrency and deduplicate validation',
      (tester) async {
    final quarkPending = Completer<http.Response>();
    final cloud115Pending = Completer<http.Response>();
    final requests = <String>[];
    final cloud115 = Cloud115SaveClient(MockClient((request) {
      requests.add('115');
      expect(request.method, 'GET');
      return cloud115Pending.future;
    }));
    final quark = QuarkSaveClient(MockClient((request) {
      if (request.url.path.endsWith('/token')) {
        return Future.value(_response({
          'code': 0,
          'data': {'stoken': 'test'}
        }));
      }
      requests.add('quark');
      return quarkPending.future;
    }));
    await _pumpSearch(tester,
        cloud115: cloud115,
        quark: quark,
        repository: _SearchRepository((query) => [
              _result('quark', 'https://pan.quark.cn/s/abc'),
              _result('115', 'https://115cdn.com/s/abc'),
              _result('duplicate', 'https://anxia.com/s/abc?password=abcd'),
            ]));
    expect(requests, ['quark']);
    expect(find.text('网盘类型'), findsNothing);
    quarkPending.complete(_response({'code': 41001, 'message': '分享已取消'}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(requests, ['quark', '115']);
    expect(find.text('115 网盘'), findsNothing);
    cloud115Pending.complete(_valid115());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('115 网盘'), findsOneWidget);
    expect(find.text('夸克网盘'), findsNothing);
    expect(find.text('资源 115'), findsOneWidget);
    expect(find.textContaining('过滤 2 条'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('old 115 validation cannot insert results into a new search',
      (tester) async {
    final oldResponse = Completer<http.Response>();
    final newResponse = Completer<http.Response>();
    final requests = <String>[];
    await _pumpSearch(tester,
        cloud115: Cloud115SaveClient(MockClient((request) {
      final code = request.url.queryParameters['share_code']!;
      requests.add(code);
      return code == 'old' ? oldResponse.future : newResponse.future;
    })),
        quark: QuarkSaveClient(
            MockClient((_) async => fail('Not a Quark result'))),
        repository: _SearchRepository((query) => [
              _result(query, 'https://115cdn.com/s/$query'),
            ]));
    expect(requests, ['old']);
    await tester.enterText(find.byType(TextField), 'new');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    expect(requests, ['old']);
    oldResponse.complete(_valid115());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(requests, ['old', 'new']);
    expect(find.text('资源 old'), findsNothing);
    expect(find.text('115 网盘'), findsNothing);
    newResponse.complete(_valid115());
    await tester.pumpAndSettle();
    expect(find.text('资源 new'), findsOneWidget);
    expect(find.text('资源 old'), findsNothing);
    expect(find.text('115 网盘'), findsOneWidget);
    expect(find.textContaining('结果 1 条 · 过滤 0 条'), findsOneWidget);
  });

  testWidgets('leaving search cancels queued 115 checks', (tester) async {
    final pending = Completer<http.Response>();
    var calls = 0;
    await _pumpSearch(tester, cloud115: Cloud115SaveClient(MockClient((_) {
      calls++;
      return pending.future;
    })),
        quark: QuarkSaveClient(
            MockClient((_) async => fail('Not a Quark result'))),
        repository: _SearchRepository((query) => [
              _result('one', 'https://115cdn.com/s/one'),
              _result('two', 'https://115cdn.com/s/two'),
            ]));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(_valid115());
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  for (final cookie in ['', 'expired-cookie']) {
    testWidgets(
        '115 missing or expired credentials retain unverified results: $cookie',
        (tester) async {
      var calls = 0;
      await _pumpSearch(tester, cookie115: cookie,
          cloud115: Cloud115SaveClient(MockClient((_) async {
        calls++;
        return _response({'state': false, 'error': '登录已过期'});
      })),
          quark: QuarkSaveClient(
              MockClient((_) async => fail('Not a Quark result'))),
          repository: _SearchRepository((query) => [
                _result('115', 'https://115cdn.com/s/abc'),
              ]));
      await tester.pumpAndSettle();
      expect(calls, cookie.isEmpty ? 0 : 1);
      expect(find.text('资源 115'), findsOneWidget);
      expect(find.text('链接暂未验证'), findsOneWidget);
      expect(find.text('115 网盘'), findsOneWidget);
    });
  }
}

SearchResult _result(String id, String url) => SearchResult(
      id: id,
      title: '资源 $id',
      posterUrl: '',
      providerId: 'online',
      providerName: 'Online',
      quality: '',
      sizeLabel: '',
      seeders: 0,
      summary: '',
      resourceUrl: url,
    );

class _SearchRepository implements SearchRepository {
  _SearchRepository(this.results);
  final List<SearchResult> Function(String query) results;
  @override
  Future<SearchFetchResult> searchOnline(String query,
          {required SearchProviderConfig provider}) async =>
      SearchFetchResult(items: results(query), filteredCount: 0);
  @override
  Future<SearchFetchResult> searchLocal(String query,
          {String? sourceId, String? sectionId, int limit = 60}) async =>
      SearchFetchResult(items: const [], filteredCount: 0);
}

class _ProviderSearchRepository extends _SearchRepository {
  _ProviderSearchRepository(this.second, List<SearchResult> first)
      : super((_) => first);
  final Future<SearchFetchResult> second;
  @override
  Future<SearchFetchResult> searchOnline(String query,
          {required SearchProviderConfig provider}) =>
      provider.id == 'second'
          ? second
          : super.searchOnline(query, provider: provider);
}
