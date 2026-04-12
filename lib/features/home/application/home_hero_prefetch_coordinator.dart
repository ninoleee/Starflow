import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

class HomeHeroPrefetchCoordinator {
  int _refreshSessionId = 0;
  final Set<String> _scheduledRefreshKeys = <String>{};

  void reset() {
    _refreshSessionId += 1;
    _scheduledRefreshKeys.clear();
  }

  void clearScheduled() {
    _scheduledRefreshKeys.clear();
  }

  void schedulePrefetch({
    required WidgetRef ref,
    required Iterable<MediaDetailTarget> targets,
    required bool Function() isPageActive,
  }) {
    if (!isPageActive() || ref.read(backgroundEnrichmentSuspendedProvider)) {
      return;
    }
    final sessionId = _refreshSessionId;
    final candidates = <MediaDetailTarget>[];
    for (final target in targets) {
      if (!_needsHeroMetadataRefresh(target)) {
        continue;
      }
      final refreshKey = _heroMetadataRefreshKey(target);
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
        _refreshMetadataInBackground(
          ref: ref,
          targets: candidates,
          sessionId: sessionId,
          isPageActive: isPageActive,
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

  Future<void> _refreshMetadataInBackground({
    required WidgetRef ref,
    required List<MediaDetailTarget> targets,
    required int sessionId,
    required bool Function() isPageActive,
  }) async {
    if (!_isRefreshSessionActive(
      ref: ref,
      sessionId: sessionId,
      isPageActive: isPageActive,
    )) {
      return;
    }
    try {
      await Future.wait(
        targets.map(
          (target) => _refreshSingleMetadataIfNeeded(
            ref: ref,
            target: target,
            sessionId: sessionId,
            isPageActive: isPageActive,
          ),
        ),
        eagerError: false,
      );
    } catch (_) {
      // Hero metadata refresh is best-effort and should never block home UI.
    }
  }

  Future<void> _refreshSingleMetadataIfNeeded({
    required WidgetRef ref,
    required MediaDetailTarget target,
    required int sessionId,
    required bool Function() isPageActive,
  }) async {
    if (!_isRefreshSessionActive(
      ref: ref,
      sessionId: sessionId,
      isPageActive: isPageActive,
    )) {
      return;
    }
    try {
      if (!_needsHeroMetadataRefresh(target)) {
        return;
      }
      final workingTarget = _ensureHeroSearchQuery(target);
      final cacheRepository = ref.read(localStorageCacheRepositoryProvider);

      if (workingTarget.sourceKind == MediaSourceKind.nas &&
          workingTarget.sourceId.trim().isNotEmpty &&
          workingTarget.itemId.trim().isNotEmpty) {
        final updatedTarget = await ref
            .read(nasMediaIndexerProvider)
            .enrichDetailTargetMetadataIfNeeded(workingTarget);
        if (!_isRefreshSessionActive(
          ref: ref,
          sessionId: sessionId,
          isPageActive: isPageActive,
        )) {
          return;
        }
        final resolvedTarget = updatedTarget ?? workingTarget;
        if (!_heroMetadataRefreshProducedUpdate(target, resolvedTarget)) {
          return;
        }
        await cacheRepository.saveDetailTarget(
          seedTarget: target,
          resolvedTarget: resolvedTarget,
        );
        return;
      }

      final settings = ref.read(appSettingsProvider);
      if (!_canAttemptHeroMetadataRefresh(settings, workingTarget)) {
        if (target.searchQuery.trim() != workingTarget.searchQuery.trim()) {
          await cacheRepository.saveDetailTarget(
            seedTarget: target,
            resolvedTarget: workingTarget,
          );
        }
        return;
      }

      if (!_isRefreshSessionActive(
        ref: ref,
        sessionId: sessionId,
        isPageActive: isPageActive,
      )) {
        return;
      }

      final refreshStatus =
          await cacheRepository.loadDetailMetadataRefreshStatus(target);
      if (!_isRefreshSessionActive(
        ref: ref,
        sessionId: sessionId,
        isPageActive: isPageActive,
      )) {
        return;
      }
      if (refreshStatus != DetailMetadataRefreshStatus.never) {
        return;
      }

      try {
        final updatedTarget =
            await ref.read(enrichedDetailTargetProvider(workingTarget).future);
        if (!_isRefreshSessionActive(
          ref: ref,
          sessionId: sessionId,
          isPageActive: isPageActive,
        )) {
          return;
        }
        await cacheRepository.saveDetailTarget(
          seedTarget: target,
          resolvedTarget: updatedTarget,
          metadataRefreshStatus:
              _heroMetadataRefreshProducedUpdate(target, updatedTarget)
                  ? DetailMetadataRefreshStatus.succeeded
                  : DetailMetadataRefreshStatus.failed,
        );
      } catch (_) {
        if (!_isRefreshSessionActive(
          ref: ref,
          sessionId: sessionId,
          isPageActive: isPageActive,
        )) {
          return;
        }
        await cacheRepository.saveDetailTarget(
          seedTarget: target,
          resolvedTarget: target,
          metadataRefreshStatus: DetailMetadataRefreshStatus.failed,
        );
      }
    } catch (_) {
      // Background hero refresh is best-effort.
    }
  }

  String _heroMetadataRefreshKey(MediaDetailTarget target) {
    final parts = [
      target.sourceKind?.name ?? '',
      target.sourceId.trim(),
      target.itemId.trim(),
      target.doubanId.trim(),
      target.imdbId.trim().toLowerCase(),
      target.tmdbId.trim(),
      target.title.trim().toLowerCase(),
    ].where((item) => item.isNotEmpty).toList(growable: false);
    return parts.join('|');
  }

  bool _needsHeroMetadataRefresh(MediaDetailTarget target) {
    final hasHeroWideVisual = target.backdropUrl.trim().isNotEmpty ||
        target.bannerUrl.trim().isNotEmpty ||
        target.extraBackdropUrls.any((item) => item.trim().isNotEmpty);
    final hasHeroTitleVisual = target.logoUrl.trim().isNotEmpty;
    final missingSearchQuery = target.searchQuery.trim().isEmpty;
    return target.needsMetadataMatch ||
        target.needsImdbRatingMatch ||
        missingSearchQuery ||
        !hasHeroWideVisual ||
        !hasHeroTitleVisual;
  }

  bool _canAttemptHeroMetadataRefresh(
    AppSettings settings,
    MediaDetailTarget target,
  ) {
    final query =
        (target.searchQuery.trim().isEmpty ? target.title : target.searchQuery)
            .trim();
    if (query.isEmpty && target.doubanId.trim().isEmpty) {
      return false;
    }

    final needsWmdb = settings.wmdbMetadataMatchEnabled &&
        (target.needsMetadataMatch ||
            _missingRatingKeyword(target.ratingLabels, '豆瓣') ||
            target.needsImdbRatingMatch ||
            target.doubanId.trim().isEmpty ||
            target.imdbId.trim().isEmpty);
    final needsTmdb = settings.tmdbMetadataMatchEnabled &&
        settings.tmdbReadAccessToken.trim().isNotEmpty &&
        (target.needsMetadataMatch ||
            target.backdropUrl.trim().isEmpty ||
            target.logoUrl.trim().isEmpty);
    return needsWmdb || needsTmdb;
  }

  bool _heroMetadataRefreshProducedUpdate(
    MediaDetailTarget current,
    MediaDetailTarget next,
  ) {
    if (!_needsHeroMetadataRefresh(next)) {
      return true;
    }
    return current.posterUrl.trim() != next.posterUrl.trim() ||
        current.searchQuery.trim() != next.searchQuery.trim() ||
        current.backdropUrl.trim() != next.backdropUrl.trim() ||
        current.logoUrl.trim() != next.logoUrl.trim() ||
        current.bannerUrl.trim() != next.bannerUrl.trim() ||
        !listEquals(current.extraBackdropUrls, next.extraBackdropUrls) ||
        current.overview.trim() != next.overview.trim() ||
        current.durationLabel.trim() != next.durationLabel.trim() ||
        current.year != next.year ||
        !listEquals(current.ratingLabels, next.ratingLabels) ||
        !listEquals(current.genres, next.genres) ||
        !listEquals(current.directors, next.directors) ||
        !listEquals(current.actors, next.actors) ||
        current.doubanId.trim() != next.doubanId.trim() ||
        current.imdbId.trim().toLowerCase() !=
            next.imdbId.trim().toLowerCase() ||
        current.tmdbId.trim() != next.tmdbId.trim() ||
        current.tvdbId.trim() != next.tvdbId.trim();
  }

  bool _missingRatingKeyword(Iterable<String> labels, String keyword) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.isEmpty) {
      return false;
    }
    return !labels.any(
      (label) => label.trim().toLowerCase().contains(normalizedKeyword),
    );
  }

  MediaDetailTarget _ensureHeroSearchQuery(MediaDetailTarget target) {
    final existingQuery = target.searchQuery.trim();
    if (existingQuery.isNotEmpty) {
      return target;
    }
    final playbackSeriesTitle =
        target.playbackTarget?.resolvedSeriesTitle ?? '';
    final derivedQuery = [
      playbackSeriesTitle,
      target.title,
    ].map((item) => item.trim()).firstWhere(
          (item) => item.isNotEmpty,
          orElse: () => '',
        );
    if (derivedQuery.isEmpty) {
      return target;
    }
    return target.copyWith(searchQuery: derivedQuery);
  }
}
