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

final playbackMemorySnapshotProvider = FutureProvider<PlaybackMemorySnapshot>((
  ref,
) async {
  ref.watch(playbackHistoryRevisionProvider);
  return ref.read(playbackMemoryRepositoryProvider).loadSnapshot();
});

final playbackResumeForDetailTargetProvider =
    FutureProvider.family<PlaybackProgressEntry?, MediaDetailTarget>((
  ref,
  target,
) async {
  final snapshot = await ref.watch(playbackMemorySnapshotProvider.future);
  return ref
      .read(playbackMemoryRepositoryProvider)
      .resumeEntryForDetailTargetFromSnapshot(snapshot, target);
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
                ? AppPreferencesStore()
                : SharedPreferencesStore(sharedPreferences)),
        _notifyChanged = notifyChanged;

  static const _storageKey = 'starflow.playback.memory.v1';
  static const recentEntryLimit = 20;

  final PreferencesStore _preferences;
  final void Function()? _notifyChanged;

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
    return _normalizeEntry(snapshot.items[key]);
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
    return _normalizeEntry(snapshot.items[itemKey]);
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
    final snapshot = await loadSnapshot();
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
    final snapshot = await loadSnapshot();
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

  Future<void> clearEntriesForResource({
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

    final snapshot = await loadSnapshot();
    if (snapshot.items.isEmpty &&
        snapshot.series.isEmpty &&
        snapshot.skipPreferences.isEmpty) {
      return;
    }

    var changed = false;
    final removedSeriesKeys = <String>{};
    final nextItems = <String, PlaybackProgressEntry>{};
    for (final entry in snapshot.items.entries) {
      if (_playbackTargetMatchesDeletedResource(
        entry.value.target,
        sourceId: normalizedSourceId,
        resourceId: normalizedResourceId,
        resourcePath: normalizedResourcePath,
        treatAsScope: treatAsScope,
      )) {
        changed = true;
        final seriesKey = entry.value.seriesKey.trim();
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

    if (!changed) {
      return;
    }

    await _saveSnapshot(
      PlaybackMemorySnapshot(
        items: nextItems,
        series: nextSeries,
        skipPreferences: nextSkipPreferences,
      ),
    );
    _notifyChanged?.call();
  }

  Future<LocalStorageCacheSummary> inspectSummary() async {
    final raw = await _preferences.getString(_storageKey) ?? '';
    final snapshot = await loadSnapshot();
    return LocalStorageCacheSummary(
      type: LocalStorageCacheType.playbackMemory,
      entryCount: snapshot.items.length + snapshot.skipPreferences.length,
      totalBytes: utf8.encode(raw).length,
    );
  }

  Future<PlaybackMemorySnapshot> loadSnapshot() async {
    return _loadSnapshot();
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

    final sorted = items.values.toList()..sort(_compareEntriesByRecency);
    final allowed =
        sorted.take(recentEntryLimit).map((entry) => entry.key).toSet();
    items.removeWhere((key, _) => !allowed.contains(key));
  }

  DateTime _nextUpdatedAt(PlaybackMemorySnapshot snapshot) {
    var next = DateTime.now();
    for (final entry in snapshot.items.values) {
      if (!next.isAfter(entry.updatedAt)) {
        next = entry.updatedAt.add(const Duration(milliseconds: 1));
      }
    }
    for (final entry in snapshot.series.values) {
      if (!next.isAfter(entry.updatedAt)) {
        next = entry.updatedAt.add(const Duration(milliseconds: 1));
      }
    }
    return next;
  }

  int _compareEntriesByRecency(
    PlaybackProgressEntry left,
    PlaybackProgressEntry right,
  ) {
    final updatedAtComparison = right.updatedAt.compareTo(left.updatedAt);
    if (updatedAtComparison != 0) {
      return updatedAtComparison;
    }
    return right.key.compareTo(left.key);
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

  PlaybackProgressEntry? _normalizeEntry(PlaybackProgressEntry? entry) {
    if (entry == null) {
      return null;
    }
    final normalizedTarget = _normalizeTargetForPersistence(entry.target);
    if (_samePlaybackTargets(normalizedTarget, entry.target)) {
      return entry;
    }
    return entry.copyWith(target: normalizedTarget);
  }

  PlaybackTarget _normalizeTargetForPersistence(PlaybackTarget target) {
    return sanitizeLoopbackPlaybackRelayTarget(target);
  }

  bool _samePlaybackTargets(PlaybackTarget left, PlaybackTarget right) {
    return left.title == right.title &&
        left.sourceId == right.sourceId &&
        left.streamUrl == right.streamUrl &&
        left.sourceName == right.sourceName &&
        left.sourceKind == right.sourceKind &&
        left.actualAddress == right.actualAddress &&
        left.itemId == right.itemId &&
        left.itemType == right.itemType &&
        left.year == right.year &&
        left.seriesId == right.seriesId &&
        left.seriesTitle == right.seriesTitle &&
        left.preferredMediaSourceId == right.preferredMediaSourceId &&
        left.subtitle == right.subtitle &&
        left.externalSubtitleFilePath == right.externalSubtitleFilePath &&
        left.externalSubtitleDisplayName == right.externalSubtitleDisplayName &&
        _sameHeaders(left.headers, right.headers) &&
        left.container == right.container &&
        left.videoCodec == right.videoCodec &&
        left.audioCodec == right.audioCodec &&
        left.seasonNumber == right.seasonNumber &&
        left.episodeNumber == right.episodeNumber &&
        left.width == right.width &&
        left.height == right.height &&
        left.bitrate == right.bitrate &&
        left.fileSizeBytes == right.fileSizeBytes;
  }

  bool _sameHeaders(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
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
  final normalizedFallback = _normalizePlaybackText(fallback);
  if (sourceId.isNotEmpty && normalizedFallback.isNotEmpty) {
    return 'path|$sourceId|$normalizedFallback';
  }
  if (normalizedFallback.isNotEmpty) {
    return 'path|$normalizedFallback';
  }
  return '';
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
      (candidate) => _playbackPathMatchesDeletedScope(
        candidate,
        normalizedResourcePath,
      ),
    );
  }
  return candidates.any(
    (candidate) => _playbackPathEqualsDeletedResource(
      candidate,
      normalizedResourcePath,
    ),
  );
}

bool _playbackPathEqualsDeletedResource(String candidate, String expectedPath) {
  final left = _normalizedPlaybackPath(candidate);
  final right = _normalizedPlaybackPath(expectedPath);
  return left.isNotEmpty && left == right;
}

bool _playbackPathMatchesDeletedScope(String candidate, String scopePath) {
  final candidateSegments = _playbackPathSegments(candidate);
  final scopeSegments = _playbackPathSegments(scopePath);
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

String _normalizedPlaybackPath(String value) {
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

List<String> _playbackPathSegments(String value) {
  return _normalizedPlaybackPath(value)
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
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
