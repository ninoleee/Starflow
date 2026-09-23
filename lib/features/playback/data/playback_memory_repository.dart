import 'dart:convert';
import 'package:starflow/features/playback/domain/playback_memory_policy.dart';
import 'package:starflow/features/playback/data/native_playback_memory_preferences.dart';
import 'package:starflow/features/playback/application/playback_policy_values.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/resource_path_identity.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

final playbackHistoryRevisionProvider = StateProvider<int>((ref) => 0);

final playbackMemoryRepositoryProvider = Provider<PlaybackMemoryRepository>((
  ref,
) {
  return PlaybackMemoryRepository(
    notifyChanged: () {
      ref.read(playbackHistoryRevisionProvider.notifier).state++;
    },
  );
});

final playbackMemorySnapshotProvider = FutureProvider<PlaybackMemorySnapshot>((
  ref,
) async {
  ref.watch(playbackHistoryRevisionProvider);
  return ref.read(playbackMemoryRepositoryProvider).loadSnapshot();
});

@immutable
class PlaybackResumeDetailLookup {
  const PlaybackResumeDetailLookup(this.target);

  final MediaDetailTarget target;

  @override
  bool operator ==(Object other) {
    return other is PlaybackResumeDetailLookup &&
        playbackResumeDetailLookupKey(target) ==
            playbackResumeDetailLookupKey(other.target);
  }

  @override
  int get hashCode => playbackResumeDetailLookupKey(target).hashCode;
}

String playbackResumeDetailLookupKey(MediaDetailTarget target) {
  final normalizedItemType = target.itemType.trim().toLowerCase();
  if (normalizedItemType == 'series') {
    return 'series:${buildSeriesKeyForMetadata(
      sourceId: target.sourceId,
      itemId: target.itemId,
      title: target.title,
      year: target.year,
    )}';
  }

  final playbackTarget = target.playbackTarget;
  if (playbackTarget != null) {
    return 'playable:${buildPlaybackItemKey(playbackTarget)}';
  }

  return [
    'detail',
    target.sourceId.trim(),
    target.itemId.trim(),
    _playbackResourceIdentity(target.resourcePath),
    _normalizePlaybackText(target.title),
    target.year,
  ].join('|');
}

final playbackResumeForDetailTargetProvider =
    FutureProvider.family<PlaybackProgressEntry?, PlaybackResumeDetailLookup>((
  ref,
  lookup,
) async {
  final snapshot = await ref.watch(playbackMemorySnapshotProvider.future);
  return ref
      .read(playbackMemoryRepositoryProvider)
      .resumeEntryForDetailTargetFromSnapshot(snapshot, lookup.target);
});

final playbackEntryForMediaItemProvider =
    FutureProvider.family<PlaybackProgressEntry?, MediaItem>((ref, item) async {
  final snapshot = await ref.watch(playbackMemorySnapshotProvider.future);
  return ref.read(playbackMemoryRepositoryProvider).entryForTargetFromSnapshot(
        snapshot,
        PlaybackTarget.fromMediaItem(item),
      );
});

final recentPlaybackEntriesProvider =
    FutureProvider.family<List<PlaybackProgressEntry>, int>((ref, limit) async {
  final snapshot = await ref.watch(playbackMemorySnapshotProvider.future);
  return ref
      .read(playbackMemoryRepositoryProvider)
      .recentDisplayEntriesFromSnapshot(snapshot, limit: limit);
});

class PlaybackMemoryRepository {
  PlaybackMemoryRepository({
    PreferencesStore? preferences,
    SharedPreferences? sharedPreferences,
    void Function()? notifyChanged,
  })  : assert(preferences == null || sharedPreferences == null),
        _preferences = preferences ??
            (sharedPreferences == null
                ? _defaultPlaybackMemoryPreferencesStore()
                : SharedPreferencesStore(sharedPreferences)),
        _notifyChanged = notifyChanged;

  static const _storageKey = 'starflow.playback.memory.v2';
  static const recentEntryLimit = PlaybackPolicyValues.memoryRecentLimit;

