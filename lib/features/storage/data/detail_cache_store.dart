import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'local_storage_cache_models.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/resource_path_identity.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';

const int _detailCacheBackgroundRecordThreshold = 16;
const int _detailCacheBackgroundDecodeThreshold = 64 * 1024;

class _EncodedDetailCachePayload {
  const _EncodedDetailCachePayload({
    required this.raw,
    required this.byteLength,
    required this.usedBackgroundIsolate,
  });

  final String raw;
  final int byteLength;
  final bool usedBackgroundIsolate;
}

class _DecodedDetailCachePayload {
  const _DecodedDetailCachePayload({
    required this.payload,
    required this.byteLength,
    required this.isValid,
    required this.usedBackgroundIsolate,
  });

  final _DetailCachePayload payload;
  final int byteLength;
  final bool isValid;
  final bool usedBackgroundIsolate;
}

_EncodedDetailCachePayload _encodeDetailCachePayload(
  _DetailCachePayload payload, {
  required bool usedBackgroundIsolate,
}) {
  final raw = jsonEncode(payload.toJson());
  return _EncodedDetailCachePayload(
    raw: raw,
    byteLength: utf8.encode(raw).length,
    usedBackgroundIsolate: usedBackgroundIsolate,
  );
}

_DecodedDetailCachePayload _decodeDetailCachePayload(
  String raw, {
  required bool usedBackgroundIsolate,
}) {
  final byteLength = utf8.encode(raw).length;
  try {
    return _DecodedDetailCachePayload(
      payload: _DetailCachePayload.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      ),
      byteLength: byteLength,
      isValid: true,
      usedBackgroundIsolate: usedBackgroundIsolate,
    );
  } catch (_) {
    return _DecodedDetailCachePayload(
      payload: const _DetailCachePayload(),
      byteLength: byteLength,
      isValid: false,
      usedBackgroundIsolate: usedBackgroundIsolate,
    );
  }
}

Future<_EncodedDetailCachePayload> _encodeDetailCachePayloadOffUiThread(
  _DetailCachePayload payload,
) {
  final useBackgroundIsolate = !kIsWeb &&
      payload.records.length >= _detailCacheBackgroundRecordThreshold;
  if (!useBackgroundIsolate) {
    return Future<_EncodedDetailCachePayload>.value(
      _encodeDetailCachePayload(
        payload,
        usedBackgroundIsolate: false,
      ),
    );
  }
  return Isolate.run(
    () => _encodeDetailCachePayload(
      payload,
      usedBackgroundIsolate: true,
    ),
  );
}

Future<_DecodedDetailCachePayload> _decodeDetailCachePayloadOffUiThread(
  String raw,
) {
  final useBackgroundIsolate =
      !kIsWeb && raw.length >= _detailCacheBackgroundDecodeThreshold;
  if (!useBackgroundIsolate) {
    return Future<_DecodedDetailCachePayload>.value(
      _decodeDetailCachePayload(
        raw,
        usedBackgroundIsolate: false,
      ),
    );
  }
  return Isolate.run(
    () => _decodeDetailCachePayload(
      raw,
      usedBackgroundIsolate: true,
    ),
  );
}

class _PendingDetailTargetSaveBatch {
  _PendingDetailTargetSaveBatch(this.requests);

  final List<DetailTargetCacheSaveRequest> requests;
  final Completer<void> completer = Completer<void>();
}

/// Owns detail records, relation invalidation, save batching and notifications.
class DetailCacheStore {
  DetailCacheStore({
    required PreferencesStore preferences,
    void Function(LocalStorageDetailCacheChangeEvent event)?
        notifyDetailCacheChanged,
    this.detailCacheChangeNotificationDelay = Duration.zero,
  })  : _preferences = preferences,
        _notifyDetailCacheChanged = notifyDetailCacheChanged;

  static const _detailCacheKey = 'starflow.local_storage.detail_cache.v1';
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
  Future<({_DetailCachePayload payload, String? raw})>?
      _detailPayloadLoadFuture;
  String? _lastPersistedDetailRaw;
  Future<void> _detailMutationTail = Future<void>.value();
  final List<_PendingDetailTargetSaveBatch> _pendingDetailTargetSaveBatches =
      <_PendingDetailTargetSaveBatch>[];
  bool _detailTargetSaveFlushScheduled = false;
  Timer? _detailTargetSaveFlushTimer;
  bool _isDisposed = false;

