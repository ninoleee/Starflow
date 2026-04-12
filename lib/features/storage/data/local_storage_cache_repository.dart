import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
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

  final PreferencesStore _preferences;
  final void Function(LocalStorageDetailCacheChangeEvent event)?
      _notifyDetailCacheChanged;
  final Duration detailCacheChangeNotificationDelay;
  Timer? _detailCacheChangeNotificationTimer;
  final Set<String> _pendingDetailCacheChangedSourceIds = <String>{};
  final Set<String> _pendingDetailCacheChangedLookupKeys = <String>{};
  bool _pendingDetailCacheInvalidateAll = false;

  void dispose() {
    _detailCacheChangeNotificationTimer?.cancel();
    _detailCacheChangeNotificationTimer = null;
    _pendingDetailCacheChangedSourceIds.clear();
    _pendingDetailCacheChangedLookupKeys.clear();
    _pendingDetailCacheInvalidateAll = false;
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
      final candidateRecord =
          candidate == null ? null : payload.records[candidate];
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
    final nextSubtitleSearchChoices = subtitleSearchChoices != null
        ? List<CachedSubtitleSearchOption>.unmodifiable(subtitleSearchChoices)
        : existing?.subtitleSearchChoices ??
            const <CachedSubtitleSearchOption>[];
    final normalizedSelectedSubtitleSearchIndex =
        nextSubtitleSearchChoices.isEmpty
            ? -1
            : (selectedSubtitleSearchIndex ??
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
    _scheduleDetailCacheChangedNotification(
      LocalStorageDetailCacheChangeEvent(
        scope: LocalStorageDetailCacheScope(
          sourceIds: {
            seedTarget.sourceId.trim(),
            resolvedTarget.sourceId.trim(),
            nextRecord.target.sourceId.trim(),
          }.where((item) => item.isNotEmpty).toSet(),
          lookupKeys: mergedLookupKeys.toSet(),
        ),
      ),
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
        ),
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
        ),
      ),
    );
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
            _pendingDetailCacheChangedLookupKeys.isNotEmpty
        ? LocalStorageDetailCacheChangeEvent(
            scope: LocalStorageDetailCacheScope(
              sourceIds: Set<String>.from(_pendingDetailCacheChangedSourceIds),
              lookupKeys:
                  Set<String>.from(_pendingDetailCacheChangedLookupKeys),
            ),
            invalidateAll: _pendingDetailCacheInvalidateAll,
          )
        : fallback;
    _pendingDetailCacheChangedSourceIds.clear();
    _pendingDetailCacheChangedLookupKeys.clear();
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