  final PreferencesStore _preferences;
  final void Function()? _notifyChanged;
  PlaybackMemorySnapshot? _cachedSnapshot;
  Future<PlaybackMemorySnapshot>? _snapshotLoad;
  Future<void> _mutationTail = Future<void>.value();
  int _cacheGeneration = 0;

  Future<void> _mutate(Future<void> Function() action) {
    final operation = _mutationTail.then((_) async {
      for (var attempt = 0;; attempt++) {
        if (_preferences is NativePlaybackMemoryPreferences) {
          invalidateSnapshotCache();
          await _loadSnapshot();
        }
        try {
          await action();
          return;
        } on PlaybackMemoryWriteConflict {
          invalidateSnapshotCache();
          if (attempt >= 7) rethrow;
        }
      }
    });
    _mutationTail =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  /// Drops the in-memory snapshot so the next read goes back to storage.
  ///
  /// The Android native player writes the same physical key while Flutter is
  /// backgrounded, so the cache must be dropped whenever the app resumes.
  void invalidateSnapshotCache() {
    _cacheGeneration++;
    _cachedSnapshot = null;
    _snapshotLoad = null;
  }

  Future<PlaybackProgressEntry?> loadEntryForTarget(
    PlaybackTarget target,
  ) async {
    final snapshot = await loadSnapshot();
    return entryForTargetFromSnapshot(snapshot, target);
  }

  PlaybackProgressEntry? entryForTargetFromSnapshot(
    PlaybackMemorySnapshot snapshot,
    PlaybackTarget target,
  ) {
    final key = buildPlaybackItemKey(target);
    if (key.isEmpty) {
      return null;
    }
    return _normalizeEntry(_entryForKey(snapshot, key));
  }

  Future<PlaybackProgressEntry?> loadResumeForDetailTarget(
    MediaDetailTarget target,
  ) async {
    final snapshot = await loadSnapshot();
    return resumeEntryForDetailTargetFromSnapshot(snapshot, target);
  }

  PlaybackProgressEntry? resumeEntryForDetailTargetFromSnapshot(
    PlaybackMemorySnapshot snapshot,
    MediaDetailTarget target,
  ) {
    final normalizedItemType = target.itemType.trim().toLowerCase();
    if (normalizedItemType == 'series') {
      final seriesKey = buildSeriesKeyForMetadata(
        sourceId: target.sourceId,
        itemId: target.itemId,
        title: target.title,
        year: target.year,
      );
      if (seriesKey.isEmpty) {
        return null;
      }
      return _normalizeEntry(snapshot.series[seriesKey]);
    }

    final playbackTarget = target.playbackTarget;
    if (playbackTarget == null) {
      return null;
    }
    final itemKey = buildPlaybackItemKey(playbackTarget);
    if (itemKey.isEmpty) {
      return null;
    }
    return _normalizeEntry(_entryForKey(snapshot, itemKey));
  }

  Future<List<PlaybackProgressEntry>> loadRecentEntries(
      {int limit = 20}) async {
    final snapshot = await loadSnapshot();
    return recentEntriesFromSnapshot(snapshot, limit: limit);
  }

  List<PlaybackProgressEntry> recentEntriesFromSnapshot(
    PlaybackMemorySnapshot snapshot, {
    int limit = 20,
  }) {
    final entries = snapshot.items.values
        .map(_normalizeEntry)
        .whereType<PlaybackProgressEntry>()
        .toList()
      ..sort(_compareEntriesByRecency);
    return entries.take(limit.clamp(1, recentEntryLimit)).toList(
          growable: false,
        );
  }

  Future<List<PlaybackProgressEntry>> loadRecentDisplayEntries({
    int limit = 20,
  }) async {
    final snapshot = await loadSnapshot();
    return recentDisplayEntriesFromSnapshot(snapshot, limit: limit);
  }

  List<PlaybackProgressEntry> recentDisplayEntriesFromSnapshot(
    PlaybackMemorySnapshot snapshot, {
    int limit = 20,
  }) {
    final combined = <String, PlaybackProgressEntry>{};

    void addEntry(String key, PlaybackProgressEntry entry) {
      final trimmedKey = key.trim();
      if (trimmedKey.isEmpty) {
        return;
      }
      final existing = combined[trimmedKey];
      if (existing == null || entry.updatedAt.isAfter(existing.updatedAt)) {
        combined[trimmedKey] = entry;
      }
    }

    for (final rawEntry in snapshot.items.values) {
      final entry = _normalizeEntry(rawEntry);
      if (entry == null) {
        continue;
      }
      final seriesKey = entry.seriesKey.trim();
      if (seriesKey.isNotEmpty) {
        continue;
      }
      addEntry('item:${entry.key}', entry);
    }

    for (final rawEntry in snapshot.series.values) {
      final entry = _normalizeEntry(rawEntry);
      if (entry == null) {
        continue;
      }
      final seriesKey = entry.seriesKey.trim();
      if (seriesKey.isNotEmpty) {
        addEntry('series:$seriesKey', entry);
      } else {
        addEntry('item:${entry.key}', entry);
      }
    }

    final entries = combined.values.toList()..sort(_compareEntriesByRecency);
    return entries.take(limit.clamp(1, recentEntryLimit)).toList(
          growable: false,
        );
  }

  Future<SeriesSkipPreference?> loadSkipPreference(
    PlaybackTarget target,
  ) async {
    final snapshot = await loadSnapshot();
    return skipPreferenceForTargetFromSnapshot(snapshot, target);
  }

  SeriesSkipPreference? skipPreferenceForTargetFromSnapshot(
    PlaybackMemorySnapshot snapshot,
    PlaybackTarget target,
  ) {
    final seriesKey = buildSeriesKeyForTarget(target);
    if (seriesKey.isEmpty) {
      return null;
    }
    return snapshot.skipPreferences[seriesKey];
  }

  Future<SeriesSubtitlePreference?> loadSubtitlePreference(
    PlaybackTarget target,
  ) async {
    final seriesKey = buildSeriesKeyForTarget(target);
    if (seriesKey.isEmpty) {
      return null;
    }
    final snapshot = await loadSnapshot();
    return snapshot.subtitlePreferences[seriesKey];
  }

  Future<void> saveSubtitlePreference(
    SeriesSubtitlePreference preference,
  ) =>
      _mutate(() async {
        final seriesKey = preference.seriesKey.trim();
        if (seriesKey.isEmpty) {
          return;
        }
        final snapshot = await _loadSnapshot();
        await _saveSnapshot(
          PlaybackMemorySnapshot(
            items: snapshot.items,
            series: snapshot.series,
            skipPreferences: snapshot.skipPreferences,
            subtitlePreferences: {
              ...snapshot.subtitlePreferences,
              seriesKey: preference,
            },
          ),
        );
        _notifyChanged?.call();
      });

  Future<void> removeSubtitlePreference(PlaybackTarget target) =>
      _mutate(() async {
        final seriesKey = buildSeriesKeyForTarget(target);
        if (seriesKey.isEmpty) {
          return;
        }
        final snapshot = await _loadSnapshot();
        if (!snapshot.subtitlePreferences.containsKey(seriesKey)) {
          return;
        }
        final nextPreferences = <String, SeriesSubtitlePreference>{
          ...snapshot.subtitlePreferences,
        }..remove(seriesKey);
        await _saveSnapshot(
          PlaybackMemorySnapshot(
            items: snapshot.items,
            series: snapshot.series,
            skipPreferences: snapshot.skipPreferences,
            subtitlePreferences: nextPreferences,
          ),
        );
        _notifyChanged?.call();
      });

  /// Callers retain [completedByAutoSkip] for the active session and clear it
  /// after a manual seek; previous stored completion is never carried forward.
  Future<void> saveProgress({
    required PlaybackTarget target,
    required Duration position,
    required Duration duration,
    bool completedByAutoSkip = false,
  }) =>
      _mutate(() async {
        final itemKey = buildPlaybackItemKey(target);
        if (itemKey.isEmpty) {
          return;
        }

        final clampedDuration = duration.isNegative ? Duration.zero : duration;
        final clampedPosition = position.isNegative ? Duration.zero : position;
        final safePosition =
            clampedDuration > Duration.zero && clampedPosition > clampedDuration
                ? clampedDuration
                : clampedPosition;
        final progress = clampedDuration.inMilliseconds <= 0
            ? 0.0
            : (safePosition.inMilliseconds / clampedDuration.inMilliseconds)
                .clamp(0.0, 1.0);
        final completed = completedByAutoSkip ||
            playbackMemoryCompleted(
              positionMs: safePosition.inMilliseconds,
              durationMs: clampedDuration.inMilliseconds,
              progress: progress,
            );
        final snapshot = await _loadSnapshot();
        final now = _nextUpdatedAt(snapshot);

        final seriesKey = buildSeriesKeyForTarget(target);
        final seriesTitle = target.resolvedSeriesTitle;
        final persistedTarget = _normalizeTargetForPersistence(target);
        final entry = PlaybackProgressEntry(
          key: itemKey,
          target: persistedTarget,
          updatedAt: now,
          seriesKey: seriesKey,
          seriesTitle: seriesTitle,
          position: safePosition,
          duration: clampedDuration,
          progress: progress,
          completed: completed,
        );

        final nextItems = <String, PlaybackProgressEntry>{
          ...snapshot.items,
          itemKey: entry,
        };
        nextItems.removeWhere((key, value) =>
            key != itemKey && buildPlaybackItemKey(value.target) == itemKey);
        _pruneRecentEntries(nextItems);

        final nextSeries = <String, PlaybackProgressEntry>{...snapshot.series};
        if (seriesKey.isNotEmpty) {
          nextSeries[seriesKey] = entry;
        }

        await _saveSnapshot(
          PlaybackMemorySnapshot(
            items: nextItems,
            series: nextSeries,
            skipPreferences: snapshot.skipPreferences,
            subtitlePreferences: snapshot.subtitlePreferences,
          ),
        );
        _notifyChanged?.call();
      });

  Future<void> saveSkipPreference(SeriesSkipPreference preference) =>
      _mutate(() async {
        final seriesKey = preference.seriesKey.trim();
        if (seriesKey.isEmpty) {
          return;
        }
        final snapshot = await _loadSnapshot();
        final nextPreferences = <String, SeriesSkipPreference>{
          ...snapshot.skipPreferences,
          seriesKey: preference,
        };
        await _saveSnapshot(
          PlaybackMemorySnapshot(
            items: snapshot.items,
            series: snapshot.series,
            skipPreferences: nextPreferences,
            subtitlePreferences: snapshot.subtitlePreferences,
          ),
        );
        _notifyChanged?.call();
      });

  Future<void> clearAll() => _mutate(() async {
        await _preferences.remove(_storageKey);
        invalidateSnapshotCache();
        _notifyChanged?.call();
      });

  Future<void> clearEntriesForResource({
    required String sourceId,
    String resourceId = '',
    required String resourcePath,
    bool treatAsScope = false,
    bool resourceIsSeries = false,
  }) =>
      _mutate(() async {
        final normalizedSourceId = sourceId.trim();
        final normalizedResourceId = resourceId.trim();
        final normalizedResourcePath = resourcePath.trim();
        if (normalizedSourceId.isEmpty ||
            (normalizedResourceId.isEmpty && normalizedResourcePath.isEmpty)) {
          return;
        }

        final snapshot = await _loadSnapshot();
        if (snapshot.items.isEmpty &&
            snapshot.series.isEmpty &&
            snapshot.skipPreferences.isEmpty &&
            snapshot.subtitlePreferences.isEmpty) {
          return;
        }

        var changed = false;
        final removedSeriesKeys = <String>{
          if (resourceIsSeries && normalizedResourceId.isNotEmpty)
            buildSeriesKeyForMetadata(
              sourceId: normalizedSourceId,
              itemId: normalizedResourceId,
              title: '',
              year: 0,
            ),
        };
        final nextItems = <String, PlaybackProgressEntry>{};
        for (final entry in snapshot.items.entries) {
          final seriesKey = entry.value.seriesKey.trim();
          final matchesDeletedTarget = _playbackTargetMatchesDeletedResource(
            entry.value.target,
            sourceId: normalizedSourceId,
            resourceId: normalizedResourceId,
            resourcePath: normalizedResourcePath,
            treatAsScope: treatAsScope,
          );
          final matchesRemovedSeriesKey =
              seriesKey.isNotEmpty && removedSeriesKeys.contains(seriesKey);
          if (matchesDeletedTarget || matchesRemovedSeriesKey) {
            changed = true;
            if (seriesKey.isNotEmpty) {
              removedSeriesKeys.add(seriesKey);
            }
            continue;
          }
          nextItems[entry.key] = entry.value;
        }

        final nextSeries = <String, PlaybackProgressEntry>{};
        for (final entry in snapshot.series.entries) {
          final seriesKey = entry.key.trim();
          final matchesDeletedTarget = _playbackTargetMatchesDeletedResource(
            entry.value.target,
            sourceId: normalizedSourceId,
            resourceId: normalizedResourceId,
            resourcePath: normalizedResourcePath,
            treatAsScope: treatAsScope,
          );
          final matchesRemovedSeriesKey =
              seriesKey.isNotEmpty && removedSeriesKeys.contains(seriesKey);
          if (matchesDeletedTarget || matchesRemovedSeriesKey) {
            changed = true;
            if (seriesKey.isNotEmpty) {
              removedSeriesKeys.add(seriesKey);
            }
            continue;
          }
          nextSeries[entry.key] = entry.value;
        }

        final nextSkipPreferences = <String, SeriesSkipPreference>{};
        for (final entry in snapshot.skipPreferences.entries) {
          final seriesKey = entry.key.trim();
          if (seriesKey.isNotEmpty && removedSeriesKeys.contains(seriesKey)) {
            changed = true;
            continue;
          }
          nextSkipPreferences[entry.key] = entry.value;
        }
        final nextSubtitlePreferences = <String, SeriesSubtitlePreference>{};
        for (final entry in snapshot.subtitlePreferences.entries) {
          final seriesKey = entry.key.trim();
          if (seriesKey.isNotEmpty && removedSeriesKeys.contains(seriesKey)) {
            changed = true;
            continue;
          }
          nextSubtitlePreferences[entry.key] = entry.value;
        }

        if (!changed) {
          return;
        }

        await _saveSnapshot(
          PlaybackMemorySnapshot(
            items: nextItems,
            series: nextSeries,
            skipPreferences: nextSkipPreferences,
            subtitlePreferences: nextSubtitlePreferences,
          ),
        );
        _notifyChanged?.call();
      });

  Future<LocalStorageCacheSummary> inspectSummary() async {
    final snapshot = await loadSnapshot();
    final raw = jsonEncode(snapshot.toJson());
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.playbackMemory,
      entryCount: snapshot.items.length +
          snapshot.skipPreferences.length +
          snapshot.subtitlePreferences.length,
      totalBytes: utf8.encode(raw).length,
    );
  }