  void dispose() {
    if (_isDisposed) return;
    if (_pendingDetailTargetSaveBatches.isNotEmpty) {
      unawaited(_flushMergedDetailTargetSaves());
    }
    _isDisposed = true;
    _detailCacheChangeNotificationTimer?.cancel();
    _detailCacheChangeNotificationTimer = null;
    _detailTargetSaveFlushTimer?.cancel();
    _detailTargetSaveFlushTimer = null;
    for (final batch in _pendingDetailTargetSaveBatches) {
      if (!batch.completer.isCompleted) {
        batch.completer.complete();
      }
    }
    _pendingDetailTargetSaveBatches.clear();
    _detailTargetSaveFlushScheduled = false;
    _pendingDetailCacheChangedSourceIds.clear();
    _pendingDetailCacheChangedLookupKeys.clear();
    _pendingDetailCacheChangedRecordIds.clear();
    _pendingDetailCacheChangedFields.clear();
    _pendingDetailCacheInvalidateAll = false;
    _detailPayloadCache = null;
    _detailPayloadLoadFuture = null;
    _lastPersistedDetailRaw = null;
  }

  Future<void> primeDetailPayload() async {
    await _loadDetailPayload();
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

    if (persistToStorage) {
      return _enqueueMergedDetailTargetSave(requestList);
    }

    await _runSerializedDetailMutation(
      () => _saveDetailTargetsBatchUnlocked(
        requestList,
        persistToStorage: persistToStorage,
      ),
    );
  }

  Future<void> _enqueueMergedDetailTargetSave(
    List<DetailTargetCacheSaveRequest> requests,
  ) {
    final pending = _PendingDetailTargetSaveBatch(requests);
    if (_isDisposed) {
      pending.completer.complete();
      return pending.completer.future;
    }
    _pendingDetailTargetSaveBatches.add(pending);
    if (!_detailTargetSaveFlushScheduled) {
      _detailTargetSaveFlushScheduled = true;
      _detailTargetSaveFlushTimer = Timer(
        const Duration(milliseconds: 16),
        () => unawaited(_flushMergedDetailTargetSaves()),
      );
    }
    return pending.completer.future;
  }

  Future<void> _flushMergedDetailTargetSaves() async {
    _detailTargetSaveFlushTimer?.cancel();
    _detailTargetSaveFlushTimer = null;
    final pendingBatches = List<_PendingDetailTargetSaveBatch>.of(
      _pendingDetailTargetSaveBatches,
    );
    _pendingDetailTargetSaveBatches.clear();
    _detailTargetSaveFlushScheduled = false;
    if (_isDisposed) {
      for (final batch in pendingBatches) {
        if (!batch.completer.isCompleted) {
          batch.completer.complete();
        }
      }
      return;
    }
    try {
      await _runSerializedDetailMutation(
        () => _saveDetailTargetsBatchUnlocked(
          pendingBatches
              .expand((batch) => batch.requests)
              .toList(growable: false),
          persistToStorage: true,
        ),
      );
      for (final batch in pendingBatches) {
        if (!batch.completer.isCompleted) {
          batch.completer.complete();
        }
      }
    } catch (error, stackTrace) {
      for (final batch in pendingBatches) {
        if (!batch.completer.isCompleted) {
          batch.completer.completeError(error, stackTrace);
        }
      }
    }
  }

  Future<void> _saveDetailTargetsBatchUnlocked(
    List<DetailTargetCacheSaveRequest> requestList, {
    required bool persistToStorage,
  }) async {
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
      if (!_isDisposed) _detailPayloadCache = nextPayload;
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

  Future<void> _runSerializedDetailMutation(
    Future<void> Function() operation,
  ) {
    // A clear/update must stay behind saves accepted during the merge window.
    if (_pendingDetailTargetSaveBatches.isNotEmpty) {
      unawaited(_flushMergedDetailTargetSaves());
    }
    final previous = _detailMutationTail;
    final completer = Completer<void>();
    _detailMutationTail = () async {
      await previous;
      try {
        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
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
    if (recordId == null) {
      final baseRecordId = requestLookupKeys.first;
      var newRecordId = baseRecordId;
      // Legacy aliases may point at an incompatible episode stored under this ID.
      var suffix = 1;
      while (records.containsKey(newRecordId)) {
        newRecordId = '$baseRecordId|record:${suffix++}';
      }
      recordId = newRecordId;
    }

    final existing = records[recordId];
    final mergedLookupKeys = {
      if (existing != null)
        ...existing.lookupKeys.where((key) => lookupKeys[key] == recordId),
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
    await _runSerializedDetailMutation(_clearDetailCacheUnlocked);
  }

  Future<void> _clearDetailCacheUnlocked() async {
    await _preferences.remove(_detailCacheKey);
    if (!_isDisposed) _detailPayloadCache = const _DetailCachePayload();
    _detailPayloadLoadFuture = null;
    _lastPersistedDetailRaw = null;
    _scheduleDetailCacheChangedNotification(
      const LocalStorageDetailCacheChangeEvent(invalidateAll: true),
    );
  }

  Future<void> clearDetailCacheForSource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }

    await _runSerializedDetailMutation(
      () => _clearDetailCacheForSourceUnlocked(normalizedSourceId),
    );
  }

  Future<void> clearLibraryRelationsForSource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }

    await _runSerializedDetailMutation(
      () => _clearDetailCacheForResourceUnlocked(
        normalizedSourceId: normalizedSourceId,
        normalizedResourceId: '',
        normalizedResourcePath: '',
        treatAsScope: true,
      ),
    );
  }

