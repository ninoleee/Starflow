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

  void _log(String message) {
    debugPrint('[HomeHeroPrefetch] $message');
  }

  void reset() {
    _refreshSessionId += 1;
    _scheduledRefreshKeys.clear();
    _log('coordinator.reset session=$_refreshSessionId');
  }

  void clearScheduled() {
    _scheduledRefreshKeys.clear();
  }

  void schedulePrefetch({
    required WidgetRef ref,
    required Iterable<MediaDetailTarget> targets,
    required bool Function() isPageActive,
    bool forceMetadataRefresh = false,
  }) {
    final pageActive = isPageActive();
    final enrichmentSuspended = ref.read(backgroundEnrichmentSuspendedProvider);
    if (!pageActive || enrichmentSuspended) {
      _log(
        'schedule.skip pageActive=$pageActive '
        'enrichmentSuspended=$enrichmentSuspended '
        'force=$forceMetadataRefresh',
      );
      return;
    }
    final sessionId = _refreshSessionId;
    final candidates = <MediaDetailTarget>[];
    for (final target in targets) {
      final refreshKey = _heroMetadataRefreshKey(target);
      final needsRefresh = _needsHeroMetadataRefresh(target);
      _log(
        'schedule.inspect session=$sessionId '
        'title=${target.title} '
        'key=$refreshKey '
        'force=$forceMetadataRefresh '
        'needsRefresh=$needsRefresh '
        'backdrop=${target.backdropUrl.trim().isNotEmpty} '
        'logo=${target.logoUrl.trim().isNotEmpty} '
        'overview=${target.overview.trim().isNotEmpty} '
        'query=${target.searchQuery.trim().isNotEmpty} '
        'metadataMatch=${target.needsMetadataMatch} '
        'imdbMatch=${target.needsImdbRatingMatch}',
      );
      if (!_needsHeroMetadataRefresh(target)) {
        _log(
          'schedule.filtered title=${target.title} reason=no-missing-hero-metadata',
        );
        continue;
      }
      if (refreshKey.isEmpty || !_scheduledRefreshKeys.add(refreshKey)) {
        _log(
          'schedule.filtered title=${target.title} '
          'reason=${refreshKey.isEmpty ? 'empty-key' : 'already-scheduled'}',
        );
        continue;
      }
      candidates.add(target);
    }
    if (candidates.isEmpty) {
      _log('schedule.skip session=$sessionId reason=no-candidates');
      return;
    }
    _log(
      'schedule.ready session=$sessionId '
      'candidates=${candidates.length} '
      'force=$forceMetadataRefresh',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isRefreshSessionActive(
        ref: ref,
        sessionId: sessionId,
        isPageActive: isPageActive,
      )) {
        _log('schedule.cancelled session=$sessionId reason=session-inactive');
        return;
      }
      unawaited(
        _refreshMetadataInBackground(
          ref: ref,
          targets: candidates,
          sessionId: sessionId,
          isPageActive: isPageActive,
          forceMetadataRefresh: forceMetadataRefresh,
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
    required bool forceMetadataRefresh,
  }) async {
    if (!_isRefreshSessionActive(
      ref: ref,
      sessionId: sessionId,
      isPageActive: isPageActive,
    )) {
      _log('refresh.skip session=$sessionId reason=session-inactive');
      return;
    }
    _log(
      'refresh.start session=$sessionId targets=${targets.length} force=$forceMetadataRefresh',
    );
    try {
      await Future.wait(
        targets.map(
          (target) => _refreshSingleMetadataIfNeeded(
            ref: ref,
            target: target,
            sessionId: sessionId,
            isPageActive: isPageActive,
            forceMetadataRefresh: forceMetadataRefresh,
          ),
        ),
        eagerError: false,
      );
    } catch (_) {
      // Hero metadata refresh is best-effort and should never block home UI.
      _log('refresh.failed session=$sessionId reason=unexpected-error');
    }
  }

  Future<void> _refreshSingleMetadataIfNeeded({
    required WidgetRef ref,
    required MediaDetailTarget target,
    required int sessionId,
    required bool Function() isPageActive,
    required bool forceMetadataRefresh,
  }) async {
    if (!_isRefreshSessionActive(
      ref: ref,
      sessionId: sessionId,
      isPageActive: isPageActive,
    )) {
      _log(
        'target.skip title=${target.title} session=$sessionId reason=session-inactive',
      );
      return;
    }
    try {
      if (!_needsHeroMetadataRefresh(target)) {
        _log(
          'target.skip title=${target.title} session=$sessionId reason=no-missing-hero-metadata',
        );
        return;
      }
      final workingTarget = _ensureHeroSearchQuery(target);
      final cacheRepository = ref.read(localStorageCacheRepositoryProvider);
      _log(
        'target.start title=${target.title} session=$sessionId '
        'force=$forceMetadataRefresh '
        'query=${workingTarget.searchQuery} '
        'sourceKind=${workingTarget.sourceKind?.name ?? 'unknown'} '
        'sourceId=${workingTarget.sourceId} '
        'itemId=${workingTarget.itemId}',
      );

      if (workingTarget.sourceKind == MediaSourceKind.nas &&
          workingTarget.sourceId.trim().isNotEmpty &&
          workingTarget.itemId.trim().isNotEmpty) {
        _log('target.nas.start title=${target.title} session=$sessionId');
        final updatedTarget = await ref
            .read(nasMediaIndexerProvider)
            .enrichDetailTargetMetadataIfNeeded(workingTarget);
        if (!_isRefreshSessionActive(
          ref: ref,
          sessionId: sessionId,
          isPageActive: isPageActive,
        )) {
          _log(
            'target.nas.skip title=${target.title} session=$sessionId reason=session-inactive-after-enrich',
          );
          return;
        }
        final resolvedTarget = updatedTarget ?? workingTarget;
        if (!_heroMetadataRefreshProducedUpdate(target, resolvedTarget)) {
          _log(
            'target.nas.skip title=${target.title} session=$sessionId reason=no-visible-update',
          );
          return;
        }
        await cacheRepository.saveDetailTarget(
          seedTarget: target,
          resolvedTarget: resolvedTarget,
        );
        _log(
          'target.nas.saved title=${target.title} session=$sessionId '
          'backdrop=${resolvedTarget.backdropUrl.trim().isNotEmpty} '
          'logo=${resolvedTarget.logoUrl.trim().isNotEmpty} '
          'overview=${resolvedTarget.overview.trim().isNotEmpty}',
        );
        return;
      }

      final settings = ref.read(appSettingsProvider);
      if (!_canAttemptHeroMetadataRefresh(settings, workingTarget)) {
        _log(
          'target.skip title=${target.title} session=$sessionId '
          'reason=settings-or-query-blocked '
          'wmdb=${settings.wmdbMetadataMatchEnabled} '
          'tmdb=${settings.tmdbMetadataMatchEnabled} '
          'tmdbToken=${settings.tmdbReadAccessToken.trim().isNotEmpty} '
          'query=${workingTarget.searchQuery.isNotEmpty} '
          'douban=${workingTarget.doubanId.trim().isNotEmpty}',
        );
        if (target.searchQuery.trim() != workingTarget.searchQuery.trim()) {
          await cacheRepository.saveDetailTarget(
            seedTarget: target,
            resolvedTarget: workingTarget,
          );
          _log(
            'target.saved-derived-query title=${target.title} session=$sessionId query=${workingTarget.searchQuery}',
          );
        }
        return;
      }

      if (!_isRefreshSessionActive(
        ref: ref,
        sessionId: sessionId,
        isPageActive: isPageActive,
      )) {
        _log(
          'target.skip title=${target.title} session=$sessionId reason=session-inactive-before-status',
        );
        return;
      }

      if (!forceMetadataRefresh) {
        final refreshStatus =
            await cacheRepository.loadDetailMetadataRefreshStatus(target);
        _log(
          'target.status title=${target.title} session=$sessionId status=${refreshStatus.name}',
        );
        if (!_isRefreshSessionActive(
          ref: ref,
          sessionId: sessionId,
          isPageActive: isPageActive,
        )) {
          _log(
            'target.skip title=${target.title} session=$sessionId reason=session-inactive-after-status',
          );
          return;
        }
        if (refreshStatus != DetailMetadataRefreshStatus.never) {
          _log(
            'target.skip title=${target.title} session=$sessionId reason=status-blocked status=${refreshStatus.name}',
          );
          return;
        }
      }

      try {
        _log('target.enrich.start title=${target.title} session=$sessionId');
        final updatedTarget =
            await ref.read(enrichedDetailTargetProvider(workingTarget).future);
        if (!_isRefreshSessionActive(
          ref: ref,
          sessionId: sessionId,
          isPageActive: isPageActive,
        )) {
          _log(
            'target.skip title=${target.title} session=$sessionId reason=session-inactive-after-enrich',
          );
          return;
        }
        final producedUpdate =
            _heroMetadataRefreshProducedUpdate(target, updatedTarget);
        await cacheRepository.saveDetailTarget(
          seedTarget: target,
          resolvedTarget: updatedTarget,
          metadataRefreshStatus: producedUpdate
              ? DetailMetadataRefreshStatus.succeeded
              : DetailMetadataRefreshStatus.failed,
        );
        _log(
          'target.enrich.saved title=${target.title} session=$sessionId '
          'producedUpdate=$producedUpdate '
          'backdrop=${updatedTarget.backdropUrl.trim().isNotEmpty} '
          'logo=${updatedTarget.logoUrl.trim().isNotEmpty} '
          'overview=${updatedTarget.overview.trim().isNotEmpty} '
          'searchQuery=${updatedTarget.searchQuery}',
        );
      } catch (_) {
        if (!_isRefreshSessionActive(
          ref: ref,
          sessionId: sessionId,
          isPageActive: isPageActive,
        )) {
          _log(
            'target.skip title=${target.title} session=$sessionId reason=session-inactive-after-enrich-error',
          );
          return;
        }
        await cacheRepository.saveDetailTarget(
          seedTarget: target,
          resolvedTarget: target,
          metadataRefreshStatus: DetailMetadataRefreshStatus.failed,
        );
        _log(
          'target.enrich.failed title=${target.title} session=$sessionId reason=provider-threw',
        );
      }
    } catch (_) {
      // Background hero refresh is best-effort.
      _log(
        'target.failed title=${target.title} session=$sessionId reason=unexpected-error',
      );
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
