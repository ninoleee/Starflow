import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';

void main() {
  group('SmartStrmWebhookClient', () {
    test('posts a_task payload to webhook url', () async {
      final client = SmartStrmWebhookClient(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(
              request.url.toString(), 'http://127.0.0.1:8024/webhook/token123');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['event'], 'a_task');
          expect(payload['task']['name'], 'movie_task');
          expect(payload['task']['storage_path'], '/quark/movie');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'success': true,
                'message': '新增成功',
                'data': {'added_count': 3},
              }),
            ),
            200,
          );
        }),
      );

      final result = await client.triggerTask(
        webhookUrl: 'http://127.0.0.1:8024/webhook/token123',
        taskName: 'movie_task',
        storagePath: '/quark/movie',
      );
      expect(result.message, '新增成功');
      expect(result.addedCount, 3);
    });

    test('throws when webhook body explicitly reports failure', () async {
      final client = SmartStrmWebhookClient(
        MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'success': false,
                'message': '任务不存在',
              }),
            ),
            200,
          );
        }),
      );

      expect(
        () => client.triggerTask(
          webhookUrl: 'http://127.0.0.1:8024/webhook/token123',
          taskName: 'movie_task',
        ),
        throwsA(
          isA<SmartStrmWebhookException>().having(
            (error) => error.message,
            'message',
            '任务不存在',
          ),
        ),
      );
    });
  });
}
