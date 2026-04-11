import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
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

final playbackResumeForDetailTargetProvider =
    FutureProvider.family<PlaybackProgressEntry?, MediaDetailTarget>((
  ref,
  target,
) async {
  ref.watch(playbackHistoryRevisionProvider);
  return ref.read(playbackMemoryRepositoryProvider).loadResumeForDetailTarget(
        target,
      );
});

final playbackEntryForMediaItemProvider =
    FutureProvider.family<PlaybackProgressEntry?, MediaItem>((ref, item) async {
  ref.watch(playbackHistoryRevisionProvider);
  return ref.read(playbackMemoryRepositoryProvider).loadEntryForTarget(
        PlaybackTarget.fromMediaItem(item),
      );
});

final recentPlaybackEntriesProvider =
    FutureProvider.family<List<PlaybackProgressEntry>, int>((ref, limit) async {
  ref.watch(playbackHistoryRevisionProvider);
  return ref.read(playbackMemoryRepositoryProvider).loadRecentDisplayEntries(
        limit: limit,
      );
});

class PlaybackMemoryRepository {
  PlaybackMemoryRepository({
    PreferencesStore? preferences,
    SharedPreferences? sharedPreferences,
    void Function()? notifyChanged,
  })  : assert(preferences == null || sharedPreferences == null),
        _preferences = preferences ??
            (sharedPreferences == null
                ? AppPreferencesStore()
                : SharedPreferencesStore(sharedPreferences)),
        _notifyChanged = notifyChanged;

  static const _storageKey = 'starflow.playback.memory.v1';
  static const recentEntryLimit = 20;

  final PreferencesStore _preferences;
  final void Function()? _notifyChanged;

  Future<PlaybackProgressEntry?> loadEntryForTarget(
      PlaybackTarget target) async {
    final key = buildPlaybackItemKey(target);
    if (key.isEmpty) {
      return null;
    }
    final snapshot = await _loadSnapshot();
    return snapshot.items[key];
  }

  Future<PlaybackProgressEntry?> loadResumeForDetailTarget(
    MediaDetailTarget target,
  ) async {
    final snapshot = await _loadSnapshot();
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
      return snapshot.series[seriesKey];
    }

    final playbackTarget = target.playbackTarget;
    if (playbackTarget == null) {
      return null;
    }
    final itemKey = buildPlaybackItemKey(playbackTarget);
    if (itemKey.isEmpty) {
      return null;
    }
    return snapshot.items[itemKey];
  }

  Future<List<PlaybackProgressEntry>> loadRecentEntries(
      {int limit = 20}) async {
    final snapshot = await _loadSnapshot();
    final entries = snapshot.items.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return entries.take(limit.clamp(1, recentEntryLimit)).toList(
          growable: false,
        );
  }

  Future<List<PlaybackProgressEntry>> loadRecentDisplayEntries({
    int limit = 20,
  }) async {
    final snapshot = await _loadSnapshot();
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

    for (final entry in snapshot.items.values) {
      final seriesKey = entry.seriesKey.trim();
      if (seriesKey.isNotEmpty) {
        continue;
      }
      addEntry('item:${entry.key}', entry);
    }

    for (final entry in snapshot.series.values) {
      final seriesKey = entry.seriesKey.trim();
      if (seriesKey.isNotEmpty) {
        addEntry('series:$seriesKey', entry);
      } else {
        addEntry('item:${entry.key}', entry);
      }
    }

    final entries = combined.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return entries.take(limit.clamp(1, recentEntryLimit)).toList(
          growable: false,
        );
  }

  Future<SeriesSkipPreference?> loadSkipPreference(
      PlaybackTarget target) async {
    final seriesKey = buildSeriesKeyForTarget(target);
    if (seriesKey.isEmpty) {
      return null;
    }
    final snapshot = await _loadSnapshot();
    return snapshot.skipPreferences[seriesKey];
  }

  Future<void> saveProgress({
    required PlaybackTarget target,
    required Duration position,
    required Duration duration,
  }) async {
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
    final completed = _isCompleted(
      position: safePosition,
      duration: clampedDuration,
      progress: progress,
    );
    final now = DateTime.now();
    final snapshot = await _loadSnapshot();

    final seriesKey = buildSeriesKeyForTarget(target);
    final seriesTitle = target.resolvedSeriesTitle;
    final entry = PlaybackProgressEntry(
      key: itemKey,
      target: target,
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
      ),
    );
    _notifyChanged?.call();
  }

  Future<void> saveSkipPreference(SeriesSkipPreference preference) async {
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
      ),
    );
    _notifyChanged?.call();
  }

  Future<void> clearAll() async {
    await _preferences.remove(_storageKey);
    _notifyChanged?.call();
  }

  Future<LocalStorageCacheSummary> inspectSummary() async {
    final raw = await _preferences.getString(_storageKey) ?? '';
    final snapshot = await _loadSnapshot();
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.playbackMemory,
      entryCount: snapshot.items.length + snapshot.skipPreferences.length,
      totalBytes: utf8.encode(raw).length,
    );
  }

  Future<PlaybackMemorySnapshot> _loadSnapshot() async {
    final raw = await _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const PlaybackMemorySnapshot();
    }

    try {
      return PlaybackMemorySnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const PlaybackMemorySnapshot();
    }
  }

  Future<void> _saveSnapshot(PlaybackMemorySnapshot snapshot) async {
    await _preferences.setString(_storageKey, jsonEncode(snapshot.toJson()));
  }

  void _pruneRecentEntries(Map<String, PlaybackProgressEntry> items) {
    if (items.length <= recentEntryLimit) {
      return;
    }

    final sorted = items.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final allowed =
        sorted.take(recentEntryLimit).map((entry) => entry.key).toSet();
    items.removeWhere((key, _) => !allowed.contains(key));
  }

  bool _isCompleted({
    required Duration position,
    required Duration duration,
    required double progress,
  }) {
    if (duration <= Duration.zero) {
      return progress >= 0.995;
    }
    final remaining = duration - position;
    return progress >= 0.985 || remaining <= const Duration(seconds: 8);
  }
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
  final normalizedFallback = _normalizePlaybackText(fallback);
  if (sourceId.isNotEmpty && normalizedFallback.isNotEmpty) {
    return 'path|$sourceId|$normalizedFallback';
  }
  if (normalizedFallback.isNotEmpty) {
    return 'path|$normalizedFallback';
  }
  return '';
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
