import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';

void main() {
  group('QuarkSaveClient', () {
    test('lists directories for folder picker', () async {
      final client = QuarkSaveClient(
        MockClient((request) async {
          expect(request.url.path, '/1/clouddrive/file/sort');
          expect(request.url.queryParameters['pdir_fid'], '0');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'dir-1',
                      'dir': true,
                      'file_name': '电影',
                      'file_path': '/电影',
                    },
                    {
                      'fid': 'file-1',
                      'dir': false,
                      'file_name': '跳过.mkv',
                    },
                  ],
                },
              }),
            ),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final directories = await client.listDirectories(
        cookie: 'kps=test; sign=test; vcode=test;',
      );

      expect(directories.length, 1);
      expect(directories.single.fid, 'dir-1');
      expect(directories.single.path, '/电影');
    });

    test('saves a quark share link to root directory', () async {
      final requests = <Uri>[];
      final client = QuarkSaveClient(
        MockClient((request) async {
          requests.add(request.url);
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['pwd_id'], 'abc123');
            expect(body['passcode'], 'pw88');
            return http.Response(jsonEncode({'code': 0, 'data': {'stoken': 'st-1'}}), 200);
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            expect(request.url.queryParameters['pwd_id'], 'abc123');
            expect(request.url.queryParameters['stoken'], 'st-1');
            expect(request.url.queryParameters['pdir_fid'], '0');
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'list': [
                    {'fid': 'fid-1', 'share_fid_token': 'token-1'},
                    {'fid': 'fid-2', 'share_fid_token': 'token-2'},
                  ],
                },
                'metadata': {'_total': 2},
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['to_pdir_fid'], '0');
            expect(body['pwd_id'], 'abc123');
            expect(body['stoken'], 'st-1');
            expect(body['fid_list'], ['fid-1', 'fid-2']);
            expect(body['fid_token_list'], ['token-1', 'token-2']);
            return http.Response(jsonEncode({'code': 0, 'data': {'task_id': 'task-9'}}), 200);
          }
          return http.Response('Not found', 404);
        }),
      );

      final result = await client.saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc123?pwd=pw88',
        cookie: 'kps=test; sign=test; vcode=test;',
      );

      expect(result.taskId, 'task-9');
      expect(result.savedCount, 2);
      expect(requests.map((item) => item.path), [
        '/1/clouddrive/share/sharepage/token',
        '/1/clouddrive/share/sharepage/detail',
        '/1/clouddrive/share/sharepage/save',
      ]);
    });
  });
}
