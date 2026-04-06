import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localStorageCacheRepositoryProvider =
    Provider<LocalStorageCacheRepository>(
  (ref) => LocalStorageCacheRepository(
    notifyDetailCacheChanged: () {
      ref.read(localStorageDetailCacheRevisionProvider.notifier).state++;
    },
  ),
);

enum DetailMetadataRefreshStatus {
  never,
  succeeded,
  failed,
}

extension DetailMetadataRefreshStatusX on DetailMetadataRefreshStatus {
  static DetailMetadataRefreshStatus fromJsonValue(Object? value) {
    final normalized = '$value'.trim().toLowerCase();
    switch (normalized) {
      case 'succeeded':
        return DetailMetadataRefreshStatus.succeeded;
      case 'failed':
        return DetailMetadataRefreshStatus.failed;
      case 'never':
      case '':
        return DetailMetadataRefreshStatus.never;
      default:
        return DetailMetadataRefreshStatus.never;
    }
  }
}

class LocalStorageCacheRepository {
  LocalStorageCacheRepository({
    PreferencesStore? preferences,
    SharedPreferences? sharedPreferences,
    void Function()? notifyDetailCacheChanged,
  })  : assert(preferences == null || sharedPreferences == null),
        _preferences = preferences ??
            (sharedPreferences == null
                ? AppPreferencesStore()
                : SharedPreferencesStore(sharedPreferences)),
        _notifyDetailCacheChanged = notifyDetailCacheChanged;

  static const _detailCacheKey = 'starflow.local_storage.detail_cache.v1';

  final PreferencesStore _preferences;
  final void Function()? _notifyDetailCacheChanged;

  Future<CachedDetailState?> loadDetailState(
    MediaDetailTarget seedTarget,
  ) async {
    final payload = await _loadDetailPayload();
    for (final lookupKey in buildLookupKeys(seedTarget)) {
      final recordId = payload.lookupKeys[lookupKey];
      if (recordId == null) {
        continue;
      }
      final record = payload.records[recordId];
      if (record != null) {
        return CachedDetailState(
          target: record.target,
          libraryMatchChoices: record.libraryMatchChoices,
          selectedLibraryMatchIndex: record.selectedLibraryMatchIndex,
          metadataRefreshStatus: record.metadataRefreshStatus,
        );
      }
    }
    return null;
  }

  Future<MediaDetailTarget?> loadDetailTarget(
      MediaDetailTarget seedTarget) async {
    return (await loadDetailState(seedTarget))?.target;
  }

  Future<DetailMetadataRefreshStatus> loadDetailMetadataRefreshStatus(
    MediaDetailTarget seedTarget,
  ) async {
    return (await loadDetailState(seedTarget))?.metadataRefreshStatus ??
        DetailMetadataRefreshStatus.never;
  }

  Future<void> saveDetailTarget({
    required MediaDetailTarget seedTarget,
    required MediaDetailTarget resolvedTarget,
    DetailMetadataRefreshStatus? metadataRefreshStatus,
    List<MediaDetailTarget>? libraryMatchChoices,
    int? selectedLibraryMatchIndex,
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
    final nextLibraryMatchChoices = libraryMatchChoices != null
        ? List<MediaDetailTarget>.unmodifiable(libraryMatchChoices)
        : existing?.libraryMatchChoices ?? const <MediaDetailTarget>[];
    final normalizedSelectedLibraryMatchIndex = nextLibraryMatchChoices.isEmpty
        ? 0
        : (selectedLibraryMatchIndex ??
                existing?.selectedLibraryMatchIndex ??
                0)
            .clamp(0, nextLibraryMatchChoices.length - 1);

    final nextRecord = _CachedDetailRecord(
      id: recordId,
      lookupKeys: mergedLookupKeys,
      updatedAt: DateTime.now(),
      target: resolvedTarget,
      libraryMatchChoices: nextLibraryMatchChoices,
      selectedLibraryMatchIndex: normalizedSelectedLibraryMatchIndex,
      metadataRefreshStatus: metadataRefreshStatus ??
          existing?.metadataRefreshStatus ??
          DetailMetadataRefreshStatus.never,
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
    _notifyDetailCacheChanged?.call();
  }

  Future<LocalStorageCacheSummary> inspectDetailCache() async {
    final raw = await _preferences.getString(_detailCacheKey) ?? '';
    final payload = await _loadDetailPayload();
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.detailData,
      entryCount: payload.records.length,
      totalBytes: utf8.encode(raw).length,
    );
  }

  Future<void> clearDetailCache() async {
    await _preferences.remove(_detailCacheKey);
    _notifyDetailCacheChanged?.call();
  }

  Future<void> clearDetailCacheForSource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }

    final payload = await _loadDetailPayload();
    if (payload.records.isEmpty || payload.lookupKeys.isEmpty) {
      return;
    }

    final recordIdsToRemove = payload.records.values
        .where(
          (record) => record.target.sourceId.trim() == normalizedSourceId,
        )
        .map((record) => record.id)
        .toSet();
    if (recordIdsToRemove.isEmpty) {
      return;
    }

