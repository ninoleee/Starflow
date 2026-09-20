import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';

import 'detail_cache_store.dart';
import 'local_storage_cache_models.dart';
import 'media_server_cache_store.dart';

export 'local_storage_cache_models.dart';

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

/// Compatibility facade; each store owns its cache, reads and mutation queue.
class LocalStorageCacheRepository {
  LocalStorageCacheRepository({
    PreferencesStore? preferences,
    SharedPreferences? sharedPreferences,
    void Function(LocalStorageDetailCacheChangeEvent event)?
        notifyDetailCacheChanged,
    this.detailCacheChangeNotificationDelay = Duration.zero,
  }) : assert(preferences == null || sharedPreferences == null) {
    final PreferencesStore store = preferences ??
        (sharedPreferences == null
            ? AppPreferencesStore()
            : SharedPreferencesStore(sharedPreferences));
    _details = DetailCacheStore(
      preferences: store,
      notifyDetailCacheChanged: notifyDetailCacheChanged,
      detailCacheChangeNotificationDelay: detailCacheChangeNotificationDelay,
    );
    _mediaServers = MediaServerCacheStore(preferences: store);
  }

  late final DetailCacheStore _details;
  late final MediaServerCacheStore _mediaServers;
  final Duration detailCacheChangeNotificationDelay;

  void dispose() {
    _details.dispose();
    _mediaServers.dispose();
  }

  Future<void> primeDetailPayload() => _details.primeDetailPayload();

  Future<CachedEmbyLibrarySnapshot> loadEmbyLibrarySnapshot(
    String sourceId, {
    String? sectionId,
    bool preferSourceSummary = false,
  }) =>
      _mediaServers.loadEmbyLibrarySnapshot(
        sourceId,
        sectionId: sectionId,
        preferSourceSummary: preferSourceSummary,
      );

  Future<void> saveEmbyLibrarySnapshot({
    required String sourceId,
    required DateTime refreshedAt,
    List<MediaCollection> collections = const <MediaCollection>[],
    List<MediaItem> fallbackItems = const <MediaItem>[],
    Map<String, List<MediaItem>> itemsBySection =
        const <String, List<MediaItem>>{},
  }) =>
      _mediaServers.saveEmbyLibrarySnapshot(
        sourceId: sourceId,
        refreshedAt: refreshedAt,
        collections: collections,
        fallbackItems: fallbackItems,
        itemsBySection: itemsBySection,
      );

  Future<void> updateMediaItemRatingCount({
    required String sourceId,
    required String itemId,
    required int ratingCount,
  }) =>
      _mediaServers.updateMediaItemRatingCount(
        sourceId: sourceId,
        itemId: itemId,
        ratingCount: ratingCount,
      );

  Future<void> clearEmbyLibrarySnapshot(String sourceId) =>
      _mediaServers.clearEmbyLibrarySnapshot(sourceId);

  Future<LocalStorageCacheSummary> inspectEmbyLibraryCache() =>
      _mediaServers.inspectEmbyLibraryCache();

  Future<void> clearAllEmbyLibrarySnapshots() =>
      _mediaServers.clearAllEmbyLibrarySnapshots();

  CachedDetailState? peekDetailState(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) =>
      _details.peekDetailState(
        seedTarget,
        allowStructuralMismatch: allowStructuralMismatch,
      );

  // Keep facade-to-facade calls virtual for existing repository subclasses.
  MediaDetailTarget? peekDetailTarget(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) =>
      peekDetailState(
        seedTarget,
        allowStructuralMismatch: allowStructuralMismatch,
      )?.target;

  Future<CachedDetailState?> loadDetailState(
    MediaDetailTarget seedTarget, {
    bool allowStructuralMismatch = false,
  }) =>
      _details.loadDetailState(
        seedTarget,
        allowStructuralMismatch: allowStructuralMismatch,
      );

