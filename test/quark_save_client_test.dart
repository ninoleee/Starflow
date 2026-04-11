import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';

http.Response _jsonResponse(
  Object? body, {
  int statusCode = 200,
  Map<String, String> headers = const {},
}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers,
    },
  );
}

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

    test('resolves a direct download url with merged cookies', () async {
      final client = QuarkSaveClient(
        MockClient((request) async {
          expect(request.url.path, '/1/clouddrive/file/download');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['fids'], ['video-1']);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'code': 0,
                'data': {
                  'download_list': [
                    {
                      'fid': 'video-1',
                      'download_url':
                          'https://download.example.com/video-1.mkv',
                      'size': 4096,
                    },
                  ],
                },
              }),
            ),
            200,
            headers: const {
              'content-type': 'application/json',
              'set-cookie':
                  '__puus=abc; Path=/, __kp=xyz; Path=/, __puus=abc; Path=/',
            },
          );
        }),
      );

      final resolved = await client.resolveDownload(
        cookie: 'kps=test; sign=test;',
        fid: 'video-1',
      );

      expect(resolved.url, 'https://download.example.com/video-1.mkv');
      expect(resolved.fileSizeBytes, 4096);
      expect(resolved.headers['Cookie'], contains('kps=test'));
      expect(resolved.headers['Cookie'], contains('sign=test'));
      expect(resolved.headers['Cookie'], contains('__puus=abc'));
      expect(resolved.headers['Cookie'], contains('__kp=xyz'));
      expect(resolved.headers['User-Agent'], isNotEmpty);
      expect(resolved.headers['Referer'], 'https://drive-pc.quark.cn');
      expect(resolved.headers['Origin'], 'https://drive-pc.quark.cn');
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
            return _jsonResponse({
              'code': 0,
              'data': {'stoken': 'st-1'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            expect(request.url.queryParameters['pwd_id'], 'abc123');
            expect(request.url.queryParameters['stoken'], 'st-1');
            expect(request.url.queryParameters['pdir_fid'], '0');
            return _jsonResponse({
              'code': 0,
              'data': {
                'list': [
                  {
                    'fid': 'fid-1',
                    'file_name': 'movie-a.mkv',
                    'share_fid_token': 'token-1',
                  },
                  {
                    'fid': 'fid-2',
                    'file_name': 'movie-b.mkv',
                    'share_fid_token': 'token-2',
                  },
                ],
              },
              'metadata': {'_total': 2},
            });
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            expect(request.url.queryParameters['pdir_fid'], '0');
            return _jsonResponse({
              'code': 0,
              'data': {'list': []},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['to_pdir_fid'], '0');
            expect(body['pwd_id'], 'abc123');
            expect(body['stoken'], 'st-1');
            expect(body['fid_list'], ['fid-1', 'fid-2']);
            expect(body['fid_token_list'], ['token-1', 'token-2']);
            return _jsonResponse({
              'code': 0,
              'data': {'task_id': 'task-9'},
            });
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
            return _jsonResponse({
              'code': 0,
              'data': {'stoken': 'st-2'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            return _jsonResponse({
              'code': 0,
              'data': {
                'list': [
                  {
                    'fid': 'fid-9',
                    'file_name': '三体01.mkv',
                    'share_fid_token': 'token-9',
                  },
                ],
              },
              'metadata': {'_total': 1},
            });
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            expect(
              request.url.queryParameters['pdir_fid'],
              anyOf('dir-parent', 'dir-child'),
            );
            return _jsonResponse({
              'code': 0,
              'data': {'list': []},
            });
          }
          if (request.url.path == '/1/clouddrive/file') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['pdir_fid'], 'dir-parent');
            expect(body['file_name'], '三体');
            expect(body['dir_path'], '/三体');
            return _jsonResponse({
              'code': 0,
              'data': {'fid': 'dir-child'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['to_pdir_fid'], 'dir-child');
            return _jsonResponse({
              'code': 0,
              'data': {'task_id': 'task-10'},
            });
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
            return _jsonResponse({
              'code': 0,
              'data': {'stoken': 'st-3'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            return _jsonResponse({
              'code': 0,
              'data': {
                'list': [
                  {
                    'fid': 'fid-11',
                    'file_name': '三体01.mkv',
                    'share_fid_token': 'token-11',
                  },
                ],
              },
              'metadata': {'_total': 1},
            });
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            expect(request.url.queryParameters['pdir_fid'], 'dir-santi');
            return _jsonResponse({
              'code': 0,
              'data': {'list': []},
            });
          }
          if (request.url.path == '/1/clouddrive/file') {
            createDirectoryCalled = true;
            return http.Response('unexpected', 500);
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['to_pdir_fid'], 'dir-santi');
            expect(body['fid_list'], ['fid-11']);
            return _jsonResponse({
              'code': 0,
              'data': {'task_id': 'task-11'},
            });
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
            return _jsonResponse({
              'code': 0,
              'data': {'stoken': 'st-4'},
            });
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            expect(
              request.url.queryParameters['pdir_fid'],
              anyOf('dir-parent', 'dir-child'),
            );
            return _jsonResponse({
              'code': 0,
              'data': {'list': []},
            });
          }
          if (request.url.path == '/1/clouddrive/file') {
            return _jsonResponse({
              'code': 0,
              'data': {'fid': 'dir-child'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            final pdirFid = request.url.queryParameters['pdir_fid'] ?? '';
            detailRequests.add(pdirFid);
            if (pdirFid == '0') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'root-folder',
                      'file_name': '流浪地球',
                      'share_fid_token': 'root-token',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
            if (pdirFid == 'root-folder') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'nested-file',
                      'file_name': 'movie.mkv',
                      'share_fid_token': 'nested-token',
                      'dir': false,
                    },
                    {
                      'fid': 'nested-dir',
                      'file_name': '字幕',
                      'share_fid_token': 'nested-dir-token',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 2},
              });
            }
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['to_pdir_fid'], 'dir-child');
            expect(body['fid_list'], ['nested-file', 'nested-dir']);
            expect(
                body['fid_token_list'], ['nested-token', 'nested-dir-token']);
            return _jsonResponse({
              'code': 0,
              'data': {'task_id': 'task-12'},
            });
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

    test(
        'recursively skips duplicate files inside an existing same-named folder',
        () async {
      var createDirectoryCalled = false;
      final saveTargets = <String>[];
      final saveFidLists = <List<String>>[];
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return _jsonResponse({
              'code': 0,
              'data': {'stoken': 'st-5'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            final pdirFid = request.url.queryParameters['pdir_fid'] ?? '';
            if (pdirFid == '0') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'root-folder',
                      'file_name': 'Movie 2024',
                      'share_fid_token': 'root-token',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
            if (pdirFid == 'root-folder') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'fid-existing',
                      'file_name': 'Movie.2024.mkv',
                      'share_fid_token': 'token-existing',
                    },
                    {
                      'fid': 'fid-new',
                      'file_name': 'Movie.2024.2160p.mkv',
                      'share_fid_token': 'token-new',
                    },
                    {
                      'fid': 'share-extras',
                      'file_name': 'Extras',
                      'share_fid_token': 'token-extras',
                      'dir': true,
                    },
                    {
                      'fid': 'share-subs',
                      'file_name': 'Subs',
                      'share_fid_token': 'token-subs',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 4},
              });
            }
            if (pdirFid == 'share-extras') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'extras-cover',
                      'file_name': 'cover.jpg',
                      'share_fid_token': 'token-cover',
                    },
                    {
                      'fid': 'extras-note',
                      'file_name': 'note.txt',
                      'share_fid_token': 'token-note',
                    },
                  ],
                },
                'metadata': {'_total': 2},
              });
            }
            return http.Response('Not found', 404);
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            final parentFid = request.url.queryParameters['pdir_fid'];
            if (parentFid == 'dir-parent') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'dir-movie',
                      'dir': true,
                      'file_name': 'Movie 2024',
                      'file_path': '/电影/Movie 2024',
                    },
                  ],
                },
              });
            }
            if (parentFid == 'dir-movie') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'local-1',
                      'dir': false,
                      'file_name': 'Movie.2024.mkv',
                      'file_path': '/电影/Movie 2024/Movie.2024.mkv',
                    },
                    {
                      'fid': 'dir-extras',
                      'dir': true,
                      'file_name': 'Extras',
                      'file_path': '/电影/Movie 2024/Extras',
                    },
                  ],
                },
              });
            }
            if (parentFid == 'dir-extras') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'local-cover',
                      'dir': false,
                      'file_name': 'cover.jpg',
                      'file_path': '/电影/Movie 2024/Extras/cover.jpg',
                    },
                  ],
                },
              });
            }
            return http.Response('Not found', 404);
          }
          if (request.url.path == '/1/clouddrive/file') {
            createDirectoryCalled = true;
            return http.Response('unexpected', 500);
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            saveTargets.add('${body['to_pdir_fid']}');
            saveFidLists
                .add((body['fid_list'] as List<dynamic>).cast<String>());
            if (saveTargets.length == 1) {
              expect(body['to_pdir_fid'], 'dir-movie');
              expect(body['fid_list'], ['fid-new', 'share-subs']);
              expect(body['fid_token_list'], ['token-new', 'token-subs']);
              return _jsonResponse({
                'code': 0,
                'data': {'task_id': 'task-13-root'},
              });
            }
            if (saveTargets.length == 2) {
              expect(body['to_pdir_fid'], 'dir-extras');
              expect(body['fid_list'], ['extras-note']);
              expect(body['fid_token_list'], ['token-note']);
              return _jsonResponse({
                'code': 0,
                'data': {'task_id': 'task-13-extras'},
              });
            }
            return _jsonResponse({
              'code': 1,
              'message': 'unexpected extra save',
            });
          }
          return http.Response('Not found', 404);
        }),
      );

      final result = await client.saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc123',
        cookie: 'kps=test; sign=test; vcode=test;',
        toPdirFid: 'dir-parent',
        toPdirPath: '/电影',
        saveFolderName: 'Movie 2024',
      );

      expect(createDirectoryCalled, isFalse);
      expect(saveTargets, ['dir-movie', 'dir-extras']);
      expect(saveFidLists, [
        ['fid-new', 'share-subs'],
        ['extras-note'],
      ]);
      expect(result.taskId, isEmpty);
      expect(result.savedCount, 3);
      expect(result.skippedCount, 2);
      expect(result.targetFolderPath, '/电影/Movie 2024');
    });

    test(
        'returns skipped result when all nested files already exist in an existing same-named folder',
        () async {
      var saveRequested = false;
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return _jsonResponse({
              'code': 0,
              'data': {'stoken': 'st-6'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            final pdirFid = request.url.queryParameters['pdir_fid'] ?? '';
            if (pdirFid == '0') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'root-folder',
                      'file_name': 'Movie 2024',
                      'share_fid_token': 'root-token',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
            if (pdirFid == 'root-folder') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'fid-existing',
                      'file_name': 'Movie.2024.mkv',
                      'share_fid_token': 'token-existing',
                    },
                    {
                      'fid': 'share-extras',
                      'file_name': 'Extras',
                      'share_fid_token': 'token-extras',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 2},
              });
            }
            if (pdirFid == 'share-extras') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'extras-note',
                      'file_name': 'note.txt',
                      'share_fid_token': 'token-note',
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
            return http.Response('Not found', 404);
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            final parentFid = request.url.queryParameters['pdir_fid'];
            if (parentFid == 'dir-parent') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'dir-movie',
                      'dir': true,
                      'file_name': 'Movie 2024',
                      'file_path': '/电影/Movie 2024',
                    },
                  ],
                },
              });
            }
            if (parentFid == 'dir-movie') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'local-1',
                      'dir': false,
                      'file_name': 'Movie.2024.mkv',
                      'file_path': '/电影/Movie 2024/Movie.2024.mkv',
                    },
                    {
                      'fid': 'dir-extras',
                      'dir': true,
                      'file_name': 'Extras',
                      'file_path': '/电影/Movie 2024/Extras',
                    },
                  ],
                },
              });
            }
            if (parentFid == 'dir-extras') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'local-note',
                      'dir': false,
                      'file_name': 'note.txt',
                      'file_path': '/电影/Movie 2024/Extras/note.txt',
                    },
                  ],
                },
              });
            }
            return http.Response('Not found', 404);
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            saveRequested = true;
          }
          return http.Response('Not found', 404);
        }),
      );

      final result = await client.saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc123',
        cookie: 'kps=test; sign=test; vcode=test;',
        toPdirFid: 'dir-parent',
        toPdirPath: '/电影',
        saveFolderName: 'Movie 2024',
      );

      expect(saveRequested, isFalse);
      expect(result.taskId, isEmpty);
      expect(result.savedCount, 0);
      expect(result.skippedCount, 2);
      expect(result.targetFolderPath, '/电影/Movie 2024');
    });

    test(
        'does not deduplicate when the matching target folder is newly created',
        () async {
      var createdDirectory = false;
      var savedToDirectory = '';
      final listedParentFids = <String>[];
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return _jsonResponse({
              'code': 0,
              'data': {'stoken': 'st-7'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            final pdirFid = request.url.queryParameters['pdir_fid'] ?? '';
            if (pdirFid == '0') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'root-folder',
                      'file_name': 'Movie 2024',
                      'share_fid_token': 'root-token',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
            if (pdirFid == 'root-folder') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'fid-existing',
                      'file_name': 'Movie.2024.mkv',
                      'share_fid_token': 'token-existing',
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
            return http.Response('Not found', 404);
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            final parentFid = request.url.queryParameters['pdir_fid'] ?? '';
            listedParentFids.add(parentFid);
            if (parentFid == 'dir-parent') {
              return _jsonResponse({
                'code': 0,
                'data': {'list': []},
              });
            }
            return http.Response('unexpected recursive dedupe lookup', 500);
          }
          if (request.url.path == '/1/clouddrive/file') {
            createdDirectory = true;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['pdir_fid'], 'dir-parent');
            expect(body['file_name'], 'Movie 2024');
            return _jsonResponse({
              'code': 0,
              'data': {'fid': 'dir-movie-new'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            savedToDirectory = '${body['to_pdir_fid']}';
            expect(body['fid_list'], ['fid-existing']);
            expect(body['fid_token_list'], ['token-existing']);
            return _jsonResponse({
              'code': 0,
              'data': {'task_id': 'task-14'},
            });
          }
          return http.Response('Not found', 404);
        }),
      );

      final result = await client.saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc123',
        cookie: 'kps=test; sign=test; vcode=test;',
        toPdirFid: 'dir-parent',
        toPdirPath: '/电影',
        saveFolderName: 'Movie 2024',
      );

      expect(createdDirectory, isTrue);
      expect(listedParentFids, ['dir-parent']);
      expect(savedToDirectory, 'dir-movie-new');
      expect(result.taskId, 'task-14');
      expect(result.savedCount, 1);
      expect(result.skippedCount, 0);
      expect(result.targetFolderPath, '/电影/Movie 2024');
    });

    test('previews a share link using the same folder mapping as saving',
        () async {
      final detailRequests = <String>[];
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return _jsonResponse({
              'code': 0,
              'data': {'stoken': 'st-preview'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            final pdirFid = request.url.queryParameters['pdir_fid'] ?? '';
            detailRequests.add(pdirFid);
            if (pdirFid == '0') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'share-root',
                      'file_name': '分享目录',
                      'share_fid_token': 'token-root',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
            if (pdirFid == 'share-root') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'share-season',
                      'file_name': 'Season 1',
                      'share_fid_token': 'token-season',
                      'dir': true,
                    },
                    {
                      'fid': 'share-ep1',
                      'file_name': 'Episode 01.mkv',
                      'share_fid_token': 'token-ep1',
                    },
                  ],
                },
                'metadata': {'_total': 2},
              });
            }
            if (pdirFid == 'share-season') {
              return _jsonResponse({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'share-ep2',
                      'file_name': 'Episode 02.mkv',
                      'share_fid_token': 'token-ep2',
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
          }
          return http.Response('Not found', 404);
        }),
      );

      final preview = await client.previewShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc123',
        cookie: 'kps=test; sign=test; vcode=test;',
        toPdirPath: '/剧集',
        saveFolderName: '三体',
      );

      expect(detailRequests, ['0', 'share-root', 'share-season']);
      expect(preview.targetFolderPath, '/剧集/三体');
      expect(
        preview.videoEntries.map((entry) => entry.relativePath).toList(),
        ['Season 1/Episode 02.mkv', 'Episode 01.mkv'],
      );
    });
  });
}
