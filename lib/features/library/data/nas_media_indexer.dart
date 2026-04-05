import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/nas_media_recognition.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final nasMediaIndexerProvider = Provider<NasMediaIndexer>((ref) {
  return NasMediaIndexer(
    store: ref.read(nasMediaIndexStoreProvider),
    webDavNasClient: ref.read(webDavNasClientProvider),
    wmdbMetadataClient: ref.read(wmdbMetadataClientProvider),
    tmdbMetadataClient: ref.read(tmdbMetadataClientProvider),
    imdbRatingClient: ref.read(imdbRatingClientProvider),
    readSettings: () => ref.read(appSettingsProvider),
  );
});

class NasMediaIndexer {
  NasMediaIndexer({
    required NasMediaIndexStore store,
    required WebDavNasClient webDavNasClient,
    required WmdbMetadataClient wmdbMetadataClient,
    required TmdbMetadataClient tmdbMetadataClient,
    required ImdbRatingClient imdbRatingClient,
    required AppSettings Function() readSettings,
  })  : _store = store,
        _webDavNasClient = webDavNasClient,
        _wmdbMetadataClient = wmdbMetadataClient,
        _tmdbMetadataClient = tmdbMetadataClient,
        _imdbRatingClient = imdbRatingClient,
        _readSettings = readSettings;

  static const int _defaultRefreshLimitPerCollection = 1200;
  static const String _seriesGroupPrefix = 'webdav-series';
  static const String _seasonGroupPrefix = 'webdav-season';

  final NasMediaIndexStore _store;
  final WebDavNasClient _webDavNasClient;
  final WmdbMetadataClient _wmdbMetadataClient;
  final TmdbMetadataClient _tmdbMetadataClient;
  final ImdbRatingClient _imdbRatingClient;
  final AppSettings Function() _readSettings;

  Future<void> clearSource(String sourceId) {
    return _store.clearSource(sourceId);
  }

  Future<NasMediaIndexRecord?> loadRecord({
    required String sourceId,
    required String resourceId,
  }) async {
    final normalizedSourceId = sourceId.trim();
    final normalizedResourceId = resourceId.trim();
    if (normalizedSourceId.isEmpty || normalizedResourceId.isEmpty) {
      return null;
    }
    final records = await _store.loadSourceRecords(normalizedSourceId);
    for (final record in records) {
      if (record.resourceId == normalizedResourceId) {
        return record;
      }
    }
    return null;
  }

  Future<List<MediaItem>> loadLibrary(
    MediaSourceConfig source, {
    String? sectionId,
    List<MediaCollection>? scopedCollections,
    int limit = 200,
  }) async {
    final records = await _loadScopedRecords(
      source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
    );
    return _materializeLibraryItems(records)
        .take(limit)
        .toList(growable: false);
  }

  Future<List<MediaItem>> loadChildren(
    MediaSourceConfig source, {
    required String parentId,
    String sectionId = '',
    List<MediaCollection>? scopedCollections,
    int limit = 200,
  }) async {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      return const [];
    }

    if (!_isSyntheticGroupId(normalizedParentId)) {
      return const [];
    }

    final records = await _loadScopedRecords(
      source,
      sectionId: sectionId,
      scopedCollections: scopedCollections,
    );
    final groups = _groupSeriesRecords(records);

    if (normalizedParentId.startsWith(_seriesGroupPrefix)) {
      final targetGroup = groups.where(
        (group) => group.seriesItemId == normalizedParentId,
      );
      if (targetGroup.isEmpty) {
        return const [];
      }
      final group = targetGroup.first;
      final seasonGroups = group.seasonGroups;
      if (seasonGroups.length <= 1) {
        return _materializeEpisodeItems(seasonGroups.values.expand((e) => e))
            .take(limit)
            .toList(growable: false);
      }
      return seasonGroups.entries
          .map((entry) => _buildSeasonItem(group, entry.key, entry.value))
          .toList(growable: false)
        ..sort((left, right) {
          final seasonComparison =
              (left.seasonNumber ?? 0).compareTo(right.seasonNumber ?? 0);
          if (seasonComparison != 0) {
            return seasonComparison;
          }
          return left.title.compareTo(right.title);
        });
    }

    if (normalizedParentId.startsWith(_seasonGroupPrefix)) {
      final parsed = _parseSeasonGroupId(normalizedParentId);
      if (parsed == null) {
        return const [];
      }
      final targetGroup = groups.where(
        (group) => group.seriesKey == parsed.seriesKey,
      );
      if (targetGroup.isEmpty) {
        return const [];
      }
      final episodes = targetGroup.first.seasonGroups[parsed.seasonNumber] ??
          const <NasMediaIndexRecord>[];
      return _materializeEpisodeItems(episodes)
          .take(limit)
          .toList(growable: false);
    }

