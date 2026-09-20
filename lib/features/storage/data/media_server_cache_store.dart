import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

import 'local_storage_cache_models.dart';

const int _embyCacheBackgroundEntryThreshold = 16;
const int _embyCacheBackgroundDecodeThreshold = 64 * 1024;
const int _embySourceSummaryItemLimit = 400;
const int _embyFullSnapshotDecodeConcurrency = 2;

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

String _encodeMediaItemsShard(List<MediaItem> items) => jsonEncode(
    <String, dynamic>{'items': items.map((item) => item.toJson()).toList()});

_EncodedEmbySnapshotShards _encodeEmbySnapshotShards(
  CachedEmbyLibrarySnapshot snapshot, {
  required bool usedBackgroundIsolate,
}) {
  String encodeItems(List<MediaItem> items) {
    return _encodeMediaItemsShard(items);
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

/// Owns media-server manifests, shards, coalesced reads and serialized writes.
class MediaServerCacheStore {
  MediaServerCacheStore({required PreferencesStore preferences})
      : _preferences = preferences;

  final PreferencesStore _preferences;
  static const _embyLibraryManifestKey =
      'starflow.local_storage.emby_library_cache.manifest.v2';
  static const _embyLibraryShardPrefix =
      'starflow.local_storage.emby_library_cache.shard.v2';
  static const _embyShardIndexKey =
      'starflow.local_storage.emby_library_cache.shards.v2';

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
  bool _isDisposed = false;

  Future<Set<String>> loadCachedMediaSourceIds() async {
    final manifest = await _loadEmbyManifest();
    return manifest.sources.keys.map((item) => item.trim()).toSet();
  }

  void dispose() {
    _isDisposed = true;
    _embyManifestCache = null;
    _embyManifestLoadFuture = null;
    _embySnapshotCache.clear();
    _embySnapshotLoadFutures.clear();
    _embyItemsShardCache.clear();
    _embyItemsShardLoadFutures.clear();
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
    if (!_isDisposed) _embySnapshotLoadFutures[cacheKey] = loadFuture;
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

  Future<void> updateMediaItemRatingCount({
    required String sourceId,
    required String itemId,
    required int ratingCount,
  }) async {
    final normalizedSourceId = sourceId.trim();
    final normalizedItemId = itemId.trim();
    if (normalizedSourceId.isEmpty ||
        normalizedItemId.isEmpty ||
        ratingCount <= 0) {
      return;
    }
    await _enqueueEmbyMutation(() async {
      final manifest = await _loadEmbyManifest();
      final source = manifest.sources[normalizedSourceId];
      if (source == null) return;
      final keys = [
        _embyFallbackShardKey(normalizedSourceId),
        _embySummaryShardKey(normalizedSourceId),
        for (final section in source.sectionIds)
          _embySectionShardKey(normalizedSourceId, section),
      ];
      var changed = false;
      try {
        for (final key in keys) {
          final items = await _loadEmbyItemsShard(key);
          if (!items.any((item) =>
              (item.id.trim() == normalizedItemId ||
                  item.playbackItemId.trim() == normalizedItemId) &&
              item.ratingCount != ratingCount)) {
            continue;
          }
          final updated = items
              .map((item) => item.id.trim() == normalizedItemId ||
                      item.playbackItemId.trim() == normalizedItemId
                  ? item.copyWith(ratingCount: ratingCount)
                  : item)
              .toList(growable: false);
          final raw = updated.length >= _embyCacheBackgroundEntryThreshold
              ? await compute(_encodeMediaItemsShard, updated)
              : _encodeMediaItemsShard(updated);
          changed = true;
          await _writeChangedEmbyPayload(key, raw);
        }
      } finally {
        if (changed) _removeEmbySnapshotCacheEntries(normalizedSourceId);
      }
    });
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
    if (!_isDisposed) _embyManifestLoadFuture = loadFuture;
    try {
      final manifest = await loadFuture;
      if (identical(_embyManifestLoadFuture, loadFuture)) {
        _embyManifestCache = manifest;
      }
      return manifest;
    } finally {
      if (identical(_embyManifestLoadFuture, loadFuture)) {
        _embyManifestLoadFuture = null;
      }
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
    if (!_isDisposed) _embyItemsShardLoadFutures[key] = loadFuture;
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
    if (!_isDisposed) {
      _embySnapshotCache[_embySnapshotCacheKey(sourceId, '')] = snapshot;
      _embySnapshotCache[
              _embySnapshotCacheKey(sourceId, '', sourceSummary: true)] =
          _buildEmbySourceSummarySnapshot(snapshot);
    }
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
    final keys = await _knownShardKeys();
    keys.addAll([
      _embyFallbackShardKey(sourceId),
      _embySummaryShardKey(sourceId),
      ...encoded.sectionRaws.keys
          .map((id) => _embySectionShardKey(sourceId, id)),
    ]);
    // Register before any payload write so an interrupted commit stays collectible.
    await _preferences.setString(
        _embyShardIndexKey, jsonEncode(keys.toList()..sort()));
    await _writeChangedEmbyPayload(
      _embyFallbackShardKey(sourceId),
      encoded.fallbackRaw,
    );
    await _writeChangedEmbyPayload(
      _embySummaryShardKey(sourceId),
      encoded.summaryRaw,
    );
    for (final entry in encoded.sectionRaws.entries) {
      await _writeChangedEmbyPayload(
        _embySectionShardKey(sourceId, entry.key),
        entry.value,
      );
    }
  }

  Future<void> _persistEmbyManifest(_EmbyCacheManifest manifest) async {
    await _writeChangedEmbyPayload(
      _embyLibraryManifestKey,
      jsonEncode(manifest.toJson()),
    );
    if (!_isDisposed) _embyManifestCache = manifest;
    _embyManifestLoadFuture = null;
  }

  Future<void> _writeChangedEmbyPayload(String key, String raw) async {
    if (await _preferences.getString(key) == raw) return;
    await _preferences.setString(key, raw);
  }

  Future<void> _clearEmbySourceShards(String sourceId) async {
    final manifest = await _loadEmbyManifest();
    final sourceManifest = manifest.sources[sourceId];
    final known = await _knownShardKeys();
    final prefix = '$_embyLibraryShardPrefix.${_embyShardToken(sourceId)}.';
    final removing = known.where((key) => key.startsWith(prefix)).toSet()
      ..addAll([
        _embyFallbackShardKey(sourceId),
        _embySummaryShardKey(sourceId),
        ...?sourceManifest?.sectionIds
            .map((id) => _embySectionShardKey(sourceId, id)),
      ]);
    for (final key in removing) {
      await _preferences.remove(key);
    }
    await _preferences.setString(_embyShardIndexKey,
        jsonEncode(known.difference(removing).toList()..sort()));
    final nextSources = Map<String, _EmbyCacheSourceManifest>.from(
      manifest.sources,
    )..remove(sourceId);
    await _persistEmbyManifest(_EmbyCacheManifest(sources: nextSources));
    _removeEmbySnapshotCacheEntries(sourceId);
  }

  Future<void> _clearAllEmbyShards() async {
    final manifest = await _loadEmbyManifest();
    final known = await _knownShardKeys();
    for (final entry in manifest.sources.entries) {
      await _preferences.remove(_embyFallbackShardKey(entry.key));
      await _preferences.remove(_embySummaryShardKey(entry.key));
      for (final sectionId in entry.value.sectionIds) {
        await _preferences.remove(
          _embySectionShardKey(entry.key, sectionId),
        );
      }
    }
    for (final key in known) {
      await _preferences.remove(key);
    }
    await _preferences.remove(_embyShardIndexKey);
    await _preferences.remove(_embyLibraryManifestKey);
    if (!_isDisposed) _embyManifestCache = const _EmbyCacheManifest();
    _embyManifestLoadFuture = null;
    _embySnapshotCache.clear();
    _embySnapshotLoadFutures.clear();
    _embyItemsShardCache.clear();
    _embyItemsShardLoadFutures.clear();
  }

  Future<Set<String>> _knownShardKeys() async {
    final keys = <String>{};
    final raw = await _preferences.getString(_embyShardIndexKey);
    if (raw != null) {
      try {
        keys.addAll((jsonDecode(raw) as List).whereType<String>());
      } on FormatException {
        /* Enumerate persisted keys below. */
      } on TypeError {/* Enumerate persisted keys below. */}
    }
    final preferences = _preferences;
    if (preferences is EnumerablePreferencesStore) {
      keys.addAll(await (preferences as EnumerablePreferencesStore).getKeys());
    }
    return keys
        .where((key) => key.startsWith('$_embyLibraryShardPrefix.'))
        .toSet();
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

int _countEmbySnapshotEntries(CachedEmbyLibrarySnapshot snapshot) {
  return snapshot.collections.length +
      snapshot.fallbackItems.length +
      snapshot.itemsBySection.values.fold<int>(
        0,
        (sum, items) => sum + items.length,
      );
}
