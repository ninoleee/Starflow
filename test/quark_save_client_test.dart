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
            return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {'stoken': 'st-1'}
                }),
                200);
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
            return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {'task_id': 'task-9'}
                }),
                200);
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
      expect(result.targetFolderPath, '/');
      expect(requests.map((item) => item.path), [
        '/1/clouddrive/share/sharepage/token',
        '/1/clouddrive/share/sharepage/detail',
        '/1/clouddrive/share/sharepage/save',
      ]);
    });

    test('creates or reuses a child folder before saving', () async {
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'stoken': 'st-2'}
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'list': [
                    {'fid': 'fid-9', 'share_fid_token': 'token-9'},
                  ],
                },
                'metadata': {'_total': 1},
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            expect(request.url.queryParameters['pdir_fid'], 'dir-parent');
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'list': []},
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/file') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['pdir_fid'], 'dir-parent');
            expect(body['file_name'], '三体');
            expect(body['dir_path'], '/电影/三体');
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'fid': 'dir-child'},
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['to_pdir_fid'], 'dir-child');
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'task_id': 'task-10'}
              }),
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      final result = await client.saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc123',
        cookie: 'kps=test; sign=test; vcode=test;',
        toPdirFid: 'dir-parent',
        toPdirPath: '/电影',
        saveFolderName: '三体',
      );

      expect(result.taskId, 'task-10');
      expect(result.savedCount, 1);
      expect(result.targetFolderPath, '/电影/三体');
    });

    test('does not create a duplicate child folder when target already matches',
        () async {
      var createDirectoryCalled = false;
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'stoken': 'st-3'}
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'list': [
                    {'fid': 'fid-11', 'share_fid_token': 'token-11'},
                  ],
                },
                'metadata': {'_total': 1},
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/file') {
            createDirectoryCalled = true;
            return http.Response('unexpected', 500);
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['to_pdir_fid'], 'dir-santi');
            expect(body['fid_list'], ['fid-11']);
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'task_id': 'task-11'}
              }),
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      final result = await client.saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc123',
        cookie: 'kps=test; sign=test; vcode=test;',
        toPdirFid: 'dir-santi',
        toPdirPath: '/电影/三体',
        saveFolderName: '三体',
      );

      expect(createDirectoryCalled, isFalse);
      expect(result.taskId, 'task-11');
      expect(result.targetFolderPath, '/电影/三体');
    });

    test('flattens a single top-level shared folder into the target folder',
        () async {
      final detailRequests = <String>[];
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'stoken': 'st-4'}
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'list': []},
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/file') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'fid': 'dir-child'}
              }),
              200,
            );
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            final pdirFid = request.url.queryParameters['pdir_fid'] ?? '';
            detailRequests.add(pdirFid);
            if (pdirFid == '0') {
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'list': [
                      {
                        'fid': 'root-folder',
                        'share_fid_token': 'root-token',
                        'dir': true,
                      },
                    ],
                  },
                  'metadata': {'_total': 1},
                }),
                200,
              );
            }
            if (pdirFid == 'root-folder') {
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'list': [
                      {
                        'fid': 'nested-file',
                        'share_fid_token': 'nested-token',
                        'dir': false,
                      },
                      {
                        'fid': 'nested-dir',
                        'share_fid_token': 'nested-dir-token',
                        'dir': true,
                      },
                    ],
                  },
                  'metadata': {'_total': 2},
                }),
                200,
              );
            }
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['to_pdir_fid'], 'dir-child');
            expect(body['fid_list'], ['nested-file', 'nested-dir']);
            expect(
                body['fid_token_list'], ['nested-token', 'nested-dir-token']);
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'task_id': 'task-12'}
              }),
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      final result = await client.saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc123',
        cookie: 'kps=test; sign=test; vcode=test;',
        toPdirFid: 'dir-parent',
        toPdirPath: '/电影',
        saveFolderName: '流浪地球',
      );

      expect(detailRequests, ['0', 'root-folder']);
      expect(result.taskId, 'task-12');
      expect(result.savedCount, 2);
      expect(result.targetFolderPath, '/电影/流浪地球');
    });
  });
}
