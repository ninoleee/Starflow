import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/application/cloud115_save_workflow_service.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/cloud_save_rules.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
        headers: {'content-type': 'application/json'});

class _Drive {
  final events = <String>[];
  final names = <String, String>{
    '101': '#01.mkv',
    '102': '#附加',
    '103': '正%片.mkv'
  };
  final renames = <Map<String, String>>[];
  bool saved = false;
  bool rejectRename = false;
  bool ignoreRename = false;
  bool alreadySaved = false;

  late final client = Cloud115SaveClient(MockClient((request) async {
    expect(request.url.host, 'webapi.115.com');
    expect(request.followRedirects, isFalse);
    expect(request.headers['cookie'], 'cookie');
    if (request.url.path == '/share/receive') {
      final body = Uri.splitQueryString(request.body);
      expect(body['cid'], '10');
      expect(body['file_id'], '1,2');
      saved = true;
      events.add('save');
      return _json({'state': true});
    }
    if (request.url.path == '/files/batch_rename') {
      expect(request.method, 'POST');
      final body = Uri.splitQueryString(request.body);
      renames.add(body);
      events.add('rename');
      if (rejectRename) return http.Response('blocked', 405);
      if (!ignoreRename) {
        for (final id in names.keys.toList()) {
          if (body.containsKey('files_new_name[$id]')) {
            names[id] = body['files_new_name[$id]']!;
          }
        }
      }
      return _json({'state': true});
    }
    expect(request.method, 'GET');
    final id = request.url.queryParameters['cid'];
    if (request.url.path == '/share/snap') {
      final rows = id == '0'
          ? [
              {'fid': '1', 'n': '#01.mkv'},
              {'cid': '2', 'n': '#附加'}
            ]
          : [
              {'fid': '3', 'n': '正%片.mkv'}
            ];
      return _json({
        'state': true,
        'data': {'count': rows.length, 'list': rows}
      });
    }
    expect(request.url.path, '/files');
    final rows = id == '10'
        ? [
            {'fid': '999', 'n': '#旧文件.mkv'},
            if (saved || alreadySaved) ...[
              {'fid': '101', 'n': names['101']!},
              {'cid': '102', 'n': names['102']!},
            ],
          ]
        : [
            {'fid': '103', 'n': names['103']!}
          ];
    return _json({'state': true, 'count': rows.length, 'data': rows});
  }));

  Future<String> run({bool enabled = true}) => Cloud115SaveWorkflowService(
        client,
        (_, __) async {
          events.add('refresh');
        },
        smartStrm: SmartStrmWebhookClient(MockClient((request) async {
          events.add('strm');
          final body = jsonDecode(request.body) as Map;
          expect(
              body['task'], {'name': '115-task', 'storage_path': '/115/Show'});
          expect(request.headers['cookie'], isNull);
          return _json({'success': true});
        })),
      ).save(
        shareUrl: 'https://115.com/s/abc',
        saveFolderName: 'Show',
        config: NetworkStorageConfig(
          cloud115Cookie: 'cookie',
          cloud115SaveFolderId: '10',
          cloud115SaveFolderPath: '/115/Show',
          commonSanitizeSavedNamesEnabled: enabled,
          smartStrmWebhookUrl: 'https://strm.test/webhook',
          cloud115SmartStrmTaskName: '115-task',
          smartStrmTaskName: 'quark-task',
          refreshMediaSourceIds: ['nas'],
        ),
      );
}

void main() {
  test('common rules rename new content and deduplicate later saves', () async {
    final drive = _Drive();
    await drive.run();
    expect(drive.renames, hasLength(3));
    expect(drive.events,
        ['save', 'rename', 'rename', 'rename', 'strm', 'refresh']);
    drive.events.clear();
    final repeated = await drive.run();
    expect(drive.events, isEmpty);
    expect(repeated, contains('保存 0 个'));
  });
  test(
      '115 saves, renames only new content, verifies names, then triggers STRM',
      () async {
    final drive = _Drive();
    final message = await drive.run();
    expect(drive.events,
        ['save', 'rename', 'rename', 'rename', 'strm', 'refresh']);
    expect(drive.renames, [
      {'files_new_name[101]': '01.mkv'},
      {'files_new_name[102]': '附加'},
      {'files_new_name[103]': '正片.mkv'},
    ]);
    expect(message, contains('已修正 3 个名称'));
  });

  test('disabled name correction keeps raw names and issues no rename',
      () async {
    final drive = _Drive();
    final message = await drive.run(enabled: false);
    expect(drive.events, ['save', 'strm', 'refresh']);
    expect(drive.renames, isEmpty);
    expect(message, isNot(contains('已修正')));
  });

  test('cleaned names deduplicate recursively on the next save', () async {
    final drive = _Drive()..alreadySaved = true;
    drive.names.addAll({'101': '01.mkv', '102': '附加', '103': '正片.mkv'});
    final message = await drive.run();
    expect(drive.events, isEmpty);
    expect(message, contains('保存 0 个'));
    expect(message, contains('略过 2 个'));
  });

  for (final refused in [false, true]) {
    test('unconfirmed rename blocks STRM without retry: refused=$refused',
        () async {
      final drive = _Drive()
        ..rejectRename = refused
        ..ignoreRename = !refused;
      final message = await drive.run();
      expect(drive.renames, hasLength(3));
      expect(drive.events, isNot(contains('strm')));
      expect(message, contains('保存 2 个'));
      expect(message, contains('未触发 STRM'));
      expect(message, isNot(contains('已修正')));
    });
  }

  test('115 rename API rejects invalid IDs without a request', () async {
    final client =
        Cloud115SaveClient(MockClient((_) async => fail('No request')));
    for (final id in ['0', '', 'invalid']) {
      await expectLater(
          client.renameEntry(cookie: 'cookie', fid: id, name: 'New.mkv'),
          throwsA(isA<CloudSaveException>()));
    }
  });

  test('legacy per-drive settings serialize but common rules control behavior',
      () {
    final old =
        NetworkStorageConfig.fromJson({'quarkSanitizeSavedNamesEnabled': true});
    expect(old.cloud115SanitizeSavedNamesEnabled, isFalse);
    final config = old.copyWith(
        cloud115SanitizeSavedNamesEnabled: true,
        cloud115SanitizedNameCharacters: '#',
        commonSanitizeSavedNamesEnabled: true,
        commonSanitizedNameCharacters: '%');
    final restored = NetworkStorageConfig.fromJson(config.toJson());
    expect(restored.cloud115SanitizeSavedNamesEnabled, isTrue);
    expect(restored.cloud115SanitizedNameCharacters, '#');
    expect(restored.quarkSanitizedNameCharacters, '#%?');
    expect(restored.effective115NameCharacters, '%');
    expect(
        restored
            .copyWith(commonSanitizeSavedNamesEnabled: false)
            .effective115NameCharacters,
        isEmpty);
  });
}