  Future<MediaDetailTarget?> loadDetailTarget(
    MediaDetailTarget seedTarget,
  ) async =>
      (await loadDetailState(seedTarget))?.target;

  Future<List<MediaDetailTarget?>> loadDetailTargetsBatch(
    Iterable<MediaDetailTarget> seedTargets,
  ) =>
      _details.loadDetailTargetsBatch(seedTargets);

  static LocalStorageDetailCacheScope buildScopeForTargets(
    Iterable<MediaDetailTarget> targets,
  ) =>
      DetailCacheStore.buildScopeForTargets(targets);

  static List<String> buildLookupKeys(MediaDetailTarget target) =>
      DetailCacheStore.buildLookupKeys(target);

  Future<DetailMetadataRefreshStatus> loadDetailMetadataRefreshStatus(
    MediaDetailTarget seedTarget,
  ) async =>
      (await loadDetailState(seedTarget))?.metadataRefreshStatus ??
      DetailMetadataRefreshStatus.never;

  Future<void> saveDetailTarget({
    required MediaDetailTarget seedTarget,
    required MediaDetailTarget resolvedTarget,
    DetailMetadataRefreshStatus? metadataRefreshStatus,
    List<MediaDetailTarget>? libraryMatchChoices,
    int? selectedLibraryMatchIndex,
    List<CachedSubtitleSearchOption>? subtitleSearchChoices,
    int? selectedSubtitleSearchIndex,
  }) =>
      _details.saveDetailTarget(
        seedTarget: seedTarget,
        resolvedTarget: resolvedTarget,
        metadataRefreshStatus: metadataRefreshStatus,
        libraryMatchChoices: libraryMatchChoices,
        selectedLibraryMatchIndex: selectedLibraryMatchIndex,
        subtitleSearchChoices: subtitleSearchChoices,
        selectedSubtitleSearchIndex: selectedSubtitleSearchIndex,
      );

  Future<void> saveDetailTargetsBatch(
    Iterable<DetailTargetCacheSaveRequest> requests,
  ) =>
      _details.saveDetailTargetsBatch(requests);

  Future<void> saveDetailTargetsBatchInMemory(
    Iterable<DetailTargetCacheSaveRequest> requests,
  ) =>
      _details.saveDetailTargetsBatchInMemory(requests);

  Future<LocalStorageCacheSummary> inspectDetailCache() =>
      _details.inspectDetailCache();

  Future<void> clearDetailCache() => _details.clearDetailCache();

  Future<void> clearDetailCacheForSource(String sourceId) =>
      _details.clearDetailCacheForSource(sourceId);

  Future<void> clearLibraryRelationsForSource(String sourceId) =>
      _details.clearLibraryRelationsForSource(sourceId);

  Future<Set<String>> loadCachedMediaSourceIds() async {
    final sourceIds = await _mediaServers.loadCachedMediaSourceIds();
    sourceIds.addAll(await _details.loadCachedMediaSourceIds());
    return sourceIds;
  }

  Future<void> clearDetailCacheForResource({
    required String sourceId,
    String resourceId = '',
    required String resourcePath,
    bool treatAsScope = false,
  }) =>
      _details.clearDetailCacheForResource(
        sourceId: sourceId,
        resourceId: resourceId,
        resourcePath: resourcePath,
        treatAsScope: treatAsScope,
      );

  Future<void> clearCache(LocalStorageCacheType type) async {
    switch (type) {
      case LocalStorageCacheType.nasMetadataIndex:
      case LocalStorageCacheType.subtitleCache:
      case LocalStorageCacheType.playbackMemory:
      case LocalStorageCacheType.televisionSearchPreferences:
      case LocalStorageCacheType.images:
        return;
      case LocalStorageCacheType.embyLibraryCache:
        await clearAllEmbyLibrarySnapshots();
        return;
      case LocalStorageCacheType.detailData:
        await clearDetailCache();
        return;
    }
  }
}
