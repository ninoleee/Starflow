import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/library/application/nas_media_index_revision.dart';
import 'package:starflow/features/library/data/nas_media_index_store.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_source_identity.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

final mediaSourceCacheLifecycleProvider = Provider<MediaSourceCacheLifecycle>(
  (ref) => DefaultMediaSourceCacheLifecycle(
    indexStore: ref.read(nasMediaIndexStoreProvider),
    nasMediaIndexer: ref.read(nasMediaIndexerProvider),
    webDavNasClient: ref.read(webDavNasClientProvider),
    localStorageCacheRepository: ref.read(localStorageCacheRepositoryProvider),
    invalidateSource: (sourceId) {
      final revisions = ref.read(
        nasMediaIndexSourceInvalidationRevisionsProvider,
      );
      ref
          .read(nasMediaIndexSourceInvalidationRevisionsProvider.notifier)
          .state = <String, int>{
        ...revisions,
        sourceId: (revisions[sourceId] ?? 0) + 1,
      };
    },
    invalidateAll: () {
      final notifier = ref.read(
        nasMediaIndexGlobalInvalidationRevisionProvider.notifier,
      );
      notifier.state += 1;
    },
    notifyIndexChanged: () {
      ref.read(nasMediaIndexRevisionProvider.notifier).state += 1;
    },
  ),
);

abstract class MediaSourceCacheLifecycle {
  Future<void> reconcileSources(List<MediaSourceConfig> sources);

  Future<void> clearSource(String sourceId);

  Future<void> clearAllIndexes();
}

class DefaultMediaSourceCacheLifecycle implements MediaSourceCacheLifecycle {
  const DefaultMediaSourceCacheLifecycle({
    required NasMediaIndexStore indexStore,
    NasMediaIndexer? nasMediaIndexer,
    required WebDavNasClient webDavNasClient,
    required LocalStorageCacheRepository localStorageCacheRepository,
    required void Function(String sourceId) invalidateSource,
    required void Function() invalidateAll,
    required void Function() notifyIndexChanged,
  })  : _indexStore = indexStore,
        _nasMediaIndexer = nasMediaIndexer,
        _webDavNasClient = webDavNasClient,
        _localStorageCacheRepository = localStorageCacheRepository,
        _invalidateSource = invalidateSource,
        _invalidateAll = invalidateAll,
        _notifyIndexChanged = notifyIndexChanged;

  final NasMediaIndexStore _indexStore;
  final NasMediaIndexer? _nasMediaIndexer;
  final WebDavNasClient _webDavNasClient;
  final LocalStorageCacheRepository _localStorageCacheRepository;
  final void Function(String sourceId) _invalidateSource;
  final void Function() _invalidateAll;
  final void Function() _notifyIndexChanged;

  @override
  Future<void> reconcileSources(List<MediaSourceConfig> sources) async {
    final sourceById = <String, MediaSourceConfig>{
      for (final source in sources)
        if (source.id.trim().isNotEmpty) source.id.trim(): source,
    };
    final states = await _indexStore.loadSourceStates();
    final indexedSourceIds = await _indexStore.loadCachedSourceIds();
    final cachedSourceIds =
        await _localStorageCacheRepository.loadCachedMediaSourceIds();
    final sourceIdsToClear = <String>{};

    for (final state in states) {
      final sourceId = state.sourceId.trim();
      final source = sourceById[sourceId];
      if (source == null) {
        sourceIdsToClear.add(sourceId);
        continue;
      }
      final currentIdentity = mediaSourceResourceIdentity(source);
      final storedIdentity = state.sourceIdentity.trim();
      final identityMatches = storedIdentity.isNotEmpty
          ? storedIdentity == currentIdentity
          : legacyIndexScopeMatchesSource(
              scopeKey: state.scopeKey,
              source: source,
            );
      if (!identityMatches) {
        sourceIdsToClear.add(sourceId);
      }
    }
    sourceIdsToClear.addAll(
      cachedSourceIds.where((sourceId) => !sourceById.containsKey(sourceId)),
    );
    sourceIdsToClear.addAll(
      indexedSourceIds.where((sourceId) => !sourceById.containsKey(sourceId)),
    );

    for (final sourceId in sourceIdsToClear) {
      await clearSource(sourceId);
    }
  }

  @override
  Future<void> clearSource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      return;
    }

    _invalidateSource(normalizedSourceId);
    final indexer = _nasMediaIndexer;
    if (indexer == null) {
      await _indexStore.clearSource(normalizedSourceId);
    } else {
      await indexer.clearSource(normalizedSourceId);
    }
    _webDavNasClient.clearMemoryCaches();
    await _localStorageCacheRepository.clearEmbyLibrarySnapshot(
      normalizedSourceId,
    );
    await _localStorageCacheRepository.clearLibraryRelationsForSource(
      normalizedSourceId,
    );
    if (indexer == null) {
      _notifyIndexChanged();
    }
    appLogInfo(
      'settings.media-source-cache',
      'Media source caches cleared',
      fields: <String, Object?>{'sourceId': normalizedSourceId},
    );
  }

  @override
  Future<void> clearAllIndexes() async {
    _invalidateAll();
    final indexer = _nasMediaIndexer;
    if (indexer == null) {
      await _indexStore.clearAll();
      _notifyIndexChanged();
    } else {
      await indexer.clearAll();
    }
    _webDavNasClient.clearMemoryCaches();
    appLogInfo(
      'settings.media-source-cache',
      'All media index caches cleared',
    );
  }
}
