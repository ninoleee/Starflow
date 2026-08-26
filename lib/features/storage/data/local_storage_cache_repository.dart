import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _detailCacheBackgroundRecordThreshold = 16;
const int _detailCacheBackgroundDecodeThreshold = 64 * 1024;
const Duration _detailCachePersistenceMergeWindow = Duration(milliseconds: 16);
const int _embyCacheBackgroundEntryThreshold = 16;
const int _embyCacheBackgroundDecodeThreshold = 64 * 1024;
const int _embySourceSummaryItemLimit = 400;
const int _embyFullSnapshotDecodeConcurrency = 2;

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

class _EmbyCacheSourceManifest {
  const _EmbyCacheSourceManifest({
    required this.refreshedAt,
    required this.collections,
    required this.sectionIds,
  });

  final DateTime? refreshedAt;
  final List<MediaCollection> collections;
  final List<String> sectionIds;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'refreshedAt': refreshedAt?.toIso8601String(),
        'collections': collections.map((item) => item.toJson()).toList(),
        'sectionIds': sectionIds,
      };

  factory _EmbyCacheSourceManifest.fromJson(Map<String, dynamic> json) {
    return _EmbyCacheSourceManifest(
      refreshedAt: DateTime.tryParse(json['refreshedAt'] as String? ?? ''),
      collections: (json['collections'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => MediaCollection.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      sectionIds: (json['sectionIds'] as List<dynamic>? ?? const [])
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class _EmbyCacheManifest {
  const _EmbyCacheManifest({
    this.sources = const <String, _EmbyCacheSourceManifest>{},
  });

  final Map<String, _EmbyCacheSourceManifest> sources;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sources': sources.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };

  factory _EmbyCacheManifest.fromJson(Map<String, dynamic> json) {
    return _EmbyCacheManifest(
      sources: (json['sources'] as Map<dynamic, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(
          '$key',
          _EmbyCacheSourceManifest.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
    );
  }
}

class _EncodedEmbySnapshotShards {
  const _EncodedEmbySnapshotShards({
    required this.fallbackRaw,
    required this.summaryRaw,
    required this.sectionRaws,
    required this.encodedBytes,
    required this.usedBackgroundIsolate,
  });

  final String fallbackRaw;
  final String summaryRaw;
  final Map<String, String> sectionRaws;
  final int encodedBytes;
  final bool usedBackgroundIsolate;
}

class _DecodedEmbyItemsShard {
  const _DecodedEmbyItemsShard({
    required this.items,
    required this.encodedBytes,
    required this.isValid,
    required this.usedBackgroundIsolate,
  });

  final List<MediaItem> items;
  final int encodedBytes;
  final bool isValid;
  final bool usedBackgroundIsolate;
}

_EncodedEmbySnapshotShards _encodeEmbySnapshotShards(
  CachedEmbyLibrarySnapshot snapshot, {
  required bool usedBackgroundIsolate,
}) {
  String encodeItems(List<MediaItem> items) {
    return jsonEncode(
      <String, dynamic>{
        'items': items.map((item) => item.toJson()).toList(),
      },
    );
  }

  final sectionItems = <String, List<MediaItem>>{
    for (final entry in snapshot.itemsBySection.entries)
      entry.key: List<MediaItem>.of(entry.value),
  };
  final fallbackBackedSectionIds = <String>{};
  final unscopedFallbackItems = <MediaItem>[];
  for (final item in snapshot.fallbackItems) {
    final sectionId = item.sectionId.trim();
    if (sectionId.isEmpty) {
      unscopedFallbackItems.add(item);
      continue;
    }
    final existing = sectionItems[sectionId];
    if (existing?.isNotEmpty == true &&
        !fallbackBackedSectionIds.contains(sectionId)) {
      continue;
    }
    final target = fallbackBackedSectionIds.add(sectionId)
        ? (sectionItems[sectionId] = <MediaItem>[])
        : sectionItems[sectionId]!;
    target.add(item);
  }
  final fallbackRaw = encodeItems(unscopedFallbackItems);
  final summaryItemsById = <String, MediaItem>{};
  for (final item in <MediaItem>[
    ...unscopedFallbackItems,
    ...sectionItems.values.expand((items) => items),
  ]) {
    final itemId = item.id.trim();
    final key = itemId.isEmpty
        ? '${item.sectionId}\u0000${item.actualAddress}\u0000${item.title}'
        : itemId;
    final existing = summaryItemsById[key];
    if (existing == null || item.addedAt.isAfter(existing.addedAt)) {
      summaryItemsById[key] = item;
    }
  }
  final summaryItems = summaryItemsById.values.toList(growable: false)
    ..sort((left, right) => right.addedAt.compareTo(left.addedAt));
  final summaryRaw = encodeItems(
    summaryItems.take(_embySourceSummaryItemLimit).toList(growable: false),
  );
  final sectionRaws = sectionItems.map(
    (key, value) => MapEntry(key, encodeItems(value)),
  );
  final encodedBytes = utf8.encode(fallbackRaw).length +
      utf8.encode(summaryRaw).length +
      sectionRaws.values.fold<int>(
        0,
        (sum, raw) => sum + utf8.encode(raw).length,
      );
  return _EncodedEmbySnapshotShards(
    fallbackRaw: fallbackRaw,
    summaryRaw: summaryRaw,
    sectionRaws: sectionRaws,
    encodedBytes: encodedBytes,
    usedBackgroundIsolate: usedBackgroundIsolate,
  );
}

Future<_EncodedEmbySnapshotShards> _encodeEmbySnapshotShardsOffUiThread(
  CachedEmbyLibrarySnapshot snapshot,
) {
  final entryCount = _countEmbySnapshotEntries(snapshot);
  if (kIsWeb || entryCount < _embyCacheBackgroundEntryThreshold) {
    return Future<_EncodedEmbySnapshotShards>.value(
      _encodeEmbySnapshotShards(
        snapshot,
        usedBackgroundIsolate: false,
      ),
    );
  }
  return Isolate.run(
    () => _encodeEmbySnapshotShards(
      snapshot,
      usedBackgroundIsolate: true,
    ),
  );
}

_DecodedEmbyItemsShard _decodeEmbyItemsShard(
  String raw, {
  required bool usedBackgroundIsolate,
}) {
  final encodedBytes = utf8.encode(raw).length;
  try {
    final decoded = jsonDecode(raw);
    final map = Map<String, dynamic>.from(decoded as Map);
    final items = (map['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => MediaItem.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return _DecodedEmbyItemsShard(
      items: items,
      encodedBytes: encodedBytes,
      isValid: true,
      usedBackgroundIsolate: usedBackgroundIsolate,
    );
  } catch (_) {
    return _DecodedEmbyItemsShard(
      items: const <MediaItem>[],
      encodedBytes: encodedBytes,
      isValid: false,
      usedBackgroundIsolate: usedBackgroundIsolate,
    );
  }
}

Future<_DecodedEmbyItemsShard> _decodeEmbyItemsShardOffUiThread(String raw) {
  if (kIsWeb || raw.length < _embyCacheBackgroundDecodeThreshold) {
    return Future<_DecodedEmbyItemsShard>.value(
      _decodeEmbyItemsShard(raw, usedBackgroundIsolate: false),
    );
  }
  return Isolate.run(
    () => _decodeEmbyItemsShard(raw, usedBackgroundIsolate: true),
  );
}

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

class _PendingDetailTargetSaveBatch {
  _PendingDetailTargetSaveBatch(this.requests);

  final List<DetailTargetCacheSaveRequest> requests;
  final Completer<void> completer = Completer<void>();
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
  static const _embyLibraryManifestKey =
      'starflow.local_storage.emby_library_cache.manifest.v2';
  static const _embyLibraryShardPrefix =
      'starflow.local_storage.emby_library_cache.shard.v2';

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
  String? _lastPersistedDetailRaw;
  Future<void> _detailMutationTail = Future<void>.value();
  final List<_PendingDetailTargetSaveBatch> _pendingDetailTargetSaveBatches =
      <_PendingDetailTargetSaveBatch>[];
  bool _detailTargetSaveFlushScheduled = false;
  _EmbyCacheManifest? _embyManifestCache;
  Future<_EmbyCacheManifest>? _embyManifestLoadFuture;
  final Map<String, CachedEmbyLibrarySnapshot> _embySnapshotCache =
      <String, CachedEmbyLibrarySnapshot>{};
  final Map<String, Future<CachedEmbyLibrarySnapshot>>
      _embySnapshotLoadFutures = <String, Future<CachedEmbyLibrarySnapshot>>{};
  final Map<String, List<MediaItem>> _embyItemsShardCache =
      <String, List<MediaItem>>{};
  final Map<String, Future<List<MediaItem>>> _embyItemsShardLoadFutures =
      <String, Future<List<MediaItem>>>{};
  Future<void> _embyMutationTail = Future<void>.value();

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
    _lastPersistedDetailRaw = null;
    _embyManifestCache = null;
    _embyManifestLoadFuture = null;
    _embySnapshotCache.clear();
    _embySnapshotLoadFutures.clear();
    _embyItemsShardCache.clear();
    _embyItemsShardLoadFutures.clear();
  }

  Future<void> primeDetailPayload() async {
    await _loadDetailPayload();
  }

  Future<CachedEmbyLibrarySnapshot> loadEmbyLibrarySnapshot(
    String sourceId, {
    String? sectionId,
    bool preferSourceSummary = false,
  }) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return const CachedEmbyLibrarySnapshot();
    }
    final normalizedSectionId = sectionId?.trim() ?? '';
    final cacheKey = _embySnapshotCacheKey(
      normalizedSourceId,
      normalizedSectionId,
      sourceSummary: preferSourceSummary && normalizedSectionId.isEmpty,
    );
    final cached = _embySnapshotCache[cacheKey];
    if (cached != null) {
      return cached;
    }
    final existingLoad = _embySnapshotLoadFutures[cacheKey];
    if (existingLoad != null) {
      return existingLoad;
    }
    final loadFuture = _loadEmbyLibrarySnapshotFromStorage(
      normalizedSourceId,
      normalizedSectionId,
      preferSourceSummary: preferSourceSummary,
    );
    _embySnapshotLoadFutures[cacheKey] = loadFuture;
    try {
      final snapshot = await loadFuture;
      if (identical(_embySnapshotLoadFutures[cacheKey], loadFuture)) {
        _embySnapshotCache[cacheKey] = snapshot;
      }
      return snapshot;
    } finally {
      if (identical(_embySnapshotLoadFutures[cacheKey], loadFuture)) {
        _embySnapshotLoadFutures.remove(cacheKey);
      }
    }
  }

  Future<CachedEmbyLibrarySnapshot> _loadEmbyLibrarySnapshotFromStorage(
    String normalizedSourceId,
    String normalizedSectionId, {
    required bool preferSourceSummary,
  }) async {
    final manifest = await _loadEmbyManifest();
    final sourceManifest = manifest.sources[normalizedSourceId];
    if (sourceManifest == null) {
      return const CachedEmbyLibrarySnapshot();
    }
    final stopwatch = Stopwatch()..start();
    late final Map<String, List<MediaItem>> itemsBySection;
    late final List<MediaItem> fallbackItems;
    var usedFullSnapshotFallback = false;
    if (normalizedSectionId.isNotEmpty) {
      final scopedItems = await _loadEmbyItemsShard(
        _embySectionShardKey(normalizedSourceId, normalizedSectionId),
      );
      fallbackItems = scopedItems.isEmpty
          ? await _loadEmbyItemsShard(
              _embyFallbackShardKey(normalizedSourceId),
            )
          : const [];
      itemsBySection = <String, List<MediaItem>>{
        normalizedSectionId: scopedItems,
      };
    } else if (preferSourceSummary) {
      final summaryItems = await _loadEmbyItemsShard(
        _embySummaryShardKey(normalizedSourceId),
      );
      if (summaryItems.isEmpty) {
        usedFullSnapshotFallback = true;
        itemsBySection = await _loadEmbySectionShards(
          normalizedSourceId,
          sourceManifest.sectionIds,
        );
        fallbackItems = await _loadEmbyItemsShard(
          _embyFallbackShardKey(normalizedSourceId),
        );
      } else {
        final grouped = <String, List<MediaItem>>{};
        final unscoped = <MediaItem>[];
        for (final item in summaryItems) {
          final currentSectionId = item.sectionId.trim();
          if (currentSectionId.isEmpty) {
            unscoped.add(item);
          } else {
            (grouped[currentSectionId] ??= <MediaItem>[]).add(item);
          }
        }
        itemsBySection = grouped;
        fallbackItems = unscoped;
      }
    } else {
      itemsBySection = await _loadEmbySectionShards(
        normalizedSourceId,
        sourceManifest.sectionIds,
      );
      fallbackItems = await _loadEmbyItemsShard(
        _embyFallbackShardKey(normalizedSourceId),
      );
    }
    final snapshot = CachedEmbyLibrarySnapshot(
      refreshedAt: sourceManifest.refreshedAt,
      collections: sourceManifest.collections,
      fallbackItems: fallbackItems,
      itemsBySection: itemsBySection,
    );
    stopwatch.stop();
    final fields = <String, Object?>{
      'sourceId': normalizedSourceId,
      'sectionId': normalizedSectionId,
      'sourceSummary': preferSourceSummary && normalizedSectionId.isEmpty,
      'fullSnapshotFallback': usedFullSnapshotFallback,
      'sectionCount': itemsBySection.length,
      'itemCount': _countEmbySnapshotEntries(snapshot),
      'durationMs': stopwatch.elapsedMilliseconds,
    };
    if (stopwatch.elapsedMilliseconds >= 500) {
      appLogInfo(
        'storage.emby-cache',
        'Slow Emby cache shard load completed',
        fields: fields,
      );
    } else {
      appLogTrace(
        'storage.emby-cache',
        'Emby cache shards loaded',
        fields: fields,
      );
    }
    return snapshot;
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
    await _enqueueEmbyMutation(
      () => _saveEmbySnapshotShards(normalizedSourceId, snapshot),
    );
  }

  Future<void> clearEmbyLibrarySnapshot(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }

    await _enqueueEmbyMutation(
      () => _clearEmbySourceShards(normalizedSourceId),
    );
  }

  Future<LocalStorageCacheSummary> inspectEmbyLibraryCache() async {
    final manifest = await _loadEmbyManifest();
    var entryCount = 0;
    var totalBytes = utf8
        .encode(await _preferences.getString(_embyLibraryManifestKey) ?? '')
        .length;
    for (final entry in manifest.sources.entries) {
      final sourceId = entry.key;
      final sourceManifest = entry.value;
      entryCount += sourceManifest.collections.length;
      final keys = <String>[
        _embyFallbackShardKey(sourceId),
        _embySummaryShardKey(sourceId),
        ...sourceManifest.sectionIds.map(
          (sectionId) => _embySectionShardKey(sourceId, sectionId),
        ),
      ];
      for (final key in keys) {
        final raw = await _preferences.getString(key) ?? '';
        totalBytes += utf8.encode(raw).length;
        if (raw.isNotEmpty && key != _embySummaryShardKey(sourceId)) {
          entryCount +=
              (await _decodeEmbyItemsShardOffUiThread(raw)).items.length;
        }
      }
    }
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.embyLibraryCache,
      entryCount: entryCount,
      totalBytes: totalBytes,
    );
  }

  Future<void> clearAllEmbyLibrarySnapshots() async {
    await _enqueueEmbyMutation(_clearAllEmbyShards);
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
    _pendingDetailTargetSaveBatches.add(pending);
    if (!_detailTargetSaveFlushScheduled) {
      _detailTargetSaveFlushScheduled = true;
      unawaited(
        _runSerializedDetailMutation(() async {
          await Future<void>.delayed(_detailCachePersistenceMergeWindow);
          final pendingBatches = List<_PendingDetailTargetSaveBatch>.of(
            _pendingDetailTargetSaveBatches,
          );
          _pendingDetailTargetSaveBatches.clear();
          _detailTargetSaveFlushScheduled = false;
          try {
            await _saveDetailTargetsBatchUnlocked(
              pendingBatches
                  .expand((batch) => batch.requests)
                  .toList(growable: false),
              persistToStorage: true,
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
        }).catchError((Object _) {}),
      );
    }
    return pending.completer.future;
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

  Future<void> _runSerializedDetailMutation(
    Future<void> Function() operation,
  ) {
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
    await _runSerializedDetailMutation(_clearDetailCacheUnlocked);
  }

  Future<void> _clearDetailCacheUnlocked() async {
    await _preferences.remove(_detailCacheKey);
    _detailPayloadCache = const _DetailCachePayload();
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

  Future<_EmbyCacheManifest> _loadEmbyManifest() async {
    final cached = _embyManifestCache;
    if (cached != null) {
      return cached;
    }
    final existingLoad = _embyManifestLoadFuture;
    if (existingLoad != null) {
      return existingLoad;
    }
    final loadFuture = _loadEmbyManifestFromStorage();
    _embyManifestLoadFuture = loadFuture;
    try {
      final manifest = await loadFuture;
      _embyManifestCache = manifest;
      return manifest;
    } finally {
      _embyManifestLoadFuture = null;
    }
  }

  Future<_EmbyCacheManifest> _loadEmbyManifestFromStorage() async {
    final raw = await _preferences.getString(_embyLibraryManifestKey) ?? '';
    if (raw.isEmpty) {
      return const _EmbyCacheManifest();
    }
    try {
      return _EmbyCacheManifest.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (error, stackTrace) {
      appLogWarning(
        'storage.emby-cache',
        'Emby cache manifest could not be decoded',
        error: error,
        stackTrace: stackTrace,
      );
      return const _EmbyCacheManifest();
    }
  }

  Future<List<MediaItem>> _loadEmbyItemsShard(String key) async {
    final cached = _embyItemsShardCache[key];
    if (cached != null) {
      return cached;
    }
    final existingLoad = _embyItemsShardLoadFutures[key];
    if (existingLoad != null) {
      return existingLoad;
    }
    final loadFuture = _loadEmbyItemsShardFromStorage(key);
    _embyItemsShardLoadFutures[key] = loadFuture;
    try {
      final items = await loadFuture;
      if (identical(_embyItemsShardLoadFutures[key], loadFuture)) {
        _embyItemsShardCache[key] = items;
      }
      return items;
    } finally {
      if (identical(_embyItemsShardLoadFutures[key], loadFuture)) {
        _embyItemsShardLoadFutures.remove(key);
      }
    }
  }

  Future<List<MediaItem>> _loadEmbyItemsShardFromStorage(String key) async {
    final raw = await _preferences.getString(key) ?? '';
    if (raw.isEmpty) {
      return const <MediaItem>[];
    }
    final decoded = await _decodeEmbyItemsShardOffUiThread(raw);
    if (!decoded.isValid) {
      appLogWarning(
        'storage.emby-cache',
        'Emby cache shard could not be decoded',
        fields: <String, Object?>{
          'encodedBytes': decoded.encodedBytes,
          'backgroundIsolate': decoded.usedBackgroundIsolate,
        },
      );
      return const <MediaItem>[];
    }
    return decoded.items;
  }

  Future<Map<String, List<MediaItem>>> _loadEmbySectionShards(
    String sourceId,
    List<String> sectionIds,
  ) async {
    if (sectionIds.isEmpty) {
      return const <String, List<MediaItem>>{};
    }
    final entries = <MapEntry<String, List<MediaItem>>>[];
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < sectionIds.length) {
        final currentIndex = nextIndex;
        nextIndex += 1;
        final sectionId = sectionIds[currentIndex];
        final items = await _loadEmbyItemsShard(
          _embySectionShardKey(sourceId, sectionId),
        );
        entries.add(MapEntry(sectionId, items));
      }
    }

    final workerCount = sectionIds.length < _embyFullSnapshotDecodeConcurrency
        ? sectionIds.length
        : _embyFullSnapshotDecodeConcurrency;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return Map<String, List<MediaItem>>.fromEntries(entries);
  }

  Future<void> _saveEmbySnapshotShards(
    String sourceId,
    CachedEmbyLibrarySnapshot snapshot,
  ) async {
    final manifest = await _loadEmbyManifest();
    final previousSectionIds =
        manifest.sources[sourceId]?.sectionIds ?? const <String>[];
    final stopwatch = Stopwatch()..start();
    final encoded = await _encodeEmbySnapshotShardsOffUiThread(snapshot);
    await _writeEmbyShardPayloads(sourceId, encoded);
    final currentSectionIds = encoded.sectionRaws.keys.toSet();
    for (final staleSectionId in previousSectionIds) {
      if (!currentSectionIds.contains(staleSectionId)) {
        await _preferences.remove(
          _embySectionShardKey(sourceId, staleSectionId),
        );
      }
    }
    final nextManifest = _EmbyCacheManifest(
      sources: <String, _EmbyCacheSourceManifest>{
        ...manifest.sources,
        sourceId: _manifestForEmbySnapshot(
          snapshot,
          sectionIds: encoded.sectionRaws.keys,
        ),
      },
    );
    await _persistEmbyManifest(nextManifest);
    _removeEmbySnapshotCacheEntries(sourceId);
    _embySnapshotCache[_embySnapshotCacheKey(sourceId, '')] = snapshot;
    _embySnapshotCache[
            _embySnapshotCacheKey(sourceId, '', sourceSummary: true)] =
        _buildEmbySourceSummarySnapshot(snapshot);
    stopwatch.stop();
    appLogTrace(
      'storage.emby-cache',
      'Emby cache persisted as shards',
      fields: <String, Object?>{
        'sourceId': sourceId,
        'sectionCount': encoded.sectionRaws.length,
        'itemCount': _countEmbySnapshotEntries(snapshot),
        'encodedBytes': encoded.encodedBytes,
        'durationMs': stopwatch.elapsedMilliseconds,
        'backgroundIsolate': encoded.usedBackgroundIsolate,
      },
    );
  }

  Future<void> _writeEmbyShardPayloads(
    String sourceId,
    _EncodedEmbySnapshotShards encoded,
  ) async {
    await _preferences.setString(
      _embyFallbackShardKey(sourceId),
      encoded.fallbackRaw,
    );
    await _preferences.setString(
      _embySummaryShardKey(sourceId),
      encoded.summaryRaw,
    );
    for (final entry in encoded.sectionRaws.entries) {
      await _preferences.setString(
        _embySectionShardKey(sourceId, entry.key),
        entry.value,
      );
    }
  }

  Future<void> _persistEmbyManifest(_EmbyCacheManifest manifest) async {
    await _preferences.setString(
      _embyLibraryManifestKey,
      jsonEncode(manifest.toJson()),
    );
    _embyManifestCache = manifest;
    _embyManifestLoadFuture = null;
  }

  Future<void> _clearEmbySourceShards(String sourceId) async {
    final manifest = await _loadEmbyManifest();
    final sourceManifest = manifest.sources[sourceId];
    if (sourceManifest == null) {
      return;
    }
    await _preferences.remove(_embyFallbackShardKey(sourceId));
    await _preferences.remove(_embySummaryShardKey(sourceId));
    for (final sectionId in sourceManifest.sectionIds) {
      await _preferences.remove(_embySectionShardKey(sourceId, sectionId));
    }
    final nextSources = Map<String, _EmbyCacheSourceManifest>.from(
      manifest.sources,
    )..remove(sourceId);
    await _persistEmbyManifest(_EmbyCacheManifest(sources: nextSources));
    _removeEmbySnapshotCacheEntries(sourceId);
  }

  Future<void> _clearAllEmbyShards() async {
    final manifest = await _loadEmbyManifest();
    for (final entry in manifest.sources.entries) {
      await _preferences.remove(_embyFallbackShardKey(entry.key));
      await _preferences.remove(_embySummaryShardKey(entry.key));
      for (final sectionId in entry.value.sectionIds) {
        await _preferences.remove(
          _embySectionShardKey(entry.key, sectionId),
        );
      }
    }
    await _preferences.remove(_embyLibraryManifestKey);
    _embyManifestCache = const _EmbyCacheManifest();
    _embyManifestLoadFuture = null;
    _embySnapshotCache.clear();
    _embySnapshotLoadFutures.clear();
    _embyItemsShardCache.clear();
    _embyItemsShardLoadFutures.clear();
  }

  Future<void> _enqueueEmbyMutation(Future<void> Function() operation) {
    final scheduled =
        _embyMutationTail.catchError((Object _) {}).then((_) => operation());
    _embyMutationTail = scheduled.catchError((Object _) {});
    return scheduled;
  }

  _EmbyCacheSourceManifest _manifestForEmbySnapshot(
    CachedEmbyLibrarySnapshot snapshot, {
    Iterable<String>? sectionIds,
  }) {
    return _EmbyCacheSourceManifest(
      refreshedAt: snapshot.refreshedAt,
      collections: snapshot.collections,
      sectionIds: (sectionIds ?? snapshot.itemsBySection.keys)
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }

  String _embySnapshotCacheKey(
    String sourceId,
    String sectionId, {
    bool sourceSummary = false,
  }) {
    final scope =
        sourceSummary ? 'summary' : (sectionId.isEmpty ? '*' : sectionId);
    return '$sourceId\u0000$scope';
  }

  String _embyFallbackShardKey(String sourceId) {
    return '$_embyLibraryShardPrefix.${_embyShardToken(sourceId)}.fallback';
  }

  String _embySummaryShardKey(String sourceId) {
    return '$_embyLibraryShardPrefix.${_embyShardToken(sourceId)}.summary';
  }

  String _embySectionShardKey(String sourceId, String sectionId) {
    return '$_embyLibraryShardPrefix.${_embyShardToken(sourceId)}.'
        '${_embyShardToken(sectionId)}';
  }

  String _embyShardToken(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }

  void _removeEmbySnapshotCacheEntries(String sourceId) {
    _embySnapshotCache.removeWhere(
      (key, _) => key.startsWith('$sourceId\u0000'),
    );
    _embySnapshotLoadFutures.removeWhere(
      (key, _) => key.startsWith('$sourceId\u0000'),
    );
    final shardPrefix =
        '$_embyLibraryShardPrefix.${_embyShardToken(sourceId)}.';
    _embyItemsShardCache.removeWhere(
      (key, _) => key.startsWith(shardPrefix),
    );
    _embyItemsShardLoadFutures.removeWhere(
      (key, _) => key.startsWith(shardPrefix),
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
      _lastPersistedDetailRaw = null;
      return const _DetailCachePayload();
    }

    final stopwatch = Stopwatch()..start();
    final decoded = await _decodeDetailCachePayloadOffUiThread(raw);
    stopwatch.stop();
    if (!decoded.isValid) {
      _lastPersistedDetailRaw = null;
      appLogWarning(
        'storage.detail-cache',
        'Detail cache payload could not be decoded',
        fields: <String, Object?>{
          'encodedBytes': decoded.byteLength,
          'decodeDurationMs': stopwatch.elapsedMilliseconds,
          'backgroundIsolate': decoded.usedBackgroundIsolate,
        },
      );
      return const _DetailCachePayload();
    }
    _lastPersistedDetailRaw = raw;
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
    return decoded.payload;
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
        _detailPayloadCache = payload;
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
      _detailPayloadCache = payload;
      _detailPayloadLoadFuture = null;
      _lastPersistedDetailRaw = encoded.raw;
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
}

CachedEmbyLibrarySnapshot _buildEmbySourceSummarySnapshot(
  CachedEmbyLibrarySnapshot snapshot,
) {
  final itemsById = <String, MediaItem>{};
  for (final item in <MediaItem>[
    ...snapshot.fallbackItems,
    ...snapshot.itemsBySection.values.expand((items) => items),
  ]) {
    final itemId = item.id.trim();
    final key = itemId.isEmpty
        ? '${item.sectionId}\u0000${item.actualAddress}\u0000${item.title}'
        : itemId;
    final existing = itemsById[key];
    if (existing == null || item.addedAt.isAfter(existing.addedAt)) {
      itemsById[key] = item;
    }
  }
  final ordered = itemsById.values.toList(growable: false)
    ..sort((left, right) => right.addedAt.compareTo(left.addedAt));
  final grouped = <String, List<MediaItem>>{};
  final unscoped = <MediaItem>[];
  for (final item in ordered.take(_embySourceSummaryItemLimit)) {
    final sectionId = item.sectionId.trim();
    if (sectionId.isEmpty) {
      unscoped.add(item);
    } else {
      (grouped[sectionId] ??= <MediaItem>[]).add(item);
    }
  }
  return CachedEmbyLibrarySnapshot(
    refreshedAt: snapshot.refreshedAt,
    collections: snapshot.collections,
    fallbackItems: List<MediaItem>.unmodifiable(unscoped),
    itemsBySection: Map<String, List<MediaItem>>.unmodifiable(
      grouped.map(
        (key, value) => MapEntry(key, List<MediaItem>.unmodifiable(value)),
      ),
    ),
  );
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
