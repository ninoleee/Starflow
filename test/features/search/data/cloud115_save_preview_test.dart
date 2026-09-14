import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';

http.Response _response(Object value) => http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  for (final passwordInUrl in [false, true]) {
    test(
        'read-only paginated nested preview with password in URL=$passwordInUrl',
        () async {
      final requests = <http.Request>[];
      const share = {
        '0': [
          {'cid': '1', 'n': 'Release'}
        ],
        '1': [
          {'cid': '2', 'n': '#Season 1'}
        ],
        '2': [
          {'fid': '3', 'n': '#E01.mkv'},
          {'fid': '4', 'n': '#E02.mkv'},
          {'fid': '5', 'n': 'poster.jpg'},
        ],
      };
      const stored = {
        '10': [
          {'cid': '11', 'n': 'Other'},
          {'cid': '20', 'n': 'SHOW'}
        ],
        '20': [
          {'cid': '21', 'n': 'Season 1'}
        ],
        '21': [
          {'fid': '22', 'n': 'e01.MKV'},
          {'fid': '23', 'n': 'cover.png'}
        ],
      };
      final client = Cloud115SaveClient(MockClient((request) async {
        requests.add(request);
        expect(request.method, 'GET');
        expect(request.followRedirects, isFalse);
        expect(request.url.host, 'webapi.115.com');
        expect(request.headers['cookie'], '115-cookie');
        final isShare = request.url.path == '/share/snap';
        final query = request.url.queryParameters;
        if (isShare) {
          expect(query['share_code'], 'abc');
          expect(query['receive_code'], passwordInUrl ? '1234' : 'abcd');
        } else {
          expect(request.url.path, '/files');
        }
        final rows = (isShare ? share : stored)[query['cid']]!;
        final page = rows.skip(int.parse(query['offset']!)).take(1).toList();
        return _response(isShare
            ? {
                'state': true,
                'data': {'list': page, 'count': rows.length}
              }
            : {'state': true, 'data': page, 'count': rows.length});
      }));
      final result = await client.previewSave(
        shareUrl:
            'https://115cdn.com/s/abc${passwordInUrl ? '?password=1234' : ''}',
        cookie: '115-cookie',
        password: 'abcd',
        folderId: '10',
        folderPath: '/Library/115',
        saveFolderName: 'Show',
        sanitizedNameCharacters: '#',
      );
      expect(result.targetFolderPath, '/Library/115/SHOW');
      expect(result.localFolderExists, isTrue);
      expect(result.missingVideos.single.relativePath, '#Season 1/#E02.mkv');
      expect(result.onlineEntries.where((e) => e.isVideo), hasLength(2));
      expect(result.localEntries.where((e) => e.isVideo), hasLength(1));
      expect(requests.where((r) => r.url.queryParameters['offset'] != '0'),
          hasLength(4));
    });
  }

  test('missing target is read-only and reports all online videos', () async {
    final client = Cloud115SaveClient(MockClient((request) async {
      expect(request.method, 'GET');
      return _response(request.url.path == '/share/snap'
          ? {
              'state': true,
              'data': {
                'count': 1,
                'list': [
                  {'fid': '1', 'n': 'E01.mkv'}
                ]
              },
            }
          : {'state': true, 'count': 0, 'data': []});
    }));
    final result = await client.previewSave(
        shareUrl: 'https://115.com/s/abc',
        cookie: 'test',
        folderPath: '/Library',
        saveFolderName: 'Show');
    expect(result.localFolderExists, isFalse);
    expect(result.targetFolderPath, '/Library/Show');
    expect(result.missingVideos.single.name, 'E01.mkv');
  });

  for (final failure in [
    '405',
    'network',
    'malformed',
    'missing-page',
    'duplicate-id'
  ]) {
    test('preview never turns $failure into no updates', () async {
      var requests = 0;
      final client = Cloud115SaveClient(MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        switch (failure) {
          case '405':
            return http.Response('blocked', 405);
          case 'network':
            throw http.ClientException('offline');
          case 'malformed':
            return _response({'state': true, 'data': {}});
          default:
            return _response({
              'state': true,
              'data': {
                'count': 2,
                'list': requests == 1 || failure == 'duplicate-id'
                    ? [
                        {'fid': '1', 'n': 'E01.mkv'}
                      ]
                    : [],
              }
            });
        }
      }));
      await expectLater(
          client.previewSave(
              shareUrl: 'https://115.com/s/abc',
              cookie: 'test',
              saveFolderName: 'Show'),
          throwsA(isA<CloudSaveException>()));
      expect(requests,
          failure.endsWith('page') || failure == 'duplicate-id' ? 2 : 1);
    });
  }

  test('invalid selected directory fails before network access', () async {
    final client =
        Cloud115SaveClient(MockClient((_) async => fail('No request')));
    await expectLater(
        client.previewSave(
            shareUrl: 'https://115.com/s/abc',
            cookie: 'test',
            folderId: 'invalid',
            saveFolderName: 'Show'),
        throwsA(isA<CloudSaveException>()));
  });
}