  Future<PlaybackMemorySnapshot> loadSnapshot() async {
    await _mutationTail;
    return _loadSnapshot();
  }

  Future<PlaybackMemorySnapshot> _loadSnapshot() async {
    final cached = _cachedSnapshot;
    if (cached != null) {
      return cached;
    }
    final generation = _cacheGeneration;
    final load = _snapshotLoad ??= _loadSnapshotFrom(_preferences);
    try {
      final snapshot = await load;
      if (generation != _cacheGeneration) {
        return _loadSnapshot();
      }
      _cachedSnapshot = snapshot;
      return snapshot;
    } finally {
      if (identical(_snapshotLoad, load)) _snapshotLoad = null;
    }
  }

  Future<PlaybackMemorySnapshot> _loadSnapshotFrom(
    PreferencesStore preferences,
  ) async {
    final raw = await preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const PlaybackMemorySnapshot();
    }

    try {
      return raw.length >= 64 * 1024
          ? await compute(_decodePlaybackSnapshot, raw)
          : _decodePlaybackSnapshot(raw);
    } catch (_) {
      return const PlaybackMemorySnapshot();
    }
  }

  Future<void> _saveSnapshot(PlaybackMemorySnapshot snapshot) async {
    final generation = _cacheGeneration;
    final raw = snapshot.series.length >= 64
        ? await compute(_encodePlaybackSnapshot, snapshot)
        : _encodePlaybackSnapshot(snapshot);
    await _preferences.setString(_storageKey, raw);
    _cacheGeneration++;
    _cachedSnapshot = generation == _cacheGeneration - 1 ? snapshot : null;
  }

  void _pruneRecentEntries(Map<String, PlaybackProgressEntry> items) {
    if (items.length <= recentEntryLimit) {
      return;
    }

    final sorted = items.values.toList()..sort(_compareEntriesByRecency);
    final allowed =
        sorted.take(recentEntryLimit).map((entry) => entry.key).toSet();
    items.removeWhere((key, _) => !allowed.contains(key));
  }

  DateTime _nextUpdatedAt(PlaybackMemorySnapshot snapshot) {
    var next = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
        isUtc: true);
    for (final entry in snapshot.items.values) {
      if (!next.isAfter(entry.updatedAt)) {
        next = DateTime.fromMillisecondsSinceEpoch(
            entry.updatedAt.millisecondsSinceEpoch + 1,
            isUtc: true);
      }
    }
    for (final entry in snapshot.series.values) {
      if (!next.isAfter(entry.updatedAt)) {
        next = DateTime.fromMillisecondsSinceEpoch(
            entry.updatedAt.millisecondsSinceEpoch + 1,
            isUtc: true);
      }
    }
    return next;
  }

  int _compareEntriesByRecency(
    PlaybackProgressEntry left,
    PlaybackProgressEntry right,
  ) {
    final updatedAtComparison = right.updatedAt.millisecondsSinceEpoch
        .compareTo(left.updatedAt.millisecondsSinceEpoch);
    if (updatedAtComparison != 0) {
      return updatedAtComparison;
    }
    return right.key.compareTo(left.key);
  }

  PlaybackProgressEntry? _normalizeEntry(PlaybackProgressEntry? entry) {
    if (entry == null) {
      return null;
    }
    final normalizedTarget = _normalizeTargetForPersistence(entry.target);
    if (identical(normalizedTarget, entry.target)) {
      return entry;
    }
    return entry.copyWith(target: normalizedTarget);
  }

  PlaybackTarget _normalizeTargetForPersistence(PlaybackTarget target) {
    if (target.isFntvTranscoding) {
      target = target.copyWith(
          streamUrl: '',
          headers: const {},
          fntvSessionLink: '',
          fntvStartPositionMs: 0,
          preferredPlaybackQualityIndex: 0);
    }
    return sanitizeLoopbackPlaybackRelayTarget(target);
  }

  PlaybackProgressEntry? _entryForKey(
    PlaybackMemorySnapshot snapshot,
    String key,
  ) {
    final exact = snapshot.items[key];
    if (exact != null &&
        (!key.startsWith('path|') ||
            buildPlaybackItemKey(exact.target) == key)) {
      return exact;
    }
    return null;
  }
}

