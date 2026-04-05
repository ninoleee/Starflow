import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';

final localStorageCacheRepositoryProvider =
    Provider<LocalStorageCacheRepository>(
  (ref) => LocalStorageCacheRepository(),
);

class LocalStorageCacheRepository {
  LocalStorageCacheRepository({
    SharedPreferences? sharedPreferences,
  }) : _sharedPreferences = sharedPreferences;

  static const _detailCacheKey = 'starflow.local_storage.detail_cache.v1';

  SharedPreferences? _sharedPreferences;

  Future<SharedPreferences> _prefs() async {
    return _sharedPreferences ??= await SharedPreferences.getInstance();
  }

  Future<MediaDetailTarget?> loadDetailTarget(MediaDetailTarget seedTarget) async {
    final payload = await _loadDetailPayload();
    for (final lookupKey in buildLookupKeys(seedTarget)) {
      final recordId = payload.lookupKeys[lookupKey];
      if (recordId == null) {
        continue;
      }
      final record = payload.records[recordId];
      if (record != null) {
        return record.target;
      }
    }
    return null;
  }

  Future<void> saveDetailTarget({
    required MediaDetailTarget seedTarget,
    required MediaDetailTarget resolvedTarget,
  }) async {
    final lookupKeys = {
      ...buildLookupKeys(seedTarget),
      ...buildLookupKeys(resolvedTarget),
    }.where((item) => item.trim().isNotEmpty).toSet();
    if (lookupKeys.isEmpty) {
      return;
    }

    final payload = await _loadDetailPayload();
    String? recordId;
    for (final lookupKey in lookupKeys) {
      final candidate = payload.lookupKeys[lookupKey];
      if (candidate != null && payload.records.containsKey(candidate)) {
        recordId = candidate;
        break;
      }
    }
    recordId ??= lookupKeys.first;

    final existing = payload.records[recordId];
    final mergedLookupKeys = {
      if (existing != null) ...existing.lookupKeys,
      ...lookupKeys,
    }.toList(growable: false)
      ..sort();

    final nextRecord = _CachedDetailRecord(
      id: recordId,
      lookupKeys: mergedLookupKeys,
      updatedAt: DateTime.now(),
      target: resolvedTarget,
    );

    final nextRecords = <String, _CachedDetailRecord>{
      ...payload.records,
      recordId: nextRecord,
    };
    final nextLookupKeys = <String, String>{
      ...payload.lookupKeys,
    };
    for (final lookupKey in mergedLookupKeys) {
      nextLookupKeys[lookupKey] = recordId;
    }

    await _saveDetailPayload(
      _DetailCachePayload(
        records: nextRecords,
        lookupKeys: nextLookupKeys,
      ),
    );
  }

  Future<LocalStorageCacheSummary> inspectDetailCache() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_detailCacheKey) ?? '';
    final payload = await _loadDetailPayload();
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.detailData,
      entryCount: payload.records.length,
      totalBytes: utf8.encode(raw).length,
    );
  }

  Future<void> clearDetailCache() async {
    final prefs = await _prefs();
    await prefs.remove(_detailCacheKey);
  }

  Future<void> clearCache(LocalStorageCacheType type) async {
    switch (type) {
      case LocalStorageCacheType.detailData:
        await clearDetailCache();
        return;
      case LocalStorageCacheType.images:
        return;
    }
  }

  static List<String> buildLookupKeys(MediaDetailTarget target) {
    final keys = <String>{};

    void addKey(String key) {
      final trimmed = key.trim();
      if (trimmed.isNotEmpty) {
        keys.add(trimmed);
      }
    }

    final sourceId = target.sourceId.trim();
    final itemId = target.itemId.trim();
    if (sourceId.isNotEmpty && itemId.isNotEmpty) {
      addKey('library|$sourceId|$itemId');
    }

    final doubanId = target.doubanId.trim();
    if (doubanId.isNotEmpty) {
      addKey('douban|$doubanId');
    }

    final imdbId = target.imdbId.trim().toLowerCase();
    if (imdbId.isNotEmpty) {
      addKey('imdb|$imdbId');
    }

    final normalizedTitle = _normalizeLookupText(target.title);
    if (normalizedTitle.isNotEmpty) {
      addKey(
        'title|$normalizedTitle|${target.year}|${target.isSeries ? 'series' : 'movie'}',
      );
    }

    final query = target.searchQuery.trim();
    final normalizedQuery = _normalizeLookupText(query);
    if (normalizedQuery.isNotEmpty && normalizedQuery != normalizedTitle) {
      addKey(
        'query|$normalizedQuery|${target.year}|${target.isSeries ? 'series' : 'movie'}',
      );
    }

    return keys.toList(growable: false);
  }

  Future<_DetailCachePayload> _loadDetailPayload() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_detailCacheKey);
    if (raw == null || raw.isEmpty) {
      return const _DetailCachePayload();
    }

    try {
      return _DetailCachePayload.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const _DetailCachePayload();
    }
  }

  Future<void> _saveDetailPayload(_DetailCachePayload payload) async {
    final prefs = await _prefs();
    await prefs.setString(_detailCacheKey, jsonEncode(payload.toJson()));
  }
}

String _normalizeLookupText(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.isEmpty) {
    return '';
  }
  return lower.replaceAll(
    RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'),
    '',
  );
}

class _DetailCachePayload {
  const _DetailCachePayload({
    this.records = const {},
    this.lookupKeys = const {},
  });

  final Map<String, _CachedDetailRecord> records;
  final Map<String, String> lookupKeys;

  Map<String, dynamic> toJson() {
    return {
      'records': records.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'lookupKeys': lookupKeys,
    };
  }

  factory _DetailCachePayload.fromJson(Map<String, dynamic> json) {
    return _DetailCachePayload(
      records:
          (json['records'] as Map<dynamic, dynamic>? ?? const {})
              .map(
                (key, value) => MapEntry(
                  '$key',
                  _CachedDetailRecord.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
                ),
              ),
      lookupKeys:
          (json['lookupKeys'] as Map<dynamic, dynamic>? ?? const {})
              .map((key, value) => MapEntry('$key', '$value')),
    );
  }
}

class _CachedDetailRecord {
  const _CachedDetailRecord({
    required this.id,
    required this.lookupKeys,
    required this.updatedAt,
    required this.target,
  });

  final String id;
  final List<String> lookupKeys;
  final DateTime updatedAt;
  final MediaDetailTarget target;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lookupKeys': lookupKeys,
      'updatedAt': updatedAt.toIso8601String(),
      'target': target.toJson(),
    };
  }

  factory _CachedDetailRecord.fromJson(Map<String, dynamic> json) {
    return _CachedDetailRecord(
      id: json['id'] as String? ?? '',
      lookupKeys:
          (json['lookupKeys'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      target: MediaDetailTarget.fromJson(
        Map<String, dynamic>.from(
          (json['target'] as Map?) ?? const {},
        ),
      ),
    );
  }
}
