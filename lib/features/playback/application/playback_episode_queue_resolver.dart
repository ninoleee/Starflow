import 'package:riverpod/misc.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class PlaybackEpisodeQueueResolver {
  PlaybackEpisodeQueueResolver({
    required this.read,
  });

  final T Function<T>(ProviderListenable<T> provider) read;

  Future<PlaybackEpisodeQueue?> resolve(PlaybackTarget target) async {
    if (!target.isEpisode) {
      return null;
    }
    final seasonNumber = target.seasonNumber;
    final episodeNumber = target.episodeNumber;
    if (seasonNumber == null || episodeNumber == null || episodeNumber <= 0) {
      return null;
    }

    final source = _findSource(target.sourceId);
    if (source == null) {
      return null;
    }

    switch (source.kind) {
      case MediaSourceKind.emby:
        return _resolveEmbyQueue(source, target);
      case MediaSourceKind.nas:
      case MediaSourceKind.quark:
        return _resolveIndexedQueue(target);
    }
  }

  MediaSourceConfig? _findSource(String sourceId) {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return null;
    }
    final sources = read(appSettingsProvider).mediaSources;
    for (final source in sources) {
      if (source.id == normalizedSourceId) {
        return source;
      }
    }
    return null;
  }

  Future<PlaybackEpisodeQueue?> _resolveEmbyQueue(
    MediaSourceConfig source,
    PlaybackTarget target,
  ) async {
    if (!source.hasActiveSession || target.seriesId.trim().isEmpty) {
      return null;
    }

    final emby = read(embyApiClientProvider);
    final seriesChildren = await emby.fetchChildren(
      source,
      parentId: target.seriesId,
      limit: 500,
    );

    List<MediaItem> seasonEpisodes;
    final seasonItems =
        seriesChildren.where(_isSeasonItem).toList(growable: false);
    if (seasonItems.isEmpty) {
      seasonEpisodes =
          seriesChildren.where(_isEpisodeItem).toList(growable: false);
    } else {
      final targetSeasonNumber = target.seasonNumber ?? 0;
      MediaItem? currentSeason;
      for (final season in seasonItems) {
        if ((season.seasonNumber ?? 0) == targetSeasonNumber) {
          currentSeason = season;
          break;
        }
      }
      if (currentSeason == null) {
        return null;
      }
      final seasonChildrenItems = await emby.fetchChildren(
        source,
        parentId: currentSeason.id,
        limit: 500,
      );
      seasonEpisodes =
          seasonChildrenItems.where(_isEpisodeItem).toList(growable: false);
    }

    return _buildQueueFromEpisodes(
      seasonEpisodes,
      currentTarget: target,
      mapTarget: (item) => _buildEpisodeTarget(
        item,
        currentTarget: target,
      ),
    );
  }

  Future<PlaybackEpisodeQueue?> _resolveIndexedQueue(
    PlaybackTarget target,
  ) async {
    final records = await read(nasMediaIndexerProvider).loadSourceRecords(
      target.sourceId,
    );
    if (records.isEmpty) {
      return null;
    }

    final currentRecord = _findIndexedCurrentRecord(records, target);
    if (currentRecord == null) {
      return null;
    }

    final targetSeasonNumber = _resolvedSeasonNumber(currentRecord);
    final targetEpisodeNumber = _resolvedEpisodeNumber(currentRecord);
    if (targetSeasonNumber == null || targetEpisodeNumber == null) {
      return null;
    }

    final seriesIdentity = _resolveIndexedSeriesIdentity(
      target: target,
      record: currentRecord,
    );
    if (seriesIdentity.isEmpty) {
      return null;
    }

    final filtered = records.where((record) {
      if (_resolvedSeasonNumber(record) != targetSeasonNumber) {
        return false;
      }
      if (_resolvedEpisodeNumber(record) == null) {
        return false;
      }
      return _matchesIndexedSeriesIdentity(record, seriesIdentity);
    }).toList(growable: false);
    if (filtered.isEmpty) {
      return null;
    }

    final sorted = <NasMediaIndexRecord>[...filtered]..sort(
        (left, right) => _compareIndexedRecords(
          left,
          right,
          currentRecord: currentRecord,
        ),
      );
    final deduped = _dedupeIndexedRecords(
      sorted,
      currentRecord: currentRecord,
    );
    final currentIndex = deduped.indexWhere(
      (record) => record.resourceId == currentRecord.resourceId,
    );
    if (currentIndex < 0) {
      return null;
    }

    final entries = deduped
        .skip(currentIndex)
        .map(
          (record) => _entryFromTarget(
            _buildIndexedEpisodeTarget(
              record,
              currentTarget: target,
              seriesTitle: _bestIndexedSeriesTitle(target, currentRecord),
            ),
          ),
        )
        .toList(growable: false);
    if (entries.isEmpty) {
      return null;
    }
    return PlaybackEpisodeQueue(entries: entries);
  }

  PlaybackEpisodeQueue? _buildQueueFromEpisodes(
    List<MediaItem> episodes, {
    required PlaybackTarget currentTarget,
    required PlaybackTarget Function(MediaItem item) mapTarget,
  }) {
    if (episodes.isEmpty) {
      return null;
    }

    final sortedEpisodes = [...episodes]..sort(_compareEpisodes);
    final currentIndex = sortedEpisodes.indexWhere(
      (item) => _matchesCurrentEpisodeItem(item, currentTarget),
    );
    if (currentIndex < 0) {
      return null;
    }

    final entries = sortedEpisodes
        .skip(currentIndex)
        .map((item) => _entryFromTarget(mapTarget(item)))
        .toList(growable: false);
    if (entries.isEmpty) {
      return null;
    }
    return PlaybackEpisodeQueue(entries: entries);
  }

  PlaybackEpisodeQueueEntry _entryFromTarget(PlaybackTarget target) {
    return PlaybackEpisodeQueueEntry(
      target: target,
      playbackItemKey: buildPlaybackItemKey(target),
      seriesKey: buildSeriesKeyForTarget(target),
    );
  }

  PlaybackTarget _buildEpisodeTarget(
    MediaItem item, {
    required PlaybackTarget currentTarget,
  }) {
    final base = PlaybackTarget.fromMediaItem(item);
    return base.copyWith(
      itemId: base.itemId.trim().isNotEmpty ? base.itemId : item.id,
      actualAddress: base.actualAddress.trim().isNotEmpty
          ? base.actualAddress
          : item.actualAddress,
      seriesId: currentTarget.seriesId,
      seriesTitle: currentTarget.resolvedSeriesTitle,
    );
  }

  PlaybackTarget _buildIndexedEpisodeTarget(
    NasMediaIndexRecord record, {
    required PlaybackTarget currentTarget,
    required String seriesTitle,
  }) {
    final base = PlaybackTarget.fromMediaItem(record.item);
    return base.copyWith(
      itemId: base.itemId.trim().isNotEmpty ? base.itemId : record.resourceId,
      actualAddress: base.actualAddress.trim().isNotEmpty
          ? base.actualAddress
          : record.resourcePath,
      seriesId: currentTarget.seriesId,
      seriesTitle: seriesTitle,
    );
  }

  NasMediaIndexRecord? _findIndexedCurrentRecord(
    List<NasMediaIndexRecord> records,
    PlaybackTarget target,
  ) {
    final normalizedItemId = target.itemId.trim();
    if (normalizedItemId.isNotEmpty) {
      for (final record in records) {
        if (record.resourceId.trim() == normalizedItemId ||
            record.item.playbackItemId.trim() == normalizedItemId) {
          return record;
        }
      }
    }

    final candidates = <String>{
      _normalizeIndexedPath(target.actualAddress),
      _normalizeIndexedPath(target.streamUrl),
    }..removeWhere((value) => value.isEmpty);
    if (candidates.isNotEmpty) {
      for (final record in records) {
        final recordCandidates = <String>{
          _normalizeIndexedPath(record.resourceId),
          _normalizeIndexedPath(record.resourcePath),
          _normalizeIndexedPath(record.item.actualAddress),
          _normalizeIndexedPath(record.item.streamUrl),
        };
        if (recordCandidates.any(candidates.contains)) {
          return record;
        }
      }
    }

    final seasonNumber = target.seasonNumber;
    final episodeNumber = target.episodeNumber;
    final normalizedTitle = _normalizeSeriesIdentity(target.title);
    for (final record in records) {
      if (_resolvedSeasonNumber(record) != seasonNumber ||
          _resolvedEpisodeNumber(record) != episodeNumber) {
        continue;
      }
      final recordTitle = _normalizeSeriesIdentity(record.item.title);
      if (normalizedTitle.isNotEmpty && normalizedTitle == recordTitle) {
        return record;
      }
    }
    return null;
  }

  List<NasMediaIndexRecord> _dedupeIndexedRecords(
    List<NasMediaIndexRecord> records, {
    required NasMediaIndexRecord currentRecord,
  }) {
    final seenEpisodes = <int>{};
    final result = <NasMediaIndexRecord>[];
    for (final record in records) {
      final episodeNumber = _resolvedEpisodeNumber(record);
      if (episodeNumber == null || !seenEpisodes.add(episodeNumber)) {
        continue;
      }
      result.add(record);
    }
    if (!result
        .any((record) => record.resourceId == currentRecord.resourceId)) {
      return records;
    }
    return result;
  }

  int _compareEpisodes(MediaItem left, MediaItem right) {
    final seasonComparison =
        (left.seasonNumber ?? 0).compareTo(right.seasonNumber ?? 0);
    if (seasonComparison != 0) {
      return seasonComparison;
    }
    final episodeComparison =
        (left.episodeNumber ?? 0).compareTo(right.episodeNumber ?? 0);
    if (episodeComparison != 0) {
      return episodeComparison;
    }
    return left.title.toLowerCase().compareTo(right.title.toLowerCase());
  }

  int _compareIndexedRecords(
    NasMediaIndexRecord left,
    NasMediaIndexRecord right, {
    required NasMediaIndexRecord currentRecord,
  }) {
    final seasonComparison = (_resolvedSeasonNumber(left) ?? 0)
        .compareTo(_resolvedSeasonNumber(right) ?? 0);
    if (seasonComparison != 0) {
      return seasonComparison;
    }
    final episodeComparison = (_resolvedEpisodeNumber(left) ?? 0)
        .compareTo(_resolvedEpisodeNumber(right) ?? 0);
    if (episodeComparison != 0) {
      return episodeComparison;
    }
    final leftIsCurrent = left.resourceId == currentRecord.resourceId;
    final rightIsCurrent = right.resourceId == currentRecord.resourceId;
    if (leftIsCurrent != rightIsCurrent) {
      return leftIsCurrent ? -1 : 1;
    }
    final fileSizeComparison =
        right.fileSizeBytes.compareTo(left.fileSizeBytes);
    if (fileSizeComparison != 0) {
      return fileSizeComparison;
    }
    return left.resourcePath
        .toLowerCase()
        .compareTo(right.resourcePath.toLowerCase());
  }

  bool _matchesCurrentEpisodeItem(MediaItem item, PlaybackTarget target) {
    final targetItemId = target.itemId.trim();
    if (targetItemId.isNotEmpty &&
        (item.playbackItemId.trim() == targetItemId ||
            item.id.trim() == targetItemId)) {
      return true;
    }

    final targetPath = target.actualAddress.trim();
    if (targetPath.isNotEmpty &&
        _normalizeIndexedPath(item.actualAddress) ==
            _normalizeIndexedPath(targetPath)) {
      return true;
    }

    return (item.seasonNumber ?? 0) == (target.seasonNumber ?? 0) &&
        (item.episodeNumber ?? 0) == (target.episodeNumber ?? 0) &&
        _normalizeSeriesIdentity(item.title) ==
            _normalizeSeriesIdentity(target.title);
  }

  bool _isSeasonItem(MediaItem item) {
    return item.itemType.trim().toLowerCase() == 'season';
  }

  bool _isEpisodeItem(MediaItem item) {
    return item.itemType.trim().toLowerCase() == 'episode';
  }

  int? _resolvedSeasonNumber(NasMediaIndexRecord record) {
    return record.item.seasonNumber ?? record.recognizedSeasonNumber;
  }

  int? _resolvedEpisodeNumber(NasMediaIndexRecord record) {
    return record.item.episodeNumber ?? record.recognizedEpisodeNumber;
  }

  String _bestIndexedSeriesTitle(
    PlaybackTarget target,
    NasMediaIndexRecord record,
  ) {
    final preferred = target.resolvedSeriesTitle.trim();
    if (preferred.isNotEmpty) {
      return preferred;
    }
    for (final candidate in [
      record.parentTitle,
      record.searchQuery,
      record.recognizedTitle,
    ]) {
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return target.title.trim();
  }

  Set<String> _resolveIndexedSeriesIdentity({
    required PlaybackTarget target,
    required NasMediaIndexRecord record,
  }) {
    return <String>{
      _normalizeSeriesIdentity(target.resolvedSeriesTitle),
      _normalizeSeriesIdentity(record.parentTitle),
      _normalizeSeriesIdentity(record.searchQuery),
      _normalizeSeriesIdentity(record.recognizedTitle),
    }..removeWhere((value) => value.isEmpty);
  }

  bool _matchesIndexedSeriesIdentity(
    NasMediaIndexRecord record,
    Set<String> seriesIdentity,
  ) {
    if (seriesIdentity.isEmpty) {
      return false;
    }
    final recordIdentity = <String>{
      _normalizeSeriesIdentity(record.parentTitle),
      _normalizeSeriesIdentity(record.searchQuery),
      _normalizeSeriesIdentity(record.recognizedTitle),
    }..removeWhere((value) => value.isEmpty);
    return recordIdentity.any(seriesIdentity.contains);
  }

  String _normalizeSeriesIdentity(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceAll(
        RegExp(r'[\s\-_.,:;!?/\\|()\[\]{}<>《》【】"“”·]+'), '');
  }

  String _normalizeIndexedPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    final rawPath = uri != null && uri.hasScheme ? uri.path : trimmed;
    return rawPath.replaceAll('\\', '/').trim().toLowerCase();
  }
}
