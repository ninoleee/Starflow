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

    test(
        'throws explicit rate limit error when ASSRT detail request returns 509',
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
                      'id': 629281,
                      'native_name': '怪奇物语',
                      'videoname': 'Stranger.Things.S01E01',
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
          return http.Response('', 509);
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

      await expectLater(
        () => provider.search(
          const OnlineSubtitleSearchRequest(
            query: '怪奇物语 S01E01',
            title: '怪奇物语',
            seasonNumber: 1,
            episodeNumber: 1,
          ),
        ),
        throwsA(
          predicate(
            (error) =>
                error is StateError &&
                '$error'.contains('ASSRT API 请求过于频繁，请稍后再试'),
          ),
        ),
      );
    });

    test('parses ASSRT detail payload nested under sub.subs', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/v1/sub/search') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 0,
                'sub': {
                  'subs': [
                    {
                      'id': 629281,
                      'native_name': '怪奇物语 第一季',
                      'videoname':
                          'Stranger.Things.S01.720p.BluRay.x264.DD5.1-HDChina',
                      'down_count': 1225,
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
                'sub': {
                  'action': 'detail',
                  'subs': [
                    {
                      'id': 629281,
                      'title': '怪奇物语 第一季',
                      'native_name': '怪奇物语 第一季',
                      'videoname':
                          'Stranger.Things.S01.720p.BluRay.x264.DD5.1-HDChina',
                      'subtype': 'Subrip(srt)',
                      'upload_time': '2020-05-20 21:56:12',
                      'down_count': 1225,
                      'lang': {'desc': '简'},
                      'filelist': [
                        {
                          'url':
                              'http://file1.assrt.net/onthefly/629281/-/1/Stranger.Things.S01E01.720p.BluRay.x264.DD5.1-HDChina.srt?api=1',
                          's': '44KB',
                          'f':
                              'Stranger.Things.S01E01.720p.BluRay.x264.DD5.1-HDChina.srt',
                        },
                      ],
                      'url':
                          'http://file1.assrt.net/download/629281/Stranger.Things.S01.BluRay.rar?api=1',
                    },
                  ],
                  'result': 'succeed',
                },
                'status': 0,
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
          query: '怪奇物语 S01E01',
          title: '怪奇物语',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      );

      expect(results, hasLength(1));
      expect(results.first.title, '怪奇物语 第一季');
      expect(results.first.languageLabel, '简');
      expect(
        results.first.downloadUrl,
        'http://file1.assrt.net/onthefly/629281/-/1/Stranger.Things.S01E01.720p.BluRay.x264.DD5.1-HDChina.srt?api=1',
      );
      expect(
        results.first.packageName,
        'Stranger.Things.S01E01.720p.BluRay.x264.DD5.1-HDChina.srt',
      );
      expect(results.first.packageKind, SubtitlePackageKind.subtitleFile);
    });

    test('uses cleaned remote file name for ASSRT file search query', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'status': 0,
              'sub': {'subs': const []},
            }),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final provider = AssrtStructuredProvider(
        client,
        config: const AssrtProviderConfig(
          enabled: true,
          token: 'test-token',
        ),
      );

      await provider.search(
        const OnlineSubtitleSearchRequest(
          query: '怪奇物语 S01E01',
          title: '怪奇物语',
          seasonNumber: 1,
          episodeNumber: 1,
          filePath:
              'https://example.com/Stranger.Things.S01E01.2160p.WEB-DL.H265.10bit.DDP5.1&DTS5.1.(mkv).strm',
        ),
      );

      expect(requests, isNotEmpty);
      expect(requests.first.url.path, '/v1/sub/search');
      expect(requests.first.url.queryParameters['q'], 'Stranger Things S01E01');
    });

    test(
        'prefers the matching episode file when ASSRT detail contains a season bundle',
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
                      'id': 3003,
                      'native_name': '怪奇物语 第一季',
                      'videoname':
                          'Stranger.Things.S01.720p.BluRay.x264.DD5.1-HDChina',
                      'down_count': 1200,
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
                  'id': 3003,
                  'title': '怪奇物语 第一季',
                  'videoname':
                      'Stranger.Things.S01.720p.BluRay.x264.DD5.1-HDChina',
                  'filelist': [
                    {
                      'f':
                          'Stranger.Things.S01E01.720p.BluRay.x264.DD5.1-HDChina.srt',
                      'url':
                          'https://cdn.assrt.net/files/stranger-things-s01e01.srt',
                    },
                    {
                      'f':
                          'Stranger.Things.S01E02.720p.BluRay.x264.DD5.1-HDChina.srt',
                      'url':
                          'https://cdn.assrt.net/files/stranger-things-s01e02.srt',
                    },
                  ],
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
          query: '怪奇物语 S01E02',
          title: '怪奇物语',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
      );

      expect(results, hasLength(1));
      expect(
        results.first.downloadUrl,
        'https://cdn.assrt.net/files/stranger-things-s01e02.srt',
      );
      expect(
        results.first.packageName,
        'Stranger.Things.S01E02.720p.BluRay.x264.DD5.1-HDChina.srt',
      );
    });
  });
}
