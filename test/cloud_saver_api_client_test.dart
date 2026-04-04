import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/cloud_saver_api_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';

void main() {
  group('CloudSaverApiClient', () {
    test('maps grouped search response into search results', () async {
      final client = CloudSaverApiClient(
        MockClient((request) async {
          expect(
            request.url.toString(),
            'http://localhost:3000/api/search?keyword=%E8%8B%B1%E9%9B%84%E6%9C%AC%E8%89%B2',
          );
          expect(request.method, 'GET');
          return http.Response.bytes(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'success': true,
                  'code': 0,
                  'data': [
                    {
                      'id': 'channel-1',
                      'list': [
                        {
                          'title': '英雄本色',
                          'content': '访问码: 8888',
                          'image': 'https://cdn.example.com/hero.jpg',
                          'cloudLinks': [
                            'https://pan.quark.cn/s/hero',
                            'https://pan.baidu.com/s/1abcd?pwd=9999',
                          ],
                          'cloudType': 'quark',
                          'channel': '电影频道',
                          'pubDate': '2026-04-01T10:00:00Z',
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
          id: 'cloudsaver-main',
          name: 'CloudSaver',
          kind: SearchProviderKind.cloudSaver,
          endpoint: 'http://localhost:3000',
          enabled: true,
          parserHint: 'cloudsaver-api',
        ),
      );

      expect(results, hasLength(2));
      expect(results.first.title, '英雄本色');
      expect(results.first.posterUrl, 'https://cdn.example.com/hero.jpg');
      expect(results.first.source, '电影频道');
      expect(results.first.password, '8888');
      expect(results.last.password, '9999');
    });

    test('logs in before testing connection when credentials are provided',
        () async {
      final requestedPaths = <String>[];
      final client = CloudSaverApiClient(
        MockClient((request) async {
          requestedPaths.add(request.url.path);
          if (request.url.path == '/api/user/login') {
            expect(jsonDecode(request.body), {
              'username': 'admin',
              'password': 'admin123',
            });
            return http.Response(
              jsonEncode({
                'success': true,
                'code': 0,
                'data': {'token': 'cloud-token'},
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }

          expect(request.headers['Authorization'], 'Bearer cloud-token');
          return http.Response(
            jsonEncode({
              'success': true,
              'code': 0,
              'data': [
                {
                  'id': 'channel-1',
                  'list': [1, 2, 3],
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final status = await client.testConnection(
        provider: const SearchProviderConfig(
          id: 'cloudsaver-main',
          name: 'CloudSaver',
          kind: SearchProviderKind.cloudSaver,
          endpoint: 'http://localhost:3000',
          enabled: true,
          username: 'admin',
          password: 'admin123',
          parserHint: 'cloudsaver-api',
        ),
      );

      expect(requestedPaths, ['/api/user/login', '/api/search']);
      expect(status.summary, '已完成认证 · 频道 1 · 结果 3');
    });
  });
}