  Future<Set<String>> loadCachedMediaSourceIds() async {
    final sourceIds = <String>{};
    final payload = await _loadDetailPayload();
    for (final record in payload.records.values) {
      for (final target in <MediaDetailTarget>[
        record.target,
        ...record.libraryMatchChoices,
      ]) {
        final sourceKind =
            target.sourceKind ?? target.playbackTarget?.sourceKind;
        if (sourceKind != MediaSourceKind.emby &&
            sourceKind != MediaSourceKind.fntv &&
            sourceKind != MediaSourceKind.nas &&
            sourceKind != MediaSourceKind.quark) {
          continue;
        }
        final sourceId = target.sourceId.trim().isNotEmpty
            ? target.sourceId.trim()
            : target.playbackTarget?.sourceId.trim() ?? '';
        if (sourceId.isNotEmpty) {
          sourceIds.add(sourceId);
        }
      }
    }
    return sourceIds;
  }

  Future<void> _clearDetailCacheForSourceUnlocked(
    String normalizedSourceId,
  ) async {
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

    await _runSerializedDetailMutation(
      () => _clearDetailCacheForResourceUnlocked(
        normalizedSourceId: normalizedSourceId,
        normalizedResourceId: normalizedResourceId,
        normalizedResourcePath: normalizedResourcePath,
        treatAsScope: treatAsScope,
      ),
    );
  }

