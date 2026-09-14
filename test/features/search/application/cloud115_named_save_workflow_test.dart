import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/application/cloud115_save_workflow_service.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

http.Response _response(Object body) => http.Response(jsonEncode(body), 200);

const _config = NetworkStorageConfig(
  cloud115Cookie: 'test',
  cloud115SaveFolderId: '10',
  cloud115SaveFolderPath: '/Library/115',
  smartStrmWebhookUrl: 'https://strm.test/webhook',
  smartStrmTaskName: 'quark-task',
  cloud115SmartStrmTaskName: '115-task',
  smartStrmDelaySeconds: 3,
  refreshMediaSourceIds: ['nas'],
  refreshDelaySeconds: 5,
);

void main() {
  test('all duplicates skip STRM and media refresh and report no additions',
      () async {
    final client = Cloud115SaveClient(MockClient((request) async {
      expect(request.method, 'GET');
      if (request.url.path == '/share/snap') {
        return _response({
          'state': true,
          'data': {
            'count': 1,
            'list': [
              {'fid': '1', 'n': 'Episode.mkv'}
            ],
          },
        });
      }
      return _response({
        'state': true,
        'count': 1,
        'data': [
          request.url.queryParameters['cid'] == '10'
              ? {'cid': '20', 'n': 'Show'}
              : {'fid': '101', 'n': 'episode.MKV'},
        ],
      });
    }));
    final workflow = Cloud115SaveWorkflowService(
      client,
      (_, __) async => fail('No new content to refresh'),
      smartStrm:
          SmartStrmWebhookClient(MockClient((_) async => fail('No STRM'))),
    );
    final progress = <String>[];
    final message = await workflow.save(
      shareUrl: 'https://115.com/s/abc',
      config: _config,
      saveFolderName: 'Show',
      onProgress: (update) => progress.add(update.message),
    );
    expect(message, '已提交到 115，保存 0 个，略过 1 个');
    expect(progress, ['115 保存中...']);
  });

  for (final path in ['/', '/Library/115', '/Library/115/Show']) {
    test('STRM receives the resolved named target under $path', () async {
      final events = <String>[];
      final selectedTarget = path.endsWith('/Show');
      final client = Cloud115SaveClient(MockClient((request) async {
        switch (request.url.path) {
          case '/share/snap':
            return _response({
              'state': true,
              'data': {
                'count': 1,
                'list': [
                  {'fid': '1', 'n': 'Episode.mkv'}
                ],
              },
            });
          case '/files':
            return _response({'state': true, 'count': 0, 'data': []});
          case '/files/add':
            expect(selectedTarget, isFalse);
            expect(Uri.splitQueryString(request.body),
                {'pid': '10', 'cname': 'Show'});
            return _response({'state': true, 'cid': '20'});
          case '/share/receive':
            expect(Uri.splitQueryString(request.body)['cid'],
                selectedTarget ? '10' : '20');
            events.add('save');
            return _response({'state': true});
          default:
            fail('Unexpected request');
        }
      }));
      final expectedPath =
          selectedTarget ? path : '${path == '/' ? '' : path}/Show';
      final workflow = Cloud115SaveWorkflowService(client, (ids, delay) async {
        events.add('refresh');
        expect(ids, ['nas']);
        expect(delay, 5);
      }, smartStrm: SmartStrmWebhookClient(MockClient((request) async {
        events.add('strm');
        final body = jsonDecode(request.body) as Map;
        expect(body['delay'], 3);
        expect(body['task']['name'], '115-task');
        expect(body['task']['storage_path'], expectedPath);
        expect(request.headers['cookie'], isNull);
        return _response({'success': true});
      })));
      final message = await workflow.save(
        shareUrl: 'https://115.com/s/abc',
        config: _config.copyWith(cloud115SaveFolderPath: path),
        saveFolderName: 'Show',
      );
      expect(events, ['save', 'strm', 'refresh']);
      expect(message, '已提交到 115，保存 1 个，略过 0 个，STRM 已延迟 3 秒触发，5 秒后刷新媒体源');
      expect(message, isNot(contains(expectedPath)));
    });
  }
}
