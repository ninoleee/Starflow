import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/pansou_api_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';

void main() {
  group('PanSouApiClient', () {
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
  });
}