  Future<void> _clearDetailCacheForResourceUnlocked({
    required String normalizedSourceId,
    required String normalizedResourceId,
    required String normalizedResourcePath,
    required bool treatAsScope,
  }) async {
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

  static List<String> buildLookupKeys(MediaDetailTarget target) {
    final keys = <String>{};
    final detailKind = _detailLookupKind(target);
    final isNestedEpisodic = _isNestedEpisodicKind(detailKind);
    final nestedScope = _nestedDetailLookupScope(target);

    void addKey(String key) {
      if (isNestedEpisodic && nestedScope == null) {
        return;
      }
      final trimmed = key.trim();
      if (trimmed.isNotEmpty) {
        keys.add(isNestedEpisodic ? '$trimmed|$nestedScope' : trimmed);
      }
    }

    final sourceId = target.sourceId.trim();
    final itemId = target.itemId.trim();
    if (sourceId.isNotEmpty && itemId.isNotEmpty) {
      keys.add('library|$sourceId|$itemId');
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
      return (await existingLoad).payload;
    }
    final loadFuture = _loadDetailPayloadFromStorage();
    if (!_isDisposed) _detailPayloadLoadFuture = loadFuture;
    try {
      final loaded = await loadFuture;
      if (identical(_detailPayloadLoadFuture, loadFuture)) {
        _detailPayloadCache = loaded.payload;
        _lastPersistedDetailRaw = loaded.raw;
      }
      return loaded.payload;
    } finally {
      if (identical(_detailPayloadLoadFuture, loadFuture)) {
        _detailPayloadLoadFuture = null;
      }
    }
  }

  Future<({_DetailCachePayload payload, String? raw})>
      _loadDetailPayloadFromStorage() async {
    final raw = await _preferences.getString(_detailCacheKey);
    if (raw == null || raw.isEmpty) {
      return (payload: const _DetailCachePayload(), raw: null);
    }

    final stopwatch = Stopwatch()..start();
    final decoded = await _decodeDetailCachePayloadOffUiThread(raw);
    stopwatch.stop();
    if (!decoded.isValid) {
      appLogWarning(
        'storage.detail-cache',
        'Detail cache payload could not be decoded',
        fields: <String, Object?>{
          'encodedBytes': decoded.byteLength,
          'decodeDurationMs': stopwatch.elapsedMilliseconds,
          'backgroundIsolate': decoded.usedBackgroundIsolate,
        },
      );
      return (payload: const _DetailCachePayload(), raw: null);
    }
    appLogTrace(
      'storage.detail-cache',
      'Detail cache payload decoded',
      fields: <String, Object?>{
        'recordCount': decoded.payload.records.length,
        'lookupKeyCount': decoded.payload.lookupKeys.length,
        'encodedBytes': decoded.byteLength,
        'decodeDurationMs': stopwatch.elapsedMilliseconds,
        'backgroundIsolate': decoded.usedBackgroundIsolate,
      },
    );
    return (payload: decoded.payload, raw: raw);
  }

  Future<void> _saveDetailPayload(_DetailCachePayload payload) async {
    final totalStopwatch = Stopwatch()..start();
    final encodeStopwatch = Stopwatch()..start();
    appLogTrace(
      'storage.detail-cache',
      'Detail cache persistence started',
      fields: <String, Object?>{
        'recordCount': payload.records.length,
        'lookupKeyCount': payload.lookupKeys.length,
      },
    );
    try {
      final encoded = await _encodeDetailCachePayloadOffUiThread(payload);
      encodeStopwatch.stop();
      if (encoded.raw == _lastPersistedDetailRaw) {
        totalStopwatch.stop();
        if (!_isDisposed) _detailPayloadCache = payload;
        _detailPayloadLoadFuture = null;
        appLogTrace(
          'storage.detail-cache',
          'Detail cache persistence skipped unchanged payload',
          fields: <String, Object?>{
            'recordCount': payload.records.length,
            'lookupKeyCount': payload.lookupKeys.length,
            'encodedBytes': encoded.byteLength,
            'encodeDurationMs': encodeStopwatch.elapsedMilliseconds,
          },
        );
        return;
      }
      final writeStopwatch = Stopwatch()..start();
      await _preferences.setString(_detailCacheKey, encoded.raw);
      writeStopwatch.stop();
      totalStopwatch.stop();
      if (!_isDisposed) _detailPayloadCache = payload;
      _detailPayloadLoadFuture = null;
      if (!_isDisposed) _lastPersistedDetailRaw = encoded.raw;
      appLogTrace(
        'storage.detail-cache',
        'Detail cache persistence completed',
        fields: <String, Object?>{
          'recordCount': payload.records.length,
          'lookupKeyCount': payload.lookupKeys.length,
          'encodedBytes': encoded.byteLength,
          'encodeDurationMs': encodeStopwatch.elapsedMilliseconds,
          'backgroundIsolate': encoded.usedBackgroundIsolate,
          'writeDurationMs': writeStopwatch.elapsedMilliseconds,
          'totalDurationMs': totalStopwatch.elapsedMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      encodeStopwatch.stop();
      totalStopwatch.stop();
      appLogError(
        'storage.detail-cache',
        'Detail cache persistence failed',
        fields: <String, Object?>{
          'recordCount': payload.records.length,
          'lookupKeyCount': payload.lookupKeys.length,
          'elapsedMs': totalStopwatch.elapsedMilliseconds,
        },
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _scheduleDetailCacheChangedNotification(
    LocalStorageDetailCacheChangeEvent event,
  ) {
    final notifyDetailCacheChanged = _notifyDetailCacheChanged;
    if (_isDisposed || notifyDetailCacheChanged == null) {
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
      ) ||
      previous.target.ratingCount != next.target.ratingCount) {
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

String? _nestedDetailLookupScope(MediaDetailTarget target) {
  final kind = _detailLookupKind(target);
  if (!_isNestedEpisodicKind(kind)) {
    return null;
  }
  final season = target.seasonNumber ?? target.playbackTarget?.seasonNumber;
  if (season == null || season < 0) {
    return null;
  }
  if (kind == 'season') {
    return 's:$season';
  }
  final episode = target.episodeNumber ?? target.playbackTarget?.episodeNumber;
  if (episode == null || episode <= 0) {
    return null;
  }
  return 's:$season|e:$episode';
}

bool _isTopLevelDetailKind(String detailKind) {
  return detailKind == 'series' || detailKind == 'movie';
}

bool _canShareDetailCacheRecord({
  required MediaDetailTarget left,
  required MediaDetailTarget right,
}) {
  if (_hasConflictingDirectorySeriesIdentity(left, right) ||
      _hasConflictingFntvSeriesIdentity(left, right)) {
    return false;
  }
  final leftKind = _detailLookupKind(left);
  final rightKind = _detailLookupKind(right);
  if (_isTopLevelDetailKind(leftKind) && _isNestedEpisodicKind(rightKind)) {
    return false;
  }
  if (_isNestedEpisodicKind(leftKind) && _isTopLevelDetailKind(rightKind)) {
    return false;
  }
  if (_isNestedEpisodicKind(leftKind) || _isNestedEpisodicKind(rightKind)) {
    if (leftKind != rightKind) {
      return false;
    }
    final leftSeason = left.seasonNumber ?? left.playbackTarget?.seasonNumber;
    final rightSeason =
        right.seasonNumber ?? right.playbackTarget?.seasonNumber;
    final leftEpisode =
        left.episodeNumber ?? left.playbackTarget?.episodeNumber;
    final rightEpisode =
        right.episodeNumber ?? right.playbackTarget?.episodeNumber;
    if ((leftSeason != null &&
            rightSeason != null &&
            leftSeason != rightSeason) ||
        (leftKind == 'episode' &&
            leftEpisode != null &&
            rightEpisode != null &&
            leftEpisode != rightEpisode)) {
      return false;
    }
    final leftScope = _nestedDetailLookupScope(left);
    final rightScope = _nestedDetailLookupScope(right);
    if (leftScope != null && rightScope != null) {
      return leftScope == rightScope;
    }
    return left.sourceId.trim().isNotEmpty &&
        left.itemId.trim().isNotEmpty &&
        left.sourceId.trim() == right.sourceId.trim() &&
        left.itemId.trim() == right.itemId.trim();
  }
  return true;
}

bool _canRestoreStructuralMismatchRecord({
  required MediaDetailTarget seedTarget,
  required _CachedDetailRecord record,
  required String matchedLookupKey,
}) {
  if (_hasConflictingDirectorySeriesIdentity(seedTarget, record.target) ||
      _hasConflictingFntvSeriesIdentity(seedTarget, record.target)) {
    return false;
  }
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

bool _hasConflictingFntvSeriesIdentity(
  MediaDetailTarget left,
  MediaDetailTarget right,
) {
  // Deleting and re-importing a series changes its GUID. A title/provider-ID
  // alias must not replace a fresh library entry with the deleted identity.
  return left.sourceKind == MediaSourceKind.fntv &&
      right.sourceKind == MediaSourceKind.fntv &&
      left.isSeries &&
      right.isSeries &&
      left.sourceId.trim().isNotEmpty &&
      left.sourceId.trim() == right.sourceId.trim() &&
      left.itemId.trim().isNotEmpty &&
      right.itemId.trim().isNotEmpty &&
      left.itemId.trim() != right.itemId.trim();
}

bool _hasConflictingDirectorySeriesIdentity(
  MediaDetailTarget left,
  MediaDetailTarget right,
) {
  final leftId = left.itemId.trim();
  final rightId = right.itemId.trim();
  if (!leftId.startsWith('webdav-series|') ||
      !rightId.startsWith('webdav-series|')) {
    return false;
  }
  return left.sourceId.trim() != right.sourceId.trim() || leftId != rightId;
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
  final normalizedResourcePath = resourcePath.trim();
  if (normalizedResourceId.isEmpty && normalizedResourcePath.isEmpty) {
    return true;
  }
  if (normalizedResourceId.isNotEmpty) {
    if (target.itemId.trim() == normalizedResourceId) {
      return true;
    }
    if ((target.playbackTarget?.itemId.trim() ?? '') == normalizedResourceId) {
      return true;
    }
  }

  if (normalizedResourcePath.isEmpty) {
    return false;
  }

  if (treatAsScope) {
    return resourcePathIsWithinScope(
            target.resourcePath, normalizedResourcePath) ||
        resourcePathIsWithinScope(
          target.playbackTarget?.actualAddress ?? '',
          normalizedResourcePath,
        );
  }

  return resourcePathsEqual(target.resourcePath, normalizedResourcePath) ||
      resourcePathsEqual(
        target.playbackTarget?.actualAddress ?? '',
        normalizedResourcePath,
      );
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
    ratingCount: target.ratingCount,
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
