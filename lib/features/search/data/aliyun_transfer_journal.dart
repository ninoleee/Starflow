import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'aliyun_transfer_client.dart';

final aliyunTransferJournalProvider =
    Provider((ref) => AliyunTransferJournal());

Map<String, dynamic> transferFileJson(AliyunTransferFile f) => {
      'file_id': f.id,
      'name': f.name,
      'parent_file_id': f.parentId,
      'type': f.isDirectory ? 'folder' : 'file',
      'size': f.size,
      'content_hash': f.sha1,
      'content_hash_name': 'sha1',
      'path': f.path,
    };
AliyunTransferFile transferFileFromJson(Map<String, dynamic> json,
        {bool allowMissingSha1 = false}) =>
    AliyunTransferFile.parse(json,
        path: (json['path'] as List).cast<String>(),
        allowMissingSha1: allowMissingSha1);

class AliyunTransferJournal {
  AliyunTransferJournal({PreferencesStore? preferences})
      : _preferences = preferences ?? AppPreferencesStore();
  final PreferencesStore _preferences;
  Future<void> _tail = Future.value();
  static const _key = 'starflow.aliyun-transfer-journal.v1';

  Future<List<Map<String, dynamic>>> list() async {
    await _tail;
    return _read();
  }

  Future<List<Map<String, dynamic>>> _read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return [];
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    if (rows.length > 200) throw StateError('Too many transfer records');
    return rows;
  }

  Future<void> put(Map<String, dynamic> record) {
    // Snapshot before queuing; callers continue mutating their in-memory task.
    final snapshot = jsonDecode(jsonEncode(record)) as Map<String, dynamic>;
    final pending = _tail.then((_) async {
      final rows = await _read();
      final index = rows.indexWhere((r) => r['id'] == snapshot['id']);
      if (index < 0) {
        if (rows.length >= 200) throw StateError('Transfer history full');
        rows.insert(0, snapshot);
      } else {
        rows[index] = snapshot;
      }
      await _preferences.setString(_key, jsonEncode(rows));
    });
    _tail = pending.catchError((Object _) {});
    return pending;
  }

  Future<void> remove(String id) {
    final pending = _tail.then((_) async {
      final rows = await _read();
      rows.removeWhere((r) => r['id'] == id);
      await _preferences.setString(_key, jsonEncode(rows));
    });
    _tail = pending.catchError((Object _) {});
    return pending;
  }
}
