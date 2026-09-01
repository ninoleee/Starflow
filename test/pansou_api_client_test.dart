import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/search/data/pansou_api_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';

void main() {
  group('PanSouApiClient', () {
    test('allows slow searches to exceed the standard request timeout',
        () async {
      final inner = MockClient((request) async {
        expect(request.url.path, '/api/search');
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {'merged_by_type': {}}
          }),
          200,
        );
      });
      final standardClient = StarflowHttpClient(
        inner,
        requestTimeout: const Duration(milliseconds: 10),
      );
      final searchClient = StarflowHttpClient(
        inner,
        requestTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(standardClient.close);
      addTearDown(searchClient.close);
      final client = PanSouApiClient(
        standardClient,
        searchClient: searchClient,
      );

      final results = await client.search(
        '金色',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
          parserHint: 'pansou-api',
        ),
      );

      expect(results, isEmpty);
    });

    test('keeps health checks on the standard request timeout', () async {
      final standardClient = StarflowHttpClient(
        MockClient((request) async {
          expect(request.url.path, '/api/health');
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }),
        requestTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(standardClient.close);
      final client = PanSouApiClient(standardClient);

      await expectLater(
        client.testConnection(
          provider: const SearchProviderConfig(
            id: 'pansou-api',
            name: 'PanSou',
            kind: SearchProviderKind.panSou,
            endpoint: 'https://so.252035.xyz',
            enabled: true,
            parserHint: 'pansou-api',
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('replaces malformed UTF-8 bytes and keeps valid search results',
        () async {
      final prefix = utf8.encode(
        '{"code":0,"data":{"merged_by_type":{"quark":['
        '{"url":"https://pan.quark.cn/s/demo","password":"",'
        '"note":"金',
      );
      final suffix = utf8.encode(
        '色","datetime":"","source":"","images":[]}]}}}',
      );
      final client = PanSouApiClient(
        MockClient((request) async {
          return http.Response.bytes(
            <int>[...prefix, 0xe9, ...suffix],
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final results = await client.search(
        '金色',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
          parserHint: 'pansou-api',
        ),
      );

      expect(results, hasLength(1));
      expect(results.single.resourceUrl, 'https://pan.quark.cn/s/demo');
      expect(results.single.title, contains('金'));
      expect(results.single.title, contains('色'));
    });

    test('maps merged_by_type response into search results', () async {
      final client = PanSouApiClient(
        MockClient((request) async {
          expect(request.url.toString(), 'https://so.252035.xyz/api/search');
          expect(request.headers['Authorization'], isNull);
          expect(jsonDecode(request.body), {
            'kw': '速度与激情',
            'res': 'merge',
          });

          return http.Response.bytes(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'code': 0,
                  'message': 'success',
                  'data': {
                    'merged_by_type': {
                      'baidu': [
                        {
                          'url': 'https://pan.baidu.com/s/1abcdef',
                          'password': '1234',
                          'note': '速度与激情全集1-10',
                          'datetime': '2023-06-10T14:23:45Z',
                          'source': 'tg:tgsearchers3',
                          'images': ['https://cdn.example.com/poster.jpg'],
                        },
                      ],
                      'quark': [
                        {
                          'url': 'https://pan.quark.cn/s/xxxx',
                          'password': '',
                          'note': '速度与激情外传',
                          'datetime': '2023-06-11T10:00:00Z',
                          'source': 'plugin:jikepan',
                          'images': [],
                        },
                      ],
                    },
                  },
                }),
              ),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final results = await client.search(
        '速度与激情',
        provider: const SearchProviderConfig(
          id: 'pansou-api',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://so.252035.xyz',
          enabled: true,
          parserHint: 'pansou-api',
        ),
      );

      expect(results, hasLength(2));
      expect(results.first.quality, '百度网盘');
      expect(results.first.password, '1234');
      expect(results.first.posterUrl, 'https://cdn.example.com/poster.jpg');
      expect(results.first.source, 'tg:tgsearchers3');
      expect(results.last.quality, '夸克网盘');
      expect(results.last.sizeLabel, '免提取码');
    });

    test('logs in before search when username and password are provided',
        () async {
      final requestedPaths = <String>[];
      final client = PanSouApiClient(
        MockClient((request) async {
          requestedPaths.add(request.url.path);

          if (request.url.path == '/api/auth/login') {
            expect(jsonDecode(request.body), {
              'username': 'admin',
              'password': 'admin123',
            });
            return http.Response(
              jsonEncode({'token': 'jwt-token-123'}),
              200,
            );
          }

          expect(request.headers['Authorization'], 'Bearer jwt-token-123');
          return http.Response.bytes(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'merged_by_type': {
                    'baidu': [
                      {
                        'url': 'https://pan.baidu.com/s/demo',
                        'password': '',
                        'note': '测试资源',
                        'datetime': '2023-06-10T14:23:45Z',
                        'source': 'plugin:demo',
                        'images': [],
                      },
                    ],
                  },
                }),
              ),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final results = await client.search(
        '测试',
        provider: const SearchProviderConfig(
          id: 'self-hosted-pansou',
          name: '自建 PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'http://localhost:8888',
          enabled: true,
          parserHint: 'pansou-api',
          username: 'admin',
          password: 'admin123',
        ),
      );

      expect(results, hasLength(1));
      expect(requestedPaths, ['/api/auth/login', '/api/search']);
    });

    test('prefers fresh login when a configured token is stale', () async {
      final requestedPaths = <String>[];
      final client = PanSouApiClient(
        MockClient((request) async {
          requestedPaths.add(request.url.path);
          if (request.url.path == '/api/auth/login') {
            expect(request.headers['Authorization'], isNull);
            return http.Response(
              jsonEncode({'token': 'fresh-token'}),
              200,
            );
          }

          expect(request.headers['Authorization'], 'Bearer fresh-token');
          expect(request.headers['Authorization'], isNot('Bearer stale-token'));
          return http.Response.bytes(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'merged_by_type': {
                      'quark': [
                        {
                          'url': 'https://pan.quark.cn/s/fresh',
                          'password': '',
                          'note': '新 Token 搜索结果',
                          'datetime': '',
                          'source': '',
                          'images': [],
                        },
                      ],
                    },
                  },
                }),
              ),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final results = await client.search(
        '开庭',
        provider: const SearchProviderConfig(
          id: 'authenticated-pansou',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://pansou.example.com',
          enabled: true,
          parserHint: 'pansou-api',
          apiKey: 'stale-token',
          username: 'admin',
          password: 'current-password',
        ),
      );

      expect(results.single.title, '新 Token 搜索结果');
      expect(requestedPaths, ['/api/auth/login', '/api/search']);
    });

    test('uses configured token when login credentials are incomplete',
        () async {
      final client = PanSouApiClient(
        MockClient((request) async {
          expect(request.url.path, '/api/search');
          expect(request.headers['Authorization'], 'Bearer configured-token');
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {'merged_by_type': {}}
            }),
            200,
          );
        }),
      );

      await client.search(
        '开庭',
        provider: const SearchProviderConfig(
          id: 'token-pansou',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://pansou.example.com',
          enabled: true,
          parserHint: 'pansou-api',
          apiKey: 'configured-token',
          username: 'admin',
        ),
      );
    });

    test('accepts nested access token login responses', () async {
      final client = PanSouApiClient(
        MockClient((request) async {
          if (request.url.path == '/api/auth/login') {
            return http.Response(
              jsonEncode({
                'data': {'access_token': 'nested-token'},
              }),
              200,
            );
          }
          expect(request.headers['Authorization'], 'Bearer nested-token');
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {'merged_by_type': {}}
            }),
            200,
          );
        }),
      );

      await client.search(
        '开庭',
        provider: const SearchProviderConfig(
          id: 'nested-token-pansou',
          name: 'PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'https://pansou.example.com',
          enabled: true,
          parserHint: 'pansou-api',
          username: 'admin',
          password: 'current-password',
        ),
      );
    });

    test('falls back to results payload when merged links are absent',
        () async {
      final client = PanSouApiClient(
        MockClient((request) async {
          expect(request.url.toString(), 'http://localhost:8888/api/search');
          return http.Response.bytes(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'total': 1,
                  'results': [
                    {
                      'channel': 'tgsearchers3',
                      'datetime': '2023-06-10T14:23:45Z',
                      'title': '英雄本色',
                      'content': '经典港片资源',
                      'images': ['https://cdn.example.com/hero.jpg'],
                      'links': [
                        {
                          'type': 'quark',
                          'url': 'https://pan.quark.cn/s/hero',
                          'password': '8888',
                          'work_title': '英雄本色 4K',
                        },
                      ],
                    },
                  ],
                }),
              ),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final results = await client.search(
        '英雄本色',
        provider: const SearchProviderConfig(
          id: 'self-hosted-pansou',
          name: '自建 PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'http://localhost:8888',
          enabled: true,
          parserHint: 'pansou-api',
        ),
      );

      expect(results, hasLength(1));
      expect(results.first.title, '英雄本色 4K');
      expect(results.first.quality, '夸克网盘');
      expect(results.first.posterUrl, 'https://cdn.example.com/hero.jpg');
      expect(results.first.password, '8888');
      expect(results.first.source, 'tg:tgsearchers3');
    });

    test('checks health endpoint for connection test', () async {
      final client = PanSouApiClient(
        MockClient((request) async {
          expect(request.url.toString(), 'http://localhost:8888/api/health');
          expect(request.method, 'GET');
          return http.Response.bytes(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'status': 'ok',
                  'auth_enabled': true,
                  'plugins_enabled': true,
                  'plugin_count': 16,
                  'plugins': ['jikepan', 'pan666'],
                  'channels_count': 1,
                  'channels': ['tgsearchers3'],
                }),
              ),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final status = await client.testConnection(
        provider: const SearchProviderConfig(
          id: 'self-hosted-pansou',
          name: '自建 PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'http://localhost:8888',
          enabled: true,
          parserHint: 'pansou-api',
        ),
      );

      expect(status.authEnabled, isTrue);
      expect(status.pluginsEnabled, isTrue);
      expect(status.pluginCount, 16);
      expect(status.channelsCount, 1);
      expect(status.summary, '已启用认证 · 插件 16 · 频道 1');
    });

    test('keeps request body minimal and filters on client side', () async {
      final client = PanSouApiClient(
        MockClient((request) async {
          expect(jsonDecode(request.body), {
            'kw': '英雄本色',
            'res': 'merge',
          });
          return http.Response.bytes(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'merged_by_type': {
                      'quark': [],
                    },
                  },
                }),
              ),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await client.search(
        '英雄本色',
        provider: const SearchProviderConfig(
          id: 'self-hosted-pansou',
          name: '自建 PanSou',
          kind: SearchProviderKind.panSou,
          endpoint: 'http://localhost:8888',
          enabled: true,
          parserHint: 'pansou-api',
          allowedCloudTypes: ['quark', 'aliyun'],
          blockedKeywords: ['枪版', '预告'],
        ),
      );
    });
  });
}
