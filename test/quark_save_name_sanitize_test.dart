import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/application/quark_save_workflow_service.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

http.Response _json(Object? body, {int statusCode = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, dynamic> _entry(String fid, String name, {bool dir = false}) {
  return {
    'fid': fid,
    'dir': dir,
    'file_name': name,
    'file_path': '/$name',
  };
}

void main() {
  group('sanitizeQuarkNameForUrl', () {
    test('strips the characters that break signed playback URLs', () {
      expect(
        sanitizeQuarkNameForUrl('#001 李想 × 罗永浩！四小时马拉松访谈'),
        '001 李想 × 罗永浩！四小时马拉松访谈',
      );
      expect(sanitizeQuarkNameForUrl('a#b?c%d.mp4'), 'abcd.mp4');
    });

    test('leaves clean names untouched', () {
      const clean = '圆桌派.S01E02.20161102.1080p.出轨.mp4';
      expect(sanitizeQuarkNameForUrl(clean), clean);
    });

    test('collapses the whitespace a stripped character leaves behind', () {
      expect(sanitizeQuarkNameForUrl('第一集 # 完整版.mp4'), '第一集 完整版.mp4');
    });

    test('returns empty when nothing usable remains', () {
      expect(sanitizeQuarkNameForUrl('###'), '');
      expect(sanitizeQuarkNameForUrl('#.#'), '');
    });

    test('honours a narrowed character set', () {
      expect(sanitizeQuarkNameForUrl('a#b%c', characters: '#'), 'ab%c');
    });
  });

  group('QuarkSaveClient.sanitizeSavedEntries', () {
    test('touches only the directories this save copied in', () async {
      final renamed = <String, String>{};
      var listings = 0;
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/file/sort') {
            listings += 1;
            final parent = request.url.queryParameters['pdir_fid'];
            if (parent == 'show') {
              return _json({
                'code': 0,
                'data': {
                  'list': [
                    // 本次新存入的
                    _entry('new-dir', '#051 新一期', dir: true),
                    // 之前几期，同样带 # ，但不该被碰
                    _entry('old-dir-a', '#001 旧一期', dir: true),
                    _entry('old-dir-b', '#002 旧二期', dir: true),
                  ],
                },
              });
            }
            return _json({
              'code': 0,
              'data': {'list': <Map<String, dynamic>>[]},
            });
          }
          if (request.url.path == '/1/clouddrive/file/rename') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            renamed['${body['fid']}'] = '${body['file_name']}';
            return _json({'code': 0, 'data': {}});
          }
          fail('unexpected request: ${request.url}');
        }),
      );

      final result = await client.sanitizeSavedEntries(
        cookie: 'cookie',
        savedEntries: const [
          QuarkSavedEntry(parentFid: 'show', name: '#051 新一期'),
        ],
        characters: kQuarkUnsafeUrlNameCharacters,
      );

      expect(renamed, {'new-dir': '051 新一期'});
      expect(
        result.renamedCount,
        1,
        reason: '已经存在的旧目录不属于本次转存，不该被改名',
      );
      expect(
        listings,
        2,
        reason: '一次列举剧集目录 + 一次下钻新目录，与已有期数无关',
      );
      expect(result.listedDirectoryCount, 2);
    });

    test('renames saved files too, without extra listings', () async {
      final renamed = <String, String>{};
      var listings = 0;
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/file/sort') {
            listings += 1;
            final parent = request.url.queryParameters['pdir_fid'];
            if (parent == 'show') {
              return _json({
                'code': 0,
                'data': {
                  'list': [
                    _entry('new-dir', '#001 一期', dir: true),
                    _entry('new-file', '第%02集.mp4'),
                    _entry('old-file', '#旧文件.mp4'),
                  ],
                },
              });
            }
            if (parent == 'new-dir') {
              return _json({
                'code': 0,
                'data': {
                  'list': [_entry('nested-file', '正片#完整版.mp4')],
                },
              });
            }
            return _json({
              'code': 0,
              'data': {'list': <Map<String, dynamic>>[]},
            });
          }
          if (request.url.path == '/1/clouddrive/file/rename') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            renamed['${body['fid']}'] = '${body['file_name']}';
            return _json({'code': 0, 'data': {}});
          }
          fail('unexpected request: ${request.url}');
        }),
      );

      final result = await client.sanitizeSavedEntries(
        cookie: 'cookie',
        savedEntries: const [
          QuarkSavedEntry(parentFid: 'show', name: '#001 一期'),
          QuarkSavedEntry(parentFid: 'show', name: '第%02集.mp4'),
        ],
        characters: kQuarkUnsafeUrlNameCharacters,
      );

      expect(renamed, {
        'new-dir': '001 一期',
        'new-file': '第02集.mp4',
        // 新建目录底下的文件也属于本次转存
        'nested-file': '正片完整版.mp4',
      });
      expect(
        renamed.containsKey('old-file'),
        isFalse,
        reason: '同目录下的旧文件不属于本次转存，不该被碰',
      );
      expect(result.renamedCount, 3);
      expect(
        listings,
        2,
        reason: '文件跟着父目录的列举一起返回，加上文件不产生额外列举请求',
      );
    });

    test('descends into a directory it just renamed', () async {
      final renamed = <String, String>{};
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/file/sort') {
            final parent = request.url.queryParameters['pdir_fid'];
            return _json({
              'code': 0,
              'data': {
                'list': switch (parent) {
                  'show' => [_entry('outer', '#外层', dir: true)],
                  'outer' => [_entry('inner', '#内层', dir: true)],
                  _ => <Map<String, dynamic>>[],
                },
              },
            });
          }
          if (request.url.path == '/1/clouddrive/file/rename') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            renamed['${body['fid']}'] = '${body['file_name']}';
            return _json({'code': 0, 'data': {}});
          }
          fail('unexpected request: ${request.url}');
        }),
      );

      final result = await client.sanitizeSavedEntries(
        cookie: 'cookie',
        savedEntries: const [
          QuarkSavedEntry(parentFid: 'show', name: '#外层'),
        ],
        characters: '#',
      );

      expect(
        renamed,
        {'outer': '外层', 'inner': '内层'},
        reason: '新建目录底下全是新内容，整棵子树都在范围内',
      );
      expect(result.renamedCount, 2);
    });

    test('does nothing when the save created no directories', () async {
      final client = QuarkSaveClient(
        MockClient((request) async {
          fail('nothing to do, must not hit the network: ${request.url}');
        }),
      );

      final result = await client.sanitizeSavedEntries(
        cookie: 'cookie',
        savedEntries: const [],
        characters: '#',
      );

      expect(result.renamedCount, 0);
      expect(result.listedDirectoryCount, 0);
    });

    test('records a failed rename and keeps going', () async {
      final renamed = <String>[];
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/file/sort') {
            final parent = request.url.queryParameters['pdir_fid'];
            return _json({
              'code': 0,
              'data': {
                'list': parent == 'show'
                    ? [
                        _entry('collide', '#冲突', dir: true),
                        _entry('fine', '#正常', dir: true),
                      ]
                    : <Map<String, dynamic>>[],
              },
            });
          }
          if (request.url.path == '/1/clouddrive/file/rename') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['fid'] == 'collide') {
              return _json({'code': 23008, 'message': '同名文件已存在'});
            }
            renamed.add('${body['fid']}');
            return _json({'code': 0, 'data': {}});
          }
          fail('unexpected request: ${request.url}');
        }),
      );

      final result = await client.sanitizeSavedEntries(
        cookie: 'cookie',
        savedEntries: const [
          QuarkSavedEntry(parentFid: 'show', name: '#冲突'),
          QuarkSavedEntry(parentFid: 'show', name: '#正常'),
        ],
        characters: '#',
      );

      expect(result.renamedCount, 1);
      expect(result.failedNames, ['#冲突']);
      expect(renamed, ['fine'], reason: '一个目录失败不应中断其余的');
    });
  });

  group('QuarkSaveClient dedup after sanitising', () {
    /// Serves a share holding one directory named `#001 一期`, while the drive
    /// already holds the sanitised copy `001 一期` from a previous save.
    QuarkSaveClient buildClient(List<List<String>> savedFidLists) {
      return QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return _json({
              'code': 0,
              'data': {'stoken': 'st'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            final pdir = request.url.queryParameters['pdir_fid'] ?? '';
            if (pdir == '0') {
              return _json({
                'code': 0,
                'data': {
                  'list': [
                    {
                      'fid': 'share-ep',
                      'file_name': '#001 一期',
                      'share_fid_token': 'tok',
                      'dir': true,
                    },
                  ],
                },
                'metadata': {'_total': 1},
              });
            }
            return _json({
              'code': 0,
              'data': {'list': <Map<String, dynamic>>[]},
              'metadata': {'_total': 0},
            });
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            final parent = request.url.queryParameters['pdir_fid'];
            return _json({
              'code': 0,
              'data': {
                'list': parent == 'show'
                    // The already-saved copy, renamed by a previous sanitise.
                    ? [_entry('drive-ep', '001 一期', dir: true)]
                    : <Map<String, dynamic>>[],
              },
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            savedFidLists.add(
              (body['fid_list'] as List<dynamic>).cast<String>(),
            );
            return _json({
              'code': 0,
              'data': {'task_id': 'task'},
            });
          }
          if (request.url.path == '/1/clouddrive/file/rename') {
            return _json({'code': 0, 'data': {}});
          }
          return _json({'code': 0, 'data': {}});
        }),
      );
    }

    test('treats a sanitised copy as already saved', () async {
      final saved = <List<String>>[];
      final result = await buildClient(saved).saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc',
        cookie: 'cookie',
        toPdirFid: 'show',
        toPdirPath: '/综艺/某节目',
        saveFolderName: '某节目',
        sanitizedNameCharacters: kQuarkUnsafeUrlNameCharacters,
      );

      expect(
        saved,
        isEmpty,
        reason: '网盘里的 001 一期 就是分享里的 #001 一期，改过名而已，不该再存一遍',
      );
      expect(result.savedCount, 0);
    });

    test('treats a sanitised file copy as already saved', () async {
      final saved = <List<String>>[];
      final client = QuarkSaveClient(
        MockClient((request) async {
          if (request.url.path == '/1/clouddrive/share/sharepage/token') {
            return _json({
              'code': 0,
              'data': {'stoken': 'st'},
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/detail') {
            final pdir = request.url.queryParameters['pdir_fid'] ?? '';
            return _json({
              'code': 0,
              'data': {
                'list': pdir == '0'
                    ? [
                        {
                          'fid': 'share-file',
                          'file_name': '第%02集.mp4',
                          'share_fid_token': 'tok',
                        },
                      ]
                    : <Map<String, dynamic>>[],
              },
              'metadata': {'_total': pdir == '0' ? 1 : 0},
            });
          }
          if (request.url.path == '/1/clouddrive/file/sort') {
            final parent = request.url.queryParameters['pdir_fid'];
            return _json({
              'code': 0,
              'data': {
                'list': parent == 'show'
                    // Saved earlier, then renamed by a previous sanitise.
                    ? [_entry('drive-file', '第02集.mp4')]
                    : <Map<String, dynamic>>[],
              },
            });
          }
          if (request.url.path == '/1/clouddrive/share/sharepage/save') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            saved.add((body['fid_list'] as List<dynamic>).cast<String>());
            return _json({
              'code': 0,
              'data': {'task_id': 'task'},
            });
          }
          return _json({'code': 0, 'data': {}});
        }),
      );

      final result = await client.saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc',
        cookie: 'cookie',
        toPdirFid: 'show',
        toPdirPath: '/综艺/某节目',
        saveFolderName: '某节目',
        sanitizedNameCharacters: kQuarkUnsafeUrlNameCharacters,
      );

      expect(
        saved,
        isEmpty,
        reason: '文件同样会被改名，去重也必须按净化后的名字比对',
      );
      expect(result.skippedCount, 1);
    });

    test('still re-saves when sanitising is off', () async {
      final saved = <List<String>>[];
      await buildClient(saved).saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc',
        cookie: 'cookie',
        toPdirFid: 'show',
        toPdirPath: '/综艺/某节目',
        saveFolderName: '某节目',
      );

      expect(
        saved.expand((item) => item),
        contains('share-ep'),
        reason: '关掉净化时行为不变，仍按原名比对',
      );
    });
  });

  group('QuarkSaveClient save task settling', () {
    /// A share with one directory, saved into an empty target. The copy task
    /// reports "running" once before reporting "finished".
    QuarkSaveClient buildClient({
      required List<String> calls,
      required bool taskFinishes,
    }) {
      var taskPolls = 0;
      return QuarkSaveClient(
        MockClient((request) async {
          final path = request.url.path;
          calls.add(path);
          if (path == '/1/clouddrive/share/sharepage/token') {
            return _json({
              'code': 0,
              'data': {'stoken': 'st'},
            });
          }
          if (path == '/1/clouddrive/share/sharepage/detail') {
            final pdir = request.url.queryParameters['pdir_fid'] ?? '';
            return _json({
              'code': 0,
              'data': {
                'list': pdir == '0'
                    ? [
                        {
                          'fid': 'share-ep',
                          'file_name': '#001 一期',
                          'share_fid_token': 'tok',
                          'dir': true,
                        },
                      ]
                    : <Map<String, dynamic>>[],
              },
              'metadata': {'_total': pdir == '0' ? 1 : 0},
            });
          }
          if (path == '/1/clouddrive/file/sort') {
            return _json({
              'code': 0,
              'data': {'list': <Map<String, dynamic>>[]},
            });
          }
          if (path == '/1/clouddrive/share/sharepage/save') {
            return _json({
              'code': 0,
              'data': {'task_id': 'task-1'},
            });
          }
          if (path == '/1/clouddrive/task') {
            taskPolls += 1;
            if (!taskFinishes) {
              return _json({
                'code': 0,
                'data': {'status': 1},
              });
            }
            return _json({
              'code': 0,
              'data': {'status': taskPolls >= 2 ? 2 : 1},
            });
          }
          return _json({'code': 0, 'data': {}});
        }),
      );
    }

    test('waits for the copy task before reporting entries as listable',
        () async {
      final calls = <String>[];
      final result =
          await buildClient(calls: calls, taskFinishes: true).saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc',
        cookie: 'cookie',
        toPdirFid: 'show',
        toPdirPath: '/综艺/某节目',
        saveFolderName: '某节目',
        sanitizedNameCharacters: kQuarkUnsafeUrlNameCharacters,
      );

      expect(
        calls,
        contains('/1/clouddrive/task'),
        reason: '夸克在后台复制，不等任务完成就去列举会什么都匹配不到',
      );
      expect(result.savedEntriesSettled, isTrue);
      expect(result.savedEntries.single.name, '#001 一期');
    });

    test('does not poll the task when sanitising is off', () async {
      final calls = <String>[];
      final result =
          await buildClient(calls: calls, taskFinishes: true).saveShareLink(
        shareUrl: 'https://pan.quark.cn/s/abc',
        cookie: 'cookie',
        toPdirFid: 'show',
        toPdirPath: '/综艺/某节目',
        saveFolderName: '某节目',
      );

      expect(
        calls,
        isNot(contains('/1/clouddrive/task')),
        reason: '不做后续改名时没必要拖慢转存',
      );
      expect(result.savedEntriesSettled, isFalse);
    });
  });

  group('QuarkSaveWorkflowService name sanitising', () {
    QuarkSaveWorkflowService buildService({required List<String> calls}) {
      return QuarkSaveWorkflowService(
        saveShareLink: ({
          required String shareUrl,
          required String cookie,
          String toPdirFid = '0',
          String toPdirPath = '/',
          String saveFolderName = '',
          String sanitizedNameCharacters = '',
        }) async {
          calls.add('save');
          return const QuarkSaveResult(
            taskId: 'task-1',
            savedCount: 2,
            targetFolderPath: '/综艺',
            targetFolderId: 'target-fid',
            savedEntries: [
              QuarkSavedEntry(parentFid: 'target-fid', name: '#001 新一期'),
            ],
            savedEntriesSettled: true,
          );
        },
        sanitizeSavedNames: ({
          required String cookie,
          required List<QuarkSavedEntry> savedEntries,
          required String characters,
        }) async {
          calls.add(
            'sanitize:${savedEntries.map((item) => item.name).join(",")}'
            ':$characters',
          );
          return const QuarkNameSanitizeResult(renamedCount: 3);
        },
        triggerSmartStrm: ({
          required String webhookUrl,
          required String taskName,
          String storagePath = '',
          int delay = 0,
        }) async {
          calls.add('smartstrm');
          return const SmartStrmTriggerResult(
            message: '',
            addedCount: null,
            rawPayload: {},
          );
        },
        resolveRefreshSourceIds: ({
          required NetworkStorageConfig networkStorage,
          required bool includeConfiguredSources,
        }) =>
            const <String>[],
        refreshSelectedSources: ({
          required List<String> sourceIds,
          required int delaySeconds,
          required bool invalidateWebDavDirectoryCache,
        }) async {},
      );
    }

    const enabled = NetworkStorageConfig(
      quarkCookie: 'cookie',
      smartStrmWebhookUrl: 'https://strm.example/webhook',
      smartStrmTaskName: 'tv',
      quarkSanitizeSavedNamesEnabled: true,
    );

    test('sanitises before triggering SmartStrm', () async {
      final calls = <String>[];
      final progressStages = <QuarkSaveWorkflowStage>[];
      final service = buildService(calls: calls);

      final result = await service.saveToQuark(
        shareUrl: 'https://pan.quark.cn/s/test',
        saveFolderName: '综艺',
        networkStorage: enabled,
        onProgress: (progress) => progressStages.add(progress.stage),
      );

      expect(
        calls,
        [
          'save',
          'sanitize:#001 新一期:$kDefaultQuarkSanitizedNameCharacters',
          'smartstrm',
        ],
        reason: 'SmartStrm 必须在改名之后触发，否则生成的 .strm 指向旧路径',
      );
      expect(result.sanitizeResult?.renamedCount, 3);
      expect(result.buildSuccessMessage(), contains('已修正 3 个名称'));
      expect(
        progressStages,
        [
          QuarkSaveWorkflowStage.saving,
          QuarkSaveWorkflowStage.saveCompleted,
          QuarkSaveWorkflowStage.sanitizingNames,
          QuarkSaveWorkflowStage.namesSanitized,
          QuarkSaveWorkflowStage.triggeringSmartStrm,
          QuarkSaveWorkflowStage.smartStrmTriggered,
        ],
      );
    });

    test('skips sanitising when the copy task never settled', () async {
      final calls = <String>[];
      final service = QuarkSaveWorkflowService(
        saveShareLink: ({
          required String shareUrl,
          required String cookie,
          String toPdirFid = '0',
          String toPdirPath = '/',
          String saveFolderName = '',
          String sanitizedNameCharacters = '',
        }) async {
          calls.add('save');
          return const QuarkSaveResult(
            taskId: 'task-1',
            savedCount: 2,
            targetFolderPath: '/综艺',
            targetFolderId: 'target-fid',
            savedEntries: [
              QuarkSavedEntry(parentFid: 'target-fid', name: '#001 新一期'),
            ],
            savedEntriesSettled: false,
          );
        },
        sanitizeSavedNames: ({
          required String cookie,
          required List<QuarkSavedEntry> savedEntries,
          required String characters,
        }) async {
          calls.add('sanitize');
          return const QuarkNameSanitizeResult();
        },
        triggerSmartStrm: ({
          required String webhookUrl,
          required String taskName,
          String storagePath = '',
          int delay = 0,
        }) async {
          calls.add('smartstrm');
          return const SmartStrmTriggerResult(
            message: '',
            addedCount: null,
            rawPayload: {},
          );
        },
        resolveRefreshSourceIds: ({
          required NetworkStorageConfig networkStorage,
          required bool includeConfiguredSources,
        }) =>
            const <String>[],
        refreshSelectedSources: ({
          required List<String> sourceIds,
          required int delaySeconds,
          required bool invalidateWebDavDirectoryCache,
        }) async {},
      );

      final result = await service.saveToQuark(
        shareUrl: 'https://pan.quark.cn/s/test',
        saveFolderName: '综艺',
        networkStorage: enabled,
      );

      expect(
        calls,
        ['save', 'smartstrm'],
        reason: '条目还不可列举时改名只会静默失败，不如跳过并记警告',
      );
      expect(result.sanitizeResult, isNull);
    });

    test('skips sanitising when the option is off', () async {
      final calls = <String>[];
      const disabled = NetworkStorageConfig(
        quarkCookie: 'cookie',
        smartStrmWebhookUrl: 'https://strm.example/webhook',
        smartStrmTaskName: 'tv',
      );
      final service = buildService(calls: calls);

      final result = await service.saveToQuark(
        shareUrl: 'https://pan.quark.cn/s/test',
        saveFolderName: '综艺',
        networkStorage: disabled,
      );

      expect(calls, ['save', 'smartstrm']);
      expect(result.sanitizeResult, isNull);
      expect(result.buildSuccessMessage(), isNot(contains('已修正')));
    });
  });
}
