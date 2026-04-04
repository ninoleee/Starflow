import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final smartStrmWebhookClientProvider = Provider<SmartStrmWebhookClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return SmartStrmWebhookClient(client);
});

class SmartStrmWebhookClient {
  SmartStrmWebhookClient(this._client);

  final http.Client _client;

  Future<void> triggerTask({
    required String webhookUrl,
    required String taskName,
    String storagePath = '',
    int delay = 0,
  }) async {
    final trimmedUrl = webhookUrl.trim();
    final trimmedTask = taskName.trim();
    if (trimmedUrl.isEmpty) {
      throw const SmartStrmWebhookException('请先填写 SmartStrm Webhook 地址');
    }
    if (trimmedTask.isEmpty) {
      throw const SmartStrmWebhookException('请先填写 SmartStrm 任务名');
    }

    final response = await _client.post(
      Uri.parse(trimmedUrl),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'event': 'a_task',
        if (delay > 0) 'delay': delay,
        'task': {
          'name': trimmedTask,
          if (storagePath.trim().isNotEmpty) 'storage_path': storagePath.trim(),
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SmartStrmWebhookException(
        'SmartStrm Webhook 请求失败：HTTP ${response.statusCode}',
      );
    }
  }
}

class SmartStrmWebhookException implements Exception {
  const SmartStrmWebhookException(this.message);

  final String message;

  @override
  String toString() => message;
}