PlaybackMemorySnapshot _decodePlaybackSnapshot(String raw) =>
    PlaybackMemorySnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));

String _encodePlaybackSnapshot(PlaybackMemorySnapshot snapshot) =>
    jsonEncode(snapshot.toJson());

PreferencesStore _defaultPlaybackMemoryPreferencesStore() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return NativePlaybackMemoryPreferences();
  }
  return AppPreferencesStore();
}

bool isLoopbackPlaybackRelayUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return false;
  }
  final host = uri.host.trim().toLowerCase();
  if (host != '127.0.0.1' && host != 'localhost' && host != '::1') {
    return false;
  }
  final segments = uri.pathSegments
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return segments.isNotEmpty && segments.first == 'playback-relay';
}

bool shouldSanitizeLoopbackPlaybackRelayTarget(PlaybackTarget target) {
  return target.sourceKind == MediaSourceKind.quark &&
      isLoopbackPlaybackRelayUrl(target.streamUrl);
}

PlaybackTarget sanitizeLoopbackPlaybackRelayTarget(PlaybackTarget target) {
  if (!shouldSanitizeLoopbackPlaybackRelayTarget(target)) {
    return target;
  }
  return target.copyWith(
    streamUrl: '',
    headers: const <String, String>{},
  );
}

String buildPlaybackItemKey(PlaybackTarget target) {
  final sourceId = target.sourceId.trim();
  final itemId = target.itemId.trim();
  if (sourceId.isNotEmpty && itemId.isNotEmpty) {
    return 'item|$sourceId|$itemId';
  }

  final fallback = target.actualAddress.trim().isNotEmpty
      ? target.actualAddress.trim()
      : target.streamUrl.trim();
  final normalizedFallback = _playbackResourceIdentity(fallback);
  if (sourceId.isNotEmpty && normalizedFallback.isNotEmpty) {
    return 'path|$sourceId|$normalizedFallback';
  }
  if (normalizedFallback.isNotEmpty) {
    return 'path|$normalizedFallback';
  }
  return '';
}

