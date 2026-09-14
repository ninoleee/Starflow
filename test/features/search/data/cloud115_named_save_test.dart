import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';

http.Response _response(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, String> _file(String id, String name) => {'fid': id, 'n': name};
Map<String, String> _directory(String id, String name) =>
    {'cid': id, 'n': name};

class _Drive {
  _Drive({required this.share, this.folders = const {}, this.pageSize = 1000});

  final Map<String, List<Map<String, String>>> share;
  final Map<String, List<Map<String, String>>> folders;
  final int pageSize;
  final requests = <http.Request>[];
  final saves = <Map<String, String>>[];
  final creates = <Map<String, String>>[];
  http.Response? createResponse;
  int? failSaveNumber;

  late final client = Cloud115SaveClient(MockClient((request) async {
    requests.add(request);
    expect(request.url.host, 'webapi.115.com');
    expect(request.followRedirects, isFalse);
    expect(request.headers['cookie'], 'test');
    if (request.method == 'POST') {
      final body = Uri.splitQueryString(request.body);
      if (request.url.path == '/files/add') {
        creates.add(body);
        return createResponse ?? _response({'state': true, 'cid': '900'});
      }
      expect(request.url.path, '/share/receive');
      expect(body['share_code'], 'abc');
      expect(body['receive_code'], '1234');
      saves.add(body);
      return saves.length == failSaveNumber
          ? http.Response('blocked', 405)
          : _response({'state': true});
    }
    expect(request.method, 'GET');
    final isShare = request.url.path == '/share/snap';
    if (isShare) {
      expect(request.url.queryParameters['receive_code'], '1234');
    } else {
      expect(request.url.path, '/files');
      expect(request.url.queryParameters['show_dir'], '1');
    }
    final cid = request.url.queryParameters['cid']!;
    final rows = (isShare ? share : folders)[cid];
    expect(rows, isNotNull,
        reason: 'Unexpected listing ${request.url.path} $cid');
    final page = rows!
        .skip(int.parse(request.url.queryParameters['offset']!))
        .take(pageSize)
        .toList();
    return _response(isShare
        ? {
            'state': true,
            'data': {'count': rows.length, 'list': page},
          }
        : {'state': true, 'count': rows.length, 'data': page});
  }));

  Future<Cloud115SaveResult> save({
    String folderId = '10',
    String folderPath = '/Library',
    String name = 'Show',
  }) =>
      client.saveShareLink(
        shareUrl: 'https://115.com/s/abc?password=1234',
        cookie: 'test',
        password: 'ignored',
        folderId: folderId,
        folderPath: folderPath,
        saveFolderName: name,
      );
}

void main() {
  for (final path in ['/', ' /Library/115/ ']) {
    test('creates a sanitized child and uses its ID under $path', () async {
      final drive = _Drive(share: {
        '0': [_file('1', 'Episode.mkv')],
      }, folders: {
        '10': [],
      });
      final result = await drive.save(folderPath: path, name: ' 不良/执念:*? ');
      expect(drive.creates.single, {'pid': '10', 'cname': '不良 执念'});
      expect(drive.saves.single['cid'], '900');
      expect(drive.saves.single['file_id'], '1');
      expect(result.savedCount, 1);
      expect(result.skippedCount, 0);
      expect(result.targetFolderId, '900');
      expect(result.targetFolderPath,
          path == '/' ? '/不良 执念' : '/Library/115/不良 执念');
      expect(drive.requests.where((r) => r.url.path == '/files').length, 1);
    });
  }

  test('reuses a paginated case-insensitive directory with its actual path',
      () async {
    final drive = _Drive(pageSize: 1, share: {
      '0': [_file('1', 'E01.mkv'), _file('2', 'E02.mkv')],
    }, folders: {
      '10': [_directory('30', 'Other'), _directory('20', 'SHOW')],
      '20': [_file('101', 'e01.MKV')],
    });
    final result = await drive.save();
    expect(drive.creates, isEmpty);
    expect(drive.saves.single['cid'], '20');
    expect(drive.saves.single['file_id'], '2');
    expect(result.targetFolderPath, '/Library/SHOW');
    expect(result.savedCount, 1);
    expect(result.skippedCount, 1);
  });

  test('the selected save directory already has the requested name', () async {
    final drive = _Drive(share: {
      '0': [_file('1', 'E01.mkv')],
    }, folders: {
      '10': [],
    });
    final result = await drive.save(folderPath: '/Library/SHOW/');
    expect(drive.creates, isEmpty);
    expect(drive.saves.single['cid'], '10');
    expect(result.targetFolderId, '10');
    expect(result.targetFolderPath, '/Library/SHOW');
  });

  test('flattens a sole wrapper exactly once and retains season directories',
      () async {
    final drive = _Drive(share: {
      '0': [_directory('1', 'Share title')],
      '1': [_directory('2', 'Season 1')],
    }, folders: {
      '10': [],
    });
    await drive.save();
    expect(drive.saves.single['file_id'], '2');
    expect(drive.saves.single['cid'], '900');
  });

  test('keeps an empty sole wrapper instead of losing the directory', () async {
    final drive = _Drive(share: {
      '0': [_directory('1', 'Empty')],
      '1': [],
    }, folders: {
      '10': [],
    });
    final result = await drive.save();
    expect(drive.saves.single['file_id'], '1');
    expect(result.savedCount, 1);
  });

  test('multiple top-level directories retain their original structure',
      () async {
    final drive = _Drive(share: {
      '0': [_directory('1', 'Season 1'), _directory('2', 'Season 2')],
    }, folders: {
      '10': [],
    });
    await drive.save();
    expect(drive.saves.single['file_id'], '1,2');
  });

  test('blank or unusable names preserve direct save compatibility', () async {
    for (final name in ['', ' .. ', '/:*?']) {
      final drive = _Drive(share: {
        '0': [_directory('1', 'Share title')],
      });
      final result = await drive.save(name: name);
      expect(drive.creates, isEmpty);
      expect(drive.saves.single['file_id'], '1');
      expect(drive.saves.single['cid'], '10');
      expect(result.targetFolderPath, '/Library');
    }
  });

  test('recursively merges seasons and paginates existing episode files',
      () async {
    final drive = _Drive(pageSize: 1, share: {
      '0': [_directory('1', 'Wrapper')],
      '1': [_directory('2', 'Season 1'), _directory('3', 'Season 2')],
      '2': [
        _file('4', 'E01.mkv'),
        _file('5', 'E02.mkv'),
        _file('6', 'E03.mkv')
      ],
    }, folders: {
      '10': [_directory('20', 'Show')],
      '20': [_directory('21', 'Season 1')],
      '21': [_file('104', 'e01.MKV'), _file('106', 'E03.mkv')],
    });
    final result = await drive.save();
    expect(drive.creates, isEmpty);
    expect(drive.saves.map((body) => [body['cid'], body['file_id']]), [
      ['20', '3'],
      ['21', '5'],
    ]);
    expect(result.savedCount, 2);
    expect(result.skippedCount, 2);
    final firstPost = drive.requests.indexWhere((r) => r.method == 'POST');
    expect(drive.requests.skip(firstPost).every((r) => r.method == 'POST'),
        isTrue);
  });

  test('all duplicate files and an existing empty directory need no writes',
      () async {
    final drive = _Drive(share: {
      '0': [_file('1', 'E01.mkv'), _directory('2', 'Extras')],
      '2': [],
    }, folders: {
      '10': [_directory('20', 'Show')],
      '20': [_file('101', 'e01.MKV'), _directory('102', 'Extras')],
    });
    final result = await drive.save();
    expect(result.savedCount, 0);
    expect(result.skippedCount, 2);
    expect(drive.requests.every((r) => r.method == 'GET'), isTrue);
  });

  for (final conflicts in [
    [_file('20', 'Show')],
    [_directory('20', 'Show'), _directory('21', 'SHOW')],
  ]) {
    test(
        'ambiguous or file-occupied named destination aborts before writes: '
        '${conflicts.length}', () async {
      final drive = _Drive(share: {
        '0': [_file('1', 'E01.mkv')],
      }, folders: {
        '10': conflicts,
      });
      await expectLater(
          drive.save(),
          throwsA(isA<QuarkSaveException>()
              .having((e) => e.message, 'message', contains('同名冲突'))));
      expect(drive.requests.every((r) => r.method == 'GET'), isTrue);
    });
  }

  for (final directory in [false, true]) {
    test('file-directory conflict aborts the entire plan: $directory',
        () async {
      final drive = _Drive(share: {
        '0': [
          _file('1', 'New.mkv'),
          directory ? _directory('2', 'Conflict') : _file('2', 'Conflict')
        ],
      }, folders: {
        '10': [_directory('20', 'Show')],
        '20': [
          directory ? _file('21', 'Conflict') : _directory('21', 'Conflict')
        ],
      });
      await expectLater(drive.save(), throwsA(isA<QuarkSaveException>()));
      expect(drive.saves, isEmpty);
      expect(drive.creates, isEmpty);
    });
  }

  test('ambiguous existing nested directories never choose the first match',
      () async {
    final drive = _Drive(share: {
      '0': [_file('1', 'New.mkv'), _directory('2', 'Season 1')],
    }, folders: {
      '10': [_directory('20', 'Show')],
      '20': [_directory('21', 'Season 1'), _directory('22', 'season 1')],
    });
    await expectLater(drive.save(), throwsA(isA<QuarkSaveException>()));
    expect(drive.saves, isEmpty);
  });

  test('a deep conflict prevents earlier planned batches from being saved',
      () async {
    final drive = _Drive(share: {
      '0': [_file('1', 'New.mkv'), _directory('2', 'Season 1')],
      '2': [_file('3', 'Conflict')],
    }, folders: {
      '10': [_directory('20', 'Show')],
      '20': [_directory('21', 'Season 1')],
      '21': [_directory('22', 'Conflict')],
    });
    await expectLater(drive.save(), throwsA(isA<QuarkSaveException>()));
    expect(drive.saves, isEmpty);
  });

  for (final invalid in [
    [_file('1', 'same.mkv'), _file('2', 'SAME.mkv')],
    [_file('1', '')],
    [_file('', 'E01.mkv')],
    [_file('0', 'E01.mkv')],
    [_file('1', 'E01.mkv'), _file('1', 'E02.mkv')],
  ]) {
    test('incomplete or conflicting share entries are not saved: $invalid',
        () async {
      final drive = _Drive(share: {'0': invalid});
      await expectLater(drive.save(), throwsA(isA<QuarkSaveException>()));
      expect(drive.saves, isEmpty);
      expect(drive.creates, isEmpty);
    });
  }

  for (final body in [
    {'state': false, 'error': 'denied'},
    {'state': true},
    {'state': true, 'cid': '0'},
    {'state': true, 'cid': '10'},
    {'state': true, 'cid': 'invalid'},
  ]) {
    test('mkdir failure or missing ID never falls back to base: $body',
        () async {
      final drive = _Drive(share: {
        '0': [_file('1', 'E01.mkv')],
      }, folders: {
        '10': [],
      })
        ..createResponse = _response(body);
      await expectLater(drive.save(), throwsA(isA<QuarkSaveException>()));
      expect(drive.creates, hasLength(1));
      expect(drive.saves, isEmpty);
    });
  }

  test('mkdir 405 identifies the stage and is never retried', () async {
    final drive = _Drive(share: {
      '0': [_file('1', 'E01.mkv')],
    }, folders: {
      '10': [],
    })
      ..createResponse = http.Response('blocked', 405);
    await expectLater(
        drive.save(),
        throwsA(isA<QuarkSaveException>().having(
            (e) => e.message, 'message', contains('创建保存目录失败（HTTP 405）'))));
    expect(drive.creates, hasLength(1));
    expect(drive.saves, isEmpty);
  });

  test('later failed batch reports confirmed partial success without retries',
      () async {
    final drive = _Drive(share: {
      '0': [_file('1', 'New.mkv'), _directory('2', 'Season 1')],
      '2': [_file('3', 'E01.mkv')],
    }, folders: {
      '10': [_directory('20', 'Show')],
      '20': [_directory('21', 'Season 1')],
      '21': [],
    })
      ..failSaveNumber = 2;
    await expectLater(
        drive.save(),
        throwsA(isA<QuarkSaveException>()
            .having((e) => e.message, 'partial', contains('部分完成，已确认保存 1 个'))
            .having((e) => e.message, 'stage', contains('提交转存失败（HTTP 405）'))
            .having((e) => e.message, 'uncertain', contains('当前批次结果未确认'))));
    expect(drive.saves, hasLength(2));
  });

  test('incomplete target pagination stops without mkdir or receive', () async {
    final requests = <http.Request>[];
    final client = Cloud115SaveClient(MockClient((request) async {
      requests.add(request);
      expect(request.method, 'GET');
      if (request.url.path == '/share/snap') {
        return _response({
          'state': true,
          'data': {
            'count': 1,
            'list': [_file('1', 'E01.mkv')]
          },
        });
      }
      return _response({
        'state': true,
        'count': 2,
        'data': request.url.queryParameters['offset'] == '0'
            ? [_directory('20', 'Other')]
            : [],
      });
    }));
    await expectLater(
        client.saveShareLink(
          shareUrl: 'https://115.com/s/abc',
          cookie: 'test',
          saveFolderName: 'Show',
        ),
        throwsA(isA<QuarkSaveException>()
            .having((e) => e.message, 'message', contains('分页不完整'))));
    expect(requests, hasLength(3));
  });
}
