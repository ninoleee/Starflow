import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localStorageCacheRepositoryProvider =
    Provider<LocalStorageCacheRepository>(
  (ref) {
    final repository = LocalStorageCacheRepository(
      notifyDetailCacheChanged: (event) {
        ref.read(localStorageDetailCacheChangeProvider.notifier).apply(event);
      },
      detailCacheChangeNotificationDelay: const Duration(milliseconds: 180),
    );
    ref.onDispose(repository.dispose);
    return repository;
  },
);

enum DetailMetadataRefreshStatus {
  never,
  succeeded,
  failed,
}

class DetailTargetCacheSaveRequest {
  const DetailTargetCacheSaveRequest({
    required this.seedTarget,
    required this.resolvedTarget,
    this.metadataRefreshStatus,
    this.libraryMatchChoices,
    this.selectedLibraryMatchIndex,
    this.subtitleSearchChoices,
    this.selectedSubtitleSearchIndex,
  });

  final MediaDetailTarget seedTarget;
  final MediaDetailTarget resolvedTarget;
  final DetailMetadataRefreshStatus? metadataRefreshStatus;
  final List<MediaDetailTarget>? libraryMatchChoices;
  final int? selectedLibraryMatchIndex;
  final List<CachedSubtitleSearchOption>? subtitleSearchChoices;
  final int? selectedSubtitleSearchIndex;
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
    void Function(LocalStorageDetailCacheChangeEvent event)?
        notifyDetailCacheChanged,
    this.detailCacheChangeNotificationDelay = Duration.zero,
  })  : assert(preferences == null || sharedPreferences == null),
        _preferences = preferences ??
            (sharedPreferences == null
                ? AppPreferencesStore()
                : SharedPreferencesStore(sharedPreferences)),
        _notifyDetailCacheChanged = notifyDetailCacheChanged;

  static const _detailCacheKey = 'starflow.local_storage.detail_cache.v1';
  static const _embyLibraryCacheKey =
      'starflow.local_storage.emby_library_cache.v1';

  final PreferencesStore _preferences;
  final void Function(LocalStorageDetailCacheChangeEvent event)?
      _notifyDetailCacheChanged;
  final Duration detailCacheChangeNotificationDelay;
  Timer? _detailCacheChangeNotificationTimer;
  final Set<String> _pendingDetailCacheChangedSourceIds = <String>{};
  final Set<String> _pendingDetailCacheChangedLookupKeys = <String>{};
  final Set<String> _pendingDetailCacheChangedRecordIds = <String>{};
  final Set<LocalStorageDetailCacheChangedField>
      _pendingDetailCacheChangedFields =
      <LocalStorageDetailCacheChangedField>{};
  bool _pendingDetailCacheInvalidateAll = false;
  _DetailCachePayload? _detailPayloadCache;
  Future<_DetailCachePayload>? _detailPayloadLoadFuture;
  _EmbyLibraryCachePayload? _embyLibraryPayloadCache;
  Future<_EmbyLibraryCachePayload>? _embyLibraryPayloadLoadFuture;

  void dispose() {
    _detailCacheChangeNotificationTimer?.cancel();
    _detailCacheChangeNotificationTimer = null;
    _pendingDetailCacheChangedSourceIds.clear();
    _pendingDetailCacheChangedLookupKeys.clear();
    _pendingDetailCacheChangedRecordIds.clear();
    _pendingDetailCacheChangedFields.clear();
    _pendingDetailCacheInvalidateAll = false;
    _detailPayloadCache = null;
    _detailPayloadLoadFuture = null;
    _embyLibraryPayloadCache = null;
    _embyLibraryPayloadLoadFuture = null;
  }

  Future<void> primeDetailPayload() async {
    await _loadDetailPayload();
  }

  Future<CachedEmbyLibrarySnapshot> loadEmbyLibrarySnapshot(
    String sourceId,
  ) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return const CachedEmbyLibrarySnapshot();
    }
    final payload = await _loadEmbyLibraryPayload();
    return payload.sources[normalizedSourceId] ??
        const CachedEmbyLibrarySnapshot();
  }

  Future<void> saveEmbyLibrarySnapshot({
    required String sourceId,
    required DateTime refreshedAt,
    List<MediaCollection> collections = const <MediaCollection>[],
    List<MediaItem> fallbackItems = const <MediaItem>[],
    Map<String, List<MediaItem>> itemsBySection =
        const <String, List<MediaItem>>{},
  }) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }

    final payload = await _loadEmbyLibraryPayload();
    final snapshot = CachedEmbyLibrarySnapshot(
      refreshedAt: refreshedAt,
      collections: List<MediaCollection>.unmodifiable(collections),
      fallbackItems: List<MediaItem>.unmodifiable(fallbackItems),
      itemsBySection: Map<String, List<MediaItem>>.unmodifiable(
        itemsBySection.map(
          (key, value) => MapEntry(
            key.trim(),
            List<MediaItem>.unmodifiable(value),
          ),
        )..removeWhere((key, _) => key.isEmpty),
      ),
    );
    await _saveEmbyLibraryPayload(
      _EmbyLibraryCachePayload(
        sources: <String, CachedEmbyLibrarySnapshot>{
          ...payload.sources,
          normalizedSourceId: snapshot,
        },
      ),
    );
  }

  Future<void> clearEmbyLibrarySnapshot(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }

    final payload = await _loadEmbyLibraryPayload();
    if (!payload.sources.containsKey(normalizedSourceId)) {
      return;
    }

    final nextSources =
        Map<String, CachedEmbyLibrarySnapshot>.from(payload.sources)
          ..remove(normalizedSourceId);
    await _saveEmbyLibraryPayload(
      _EmbyLibraryCachePayload(sources: nextSources),
    );
  }

  Future<LocalStorageCacheSummary> inspectEmbyLibraryCache() async {
    final raw = await _preferences.getString(_embyLibraryCacheKey) ?? '';
    final payload = await _loadEmbyLibraryPayload();
    final entryCount = payload.sources.values.fold<int>(
      0,
      (sum, snapshot) => sum + _countEmbySnapshotEntries(snapshot),
    );
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.embyLibraryCache,
      entryCount: entryCount,
      totalBytes: utf8.encode(raw).length,
    );
  }

  Future<void> clearAllEmbyLibrarySnapshots() async {
    await _preferences.remove(_embyLibraryCacheKey);
    _embyLibraryPayloadCache = const _EmbyLibraryCachePayload();
    _embyLibraryPayloadLoadFuture = null;
  }

  CachedDetailState? peekDetailState(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) {
    final payload = _detailPayloadCache;
    if (payload == null) {
      return null;
    }
    return _loadDetailStateFromPayload(
      payload,
      seedTarget,
      allowStructuralMismatch: allowStructuralMismatch,
    );
  }

  MediaDetailTarget? peekDetailTarget(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) {
    return peekDetailState(
      seedTarget,
      allowStructuralMismatch: allowStructuralMismatch,
    )?.target;
  }

  Future<CachedDetailState?> loadDetailState(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) async {
    final payload = await _loadDetailPayload();
    return _loadDetailStateFromPayload(
      payload,
      seedTarget,
      allowStructuralMismatch: allowStructuralMismatch,
    );
  }

  Future<MediaDetailTarget?> loadDetailTarget(
      MediaDetailTarget seedTarget) async {
    return (await loadDetailState(seedTarget))?.target;
  }

  Future<List<MediaDetailTarget?>> loadDetailTargetsBatch(
    Iterable<MediaDetailTarget> seedTargets,
  ) async {
    final targets = seedTargets.toList(growable: false);
    if (targets.isEmpty) {
      return const <MediaDetailTarget?>[];
    }

    final payload = await _loadDetailPayload();
    return targets
        .map((target) => _loadDetailStateFromPayload(payload, target)?.target)
        .toList(growable: false);
  }

  static LocalStorageDetailCacheScope buildScopeForTargets(
    Iterable<MediaDetailTarget> targets,
  ) {
    final sourceIds = <String>{};
    final lookupKeys = <String>{};
    for (final target in targets) {
      final sourceId = target.sourceId.trim();
      if (sourceId.isNotEmpty) {
        sourceIds.add(sourceId);
      }
      lookupKeys.addAll(buildLookupKeys(target));
    }
    return LocalStorageDetailCacheScope(
      sourceIds: sourceIds,
      lookupKeys: lookupKeys,
    );
  }

  CachedDetailState? _loadDetailStateFromPayload(
    _DetailCachePayload payload,
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) {
    for (final lookupKey in buildLookupKeys(seedTarget)) {
      final recordId = payload.lookupKeys[lookupKey];
      if (recordId == null) {
        continue;
      }
      final record = payload.records[recordId];
      if (record != null &&
          (_canShareDetailCacheRecord(
                left: seedTarget,
                right: record.target,
              ) ||
              (allowStructuralMismatch &&
                  _canRestoreStructuralMismatchRecord(
                    seedTarget: seedTarget,
                    record: record,
                    matchedLookupKey: lookupKey,
                  )))) {
        return CachedDetailState(
          target: record.target,
          libraryMatchChoices: record.libraryMatchChoices,
          selectedLibraryMatchIndex: record.selectedLibraryMatchIndex,
          subtitleSearchChoices: record.subtitleSearchChoices,
          selectedSubtitleSearchIndex: record.selectedSubtitleSearchIndex,
          metadataRefreshStatus: record.metadataRefreshStatus,
        );
      }
    }
    return null;
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
    List<CachedSubtitleSearchOption>? subtitleSearchChoices,
    int? selectedSubtitleSearchIndex,
  }) async {
    await _saveDetailTargetsBatch(
      [
        DetailTargetCacheSaveRequest(
          seedTarget: seedTarget,
          resolvedTarget: resolvedTarget,
          metadataRefreshStatus: metadataRefreshStatus,
          libraryMatchChoices: libraryMatchChoices,
          selectedLibraryMatchIndex: selectedLibraryMatchIndex,
          subtitleSearchChoices: subtitleSearchChoices,
          selectedSubtitleSearchIndex: selectedSubtitleSearchIndex,
        ),
      ],
      persistToStorage: true,
    );
  }

  Future<void> saveDetailTargetsBatch(
    Iterable<DetailTargetCacheSaveRequest> requests,
  ) async {
    await _saveDetailTargetsBatch(
      requests,
      persistToStorage: true,
    );
  }

  Future<void> saveDetailTargetsBatchInMemory(
    Iterable<DetailTargetCacheSaveRequest> requests,
  ) async {
    await _saveDetailTargetsBatch(
      requests,
      persistToStorage: false,
    );
  }

  Future<void> _saveDetailTargetsBatch(
    Iterable<DetailTargetCacheSaveRequest> requests, {
    required bool persistToStorage,
  }) async {
    final requestList = requests.toList(growable: false);
    if (requestList.isEmpty) {
      return;
    }

    final payload = await _loadDetailPayload();
    final nextRecords = <String, _CachedDetailRecord>{...payload.records};
    final nextLookupKeys = <String, String>{...payload.lookupKeys};
    final changedSourceIds = <String>{};
    final changedLookupKeys = <String>{};
    final changedRecordIds = <String>{};
    final changedFields = <LocalStorageDetailCacheChangedField>{};
    var hasChanges = false;

    for (final request in requestList) {
      final applied = _applyDetailTargetSave(
        records: nextRecords,
        lookupKeys: nextLookupKeys,
        request: request,
      );
      if (applied == null) {
        continue;
      }
      hasChanges = true;
      changedSourceIds.addAll(applied.sourceIds);
      changedLookupKeys.addAll(applied.lookupKeys);
      changedRecordIds.add(applied.recordId);
      changedFields.addAll(applied.changedFields);
    }

    if (!hasChanges) {
      return;
    }

    final nextPayload = _DetailCachePayload(
      records: nextRecords,
      lookupKeys: nextLookupKeys,
    );
    if (persistToStorage) {
      await _saveDetailPayload(nextPayload);
    } else {
      _detailPayloadCache = nextPayload;
      _detailPayloadLoadFuture = null;
    }
    _scheduleDetailCacheChangedNotification(
      LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: changedSourceIds,
          lookupKeys: changedLookupKeys,
          recordIds: changedRecordIds,
        ),
        changedFields: changedFields,
      ),
    );
  }

  _AppliedDetailTargetSave? _applyDetailTargetSave({
    required Map<String, _CachedDetailRecord> records,
    required Map<String, String> lookupKeys,
    required DetailTargetCacheSaveRequest request,
  }) {
    final seedTarget = request.seedTarget;
    final resolvedTarget = request.resolvedTarget;
    final requestLookupKeys = {
      ...buildLookupKeys(seedTarget),
      ...buildLookupKeys(resolvedTarget),
    }.where((item) => item.trim().isNotEmpty).toSet();
    if (requestLookupKeys.isEmpty) {
      return null;
    }

    String? recordId;
    for (final lookupKey in requestLookupKeys) {
      final candidate = lookupKeys[lookupKey];
      final candidateRecord = candidate == null ? null : records[candidate];
      if (candidateRecord != null &&
          _canShareDetailCacheRecord(
            left: seedTarget,
            right: candidateRecord.target,
          ) &&
          _canShareDetailCacheRecord(
            left: resolvedTarget,
            right: candidateRecord.target,
          )) {
        recordId = candidate;
        break;
      }
    }
    recordId ??= requestLookupKeys.first;

    final existing = records[recordId];
    final mergedLookupKeys = {
      if (existing != null) ...existing.lookupKeys,
      ...requestLookupKeys,
    }.toList(growable: false)
      ..sort();
    final nextLibraryMatchChoices = request.libraryMatchChoices != null
        ? List<MediaDetailTarget>.unmodifiable(request.libraryMatchChoices!)
        : existing?.libraryMatchChoices ?? const <MediaDetailTarget>[];
    final normalizedSelectedLibraryMatchIndex = nextLibraryMatchChoices.isEmpty
        ? 0
        : (request.selectedLibraryMatchIndex ??
                existing?.selectedLibraryMatchIndex ??
                0)
            .clamp(0, nextLibraryMatchChoices.length - 1);
    final nextSubtitleSearchChoices = request.subtitleSearchChoices != null
        ? List<CachedSubtitleSearchOption>.unmodifiable(
            request.subtitleSearchChoices!,
          )
        : existing?.subtitleSearchChoices ??
            const <CachedSubtitleSearchOption>[];
    final normalizedSelectedSubtitleSearchIndex =
        nextSubtitleSearchChoices.isEmpty
            ? -1
            : (request.selectedSubtitleSearchIndex ??
                    existing?.selectedSubtitleSearchIndex ??
                    -1)
                .clamp(-1, nextSubtitleSearchChoices.length - 1);

    final nextRecord = _CachedDetailRecord(
      id: recordId,
      lookupKeys: mergedLookupKeys,
      updatedAt: DateTime.now(),
      target: resolvedTarget,
      libraryMatchChoices: nextLibraryMatchChoices,
      selectedLibraryMatchIndex: normalizedSelectedLibraryMatchIndex,
      subtitleSearchChoices: nextSubtitleSearchChoices,
      selectedSubtitleSearchIndex: normalizedSelectedSubtitleSearchIndex,
      metadataRefreshStatus: request.metadataRefreshStatus ??
          existing?.metadataRefreshStatus ??
          DetailMetadataRefreshStatus.never,
    );
    final changedFields = _resolveRecordChangedFields(
      previous: existing,
      next: nextRecord,
    );
    if (existing != null &&
        changedFields.isEmpty &&
        _sameStringList(existing.lookupKeys, nextRecord.lookupKeys)) {
      return null;
    }

    records[recordId] = nextRecord;
    for (final lookupKey in mergedLookupKeys) {
      lookupKeys[lookupKey] = recordId;
    }
    return _AppliedDetailTargetSave(
      recordId: recordId,
      lookupKeys: mergedLookupKeys.toSet(),
      sourceIds: {
        seedTarget.sourceId.trim(),
        resolvedTarget.sourceId.trim(),
        nextRecord.target.sourceId.trim(),
      }.where((item) => item.isNotEmpty).toSet(),
      changedFields: changedFields,
    );
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
    _detailPayloadCache = const _DetailCachePayload();
    _detailPayloadLoadFuture = null;
    _scheduleDetailCacheChangedNotification(
      const LocalStorageDetailCacheChangeEvent(invalidateAll: true),
    );
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
    final removedLookupKeys = payload.records.values
        .where((record) => recordIdsToRemove.contains(record.id))
        .expand((record) => record.lookupKeys)
        .where((item) => item.trim().isNotEmpty)
        .toSet();

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
    _scheduleDetailCacheChangedNotification(
      LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {normalizedSourceId},
          lookupKeys: removedLookupKeys,
          recordIds: recordIdsToRemove,
        ),
        changedFields: allLocalStorageDetailCacheChangedFields,
      ),
    );
  }

  Future<void> clearDetailCacheForResource({
    required String sourceId,
    String resourceId = '',
    required String resourcePath,
    bool treatAsScope = false,
  }) async {
    final normalizedSourceId = sourceId.trim();
    final normalizedResourceId = resourceId.trim();
    final normalizedResourcePath = resourcePath.trim();
    if (normalizedSourceId.isEmpty ||
        (normalizedResourceId.isEmpty && normalizedResourcePath.isEmpty)) {
      return;
    }

    final payload = await _loadDetailPayload();
    if (payload.records.isEmpty || payload.lookupKeys.isEmpty) {
      return;
    }

    var changed = false;
    final changedSourceIds = <String>{normalizedSourceId};
    final changedLookupKeys = <String>{};
    final changedRecordIds = <String>{};
    final nextRecords = <String, _CachedDetailRecord>{};
    for (final record in payload.records.values) {
      final nextRecord = _removeResourceRelationsFromRecord(
        record,
        sourceId: normalizedSourceId,
        resourceId: normalizedResourceId,
        resourcePath: normalizedResourcePath,
        treatAsScope: treatAsScope,
      );
      if (!identical(nextRecord, record)) {
        changed = true;
        changedRecordIds.add(record.id);
        changedLookupKeys.addAll(record.lookupKeys);
        changedLookupKeys.addAll(nextRecord.lookupKeys);
        final currentSourceId = record.target.sourceId.trim();
        if (currentSourceId.isNotEmpty) {
          changedSourceIds.add(currentSourceId);
        }
        final nextSourceId = nextRecord.target.sourceId.trim();
        if (nextSourceId.isNotEmpty) {
          changedSourceIds.add(nextSourceId);
        }
      }
      if (nextRecord.lookupKeys.isNotEmpty) {
        nextRecords[nextRecord.id] = nextRecord;
      } else {
        changed = true;
      }
    }

    if (!changed) {
      return;
    }

    final nextLookupKeys = <String, String>{};
    for (final record in nextRecords.values) {
      for (final lookupKey in record.lookupKeys) {
        final trimmed = lookupKey.trim();
        if (trimmed.isNotEmpty) {
          nextLookupKeys[trimmed] = record.id;
        }
      }
    }

    await _saveDetailPayload(
      _DetailCachePayload(
        records: nextRecords,
        lookupKeys: nextLookupKeys,
      ),
    );
    _scheduleDetailCacheChangedNotification(
      LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: changedSourceIds,
          lookupKeys: changedLookupKeys,
          recordIds: changedRecordIds,
        ),
        changedFields: const {
          LocalStorageDetailCacheChangedField.availability,
          LocalStorageDetailCacheChangedField.playback,
          LocalStorageDetailCacheChangedField.structure,
          LocalStorageDetailCacheChangedField.choices,
        },
      ),
    );
  }

  Future<void> clearCache(LocalStorageCacheType type) async {
    switch (type) {
      case LocalStorageCacheType.nasMetadataIndex:
      case LocalStorageCacheType.subtitleCache:
      case LocalStorageCacheType.playbackMemory:
      case LocalStorageCacheType.televisionSearchPreferences:
        return;
      case LocalStorageCacheType.embyLibraryCache:
        await clearAllEmbyLibrarySnapshots();
        return;
      case LocalStorageCacheType.detailData:
        await clearDetailCache();
        return;
      case LocalStorageCacheType.images:
        return;
    }
  }

  Future<_EmbyLibraryCachePayload> _loadEmbyLibraryPayload() async {
    final cached = _embyLibraryPayloadCache;
    if (cached != null) {
      return cached;
    }
    final existingLoad = _embyLibraryPayloadLoadFuture;
    if (existingLoad != null) {
      return existingLoad;
    }
    final loadFuture = _loadEmbyLibraryPayloadFromStorage();
    _embyLibraryPayloadLoadFuture = loadFuture;
    try {
      final payload = await loadFuture;
      _embyLibraryPayloadCache = payload;
      return payload;
    } finally {
      _embyLibraryPayloadLoadFuture = null;
    }
  }

  Future<_EmbyLibraryCachePayload> _loadEmbyLibraryPayloadFromStorage() async {
    final raw = await _preferences.getString(_embyLibraryCacheKey);
    if (raw == null || raw.isEmpty) {
      return const _EmbyLibraryCachePayload();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _EmbyLibraryCachePayload.fromJson(decoded);
      }
      if (decoded is Map) {
        return _EmbyLibraryCachePayload.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {
      return const _EmbyLibraryCachePayload();
    }
    return const _EmbyLibraryCachePayload();
  }

  Future<void> _saveEmbyLibraryPayload(_EmbyLibraryCachePayload payload) async {
    _embyLibraryPayloadCache = payload;
    _embyLibraryPayloadLoadFuture = null;
    final raw = jsonEncode(payload.toJson());
    await _preferences.setString(
      _embyLibraryCacheKey,
      raw,
    );
  }

  static List<String> buildLookupKeys(MediaDetailTarget target) {
    final keys = <String>{};
    final detailKind = _detailLookupKind(target);
    final isNestedEpisodic = _isNestedEpisodicKind(detailKind);

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
      if (detailKind.isNotEmpty) {
        addKey('douban|$detailKind|$doubanId');
      }
      if (!isNestedEpisodic) {
        addKey('douban|$doubanId');
      }
    }

    final imdbId = target.imdbId.trim().toLowerCase();
    if (imdbId.isNotEmpty) {
      if (detailKind.isNotEmpty) {
        addKey('imdb|$detailKind|$imdbId');
      }
      if (!isNestedEpisodic) {
        addKey('imdb|$imdbId');
      }
    }

    final tmdbId = target.tmdbId.trim();
    if (tmdbId.isNotEmpty) {
      if (detailKind.isNotEmpty) {
        addKey('tmdb|$detailKind|$tmdbId');
      }
      if (!isNestedEpisodic) {
        addKey('tmdb|$tmdbId');
      }
    }

    final tvdbId = target.tvdbId.trim();
    if (tvdbId.isNotEmpty) {
      if (detailKind.isNotEmpty) {
        addKey('tvdb|$detailKind|$tvdbId');
      }
      if (!isNestedEpisodic) {
        addKey('tvdb|$tvdbId');
      }
    }

    final wikidataId = target.wikidataId.trim().toUpperCase();
    if (wikidataId.isNotEmpty) {
      if (detailKind.isNotEmpty) {
        addKey('wikidata|$detailKind|$wikidataId');
      }
      if (!isNestedEpisodic) {
        addKey('wikidata|$wikidataId');
      }
    }

    final normalizedTitle = _normalizeLookupText(target.title);
    if (normalizedTitle.isNotEmpty) {
      _addTextLookupKeys(
        addKey: addKey,
        prefix: 'title',
        normalizedValue: normalizedTitle,
        year: target.year,
        detailKind: detailKind,
        includeLooseKeys: !isNestedEpisodic,
      );
    }

    final query = target.searchQuery.trim();
    final normalizedQuery = _normalizeLookupText(query);
    if (normalizedQuery.isNotEmpty && normalizedQuery != normalizedTitle) {
      _addTextLookupKeys(
        addKey: addKey,
        prefix: 'query',
        normalizedValue: normalizedQuery,
        year: target.year,
        detailKind: detailKind,
        includeLooseKeys: !isNestedEpisodic,
      );
    }

    return keys.toList(growable: false);
  }

  Future<_DetailCachePayload> _loadDetailPayload() async {
    final cached = _detailPayloadCache;
    if (cached != null) {
      return cached;
    }
    final existingLoad = _detailPayloadLoadFuture;
    if (existingLoad != null) {
      return existingLoad;
    }
    final loadFuture = _loadDetailPayloadFromStorage();
    _detailPayloadLoadFuture = loadFuture;
    try {
      final payload = await loadFuture;
      _detailPayloadCache = payload;
      return payload;
    } finally {
      _detailPayloadLoadFuture = null;
    }
  }

  Future<_DetailCachePayload> _loadDetailPayloadFromStorage() async {
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
    _detailPayloadCache = payload;
    _detailPayloadLoadFuture = null;
    final raw = jsonEncode(payload.toJson());
    await _preferences.setString(_detailCacheKey, raw);
  }

  void _scheduleDetailCacheChangedNotification(
    LocalStorageDetailCacheChangeEvent event,
  ) {
    final notifyDetailCacheChanged = _notifyDetailCacheChanged;
    if (notifyDetailCacheChanged == null) {
      return;
    }
    if (event.invalidateAll) {
      _pendingDetailCacheInvalidateAll = true;
      _pendingDetailCacheChangedSourceIds.clear();
      _pendingDetailCacheChangedLookupKeys.clear();
      _pendingDetailCacheChangedRecordIds.clear();
      _pendingDetailCacheChangedFields.clear();
    } else if (!_pendingDetailCacheInvalidateAll) {
      _pendingDetailCacheChangedSourceIds.addAll(
        event.scope.sourceIds
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
      _pendingDetailCacheChangedLookupKeys.addAll(
        event.scope.lookupKeys
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
      _pendingDetailCacheChangedRecordIds.addAll(
        event.scope.recordIds
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
      _pendingDetailCacheChangedFields.addAll(event.effectiveChangedFields);
    }
    if (detailCacheChangeNotificationDelay <= Duration.zero) {
      _detailCacheChangeNotificationTimer?.cancel();
      _detailCacheChangeNotificationTimer = null;
      notifyDetailCacheChanged(_consumePendingDetailCacheChangeEvent(event));
      return;
    }
    _detailCacheChangeNotificationTimer?.cancel();
    _detailCacheChangeNotificationTimer = Timer(
      detailCacheChangeNotificationDelay,
      () {
        notifyDetailCacheChanged(_consumePendingDetailCacheChangeEvent(event));
      },
    );
  }

  LocalStorageDetailCacheChangeEvent _consumePendingDetailCacheChangeEvent(
    LocalStorageDetailCacheChangeEvent fallback,
  ) {
    final event = _pendingDetailCacheInvalidateAll ||
            _pendingDetailCacheChangedSourceIds.isNotEmpty ||
            _pendingDetailCacheChangedLookupKeys.isNotEmpty ||
            _pendingDetailCacheChangedRecordIds.isNotEmpty
        ? LocalStorageDetailCacheChangeEvent(
            scope: LocalStorageDetailCacheScope(
              sourceIds: Set<String>.from(_pendingDetailCacheChangedSourceIds),
              lookupKeys:
                  Set<String>.from(_pendingDetailCacheChangedLookupKeys),
              recordIds: Set<String>.from(_pendingDetailCacheChangedRecordIds),
            ),
            invalidateAll: _pendingDetailCacheInvalidateAll,
            changedFields: Set<LocalStorageDetailCacheChangedField>.from(
              _pendingDetailCacheChangedFields,
            ),
          )
        : fallback;
    _pendingDetailCacheChangedSourceIds.clear();
    _pendingDetailCacheChangedLookupKeys.clear();
    _pendingDetailCacheChangedRecordIds.clear();
    _pendingDetailCacheChangedFields.clear();
    _pendingDetailCacheInvalidateAll = false;
    return event;
  }

  _CachedDetailRecord _removeResourceRelationsFromRecord(
    _CachedDetailRecord record, {
    required String sourceId,
    required String resourceId,
    required String resourcePath,
    required bool treatAsScope,
  }) {
    final normalizedChoices = <MediaDetailTarget>[];
    final removedChoiceIndices = <int>[];
    for (var index = 0; index < record.libraryMatchChoices.length; index++) {
      final choice = record.libraryMatchChoices[index];
      if (_detailTargetMatchesDeletedResource(
        choice,
        sourceId: sourceId,
        resourceId: resourceId,
        resourcePath: resourcePath,
        treatAsScope: treatAsScope,
      )) {
        removedChoiceIndices.add(index);
      } else {
        normalizedChoices.add(choice);
      }
    }

    final targetMatches = _detailTargetMatchesDeletedResource(
      record.target,
      sourceId: sourceId,
      resourceId: resourceId,
      resourcePath: resourcePath,
      treatAsScope: treatAsScope,
    );
    if (!targetMatches && removedChoiceIndices.isEmpty) {
      return record;
    }

    final oldChoiceCount = record.libraryMatchChoices.length;
    final oldSelectedIndex = oldChoiceCount == 0
        ? 0
        : record.selectedLibraryMatchIndex.clamp(0, oldChoiceCount - 1);
    final removedBeforeSelected =
        removedChoiceIndices.where((index) => index < oldSelectedIndex).length;
    final selectedChoiceRemoved =
        removedChoiceIndices.contains(oldSelectedIndex);

    MediaDetailTarget nextTarget = record.target;
    var nextSelectedIndex = 0;
    if (normalizedChoices.isNotEmpty) {
      nextSelectedIndex = (oldSelectedIndex - removedBeforeSelected)
          .clamp(0, normalizedChoices.length - 1);
      if (targetMatches || selectedChoiceRemoved) {
        nextTarget = normalizedChoices[nextSelectedIndex];
      }
    } else if (targetMatches) {
      nextTarget = _stripResolvedLibraryResource(record.target);
    }

    final nextLookupKeys = {
      for (final lookupKey in record.lookupKeys)
        if (!_isSourceLibraryLookupKey(lookupKey, sourceId)) lookupKey.trim(),
      ...buildLookupKeys(nextTarget),
    }.where((item) => item.isNotEmpty).toList(growable: false)
      ..sort();

    return _CachedDetailRecord(
      id: record.id,
      lookupKeys: nextLookupKeys,
      updatedAt: DateTime.now(),
      target: nextTarget,
      libraryMatchChoices:
          List<MediaDetailTarget>.unmodifiable(normalizedChoices),
      selectedLibraryMatchIndex:
          normalizedChoices.isEmpty ? 0 : nextSelectedIndex,
      subtitleSearchChoices: record.subtitleSearchChoices,
      selectedSubtitleSearchIndex: record.selectedSubtitleSearchIndex,
      metadataRefreshStatus: record.metadataRefreshStatus,
    );
  }
}

Set<LocalStorageDetailCacheChangedField> _resolveRecordChangedFields({
  required _CachedDetailRecord? previous,
  required _CachedDetailRecord next,
}) {
  if (previous == null) {
    return allLocalStorageDetailCacheChangedFields;
  }

  final changedFields = <LocalStorageDetailCacheChangedField>{};
  if (!_sameStringList(previous.lookupKeys, next.lookupKeys) ||
      !_sameProviderIds(
        previous.target.providerIds,
        next.target.providerIds,
      ) ||
      previous.target.itemId != next.target.itemId ||
      previous.target.sourceId != next.target.sourceId ||
      previous.target.itemType != next.target.itemType ||
      previous.target.seasonNumber != next.target.seasonNumber ||
      previous.target.episodeNumber != next.target.episodeNumber ||
      previous.target.sectionId != next.target.sectionId ||
      previous.target.sectionName != next.target.sectionName ||
      previous.target.sourceKind != next.target.sourceKind ||
      previous.target.sourceName != next.target.sourceName ||
      previous.target.searchQuery != next.target.searchQuery ||
      previous.target.doubanId != next.target.doubanId ||
      previous.target.imdbId != next.target.imdbId ||
      previous.target.tmdbId != next.target.tmdbId ||
      previous.target.tvdbId != next.target.tvdbId ||
      previous.target.wikidataId != next.target.wikidataId ||
      previous.target.tmdbSetId != next.target.tmdbSetId) {
    changedFields.add(LocalStorageDetailCacheChangedField.structure);
  }
  if (previous.target.title != next.target.title ||
      previous.target.overview != next.target.overview ||
      previous.target.year != next.target.year ||
      previous.target.durationLabel != next.target.durationLabel ||
      !_sameStringList(previous.target.genres, next.target.genres) ||
      !_sameStringList(previous.target.directors, next.target.directors) ||
      !_sameJsonEncodedObjects(
        previous.target.directorProfiles.map((item) => item.toJson()).toList(),
        next.target.directorProfiles.map((item) => item.toJson()).toList(),
      ) ||
      !_sameStringList(previous.target.actors, next.target.actors) ||
      !_sameJsonEncodedObjects(
        previous.target.actorProfiles.map((item) => item.toJson()).toList(),
        next.target.actorProfiles.map((item) => item.toJson()).toList(),
      ) ||
      !_sameStringList(previous.target.platforms, next.target.platforms) ||
      !_sameJsonEncodedObjects(
        previous.target.platformProfiles.map((item) => item.toJson()).toList(),
        next.target.platformProfiles.map((item) => item.toJson()).toList(),
      )) {
    changedFields.add(LocalStorageDetailCacheChangedField.summary);
  }
  if (previous.target.posterUrl != next.target.posterUrl ||
      !_sameStringMap(
          previous.target.posterHeaders, next.target.posterHeaders) ||
      previous.target.backdropUrl != next.target.backdropUrl ||
      !_sameStringMap(
        previous.target.backdropHeaders,
        next.target.backdropHeaders,
      ) ||
      previous.target.logoUrl != next.target.logoUrl ||
      !_sameStringMap(previous.target.logoHeaders, next.target.logoHeaders) ||
      previous.target.bannerUrl != next.target.bannerUrl ||
      !_sameStringMap(
        previous.target.bannerHeaders,
        next.target.bannerHeaders,
      ) ||
      !_sameStringList(
        previous.target.extraBackdropUrls,
        next.target.extraBackdropUrls,
      ) ||
      !_sameStringMap(
        previous.target.extraBackdropHeaders,
        next.target.extraBackdropHeaders,
      )) {
    changedFields.add(LocalStorageDetailCacheChangedField.artwork);
  }
  if (!_sameStringList(
    previous.target.ratingLabels,
    next.target.ratingLabels,
  )) {
    changedFields.add(LocalStorageDetailCacheChangedField.ratings);
  }
  if (previous.target.availabilityLabel != next.target.availabilityLabel ||
      previous.target.resourcePath != next.target.resourcePath) {
    changedFields.add(LocalStorageDetailCacheChangedField.availability);
  }
  if (!_samePlaybackTargets(
    previous.target.playbackTarget,
    next.target.playbackTarget,
  )) {
    changedFields.add(LocalStorageDetailCacheChangedField.playback);
  }
  if (!_sameJsonEncodedObjects(
        previous.libraryMatchChoices.map((item) => item.toJson()).toList(),
        next.libraryMatchChoices.map((item) => item.toJson()).toList(),
      ) ||
      previous.selectedLibraryMatchIndex != next.selectedLibraryMatchIndex ||
      !_sameJsonEncodedObjects(
        previous.subtitleSearchChoices.map((item) => item.toJson()).toList(),
        next.subtitleSearchChoices.map((item) => item.toJson()).toList(),
      ) ||
      previous.selectedSubtitleSearchIndex !=
          next.selectedSubtitleSearchIndex) {
    changedFields.add(LocalStorageDetailCacheChangedField.choices);
  }
  if (previous.metadataRefreshStatus != next.metadataRefreshStatus) {
    changedFields.add(LocalStorageDetailCacheChangedField.metadataStatus);
  }
  return changedFields;
}

bool _sameStringList(Iterable<String> left, Iterable<String> right) {
  final leftList = left is List<String> ? left : left.toList(growable: false);
  final rightList =
      right is List<String> ? right : right.toList(growable: false);
  return listEquals(leftList, rightList);
}

bool _sameStringMap(Map<String, String> left, Map<String, String> right) {
  return mapEquals(left, right);
}

bool _sameProviderIds(Map<String, String> left, Map<String, String> right) {
  return mapEquals(left, right);
}

bool _samePlaybackTargets(PlaybackTarget? left, PlaybackTarget? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null) {
    return left == right;
  }
  return _sameJsonEncodedObjects(left.toJson(), right.toJson());
}

bool _sameJsonEncodedObjects(Object? left, Object? right) {
  return jsonEncode(left) == jsonEncode(right);
}

String _detailLookupKind(MediaDetailTarget target) {
  final itemType = target.itemType.trim().toLowerCase();
  if (itemType.isNotEmpty) {
    return itemType;
  }
  if (target.episodeNumber != null && target.episodeNumber! > 0) {
    return 'episode';
  }
  if (target.seasonNumber != null && target.seasonNumber! > 0) {
    return 'season';
  }
  final playbackTarget = target.playbackTarget;
  if (playbackTarget?.isEpisode == true) {
    return 'episode';
  }
  if (playbackTarget?.isSeries == true) {
    return 'series';
  }
  if (playbackTarget?.isMovie == true) {
    return 'movie';
  }
  return target.isSeries ? 'series' : 'movie';
}

bool _isNestedEpisodicKind(String detailKind) {
  return detailKind == 'episode' || detailKind == 'season';
}

bool _isTopLevelDetailKind(String detailKind) {
  return detailKind == 'series' || detailKind == 'movie';
}

bool _canShareDetailCacheRecord({
  required MediaDetailTarget left,
  required MediaDetailTarget right,
}) {
  final leftKind = _detailLookupKind(left);
  final rightKind = _detailLookupKind(right);
  if (_isTopLevelDetailKind(leftKind) && _isNestedEpisodicKind(rightKind)) {
    return false;
  }
  if (_isNestedEpisodicKind(leftKind) && _isTopLevelDetailKind(rightKind)) {
    return false;
  }
  return true;
}

bool _canRestoreStructuralMismatchRecord({
  required MediaDetailTarget seedTarget,
  required _CachedDetailRecord record,
  required String matchedLookupKey,
}) {
  final seedKind = _detailLookupKind(seedTarget);
  final recordKind = _detailLookupKind(record.target);
  final isCrossKindPair = (_isTopLevelDetailKind(seedKind) &&
          _isNestedEpisodicKind(recordKind)) ||
      (_isNestedEpisodicKind(seedKind) && _isTopLevelDetailKind(recordKind));
  if (!isCrossKindPair) {
    return false;
  }

  final normalizedLookupKey = matchedLookupKey.trim();
  if (normalizedLookupKey.isEmpty ||
      !record.lookupKeys.contains(normalizedLookupKey)) {
    return false;
  }

  if (_isStrongStructuralLookupKey(normalizedLookupKey)) {
    return true;
  }
  return record.libraryMatchChoices.isNotEmpty;
}

bool _isStrongStructuralLookupKey(String lookupKey) {
  final normalized = lookupKey.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  for (final prefix in const [
    'library|',
    'douban|',
    'imdb|',
    'tmdb|',
    'tvdb|',
    'wikidata|',
  ]) {
    if (normalized.startsWith(prefix)) {
      return true;
    }
  }

  final parts = normalized.split('|');
  if (parts.length >= 3 && (parts.first == 'title' || parts.first == 'query')) {
    return true;
  }
  return false;
}

void _addTextLookupKeys({
  required void Function(String key) addKey,
  required String prefix,
  required String normalizedValue,
  required int year,
  required String detailKind,
  required bool includeLooseKeys,
}) {
  final normalizedKind = detailKind.trim().toLowerCase();
  if (normalizedValue.isEmpty) {
    return;
  }
  if (normalizedKind.isNotEmpty) {
    addKey('$prefix|$normalizedValue|$year|$normalizedKind');
    addKey('$prefix|$normalizedValue|$normalizedKind');
  } else if (year > 0) {
    addKey('$prefix|$normalizedValue|$year');
  }
  if (!includeLooseKeys) {
    return;
  }
  if (year > 0) {
    addKey('$prefix|$normalizedValue|$year');
  }
  addKey('$prefix|$normalizedValue');
}

class CachedDetailState {
  const CachedDetailState({
    required this.target,
    this.libraryMatchChoices = const [],
    this.selectedLibraryMatchIndex = 0,
    this.subtitleSearchChoices = const [],
    this.selectedSubtitleSearchIndex = -1,
    this.metadataRefreshStatus = DetailMetadataRefreshStatus.never,
  });

  final MediaDetailTarget target;
  final List<MediaDetailTarget> libraryMatchChoices;
  final int selectedLibraryMatchIndex;
  final List<CachedSubtitleSearchOption> subtitleSearchChoices;
  final int selectedSubtitleSearchIndex;
  final DetailMetadataRefreshStatus metadataRefreshStatus;
}

class CachedEmbyLibrarySnapshot {
  const CachedEmbyLibrarySnapshot({
    this.refreshedAt,
    this.collections = const <MediaCollection>[],
    this.fallbackItems = const <MediaItem>[],
    this.itemsBySection = const <String, List<MediaItem>>{},
  });

  final DateTime? refreshedAt;
  final List<MediaCollection> collections;
  final List<MediaItem> fallbackItems;
  final Map<String, List<MediaItem>> itemsBySection;

  bool get hasData {
    if (fallbackItems.isNotEmpty) {
      return true;
    }
    return itemsBySection.values.any((items) => items.isNotEmpty);
  }

  Map<String, dynamic> toJson() {
    return {
      'refreshedAt': refreshedAt?.toIso8601String(),
      'collections': collections.map((item) => item.toJson()).toList(),
      'fallbackItems': fallbackItems.map((item) => item.toJson()).toList(),
      'itemsBySection': itemsBySection.map(
        (key, value) => MapEntry(
          key,
          value.map((item) => item.toJson()).toList(),
        ),
      ),
    };
  }

  factory CachedEmbyLibrarySnapshot.fromJson(Map<String, dynamic> json) {
    return CachedEmbyLibrarySnapshot(
      refreshedAt: DateTime.tryParse(json['refreshedAt'] as String? ?? ''),
      collections: (json['collections'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => MediaCollection.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      fallbackItems: (json['fallbackItems'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => MediaItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      itemsBySection:
          (json['itemsBySection'] as Map<dynamic, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(
          '$key',
          (value as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) => MediaItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
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

bool _isSourceLibraryLookupKey(String lookupKey, String sourceId) {
  final normalizedLookupKey = lookupKey.trim();
  final normalizedSourceId = sourceId.trim();
  if (normalizedLookupKey.isEmpty || normalizedSourceId.isEmpty) {
    return false;
  }
  return normalizedLookupKey.startsWith('library|$normalizedSourceId|');
}

bool _detailTargetMatchesDeletedResource(
  MediaDetailTarget target, {
  required String sourceId,
  required String resourceId,
  required String resourcePath,
  required bool treatAsScope,
}) {
  final normalizedSourceId = sourceId.trim();
  if (normalizedSourceId.isEmpty) {
    return false;
  }

  final targetSourceId = target.sourceId.trim();
  final playbackSourceId = target.playbackTarget?.sourceId.trim() ?? '';
  if (targetSourceId != normalizedSourceId &&
      playbackSourceId != normalizedSourceId) {
    return false;
  }

  final normalizedResourceId = resourceId.trim();
  if (normalizedResourceId.isNotEmpty) {
    if (target.itemId.trim() == normalizedResourceId) {
      return true;
    }
    if ((target.playbackTarget?.itemId.trim() ?? '') == normalizedResourceId) {
      return true;
    }
  }

  final normalizedResourcePath = resourcePath.trim();
  if (normalizedResourcePath.isEmpty) {
    return false;
  }

  if (treatAsScope) {
    return _pathMatchesDeletedScope(
            target.resourcePath, normalizedResourcePath) ||
        _pathMatchesDeletedScope(
          target.playbackTarget?.actualAddress ?? '',
          normalizedResourcePath,
        );
  }

  return _pathEqualsDeletedResource(
          target.resourcePath, normalizedResourcePath) ||
      _pathEqualsDeletedResource(
        target.playbackTarget?.actualAddress ?? '',
        normalizedResourcePath,
      );
}

bool _pathEqualsDeletedResource(String candidate, String expectedPath) {
  final left = _normalizedCachePath(candidate);
  final right = _normalizedCachePath(expectedPath);
  return left.isNotEmpty && left == right;
}

bool _pathMatchesDeletedScope(String candidate, String scopePath) {
  final candidateSegments = _cachePathSegments(candidate);
  final scopeSegments = _cachePathSegments(scopePath);
  if (candidateSegments.isEmpty ||
      scopeSegments.isEmpty ||
      candidateSegments.length < scopeSegments.length) {
    return false;
  }
  for (var index = 0; index < scopeSegments.length; index++) {
    if (candidateSegments[index] != scopeSegments[index]) {
      return false;
    }
  }
  return true;
}

String _normalizedCachePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  final rawPath = (uri != null && uri.hasScheme) ? uri.path : trimmed;
  final normalized = rawPath.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) {
    return '';
  }
  return normalized.replaceAll(RegExp(r'/+'), '/');
}

List<String> _cachePathSegments(String value) {
  return _normalizedCachePath(value)
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
}

MediaDetailTarget _stripResolvedLibraryResource(MediaDetailTarget target) {
  return MediaDetailTarget(
    title: target.title,
    posterUrl: target.posterUrl,
    posterHeaders: target.posterHeaders,
    backdropUrl: target.backdropUrl,
    backdropHeaders: target.backdropHeaders,
    logoUrl: target.logoUrl,
    logoHeaders: target.logoHeaders,
    bannerUrl: target.bannerUrl,
    bannerHeaders: target.bannerHeaders,
    extraBackdropUrls: target.extraBackdropUrls,
    extraBackdropHeaders: target.extraBackdropHeaders,
    overview: target.overview,
    year: target.year,
    durationLabel: target.durationLabel,
    ratingLabels: target.ratingLabels,
    genres: target.genres,
    directors: target.directors,
    directorProfiles: target.directorProfiles,
    actors: target.actors,
    actorProfiles: target.actorProfiles,
    platforms: target.platforms,
    platformProfiles: target.platformProfiles,
    availabilityLabel: '无',
    searchQuery: target.searchQuery,
    playbackTarget: null,
    itemId: '',
    sourceId: '',
    itemType: target.itemType,
    seasonNumber: target.seasonNumber,
    episodeNumber: target.episodeNumber,
    sectionId: '',
    sectionName: '',
    resourcePath: '',
    doubanId: target.doubanId,
    imdbId: target.imdbId,
    tmdbId: target.tmdbId,
    tvdbId: target.tvdbId,
    wikidataId: target.wikidataId,
    tmdbSetId: target.tmdbSetId,
    providerIds: target.providerIds,
    sourceKind: null,
    sourceName: '',
  );
}

int _countEmbySnapshotEntries(CachedEmbyLibrarySnapshot snapshot) {
  return snapshot.collections.length +
      snapshot.fallbackItems.length +
      snapshot.itemsBySection.values.fold<int>(
        0,
        (sum, items) => sum + items.length,
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

class _EmbyLibraryCachePayload {
  const _EmbyLibraryCachePayload({
    this.sources = const <String, CachedEmbyLibrarySnapshot>{},
  });

  final Map<String, CachedEmbyLibrarySnapshot> sources;

  Map<String, dynamic> toJson() {
    return {
      'sources': sources.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }

  factory _EmbyLibraryCachePayload.fromJson(Map<String, dynamic> json) {
    return _EmbyLibraryCachePayload(
      sources: (json['sources'] as Map<dynamic, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(
          '$key',
          CachedEmbyLibrarySnapshot.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
    );
  }
}

class _AppliedDetailTargetSave {
  const _AppliedDetailTargetSave({
    required this.recordId,
    required this.lookupKeys,
    required this.sourceIds,
    required this.changedFields,
  });

  final String recordId;
  final Set<String> lookupKeys;
  final Set<String> sourceIds;
  final Set<LocalStorageDetailCacheChangedField> changedFields;
}

class _CachedDetailRecord {
  const _CachedDetailRecord({
    required this.id,
    required this.lookupKeys,
    required this.updatedAt,
    required this.target,
    this.libraryMatchChoices = const [],
    this.selectedLibraryMatchIndex = 0,
    this.subtitleSearchChoices = const [],
    this.selectedSubtitleSearchIndex = -1,
    this.metadataRefreshStatus = DetailMetadataRefreshStatus.never,
  });

  final String id;
  final List<String> lookupKeys;
  final DateTime updatedAt;
  final MediaDetailTarget target;
  final List<MediaDetailTarget> libraryMatchChoices;
  final int selectedLibraryMatchIndex;
  final List<CachedSubtitleSearchOption> subtitleSearchChoices;
  final int selectedSubtitleSearchIndex;
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
      'subtitleSearchChoices':
          subtitleSearchChoices.map((item) => item.toJson()).toList(),
      'selectedSubtitleSearchIndex': selectedSubtitleSearchIndex,
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
      subtitleSearchChoices:
          (json['subtitleSearchChoices'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) => CachedSubtitleSearchOption.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false),
      selectedSubtitleSearchIndex:
          (json['selectedSubtitleSearchIndex'] as num?)?.toInt() ?? -1,
      metadataRefreshStatus: DetailMetadataRefreshStatusX.fromJsonValue(
        json['metadataRefreshStatus'],
      ),
    );
  }
}