String _playbackResourceIdentity(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme && uri.hasAuthority) {
    // Drop only known transport credentials. Query-based resource IDs must not
    // collapse into the same fallback key.
    const transportKeys = {
      'token',
      'access_token',
      'api_key',
      'apikey',
      'authorization',
      'signature',
      'sign',
      'expires',
      'x-emby-token'
    };
    final query = Map<String, List<String>>.from(uri.queryParametersAll)
      ..removeWhere((key, _) =>
          transportKeys.contains(key.toLowerCase()) ||
          key.toLowerCase().startsWith('x-amz-'));
    final sortedKeys = query.keys.toList()..sort();
    return Uri(
            scheme: uri.scheme,
            userInfo: uri.userInfo,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            pathSegments: uri.pathSegments,
            queryParameters: query.isEmpty
                ? null
                : {for (final key in sortedKeys) key: query[key]!})
        .toString();
  }
  return trimmed;
}

bool _playbackTargetMatchesDeletedResource(
  PlaybackTarget target, {
  required String sourceId,
  required String resourceId,
  required String resourcePath,
  required bool treatAsScope,
}) {
  final normalizedSourceId = sourceId.trim();
  if (normalizedSourceId.isEmpty ||
      target.sourceId.trim() != normalizedSourceId) {
    return false;
  }

  final normalizedResourceId = resourceId.trim();
  if (normalizedResourceId.isNotEmpty &&
      target.itemId.trim() == normalizedResourceId) {
    return true;
  }
  if (normalizedResourceId.isNotEmpty &&
      target.seriesId.trim() == normalizedResourceId) {
    return true;
  }

  final normalizedResourcePath = resourcePath.trim();
  if (normalizedResourcePath.isEmpty) {
    return false;
  }

  final candidates = <String>[
    target.actualAddress,
    target.itemId,
  ];
  if (treatAsScope) {
    return candidates.any(
      (candidate) => resourcePathIsWithinScope(
        candidate,
        normalizedResourcePath,
      ),
    );
  }
  return candidates.any(
    (candidate) => resourcePathsEqual(
      candidate,
      normalizedResourcePath,
    ),
  );
}