    return const [];
  }

  Future<void> refreshSource(
    MediaSourceConfig source, {
    List<MediaCollection>? scopedCollections,
    int limitPerCollection = _defaultRefreshLimitPerCollection,
    bool forceFullRescan = false,
  }) async {
    if (source.kind != MediaSourceKind.nas || source.endpoint.trim().isEmpty) {
      return;
    }

    if (forceFullRescan) {
      _wmdbMetadataClient.clearCache();
      _tmdbMetadataClient.clearCache();
      _imdbRatingClient.clearCache();
    }

    final now = DateTime.now();
    final scannedItems = await _scanSource(
      source,
      scopedCollections: scopedCollections,
      limitPerCollection: limitPerCollection,
    );
    final existingRecords = forceFullRescan
        ? const <String, NasMediaIndexRecord>{}
        : {
            for (final record in await _store.loadSourceRecords(source.id))
              record.resourceId: record,
          };
    final nextRecords = <NasMediaIndexRecord>[];

    for (final scannedItem in scannedItems) {
      final fingerprint = _buildFingerprint(
        sourceId: source.id,
        resourcePath: scannedItem.actualAddress,
        modifiedAt: scannedItem.modifiedAt,
        fileSizeBytes: scannedItem.fileSizeBytes,
      );
      final existing = existingRecords[scannedItem.resourceId];
      if (existing != null && existing.fingerprint == fingerprint) {
        nextRecords.add(
          _reuseRecord(
            existing,
            scannedItem: scannedItem,
            source: source,
            indexedAt: now,
          ),
        );
        continue;
      }
      nextRecords.add(
        await _indexScannedItem(
          source,
          scannedItem,
          indexedAt: now,
          fingerprint: fingerprint,
        ),
      );
    }

    await _store.replaceSourceRecords(
      sourceId: source.id,
      records: nextRecords,
      state: NasMediaIndexSourceState(
        sourceId: source.id,
        lastIndexedAt: now,
        recordCount: nextRecords.length,
        scopeKey: _buildScopeKey(source, scopedCollections),
      ),
    );
  }

  Future<MediaDetailTarget?> applyManualMetadata({
    required MediaDetailTarget target,
    required String searchQuery,
    MetadataMatchResult? metadataMatch,
    ImdbRatingMatch? imdbRatingMatch,
  }) async {
    final sourceId = target.sourceId.trim();
    final resourceId = target.itemId.trim();
    if (sourceId.isEmpty || resourceId.isEmpty) {
      return null;
    }
    if (metadataMatch == null && imdbRatingMatch == null) {
      return null;
    }

    final records = await _store.loadSourceRecords(sourceId);
    if (records.isEmpty) {
      return null;
    }
    final targetIndex =
        records.indexWhere((record) => record.resourceId == resourceId);
    if (targetIndex < 0) {
      return null;
    }

    final currentRecord = records[targetIndex];
    final now = DateTime.now();
    final nextItem = _applyManualMetadataToItem(
      currentRecord.item,
      metadataMatch: metadataMatch,
      imdbRatingMatch: imdbRatingMatch,
    );
    final nextRecord = NasMediaIndexRecord(
      id: currentRecord.id,
      sourceId: currentRecord.sourceId,
      sectionId: currentRecord.sectionId,
      sectionName: currentRecord.sectionName,
      resourceId: currentRecord.resourceId,
      resourcePath: currentRecord.resourcePath,
      fingerprint: currentRecord.fingerprint,
      fileSizeBytes: currentRecord.fileSizeBytes,
      modifiedAt: currentRecord.modifiedAt,
      indexedAt: now,
      scrapedAt: now,
      recognizedTitle: currentRecord.recognizedTitle,
      searchQuery: searchQuery.trim().isEmpty
          ? currentRecord.searchQuery
          : searchQuery.trim(),
      originalFileName: currentRecord.originalFileName,
      parentTitle: currentRecord.parentTitle,
      recognizedYear: currentRecord.recognizedYear,
      recognizedItemType: currentRecord.recognizedItemType,
      preferSeries: currentRecord.preferSeries,
      recognizedSeasonNumber: currentRecord.recognizedSeasonNumber,
      recognizedEpisodeNumber: currentRecord.recognizedEpisodeNumber,
      sidecarMatched: currentRecord.sidecarMatched,
      wmdbMatched: currentRecord.wmdbMatched ||
          metadataMatch?.provider == MetadataMatchProvider.wmdb,
      tmdbMatched: currentRecord.tmdbMatched ||
          metadataMatch?.provider == MetadataMatchProvider.tmdb,
      imdbMatched: currentRecord.imdbMatched ||
          (imdbRatingMatch?.ratingLabel.trim().isNotEmpty ?? false),
      item: nextItem,
    );
    final nextRecords = [...records];
    nextRecords[targetIndex] = nextRecord;
    final existingState = await _store.loadSourceState(sourceId);
    await _store.replaceSourceRecords(
      sourceId: sourceId,
      records: nextRecords,
      state: NasMediaIndexSourceState(
        sourceId: sourceId,
        lastIndexedAt: now,
        recordCount: nextRecords.length,
        scopeKey: existingState?.scopeKey ?? '',
      ),
    );

    return MediaDetailTarget.fromMediaItem(
      nextItem,
      availabilityLabel: target.availabilityLabel,
      searchQuery:
          searchQuery.trim().isEmpty ? target.searchQuery : searchQuery.trim(),
    );
  }

  Future<List<WebDavScannedItem>> _scanSource(
    MediaSourceConfig source, {
    required List<MediaCollection>? scopedCollections,
    required int limitPerCollection,
  }) async {
    if (scopedCollections != null && scopedCollections.isNotEmpty) {
      final groups = await Future.wait(
        scopedCollections.map(
          (collection) => _webDavNasClient.scanLibrary(
            source,
            sectionId: collection.id,
            sectionName: collection.title,
            limit: limitPerCollection,
          ),
        ),
      );
      final deduped = <String, WebDavScannedItem>{};
      for (final item in groups.expand((group) => group)) {
        deduped[item.resourceId] = item;
      }
      final items = deduped.values.toList(growable: false);
      items.sort((left, right) => right.addedAt.compareTo(left.addedAt));
      return items;
    }
    return _webDavNasClient.scanLibrary(
      source,
      limit: limitPerCollection,
    );
  }

  Future<List<NasMediaIndexRecord>> _loadScopedRecords(
    MediaSourceConfig source, {
    String? sectionId,
    List<MediaCollection>? scopedCollections,
  }) async {
    final scopeKey = _buildScopeKey(source, scopedCollections);
    final state = await _store.loadSourceState(source.id);
    if (state == null || state.scopeKey != scopeKey) {
      await refreshSource(
        source,
        scopedCollections: scopedCollections,
      );
    }

    final normalizedSectionId = sectionId?.trim() ?? '';
    final records = await _store.loadSourceRecords(source.id);
    return records
        .where(
          (record) =>
              normalizedSectionId.isEmpty ||
              record.sectionId == normalizedSectionId,
        )
        .toList(growable: false);
  }

  List<MediaItem> _materializeLibraryItems(List<NasMediaIndexRecord> records) {
    final nonSeriesItems = <MediaItem>[];
    final groups = _groupSeriesRecords(records);
    final groupedResourceIds = groups
        .expand((group) => group.records.map((record) => record.resourceId))
        .toSet();

    for (final record in records) {
      if (!groupedResourceIds.contains(record.resourceId)) {
        nonSeriesItems.add(record.item);
      }
    }

    final seriesItems = groups.map(_buildSeriesItem);
    final allItems = [...nonSeriesItems, ...seriesItems];
    allItems.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return allItems;
  }

  List<_SeriesRecordGroup> _groupSeriesRecords(
      List<NasMediaIndexRecord> records) {
    final grouped = <String, List<NasMediaIndexRecord>>{};
    for (final record in records) {
      if (!_shouldGroupAsSeries(record)) {
        continue;
      }
      final title = _seriesTitleForRecord(record);
      if (title.isEmpty) {
        continue;
      }
      final key = _buildSeriesGroupKey(record, title);
      grouped.putIfAbsent(key, () => <NasMediaIndexRecord>[]).add(record);
    }
    return grouped.entries
        .map(
          (entry) => _SeriesRecordGroup(
            seriesKey: entry.key,
            records: entry.value,
            title: _seriesTitleForRecord(entry.value.first),
          ),
        )
        .toList(growable: false);
  }

  bool _shouldGroupAsSeries(NasMediaIndexRecord record) {
    final itemType = record.item.itemType.trim().toLowerCase();
    if (itemType == 'series' || itemType == 'season') {
      return false;
    }
    return itemType == 'episode' ||
        record.recognizedItemType.trim().toLowerCase() == 'episode' ||
        record.preferSeries ||
        record.recognizedSeasonNumber != null ||
        record.recognizedEpisodeNumber != null;
  }

  String _seriesTitleForRecord(NasMediaIndexRecord record) {
    final itemTitle = record.item.title.trim();
    final parentTitle = record.parentTitle.trim();
    final recognizedTitle = record.recognizedTitle.trim();
    final itemType = record.item.itemType.trim().toLowerCase();
    if (itemType == 'episode') {
      if (parentTitle.isNotEmpty) {
        return parentTitle;
      }
      if (recognizedTitle.isNotEmpty) {
        return recognizedTitle;
      }
    }
    if (record.preferSeries && parentTitle.isNotEmpty) {
      return parentTitle;
    }
    if (record.preferSeries && recognizedTitle.isNotEmpty) {
      return recognizedTitle;
    }
    return itemTitle;
  }

  String _buildSeriesGroupKey(NasMediaIndexRecord record, String title) {
    final imdbId = record.item.imdbId.trim();
    final tmdbId = record.item.tmdbId.trim();
    if (imdbId.isNotEmpty) {
      return 'imdb:$imdbId';
    }
    if (tmdbId.isNotEmpty) {
      return 'tmdb:$tmdbId';
    }
    return 'title:${record.sectionId.trim()}|${title.toLowerCase()}';
  }

  MediaItem _buildSeriesItem(_SeriesRecordGroup group) {
    final records = [...group.records]
      ..sort((left, right) => right.item.addedAt.compareTo(left.item.addedAt));
    final base = records.first;
    final bestOverview = records
        .map((record) => record.item.overview.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final bestPoster = records
        .map((record) => record.item.posterUrl.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final posterHeaders = records
        .map((record) => record.item.posterHeaders)
        .firstWhere((value) => value.isNotEmpty, orElse: () => const {});
    final bestYear = records
        .map((record) => record.item.year)
        .firstWhere((value) => value > 0, orElse: () => 0);
    final ratingLabels = _mergeLabels(
      const [],
      records.expand((record) => record.item.ratingLabels).toList(),
    );
    final genres =
        _dedupe(records.expand((record) => record.item.genres).toList());
    final directors =
        _dedupe(records.expand((record) => record.item.directors).toList());
    final actors =
        _dedupe(records.expand((record) => record.item.actors).toList());
    final imdbId = records
        .map((record) => record.item.imdbId.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final tmdbId = records
        .map((record) => record.item.tmdbId.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final doubanId = records
        .map((record) => record.item.doubanId.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final lastAddedAt = records
        .map((record) => record.item.addedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);

    return MediaItem(
      id: _buildSeriesItemId(group.seriesKey),
      title: group.title,
      overview: bestOverview,
      posterUrl: bestPoster,
      posterHeaders: posterHeaders,
      year: bestYear,
      durationLabel: '剧集',
      genres: genres,
      directors: directors,
      actors: actors,
      itemType: 'series',
      sectionId: base.sectionId,
      sectionName: base.sectionName,
      sourceId: base.sourceId,
      sourceName: base.item.sourceName,
      sourceKind: base.item.sourceKind,
      streamUrl: '',
      actualAddress: base.parentTitle.trim().isNotEmpty
          ? base.parentTitle.trim()
          : base.item.actualAddress,
      streamHeaders: const {},
      imdbId: imdbId,
      tmdbId: tmdbId,
      doubanId: doubanId,
      ratingLabels: ratingLabels,
      addedAt: lastAddedAt,
    );
  }

  MediaItem _buildSeasonItem(
    _SeriesRecordGroup group,
    int seasonNumber,
    List<NasMediaIndexRecord> records,
  ) {
    final sorted = [...records]
      ..sort((left, right) => right.item.addedAt.compareTo(left.item.addedAt));
    final base = sorted.first;
    final label = seasonNumber == 0 ? '特别篇' : '第 $seasonNumber 季';
    return MediaItem(
      id: _buildSeasonItemId(group.seriesKey, seasonNumber),
      title: label,
      overview: base.item.overview,
      posterUrl: base.item.posterUrl,
      posterHeaders: base.item.posterHeaders,
      year: base.item.year,
      durationLabel: '剧集',
      genres: _dedupe(records.expand((record) => record.item.genres).toList()),
      directors:
          _dedupe(records.expand((record) => record.item.directors).toList()),
      actors: _dedupe(records.expand((record) => record.item.actors).toList()),
      itemType: 'season',
      sectionId: base.sectionId,
      sectionName: base.sectionName,
      sourceId: base.sourceId,
      sourceName: base.item.sourceName,
      sourceKind: base.item.sourceKind,
      streamUrl: '',
      actualAddress: base.item.actualAddress,
      streamHeaders: const {},
      seasonNumber: seasonNumber,
      imdbId: base.item.imdbId,
      tmdbId: base.item.tmdbId,
      doubanId: base.item.doubanId,
      ratingLabels: _mergeLabels(
          const [], records.expand((e) => e.item.ratingLabels).toList()),
      addedAt: sorted.first.item.addedAt,
    );
  }

  List<MediaItem> _materializeEpisodeItems(
      Iterable<NasMediaIndexRecord> records) {
    final items = records.map((record) => record.item).toList(growable: false)
      ..sort((left, right) {
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
        return left.title.compareTo(right.title);
      });
    return items;
  }

  String _buildSeriesItemId(String seriesKey) {
    return '$_seriesGroupPrefix|${Uri.encodeComponent(seriesKey)}';
  }

  String _buildSeasonItemId(String seriesKey, int seasonNumber) {
    return '$_seasonGroupPrefix|${Uri.encodeComponent(seriesKey)}|$seasonNumber';
  }

  bool _isSyntheticGroupId(String id) {
    return id.startsWith(_seriesGroupPrefix) ||
        id.startsWith(_seasonGroupPrefix);
  }

  _ParsedSeasonGroupId? _parseSeasonGroupId(String id) {
    final parts = id.split('|');
    if (parts.length != 3 || parts.first != _seasonGroupPrefix) {
      return null;
    }
    final seriesKey = Uri.decodeComponent(parts[1]);
    final seasonNumber = int.tryParse(parts[2]);
    if (seasonNumber == null) {
      return null;
    }
    return _ParsedSeasonGroupId(
      seriesKey: seriesKey,
      seasonNumber: seasonNumber,
    );
  }

  NasMediaIndexRecord _reuseRecord(
    NasMediaIndexRecord existing, {
    required WebDavScannedItem scannedItem,
    required MediaSourceConfig source,
    required DateTime indexedAt,
  }) {
    final refreshedItem = MediaItem(
      id: scannedItem.resourceId,
      title: existing.item.title,
      originalTitle: existing.item.originalTitle,
      sortTitle: existing.item.sortTitle,
      overview: existing.item.overview,
      posterUrl: existing.item.posterUrl,
      posterHeaders: existing.item.posterHeaders,
      year: existing.item.year,
      durationLabel: existing.item.durationLabel,
      genres: existing.item.genres,
      directors: existing.item.directors,
      actors: existing.item.actors,
      itemType: existing.item.itemType,
      sectionId: scannedItem.sectionId,
      sectionName: scannedItem.sectionName,
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
      streamUrl: scannedItem.streamUrl,
      actualAddress: scannedItem.actualAddress,
      streamHeaders: scannedItem.streamHeaders,
      playbackItemId: existing.item.playbackItemId,
      preferredMediaSourceId: existing.item.preferredMediaSourceId,
      seasonNumber: existing.item.seasonNumber,
      episodeNumber: existing.item.episodeNumber,
      playbackProgress: existing.item.playbackProgress,
      doubanId: existing.item.doubanId,
      imdbId: existing.item.imdbId,
      tmdbId: existing.item.tmdbId,
      ratingLabels: existing.item.ratingLabels,
      addedAt: scannedItem.addedAt,
      lastWatchedAt: existing.item.lastWatchedAt,
    );
    return NasMediaIndexRecord(
      id: existing.id,
      sourceId: existing.sourceId,
      sectionId: scannedItem.sectionId,
      sectionName: scannedItem.sectionName,
      resourceId: existing.resourceId,
      resourcePath: scannedItem.actualAddress,
      fingerprint: existing.fingerprint,
      fileSizeBytes: scannedItem.fileSizeBytes,
      modifiedAt: scannedItem.modifiedAt,
      indexedAt: indexedAt,
      scrapedAt: existing.scrapedAt,
      recognizedTitle: existing.recognizedTitle,
      searchQuery: existing.searchQuery,
      originalFileName: scannedItem.fileName,
      parentTitle: existing.parentTitle,
      recognizedYear: existing.recognizedYear,
      recognizedItemType: existing.recognizedItemType,
      preferSeries: existing.preferSeries,
      recognizedSeasonNumber: existing.recognizedSeasonNumber,
      recognizedEpisodeNumber: existing.recognizedEpisodeNumber,
      sidecarMatched: existing.sidecarMatched,
      wmdbMatched: existing.wmdbMatched,
      tmdbMatched: existing.tmdbMatched,
      imdbMatched: existing.imdbMatched,
      item: refreshedItem,
    );
  }

  Future<NasMediaIndexRecord> _indexScannedItem(
    MediaSourceConfig source,
    WebDavScannedItem scannedItem, {
    required DateTime indexedAt,
    required String fingerprint,
  }) async {
    final settings = _readSettings();
    final recognition = NasMediaRecognizer.recognize(scannedItem.actualAddress);
    final seed = scannedItem.metadataSeed;

    var title =
        seed.title.trim().isNotEmpty ? seed.title.trim() : recognition.title;
    var originalTitle = '';
    var overview = seed.overview.trim();
    var posterUrl = seed.posterUrl.trim();
    var posterHeaders =
        posterUrl.isNotEmpty ? seed.posterHeaders : const <String, String>{};
    var year = seed.year > 0 ? seed.year : recognition.year;
    var durationLabel = seed.durationLabel.trim();
    var genres = _dedupe(seed.genres);
    var directors = _dedupe(seed.directors);
    var actors = _dedupe(seed.actors);
    var ratingLabels = <String>[];
    var itemType = seed.itemType.trim().isNotEmpty
        ? seed.itemType.trim()
        : recognition.itemType.trim();
    var seasonNumber = seed.seasonNumber ?? recognition.seasonNumber;
    var episodeNumber = seed.episodeNumber ?? recognition.episodeNumber;
    var doubanId = '';
    var imdbId = seed.imdbId.trim().isNotEmpty
        ? seed.imdbId.trim()
        : recognition.imdbId.trim();
    var tmdbId = seed.tmdbId.trim().isNotEmpty
        ? seed.tmdbId.trim()
        : recognition.tmdbId.trim();

    final titleLocked = seed.hasSidecarMatch && seed.title.trim().isNotEmpty;
    final overviewLocked = seed.overview.trim().isNotEmpty;
    final posterLocked = seed.posterUrl.trim().isNotEmpty;
    final yearLocked = seed.year > 0;
    final durationLocked = seed.durationLabel.trim().isNotEmpty &&
        seed.durationLabel.trim() != '文件';
    final genresLocked = seed.genres.isNotEmpty;
    final peopleLocked = seed.directors.isNotEmpty || seed.actors.isNotEmpty;
    final typeLocked = seed.itemType.trim().isNotEmpty;
    final seasonLocked = seed.seasonNumber != null;
    final episodeLocked = seed.episodeNumber != null;

    var wmdbMatched = false;
    var tmdbMatched = false;
    var imdbMatched = false;

    final baseQuery =
        title.trim().isNotEmpty ? title.trim() : recognition.searchQuery;
    final preferSeries = recognition.preferSeries ||
        itemType.trim().toLowerCase() == 'episode' ||
        itemType.trim().toLowerCase() == 'series';

    if (settings.wmdbMetadataMatchEnabled && baseQuery.isNotEmpty) {
      try {
        final wmdbMatch = await _wmdbMetadataClient.matchTitle(
          query: baseQuery,
          year: year > 0 ? year : recognition.year,
          preferSeries: preferSeries,
          actors: actors,
        );
        if (wmdbMatch != null) {
          wmdbMatched = true;
          if (!titleLocked && wmdbMatch.title.trim().isNotEmpty) {
            title = wmdbMatch.title.trim();
          }
          if (originalTitle.trim().isEmpty &&
              wmdbMatch.originalTitle.trim().isNotEmpty) {
            originalTitle = wmdbMatch.originalTitle.trim();
          }
          if (!overviewLocked && wmdbMatch.overview.trim().isNotEmpty) {
            overview = wmdbMatch.overview.trim();
          }
          if (!posterLocked && wmdbMatch.posterUrl.trim().isNotEmpty) {
            posterUrl = wmdbMatch.posterUrl.trim();
            posterHeaders = const {};
          }
          if (!yearLocked && wmdbMatch.year > 0) {
            year = wmdbMatch.year;
          }
          if (!durationLocked && wmdbMatch.durationLabel.trim().isNotEmpty) {
            durationLabel = wmdbMatch.durationLabel.trim();
          }
          if (!genresLocked && wmdbMatch.genres.isNotEmpty) {
            genres = _dedupe(wmdbMatch.genres);
          }
          if (!peopleLocked) {
            if (wmdbMatch.directors.isNotEmpty) {
              directors = _dedupe(wmdbMatch.directors);
            }
            if (wmdbMatch.actors.isNotEmpty) {
              actors = _dedupe(wmdbMatch.actors);
            }
          }
          ratingLabels = _mergeLabels(ratingLabels, wmdbMatch.ratingLabels);
          if (doubanId.trim().isEmpty && wmdbMatch.doubanId.trim().isNotEmpty) {
            doubanId = wmdbMatch.doubanId.trim();
          }
          if (imdbId.trim().isEmpty && wmdbMatch.imdbId.trim().isNotEmpty) {
            imdbId = wmdbMatch.imdbId.trim();
          }
          if (tmdbId.trim().isEmpty && wmdbMatch.tmdbId.trim().isNotEmpty) {
            tmdbId = wmdbMatch.tmdbId.trim();
          }
        }
      } catch (_) {
        // Keep indexing even if online matching fails.
      }
    }

    if (settings.tmdbMetadataMatchEnabled &&
        settings.tmdbReadAccessToken.trim().isNotEmpty &&
        baseQuery.isNotEmpty) {
      final needsTmdb = tmdbId.trim().isEmpty ||
          (!posterLocked && posterUrl.trim().isEmpty) ||
          (!overviewLocked && overview.trim().isEmpty) ||
          (!peopleLocked && (directors.isEmpty || actors.isEmpty)) ||
          (!genresLocked && genres.isEmpty) ||
          (!durationLocked && durationLabel.trim().isEmpty);
      if (needsTmdb) {
        try {
          final tmdbMatch = await _tmdbMetadataClient.matchTitle(
            query: title.trim().isNotEmpty ? title.trim() : baseQuery,
            readAccessToken: settings.tmdbReadAccessToken.trim(),
            year: year,
            preferSeries: preferSeries,
          );
          if (tmdbMatch != null) {
            tmdbMatched = true;
            if (!titleLocked &&
                !wmdbMatched &&
                tmdbMatch.title.trim().isNotEmpty) {
              title = tmdbMatch.title.trim();
            }
            if (originalTitle.trim().isEmpty &&
                tmdbMatch.originalTitle.trim().isNotEmpty) {
              originalTitle = tmdbMatch.originalTitle.trim();
            }
            if (!posterLocked && tmdbMatch.posterUrl.trim().isNotEmpty) {
              posterUrl = tmdbMatch.posterUrl.trim();
              posterHeaders = const {};
            }
            if (!overviewLocked &&
                overview.trim().isEmpty &&
                tmdbMatch.overview.trim().isNotEmpty) {
              overview = tmdbMatch.overview.trim();
            }
            if (!yearLocked && year <= 0 && tmdbMatch.year > 0) {
              year = tmdbMatch.year;
            }
            if (!durationLocked &&
                (durationLabel.trim().isEmpty ||
                    durationLabel.trim() == '文件' ||
                    durationLabel.trim() == '剧集') &&
                tmdbMatch.durationLabel.trim().isNotEmpty) {
              durationLabel = tmdbMatch.durationLabel.trim();
            }
            if (!genresLocked &&
                genres.isEmpty &&
                tmdbMatch.genres.isNotEmpty) {
              genres = _dedupe(tmdbMatch.genres);
            }
            if (!peopleLocked) {
              if (directors.isEmpty && tmdbMatch.directors.isNotEmpty) {
                directors = _dedupe(tmdbMatch.directors);
              }
              if (actors.isEmpty && tmdbMatch.actors.isNotEmpty) {
                actors = _dedupe(tmdbMatch.actors);
              }
            }
            if (tmdbId.trim().isEmpty && tmdbMatch.tmdbId.trim().isNotEmpty) {
              tmdbId = tmdbMatch.tmdbId.trim();
            }
            if (imdbId.trim().isEmpty && tmdbMatch.imdbId.trim().isNotEmpty) {
              imdbId = tmdbMatch.imdbId.trim();
            }
          }
        } catch (_) {
          // Keep indexing even if online matching fails.
        }
      }
    }

    if (settings.imdbRatingMatchEnabled &&
        !_hasRatingLabelKeyword(ratingLabels, 'imdb') &&
        baseQuery.isNotEmpty) {
      try {
        final imdbMatch = await _imdbRatingClient.matchRating(
          query: title.trim().isNotEmpty ? title.trim() : baseQuery,
          year: year,
          preferSeries: preferSeries,
          imdbId: imdbId,
        );
        if (imdbMatch != null) {
          imdbMatched = true;
          if (imdbId.trim().isEmpty && imdbMatch.imdbId.trim().isNotEmpty) {
            imdbId = imdbMatch.imdbId.trim();
          }
          if (imdbMatch.ratingLabel.trim().isNotEmpty) {
            ratingLabels =
                _mergeLabels(ratingLabels, [imdbMatch.ratingLabel.trim()]);
          }
        }
      } catch (_) {
        // Keep indexing even if online matching fails.
      }
    }

    if (!typeLocked && itemType.trim().isEmpty) {
      itemType = recognition.itemType.trim();
    }
    if (!seasonLocked) {
      seasonNumber = recognition.seasonNumber;
    }
    if (!episodeLocked) {
      episodeNumber = recognition.episodeNumber;
    }

    if (durationLabel.trim().isEmpty) {
      durationLabel = itemType.trim().toLowerCase() == 'episode' ? '剧集' : '文件';
    }
    if (title.trim().isEmpty) {
      title = recognition.title.trim().isNotEmpty
          ? recognition.title.trim()
          : scannedItem.fileName;
    }

    final item = MediaItem(
      id: scannedItem.resourceId,
      title: title.trim(),
      originalTitle: originalTitle.trim(),
      sortTitle: title.trim(),
      overview: overview.trim(),
      posterUrl: posterUrl.trim(),
      posterHeaders: posterHeaders,
      year: year,
      durationLabel: durationLabel.trim(),
      genres: _dedupe(genres),
      directors: _dedupe(directors),
      actors: _dedupe(actors),
      itemType: itemType.trim(),
      sectionId: scannedItem.sectionId,
      sectionName: scannedItem.sectionName,
      sourceId: source.id,
      sourceName: source.name,
      sourceKind: source.kind,
      streamUrl: scannedItem.streamUrl,
      actualAddress: scannedItem.actualAddress,
      streamHeaders: scannedItem.streamHeaders,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      doubanId: doubanId.trim(),
      imdbId: imdbId.trim(),
      tmdbId: tmdbId.trim(),
      ratingLabels: _dedupe(ratingLabels),
      addedAt: scannedItem.addedAt,
    );

    return NasMediaIndexRecord(
      id: NasMediaIndexRecord.buildRecordId(
        sourceId: source.id,
        resourceId: scannedItem.resourceId,
      ),
      sourceId: source.id,
      sectionId: scannedItem.sectionId,
      sectionName: scannedItem.sectionName,
      resourceId: scannedItem.resourceId,
      resourcePath: scannedItem.actualAddress,
      fingerprint: fingerprint,
      fileSizeBytes: scannedItem.fileSizeBytes,
      modifiedAt: scannedItem.modifiedAt,
      indexedAt: indexedAt,
      scrapedAt: indexedAt,
      recognizedTitle: recognition.title,
      searchQuery: baseQuery,
      originalFileName: recognition.originalFileName,
      parentTitle: recognition.parentTitle,
      recognizedYear: recognition.year,
      recognizedItemType: recognition.itemType,
      preferSeries: recognition.preferSeries,
      recognizedSeasonNumber: recognition.seasonNumber,
      recognizedEpisodeNumber: recognition.episodeNumber,
      sidecarMatched: seed.hasSidecarMatch,
      wmdbMatched: wmdbMatched,
      tmdbMatched: tmdbMatched,
      imdbMatched: imdbMatched,
      item: item,
    );
  }

  String _buildScopeKey(
    MediaSourceConfig source,
    List<MediaCollection>? scopedCollections,
  ) {
    if (scopedCollections != null && scopedCollections.isNotEmpty) {
      final ids = scopedCollections
          .map((item) => item.id.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
        ..sort();
      return 'collections|${ids.join(',')}|structure:${source.webDavStructureInferenceEnabled}';
    }
    final root = source.libraryPath.trim().isNotEmpty
        ? source.libraryPath.trim()
        : source.endpoint.trim();
    return 'root|$root|structure:${source.webDavStructureInferenceEnabled}';
  }

  String _buildFingerprint({
    required String sourceId,
    required String resourcePath,
    required DateTime? modifiedAt,
    required int fileSizeBytes,
  }) {
    return [
      sourceId.trim(),
      resourcePath.trim(),
      modifiedAt?.toUtc().toIso8601String() ?? '',
      '$fileSizeBytes',
    ].join('|');
  }

  static List<String> _dedupe(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  static List<String> _mergeLabels(
    List<String> current,
    List<String> next,
  ) {
    return _dedupe([...current, ...next]);
  }

  static bool _hasRatingLabelKeyword(
    Iterable<String> labels,
    String keyword,
  ) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.isEmpty) {
      return false;
    }
    return labels.any(
      (label) => label.trim().toLowerCase().contains(normalizedKeyword),
    );
  }

  MediaItem _applyManualMetadataToItem(
    MediaItem item, {
    MetadataMatchResult? metadataMatch,
    ImdbRatingMatch? imdbRatingMatch,
  }) {
    var nextItem = item;
    if (metadataMatch != null) {
      final filteredRatingLabels = _filterSupplementalRatingLabels(
        existing: nextItem.ratingLabels,
        supplemental: metadataMatch.ratingLabels,
      );
      final resolvedTitle = metadataMatch.title.trim();
      final resolvedPosterUrl = metadataMatch.posterUrl.trim();
      nextItem = nextItem.copyWith(
        title: resolvedTitle.isNotEmpty ? resolvedTitle : nextItem.title,
        originalTitle: metadataMatch.originalTitle.trim().isNotEmpty
            ? metadataMatch.originalTitle.trim()
            : nextItem.originalTitle,
        sortTitle:
            resolvedTitle.isNotEmpty ? resolvedTitle : nextItem.sortTitle,
        overview: metadataMatch.overview.trim().isNotEmpty
            ? metadataMatch.overview.trim()
            : nextItem.overview,
        posterUrl: resolvedPosterUrl.isNotEmpty
            ? resolvedPosterUrl
            : nextItem.posterUrl,
        posterHeaders: resolvedPosterUrl.isNotEmpty
            ? const <String, String>{}
            : nextItem.posterHeaders,
        year: metadataMatch.year > 0 ? metadataMatch.year : nextItem.year,
        durationLabel: metadataMatch.durationLabel.trim().isNotEmpty
            ? metadataMatch.durationLabel.trim()
            : nextItem.durationLabel,
        genres: metadataMatch.genres.isNotEmpty
            ? _dedupe(metadataMatch.genres)
            : nextItem.genres,
        directors: metadataMatch.directors.isNotEmpty
            ? _dedupe(metadataMatch.directors)
            : nextItem.directors,
        actors: metadataMatch.actors.isNotEmpty
            ? _dedupe(metadataMatch.actors)
            : nextItem.actors,
        doubanId: metadataMatch.doubanId.trim().isNotEmpty
            ? metadataMatch.doubanId.trim()
            : nextItem.doubanId,
        imdbId: metadataMatch.imdbId.trim().isNotEmpty
            ? metadataMatch.imdbId.trim()
            : nextItem.imdbId,
        tmdbId: metadataMatch.tmdbId.trim().isNotEmpty
            ? metadataMatch.tmdbId.trim()
            : nextItem.tmdbId,
        ratingLabels: _mergeLabels(nextItem.ratingLabels, filteredRatingLabels),
      );
    }
    if (imdbRatingMatch != null &&
        imdbRatingMatch.ratingLabel.trim().isNotEmpty) {
      nextItem = nextItem.copyWith(
        imdbId: imdbRatingMatch.imdbId.trim().isNotEmpty
            ? imdbRatingMatch.imdbId.trim()
            : nextItem.imdbId,
        ratingLabels: _mergeLabels(
          nextItem.ratingLabels,
          [imdbRatingMatch.ratingLabel.trim()],
        ),
      );
    }
    return nextItem;
  }

  List<String> _filterSupplementalRatingLabels({
    required List<String> existing,
    required List<String> supplemental,
  }) {
    if (!_hasRatingLabelKeyword(existing, '豆瓣')) {
      return supplemental;
    }
    return supplemental
        .where((label) => !label.trim().toLowerCase().contains('豆瓣'))
        .toList(growable: false);
  }
}

class _SeriesRecordGroup {
  const _SeriesRecordGroup({
    required this.seriesKey,
    required this.records,
    required this.title,
  });

  final String seriesKey;
  final List<NasMediaIndexRecord> records;
  final String title;

  String get seriesItemId {
    return '${NasMediaIndexer._seriesGroupPrefix}|${Uri.encodeComponent(seriesKey)}';
  }

  Map<int, List<NasMediaIndexRecord>> get seasonGroups {
    final grouped = <int, List<NasMediaIndexRecord>>{};
    for (final record in records) {
      final seasonNumber =
          record.item.seasonNumber ?? record.recognizedSeasonNumber ?? 1;
      grouped
          .putIfAbsent(seasonNumber, () => <NasMediaIndexRecord>[])
          .add(record);
    }
    return grouped;
  }
}

class _ParsedSeasonGroupId {
  const _ParsedSeasonGroupId({
    required this.seriesKey,
    required this.seasonNumber,
  });

  final String seriesKey;
  final int seasonNumber;
}
