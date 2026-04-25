import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/features/details/application/detail_target_resolver.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

class DetailRatingPrefetchCoordinator {
  static const int _maxParallelPrefetchWorkers = 3;

  int _refreshSessionId = 0;
  final Set<String> _scheduledRefreshKeys = <String>{};

  void reset() {
    _refreshSessionId += 1;
    _scheduledRefreshKeys.clear();
  }

  void schedulePrefetch({
    required WidgetRef ref,
    required Iterable<MediaDetailTarget> targets,
    required bool Function() isPageActive,
    bool preferDoubanOnly = false,
  }) {
    _schedulePrefetch(
      ref: ref,
      targets: targets,
      isPageActive: isPageActive,
      preferDoubanOnly: preferDoubanOnly,
      persistToDisk: true,
    );
  }

  void scheduleInMemoryPrefetch({
    required WidgetRef ref,
    required Iterable<MediaDetailTarget> targets,
    required bool Function() isPageActive,
    bool preferDoubanOnly = false,
  }) {
    _schedulePrefetch(
      ref: ref,
      targets: targets,
      isPageActive: isPageActive,
      preferDoubanOnly: preferDoubanOnly,
      persistToDisk: false,
    );
  }

  void _schedulePrefetch({
    required WidgetRef ref,
    required Iterable<MediaDetailTarget> targets,
    required bool Function() isPageActive,
    required bool preferDoubanOnly,
    required bool persistToDisk,
  }) {
    final backgroundSuspended = ref.read(backgroundEnrichmentSuspendedProvider);
    if (!isPageActive() || backgroundSuspended) {
      return;
    }

    final sessionId = _refreshSessionId;
    final candidates = <MediaDetailTarget>[];
    for (final target in targets) {
      if (!_needsRatingPrefetch(
        target,
        preferDoubanOnly: preferDoubanOnly,
      )) {
        continue;
      }
      final refreshKey = _ratingPrefetchKey(
        target,
        preferDoubanOnly: preferDoubanOnly,
      );
      if (refreshKey.isEmpty || !_scheduledRefreshKeys.add(refreshKey)) {
        continue;
      }
      candidates.add(target);
    }
    if (candidates.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isRefreshSessionActive(
        ref: ref,
        sessionId: sessionId,
        isPageActive: isPageActive,
      )) {
        return;
      }
      unawaited(
        _prefetchRatingsInBackground(
          ref: ref,
          targets: candidates,
          sessionId: sessionId,
          isPageActive: isPageActive,
          persistToDisk: persistToDisk,
        ),
      );
    });
  }

  bool _isRefreshSessionActive({
    required WidgetRef ref,
    required int sessionId,
    required bool Function() isPageActive,
  }) {
    return isPageActive() &&
        _refreshSessionId == sessionId &&
        !ref.read(backgroundEnrichmentSuspendedProvider);
  }

  Future<void> _prefetchRatingsInBackground({
    required WidgetRef ref,
    required List<MediaDetailTarget> targets,
    required int sessionId,
    required bool Function() isPageActive,
    required bool persistToDisk,
  }) async {
    final cacheRepository = ref.read(localStorageCacheRepositoryProvider);
    try {
      await cacheRepository.primeDetailPayload();
      if (!_isRefreshSessionActive(
        ref: ref,
        sessionId: sessionId,
        isPageActive: isPageActive,
      )) {
        return;
      }

      final updates = <DetailTargetCacheSaveRequest>[];
      var nextIndex = 0;
      final workerCount = targets.length < _maxParallelPrefetchWorkers
          ? targets.length
          : _maxParallelPrefetchWorkers;

      Future<void> runWorker() async {
        while (true) {
          if (!_isRefreshSessionActive(
            ref: ref,
            sessionId: sessionId,
            isPageActive: isPageActive,
          )) {
            return;
          }
          if (nextIndex >= targets.length) {
            return;
          }
          final target = targets[nextIndex++];
          final update = await _prefetchSingleTarget(
            ref: ref,
            target: target,
            sessionId: sessionId,
            isPageActive: isPageActive,
            cacheRepository: cacheRepository,
          );
          if (update != null) {
            updates.add(update);
          }
          if (!_isRefreshSessionActive(
            ref: ref,
            sessionId: sessionId,
            isPageActive: isPageActive,
          )) {
            return;
          }
          await Future<void>.delayed(Duration.zero);
        }
      }

      await Future.wait(
        List<Future<void>>.generate(workerCount, (_) => runWorker()),
        eagerError: false,
      );
      if (updates.isEmpty ||
          !_isRefreshSessionActive(
            ref: ref,
            sessionId: sessionId,
            isPageActive: isPageActive,
          )) {
        return;
      }
      if (persistToDisk) {
        await cacheRepository.saveDetailTargetsBatch(updates);
      } else {
        await cacheRepository.saveDetailTargetsBatchInMemory(updates);
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<DetailTargetCacheSaveRequest?> _prefetchSingleTarget({
    required WidgetRef ref,
    required MediaDetailTarget target,
    required int sessionId,
    required bool Function() isPageActive,
    required LocalStorageCacheRepository cacheRepository,
  }) async {
    if (!_isRefreshSessionActive(
      ref: ref,
      sessionId: sessionId,
      isPageActive: isPageActive,
    )) {
      return null;
    }

    try {
      final cachedState = cacheRepository.peekDetailState(target) ??
          await cacheRepository.loadDetailState(target);
      if (!_isRefreshSessionActive(
        ref: ref,
        sessionId: sessionId,
        isPageActive: isPageActive,
      )) {
        return null;
      }
      if ((cachedState?.metadataRefreshStatus ??
              DetailMetadataRefreshStatus.never) !=
          DetailMetadataRefreshStatus.never) {
        return null;
      }

      MediaDetailTarget? updatedTarget;
      if (target.sourceKind == MediaSourceKind.nas &&
          target.sourceId.trim().isNotEmpty &&
          target.itemId.trim().isNotEmpty) {
        updatedTarget = await ref
            .read(nasMediaIndexerProvider)
            .enrichDetailTargetMetadataIfNeeded(target);
      }
      updatedTarget ??=
          await ref.read(detailTargetResolverProvider).resolveMetadataOnly(
                target: target,
                backgroundWorkSuspended: false,
              );

      if (!_isRefreshSessionActive(
        ref: ref,
        sessionId: sessionId,
        isPageActive: isPageActive,
      )) {
        return null;
      }
      if (!_ratingPrefetchProducedUpdate(target, updatedTarget)) {
        return DetailTargetCacheSaveRequest(
          seedTarget: target,
          resolvedTarget: updatedTarget,
          metadataRefreshStatus: DetailMetadataRefreshStatus.failed,
        );
      }
      return DetailTargetCacheSaveRequest(
        seedTarget: target,
        resolvedTarget: updatedTarget,
        metadataRefreshStatus: DetailMetadataRefreshStatus.succeeded,
      );
    } catch (_) {
      return DetailTargetCacheSaveRequest(
        seedTarget: target,
        resolvedTarget: target,
        metadataRefreshStatus: DetailMetadataRefreshStatus.failed,
      );
    }
  }

  bool _needsRatingPrefetch(
    MediaDetailTarget target, {
    required bool preferDoubanOnly,
  }) {
    final searchQuery =
        (target.searchQuery.trim().isEmpty ? target.title : target.searchQuery)
            .trim();
    if (searchQuery.isEmpty &&
        target.doubanId.trim().isEmpty &&
        target.imdbId.trim().isEmpty) {
      return false;
    }
    return resolvePreferredPosterRatingLabel(
      target.ratingLabels,
      preferDoubanOnly: preferDoubanOnly,
    ).isEmpty;
  }

  bool _ratingPrefetchProducedUpdate(
    MediaDetailTarget current,
    MediaDetailTarget next,
  ) {
    final currentBadge =
        resolvePreferredPosterRatingLabel(current.ratingLabels);
    final nextBadge = resolvePreferredPosterRatingLabel(next.ratingLabels);
    if (nextBadge.isNotEmpty && nextBadge != currentBadge) {
      return true;
    }
    return current.doubanId.trim() != next.doubanId.trim() ||
        current.imdbId.trim().toLowerCase() !=
            next.imdbId.trim().toLowerCase() ||
        current.tmdbId.trim() != next.tmdbId.trim() ||
        current.posterUrl.trim() != next.posterUrl.trim() ||
        current.searchQuery.trim() != next.searchQuery.trim();
  }

  String _ratingPrefetchKey(
    MediaDetailTarget target, {
    required bool preferDoubanOnly,
  }) {
    final parts = [
      preferDoubanOnly ? 'douban-only' : 'fallback',
      target.sourceKind?.name ?? '',
      target.sourceId.trim(),
      target.itemId.trim(),
      target.doubanId.trim(),
      target.imdbId.trim().toLowerCase(),
      target.tmdbId.trim(),
      target.title.trim().toLowerCase(),
      target.searchQuery.trim().toLowerCase(),
    ].where((item) => item.isNotEmpty).toList(growable: false);
    return parts.join('|');
  }
}
