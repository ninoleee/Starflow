import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/application/cloud115_save_workflow_service.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

http.Response response(Object body) => http.Response(jsonEncode(body), 200);

void main() {
  for (final path in ['/', '/115/Movies']) {
    test('save triggers STRM before refresh using 115 path $path', () async {
      final events = <String>[];
      final client = Cloud115SaveClient(MockClient((request) async {
        if (request.method == 'POST') {
          events.add('save');
          return response({'state': true});
        }
        return response({
          'state': true,
          'data': {
            'count': 1,
            'list': [
              {'fid': '1'}
            ],
          }
        });
      }));
      final webhook = SmartStrmWebhookClient(MockClient((request) async {
        events.add('strm');
        expect(request.url.toString(), 'https://strm.test/webhook');
        final body = jsonDecode(request.body) as Map;
        expect(body['event'], 'a_task');
        expect(body['delay'], 3);
        expect(body['task']['name'], 'movies');
        expect(body['task']['storage_path'], path == '/' ? null : path);
        return response({'success': true});
      }));
      final service = Cloud115SaveWorkflowService(client, (ids, delay) async {
        events.add('refresh');
        expect(ids, ['nas']);
        expect(delay, 5);
      }, smartStrm: webhook);
      final message = await service.save(
          shareUrl: 'https://115.com/s/abc',
          config: NetworkStorageConfig(
              cloud115Cookie: 'test',
              cloud115SaveFolderPath: path,
              quarkSaveFolderPath: '/quark',
              smartStrmWebhookUrl: 'https://strm.test/webhook',
              smartStrmTaskName: 'quark-movies',
              cloud115SmartStrmTaskName: 'movies',
              smartStrmDelaySeconds: 3,
              refreshDelaySeconds: 5,
              refreshMediaSourceIds: ['nas']));
      expect(events, ['save', 'strm', 'refresh']);
      expect(message, contains('STRM 已延迟 3 秒触发'));
    });
  }

  test('STRM failure preserves save success and still refreshes', () async {
    var refreshed = false;
    final client = Cloud115SaveClient(
        MockClient((request) async => response(request.method == 'POST'
            ? {'state': true}
            : {
                'state': true,
                'data': {
                  'count': 1,
                  'list': [
                    {'fid': '1'}
                  ]
                }
              })));
    final webhook = SmartStrmWebhookClient(MockClient((request) async {
      expect(jsonDecode(request.body)['delay'], 1);
      return http.Response('error', 500);
    }));
    final service = Cloud115SaveWorkflowService(client, (ids, delay) async {
      refreshed = true;
    }, smartStrm: webhook);
    final message = await service.save(
        shareUrl: 'https://115.com/s/abc',
        config: const NetworkStorageConfig(
            cloud115Cookie: 'test',
            smartStrmWebhookUrl: 'https://strm.test/webhook',
            cloud115SmartStrmTaskName: 'movies',
            smartStrmDelaySeconds: 0,
            refreshMediaSourceIds: ['nas']));
    expect(refreshed, isTrue);
    expect(message, contains('已保存到 115'));
    expect(message, contains('STRM 触发失败'));
  });

  test('save failure never triggers STRM or refresh', () async {
    final service = Cloud115SaveWorkflowService(
        Cloud115SaveClient(MockClient((_) async => response({'state': false}))),
        (ids, delay) async => fail('Must not refresh'),
        smartStrm: SmartStrmWebhookClient(
            MockClient((_) async => fail('Must not trigger'))));
    await expectLater(
        service.save(
            shareUrl: 'https://115.com/s/abc',
            config: const NetworkStorageConfig(
                cloud115Cookie: 'test',
                smartStrmWebhookUrl: 'https://strm.test/webhook',
                cloud115SmartStrmTaskName: 'movies',
                refreshMediaSourceIds: ['nas'])),
        throwsA(isA<QuarkSaveException>()));
  });

  test('settings round trip and legacy defaults preserve both providers', () {
    final config = NetworkStorageConfig.fromJson({}).copyWith(
      cloud115Cookie: 'test',
      cloud115SmartStrmTaskName: '115-movies',
      smartStrmTaskName: 'quark-movies',
      cloud115SaveFolderId: '42',
      cloud115SaveFolderPath: '/Movies',
      quarkCookie: 'quark',
    );
    final restored = NetworkStorageConfig.fromJson(config.toJson());
    expect(restored.cloud115SaveFolderId, '42');
    expect(restored.copyWith(quarkCookie: 'new').cloud115Cookie, 'test');
    expect(restored.quarkCookie, 'quark');
    expect(restored.cloud115SmartStrmTaskName, '115-movies');
    expect(
        restored
            .copyWith(smartStrmTaskName: 'new-quark')
            .cloud115SmartStrmTaskName,
        '115-movies');
    expect(
        NetworkStorageConfig.fromJson({'smartStrmTaskName': 'old-quark'})
            .cloud115SmartStrmTaskName,
        isEmpty);
    expect(restored.hasAnyConfigured, isTrue);
    expect(NetworkStorageConfig.fromJson({}).cloud115SaveFolderId, '0');
  });

  test(
      'parses supported domains and rejects credential forwarding to other hosts',
      () {
    expect(
        Cloud115ShareLink.parse('https://115cdn.com/s/abc?password=1234')
            .password,
        '1234');
    expect(Cloud115ShareLink.parse('https://anxia.com/s/abc 接收码：abcd').password,
        'abcd');
    expect(() => Cloud115ShareLink.parse('https://115.com.evil.test/s/abc'),
        throwsA(isA<QuarkSaveException>()));
  });

  test('paginates before saving all top-level entries with separate password',
      () async {
    var calls = 0;
    final client = Cloud115SaveClient(MockClient((request) async {
      calls++;
      expect(request.headers['cookie'], 'test');
      if (request.method == 'POST') {
        expect(request.url.path, '/share/receive');
        final body = Uri.splitQueryString(request.body);
        expect(body['file_id'], '1,2');
        expect(body['cid'], '42');
        expect(body['receive_code'], '1234');
        return response({'state': true});
      }
      final offset = request.url.queryParameters['offset'];
      return response({
        'state': true,
        'data': {
          'count': 2,
          'list': [
            offset == '0' ? {'fid': '1'} : {'cid': '2'}
          ]
        }
      });
    }));
    expect(
        await client.saveShareLink(
            shareUrl: 'https://115.com/s/abc',
            cookie: 'test',
            password: '1234',
            folderId: '42'),
        2);
    expect(calls, 3);
  });

  test('failed validation never submits a save', () async {
    final client = Cloud115SaveClient(MockClient((request) async {
      expect(request.method, 'GET');
      return response({'state': false, 'error': 'expired'});
    }));
    await expectLater(
        client.saveShareLink(shareUrl: 'https://115.com/s/abc', cookie: 'test'),
        throwsA(isA<QuarkSaveException>()));
  });

  test('folder picker omits files and preserves parent path', () async {
    final client = Cloud115SaveClient(MockClient((request) async => response({
          'state': true,
          'count': 2,
          'data': [
            {'cid': '2', 'n': 'Movies'},
            {'fid': '3', 'cid': '0', 'n': 'file.mkv'}
          ],
        })));
    final entries =
        await client.listDirectories(cookie: 'test', parentPath: '/Library');
    expect(entries.single.path, '/Library/Movies');
  });

  test('refresh failure retains successful save message', () async {
    final client = Cloud115SaveClient(
        MockClient((request) async => response(request.method == 'POST'
            ? {'state': true}
            : {
                'state': true,
                'data': {
                  'count': 1,
                  'list': [
                    {'fid': '1'}
                  ]
                },
              })));
    final service = Cloud115SaveWorkflowService(client, (ids, delay) async {
      throw StateError('refresh failed');
    }, smartStrm: SmartStrmWebhookClient(MockClient((_) async {
      fail('Unconfigured SmartStrm must not be called');
    })));
    final message = await service.save(
        shareUrl: 'https://115.com/s/abc',
        config: const NetworkStorageConfig(
            cloud115Cookie: 'test',
            refreshMediaSourceIds: ['nas'],
            smartStrmWebhookUrl: 'https://strm.test/webhook',
            smartStrmTaskName: 'quark-only'));
    expect(message, contains('已保存到 115'));
    expect(message, contains('刷新失败'));
  });
}
