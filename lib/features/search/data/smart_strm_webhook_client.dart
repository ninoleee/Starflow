import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/search/data/smart_strm_log_repository.dart';

final smartStrmWebhookClientProvider = Provider<SmartStrmWebhookClient>((ref) {
  final client = ref.watch(starflowHttpClientProvider);
  return SmartStrmWebhookClient(
    client,
    logRepository: ref.read(smartStrmWebhookLogRepositoryProvider),
  );
});

class SmartStrmWebhookClient {
  SmartStrmWebhookClient(
    this._client, {
    SmartStrmWebhookLogRepository? logRepository,
  }) : _logRepository = logRepository;

  final http.Client _client;
  final SmartStrmWebhookLogRepository? _logRepository;

  Future<SmartStrmTriggerResult> triggerTask({
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

    final trimmedStoragePath = storagePath.trim();
    final requestBody = {
      'event': 'a_task',
      if (delay > 0) 'delay': delay,
      'task': {
        'name': trimmedTask,
        if (trimmedStoragePath.isNotEmpty) 'storage_path': trimmedStoragePath,
      },
    };

    try {
      final response = await _client.post(
        Uri.parse(trimmedUrl),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      final payload = _decode(response);
      final payloadText = _stringifyPayload(response, payload);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = 'SmartStrm Webhook 请求失败：HTTP ${response.statusCode}';
        await _appendLog(
          success: false,
          webhookUrl: trimmedUrl,
          taskName: trimmedTask,
          storagePath: trimmedStoragePath,
          message: message,
          httpStatusCode: response.statusCode,
          addedCount: _extractAddedCount(payload),
          payloadText: payloadText,
        );
        throw SmartStrmWebhookException(message);
      }
      if (_looksLikeFailure(payload)) {
        final message = _resolveErrorMessage(payload) ?? 'SmartStrm 返回了失败结果';
        await _appendLog(
          success: false,
          webhookUrl: trimmedUrl,
          taskName: trimmedTask,
          storagePath: trimmedStoragePath,
          message: message,
          httpStatusCode: response.statusCode,
          addedCount: _extractAddedCount(payload),
          payloadText: payloadText,
        );
        throw SmartStrmWebhookException(message);
      }
      final result = SmartStrmTriggerResult(
        message: _extractMessage(payload),
        addedCount: _extractAddedCount(payload),
        rawPayload: payload,
      );
      await _appendLog(
        success: true,
        webhookUrl: trimmedUrl,
        taskName: trimmedTask,
        storagePath: trimmedStoragePath,
        message:
            result.message.trim().isEmpty ? 'SmartStrm 任务触发成功' : result.message,
        httpStatusCode: response.statusCode,
        addedCount: result.addedCount,
        payloadText: payloadText,
      );
      return result;
    } catch (error) {
      if (error is SmartStrmWebhookException) {
        rethrow;
      }
      final message = 'SmartStrm Webhook 请求异常：$error';
      await _appendLog(
        success: false,
        webhookUrl: trimmedUrl,
        taskName: trimmedTask,
        storagePath: trimmedStoragePath,
        message: message,
        payloadText: '',
      );
      throw SmartStrmWebhookException(message);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.trim().isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return const {};
    }
    return const {};
  }

  bool _looksLikeFailure(Map<String, dynamic> payload) {
    if (payload.isEmpty) {
      return false;
    }
    final boolFields = [
      payload['success'],
      payload['ok'],
      payload['result'],
    ];
    if (boolFields.any((value) => value == false)) {
      return true;
    }
    final status =
        '${payload['status'] ?? payload['state'] ?? ''}'.trim().toLowerCase();
    if (status == 'error' ||
        status == 'failed' ||
        status == 'fail' ||
        status == 'false') {
      return true;
    }
    final codeValue = payload['code'];
    if (codeValue is num && codeValue >= 400) {
      return true;
    }
    return false;
  }

  String _extractMessage(Map<String, dynamic> payload) {
    for (final key in ['message', 'msg', 'detail']) {
      final value = '${payload[key] ?? ''}'.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    final data = payload['data'];
    if (data is Map) {
      for (final key in ['message', 'msg', 'detail']) {
        final value = '${data[key] ?? ''}'.trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return '';
  }

  int? _extractAddedCount(Map<String, dynamic> payload) {
    final preferredKeys = [
      'addedCount',
      'added_count',
      'added',
      'createdCount',
      'created_count',
      'created',
      'successCount',
      'success_count',
      'successNum',
      'success_num',
      'insertedCount',
      'inserted_count',
      'inserted',
      'count',
      'total',
    ];
    final direct = _findCountInMap(payload, preferredKeys);
    if (direct != null) {
      return direct;
    }
    final data = payload['data'];
    if (data is Map) {
      final nested = _findCountInMap(
        Map<String, dynamic>.from(data),
        preferredKeys,
      );
      if (nested != null) {
        return nested;
      }
    }
    final message = _extractMessage(payload);
    final messageMatch = RegExp(r'(\d+)').firstMatch(message);
    return int.tryParse(messageMatch?.group(1) ?? '');
  }

  int? _findCountInMap(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = payload[key];
      if (value is int && value >= 0) {
        return value;
      }
      if (value is num && value >= 0) {
        return value.toInt();
      }
      final parsed = int.tryParse('${value ?? ''}'.trim());
      if (parsed != null && parsed >= 0) {
        return parsed;
      }
    }
    return null;
  }

  String? _resolveErrorMessage(Map<String, dynamic> payload) {
    final message = _extractMessage(payload);
    return message.isEmpty ? null : message;
  }

  String _stringifyPayload(
    http.Response response,
    Map<String, dynamic> payload,
  ) {
    if (payload.isNotEmpty) {
      try {
        return const JsonEncoder.withIndent('  ').convert(payload);
      } catch (_) {
        return payload.toString();
      }
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) {
      return '';
    }
    return body.length > 4000 ? '${body.substring(0, 4000)}…' : body;
  }

  Future<void> _appendLog({
    required bool success,
    required String webhookUrl,
    required String taskName,
    required String storagePath,
    required String message,
    int? httpStatusCode,
    int? addedCount,
    String payloadText = '',
  }) async {
    final repository = _logRepository;
    if (repository == null) {
      return;
    }
    await repository.append(
      SmartStrmWebhookLogEntry(
        createdAt: DateTime.now(),
        success: success,
        webhookUrl: webhookUrl,
        taskName: taskName,
        storagePath: storagePath,
        message: message,
        httpStatusCode: httpStatusCode,
        addedCount: addedCount,
        payloadText: payloadText,
      ),
    );
  }
}

class SmartStrmTriggerResult {
  const SmartStrmTriggerResult({
    required this.message,
    required this.addedCount,
    required this.rawPayload,
  });

  final String message;
  final int? addedCount;
  final Map<String, dynamic> rawPayload;
}

class SmartStrmWebhookException implements Exception {
  const SmartStrmWebhookException(this.message);

  final String message;

  @override
  String toString() => message;
}
