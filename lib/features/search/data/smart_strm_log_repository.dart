import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final smartStrmWebhookLogRevisionProvider = StateProvider<int>((ref) => 0);

final smartStrmWebhookLogRepositoryProvider =
    Provider<SmartStrmWebhookLogRepository>(
  (ref) => SmartStrmWebhookLogRepository(
    notifyChanged: () {
      ref.read(smartStrmWebhookLogRevisionProvider.notifier).state++;
    },
  ),
);

final smartStrmWebhookLogsProvider =
    FutureProvider.autoDispose<List<SmartStrmWebhookLogEntry>>((ref) async {
  ref.watch(smartStrmWebhookLogRevisionProvider);
  return ref.read(smartStrmWebhookLogRepositoryProvider).loadEntries();
});

class SmartStrmWebhookLogRepository {
  SmartStrmWebhookLogRepository({
    SharedPreferences? sharedPreferences,
    void Function()? notifyChanged,
  })  : _sharedPreferences = sharedPreferences,
        _notifyChanged = notifyChanged;

  static const _storageKey = 'starflow.smart_strm.logs.v1';
  static const _maxEntries = 100;

  SharedPreferences? _sharedPreferences;
  final void Function()? _notifyChanged;

  Future<SharedPreferences> _prefs() async {
    return _sharedPreferences ??= await SharedPreferences.getInstance();
  }

  Future<List<SmartStrmWebhookLogEntry>> loadEntries() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      final list = decoded is List ? decoded : const [];
      return list
          .whereType<Map>()
          .map((item) => SmartStrmWebhookLogEntry.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> append(SmartStrmWebhookLogEntry entry) async {
    final prefs = await _prefs();
    final entries = await loadEntries();
    final next = [
      entry,
      ...entries,
    ].take(_maxEntries).map((item) => item.toJson()).toList(growable: false);
    await prefs.setString(_storageKey, jsonEncode(next));
    _notifyChanged?.call();
  }

  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_storageKey);
    _notifyChanged?.call();
  }
}

class SmartStrmWebhookLogEntry {
  const SmartStrmWebhookLogEntry({
    required this.createdAt,
    required this.success,
    required this.webhookUrl,
    required this.taskName,
    required this.storagePath,
    required this.message,
    required this.httpStatusCode,
    required this.addedCount,
    required this.payloadText,
  });

  final DateTime createdAt;
  final bool success;
  final String webhookUrl;
  final String taskName;
  final String storagePath;
  final String message;
  final int? httpStatusCode;
  final int? addedCount;
  final String payloadText;

  Map<String, dynamic> toJson() {
    return {
      'createdAt': createdAt.toIso8601String(),
      'success': success,
      'webhookUrl': webhookUrl,
      'taskName': taskName,
      'storagePath': storagePath,
      'message': message,
      'httpStatusCode': httpStatusCode,
      'addedCount': addedCount,
      'payloadText': payloadText,
    };
  }

  factory SmartStrmWebhookLogEntry.fromJson(Map<String, dynamic> json) {
    return SmartStrmWebhookLogEntry(
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      success: json['success'] == true,
      webhookUrl: '${json['webhookUrl'] ?? ''}',
      taskName: '${json['taskName'] ?? ''}',
      storagePath: '${json['storagePath'] ?? ''}',
      message: '${json['message'] ?? ''}',
      httpStatusCode: json['httpStatusCode'] is num
          ? (json['httpStatusCode'] as num).toInt()
          : int.tryParse('${json['httpStatusCode'] ?? ''}'),
      addedCount: json['addedCount'] is num
          ? (json['addedCount'] as num).toInt()
          : int.tryParse('${json['addedCount'] ?? ''}'),
      payloadText: '${json['payloadText'] ?? ''}',
    );
  }
}