    final nextRecords = Map<String, _CachedDetailRecord>.from(payload.records)
      ..removeWhere((key, _) => recordIdsToRemove.contains(key));
    final nextLookupKeys = Map<String, String>.from(payload.lookupKeys)
      ..removeWhere((_, recordId) => recordIdsToRemove.contains(recordId));

    await _saveDetailPayload(
      _DetailCachePayload(
        records: nextRecords,
        lookupKeys: nextLookupKeys,
      ),
    );
    _notifyDetailCacheChanged?.call();
  }

  Future<void> clearCache(LocalStorageCacheType type) async {
    switch (type) {
      case LocalStorageCacheType.nasMetadataIndex:
      case LocalStorageCacheType.playbackMemory:
      case LocalStorageCacheType.televisionSearchPreferences:
        return;
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

    final tmdbId = target.tmdbId.trim();
    if (tmdbId.isNotEmpty) {
      addKey('tmdb|$tmdbId');
    }

    final tvdbId = target.tvdbId.trim();
    if (tvdbId.isNotEmpty) {
      addKey('tvdb|$tvdbId');
    }

    final wikidataId = target.wikidataId.trim().toUpperCase();
    if (wikidataId.isNotEmpty) {
      addKey('wikidata|$wikidataId');
    }

    final normalizedTitle = _normalizeLookupText(target.title);
    if (normalizedTitle.isNotEmpty) {
      addKey(
        'title|$normalizedTitle|${target.year}|${target.isSeries ? 'series' : 'movie'}',
      );
      if (target.year > 0) {
        addKey('title|$normalizedTitle|${target.year}');
      }
      addKey('title|$normalizedTitle|${target.isSeries ? 'series' : 'movie'}');
      addKey('title|$normalizedTitle');
    }

    final query = target.searchQuery.trim();
    final normalizedQuery = _normalizeLookupText(query);
    if (normalizedQuery.isNotEmpty && normalizedQuery != normalizedTitle) {
      addKey(
        'query|$normalizedQuery|${target.year}|${target.isSeries ? 'series' : 'movie'}',
      );
      if (target.year > 0) {
        addKey('query|$normalizedQuery|${target.year}');
      }
      addKey('query|$normalizedQuery|${target.isSeries ? 'series' : 'movie'}');
      addKey('query|$normalizedQuery');
    }

    return keys.toList(growable: false);
  }

  Future<_DetailCachePayload> _loadDetailPayload() async {
    final raw = await _preferences.getString(_detailCacheKey);
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
    await _preferences.setString(_detailCacheKey, jsonEncode(payload.toJson()));
  }
}

class CachedDetailState {
  const CachedDetailState({
    required this.target,
    this.libraryMatchChoices = const [],
    this.selectedLibraryMatchIndex = 0,
    this.metadataRefreshStatus = DetailMetadataRefreshStatus.never,
  });

  final MediaDetailTarget target;
  final List<MediaDetailTarget> libraryMatchChoices;
  final int selectedLibraryMatchIndex;
  final DetailMetadataRefreshStatus metadataRefreshStatus;
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
      records: (json['records'] as Map<dynamic, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(
          '$key',
          _CachedDetailRecord.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
      lookupKeys: (json['lookupKeys'] as Map<dynamic, dynamic>? ?? const {})
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
    this.libraryMatchChoices = const [],
    this.selectedLibraryMatchIndex = 0,
    this.metadataRefreshStatus = DetailMetadataRefreshStatus.never,
  });

  final String id;
  final List<String> lookupKeys;
  final DateTime updatedAt;
  final MediaDetailTarget target;
  final List<MediaDetailTarget> libraryMatchChoices;
  final int selectedLibraryMatchIndex;
  final DetailMetadataRefreshStatus metadataRefreshStatus;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lookupKeys': lookupKeys,
      'updatedAt': updatedAt.toIso8601String(),
      'target': target.toJson(),
      'libraryMatchChoices':
          libraryMatchChoices.map((item) => item.toJson()).toList(),
      'selectedLibraryMatchIndex': selectedLibraryMatchIndex,
      'metadataRefreshStatus': metadataRefreshStatus.name,
    };
  }

  factory _CachedDetailRecord.fromJson(Map<String, dynamic> json) {
    return _CachedDetailRecord(
      id: json['id'] as String? ?? '',
      lookupKeys: (json['lookupKeys'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      target: MediaDetailTarget.fromJson(
        Map<String, dynamic>.from(
          (json['target'] as Map?) ?? const {},
        ),
      ),
      libraryMatchChoices:
          (json['libraryMatchChoices'] as List<dynamic>? ?? const [])
              .map(
                (item) => MediaDetailTarget.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false),
      selectedLibraryMatchIndex:
          (json['selectedLibraryMatchIndex'] as num?)?.toInt() ?? 0,
      metadataRefreshStatus: DetailMetadataRefreshStatusX.fromJsonValue(
        json['metadataRefreshStatus'],
      ),
    );
  }
}