String buildSeriesKeyForTarget(PlaybackTarget target) {
  final sourceId = target.sourceId.trim();
  final seriesId = target.seriesId.trim();
  if (sourceId.isNotEmpty && seriesId.isNotEmpty) {
    return 'series|$sourceId|$seriesId';
  }

  if (target.isSeries) {
    return buildSeriesKeyForMetadata(
      sourceId: sourceId,
      itemId: target.itemId,
      title: target.title,
      year: target.year,
    );
  }

  final normalizedSeriesTitle = _normalizePlaybackText(target.seriesTitle);
  if (sourceId.isNotEmpty && normalizedSeriesTitle.isNotEmpty) {
    return 'series-title|$sourceId|$normalizedSeriesTitle';
  }
  return '';
}

String buildSeriesKeyForMetadata({
  required String sourceId,
  required String itemId,
  required String title,
  required int year,
}) {
  final normalizedSourceId = sourceId.trim();
  final normalizedItemId = itemId.trim();
  if (normalizedSourceId.isNotEmpty && normalizedItemId.isNotEmpty) {
    return 'series|$normalizedSourceId|$normalizedItemId';
  }

  final normalizedTitle = _normalizePlaybackText(title);
  if (normalizedSourceId.isNotEmpty && normalizedTitle.isNotEmpty) {
    return 'series-title|$normalizedSourceId|$normalizedTitle|$year';
  }
  return '';
}

String _normalizePlaybackText(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.isEmpty) {
    return '';
  }
  return lower.replaceAll(
    RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'),
    '',
  );
}
