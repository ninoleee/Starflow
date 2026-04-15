import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/playback/data/online_subtitle_provider_protocol.dart';
import 'package:starflow/features/playback/domain/online_subtitle_structured_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

void main() {
  group('AssrtStructuredProvider', () {
    test('hydrates ASSRT API results into direct subtitle hits', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.url.path == '/v1/sub/search') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 0,
                'sub': {
                  'subs': [
                    {
                      'id': 1001,
                      'native_name': '保护者',
                      'videoname': 'The.Protector.S01E01.1080p.WEB-DL',
                      'down_count': 18,
                    },
                  ],
                },
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path == '/v1/sub/detail') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 0,
                'sub': {
                  'id': 1001,
                  'title': '保护者',
                  'native_name': '保护者',
                  'videoname': 'The.Protector.S01E01.1080p.WEB-DL',
                  'subtype': 'ASS',
                  'upload_time': '2026-04-15 10:00:00',
                  'down_count': 77,
                  'vote_score': 8.5,
                  'lang': {'desc': '简体中文'},
                  'producer': {'source': '字幕组'},
                  'filelist': [
                    {
                      'f': 'The.Protector.S01E01.chs.ass',
                      's': 12345,
                      'url': 'https://cdn.assrt.net/files/protector.chs.ass',
                    },
                  ],
                  'url': 'https://cdn.assrt.net/files/protector.package.zip',
                },
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('', 404);
      });

      final provider = AssrtStructuredProvider(
        client,
        config: const AssrtProviderConfig(
          enabled: true,
          token: 'test-token',
        ),
      );

      final results = await provider.search(
        const OnlineSubtitleSearchRequest(
          query: '保护者 S01E01',
          title: '保护者',
          seasonNumber: 1,
          episodeNumber: 1,
          filePath: r'C:\Video\The.Protector.S01E01.1080p.WEB-DL.mkv',
        ),
      );

      expect(requests, hasLength(2));
      expect(requests.first.url.path, '/v1/sub/search');
      expect(requests.first.url.queryParameters['is_file'], '1');
      expect(requests.first.url.queryParameters['no_muxer'], '1');
      expect(requests.first.url.queryParameters['filelist'], '1');
      expect(
        requests.first.url.queryParameters['q'],
        contains('The Protector S01E01'),
      );
      expect(requests.last.url.path, '/v1/sub/detail');
      expect(requests.last.url.queryParameters['id'], '1001');

      expect(results, hasLength(1));
      expect(results.first.source, OnlineSubtitleSource.assrt);
      expect(results.first.title, '保护者');
      expect(results.first.languageLabel, '简体中文');
      expect(results.first.downloadCount, 77);
      expect(results.first.downloadUrl,
          'https://cdn.assrt.net/files/protector.chs.ass');
      expect(results.first.packageName, 'The.Protector.S01E01.chs.ass');
      expect(results.first.packageKind, SubtitlePackageKind.subtitleFile);
    });

    test('falls back to package download when detail has no direct files',
        () async {
      final client = MockClient((request) async {
        if (request.url.path == '/v1/sub/search') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 0,
                'sub': {
                  'subs': [
                    {
                      'id': 2002,
                      'native_name': '地球脉动',
                      'videoname': 'Planet Earth',
                      'down_count': 9,
                    },
                  ],
                },
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path == '/v1/sub/detail') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 0,
                'sub': {
                  'id': 2002,
                  'title': '地球脉动',
                  'videoname': 'Planet Earth',
                  'filename': 'planet.earth.package.zip',
                  'lang': {'desc': '中英双语'},
                  'filelist': const [],
                  'url': 'https://cdn.assrt.net/files/planet.earth.package.zip',
                },
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('', 404);
      });

      final provider = AssrtStructuredProvider(
        client,
        config: const AssrtProviderConfig(
          enabled: true,
          token: 'test-token',
        ),
      );

      final results = await provider.search(
        const OnlineSubtitleSearchRequest(
          query: '地球脉动',
          title: '地球脉动',
        ),
      );

      expect(results, hasLength(1));
      expect(results.first.title, '地球脉动');
      expect(results.first.packageName, 'planet.earth.package.zip');
      expect(results.first.packageKind, SubtitlePackageKind.zipArchive);
      expect(results.first.downloadUrl,
          'https://cdn.assrt.net/files/planet.earth.package.zip');
    });
  });
}
