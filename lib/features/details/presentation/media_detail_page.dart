import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/debug_trace_once.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/person_credits_page.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/metadata_match_resolver.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/application/playback_session.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

final enrichedDetailTargetProvider =
    FutureProvider.autoDispose.family<MediaDetailTarget, MediaDetailTarget>((
  ref,
  target,
) async {
  final backgroundWorkSuspended = ref.watch(backgroundWorkSuspendedProvider);
  final settings = ref.watch(appSettingsProvider);
  if (backgroundWorkSuspended) {
    final localStorageCacheRepository =
        ref.read(localStorageCacheRepositoryProvider);
    final cachedTarget =
        await localStorageCacheRepository.loadDetailTarget(target);
    return cachedTarget == null
        ? target
        : _mergeCachedDetailTarget(
            current: target,
            cached: cachedTarget,
          );
  }
  return _resolveDetailTargetIfNeeded(
    ref: ref,
    settings: settings,
    target: target,
  );
});

Future<MediaDetailTarget> _resolveDetailTargetIfNeeded({
  required Ref ref,
  required AppSettings settings,
  required MediaDetailTarget target,
}) async {
  final traceKey = _detailTraceKey(target);
  DebugTraceOnce.logMetadata(
    traceKey,
    'start',
    'title=${target.title} source=${target.sourceKind?.name ?? 'unknown'} '
        'itemId=${target.itemId} doubanId=${target.doubanId} imdbId=${target.imdbId} '
        'poster=${target.posterUrl.trim().isNotEmpty} overview=${target.hasUsefulOverview} '
        'ratings=${target.ratingLabels.join(' | ')}',
  );
  final localStorageCacheRepository = ref.read(
    localStorageCacheRepositoryProvider,
  );

  final cachedTarget =
      await localStorageCacheRepository.loadDetailTarget(target);
  DebugTraceOnce.logMetadata(
    traceKey,
    'cache-load',
    cachedTarget == null
        ? 'cache=miss'
        : 'cache=hit poster=${cachedTarget.posterUrl.trim().isNotEmpty} '
            'backdrop=${cachedTarget.backdropUrl.trim().isNotEmpty} '
            'logo=${cachedTarget.logoUrl.trim().isNotEmpty} '
            'ratings=${cachedTarget.ratingLabels.join(' | ')}',
  );
  var nextTarget = cachedTarget == null
      ? target
      : _mergeCachedDetailTarget(
          current: target,
          cached: cachedTarget,
        );
  if (_shouldAutoEnrichMetadataTarget(
    settings: settings,
    target: nextTarget,
  )) {
    DebugTraceOnce.logMetadata(
      traceKey,
      'auto-enrich',
      'enabled query=${_detailMetadataQuery(nextTarget)} '
          'needsMetadata=${nextTarget.needsMetadataMatch} '
          'needsImdb=${nextTarget.needsImdbRatingMatch}',
    );
    nextTarget = await _resolveAutomaticMetadataIfNeeded(
      settings: settings,
      target: nextTarget,
      wmdbMetadataClient: ref.read(wmdbMetadataClientProvider),
      tmdbMetadataClient: ref.read(tmdbMetadataClientProvider),
      imdbRatingClient: ref.read(imdbRatingClientProvider),
    );
  } else {
    DebugTraceOnce.logMetadata(traceKey, 'auto-enrich', 'skipped');
  }

  Future<void> saveResolvedTarget() async {
    try {
      await localStorageCacheRepository.saveDetailTarget(
        seedTarget: target,
        resolvedTarget: nextTarget,
      );
    } catch (_) {
      // Ignore cache persistence failures.
    }
  }

  final playback = nextTarget.playbackTarget;
  if (playback == null) {
    DebugTraceOnce.logMetadata(
        traceKey, 'playback-resolve', 'skipped no playback target');
    await saveResolvedTarget();
    return nextTarget;
  }

  final shouldResolve = playback.sourceKind == MediaSourceKind.emby &&
      playback.itemId.trim().isNotEmpty &&
      (playback.streamUrl.trim().isEmpty ||
          playback.formatLabel.trim().isEmpty ||
          playback.resolutionLabel.trim().isEmpty ||
          playback.fileSizeLabel.trim().isEmpty);
  if (!shouldResolve) {
    DebugTraceOnce.logMetadata(
      traceKey,
      'playback-resolve',
      'skipped streamReady=${playback.streamUrl.trim().isNotEmpty} '
          'format=${playback.formatLabel.trim().isNotEmpty} '
          'resolution=${playback.resolutionLabel.trim().isNotEmpty} '
          'fileSize=${playback.fileSizeLabel.trim().isNotEmpty}',
    );
    await saveResolvedTarget();
    return nextTarget;
  }

  MediaSourceConfig? source;
  for (final candidate in settings.mediaSources) {
    if (candidate.id == playback.sourceId) {
      source = candidate;
      break;
    }
  }
  if (source == null || !source.hasActiveSession) {
    DebugTraceOnce.logMetadata(
      traceKey,
      'playback-resolve',
      'skipped no active emby source',
    );
    await saveResolvedTarget();
    return nextTarget;
  }

  try {
    DebugTraceOnce.logMetadata(
      traceKey,
      'playback-resolve',
      'request itemId=${playback.itemId} source=${source.name}',
    );
    final resolvedPlayback =
        await ref.read(embyApiClientProvider).resolvePlaybackTarget(
              source: source,
              target: playback,
            );
    nextTarget = nextTarget.copyWith(playbackTarget: resolvedPlayback);
    DebugTraceOnce.logMetadata(
      traceKey,
      'playback-resolve',
      'success format=${resolvedPlayback.formatLabel} '
          'resolution=${resolvedPlayback.resolutionLabel} '
          'size=${resolvedPlayback.fileSizeLabel}',
    );
  } catch (_) {
    DebugTraceOnce.logMetadata(traceKey, 'playback-resolve', 'failed');
    await saveResolvedTarget();
    return nextTarget;
  }

  await saveResolvedTarget();
  DebugTraceOnce.logMetadata(
    traceKey,
    'done',
    'final poster=${nextTarget.posterUrl.trim().isNotEmpty} '
        'backdrop=${nextTarget.backdropUrl.trim().isNotEmpty} '
        'logo=${nextTarget.logoUrl.trim().isNotEmpty} '
        'ratings=${nextTarget.ratingLabels.join(' | ')}',
  );
  return nextTarget;
}

bool _shouldAutoEnrichMetadataTarget({
  required AppSettings settings,
  required MediaDetailTarget target,
}) {
  if (target.sourceKind == MediaSourceKind.nas &&
      target.sourceId.trim().isNotEmpty) {
    return false;
  }
  if (_detailMetadataQuery(target).isEmpty && target.doubanId.trim().isEmpty) {
    return false;
  }

  final needsWmdb = settings.wmdbMetadataMatchEnabled &&
      (target.needsMetadataMatch ||
          _needsRatingLabel(target, keyword: '豆瓣') ||
          target.needsImdbRatingMatch ||
          target.doubanId.trim().isEmpty ||
          target.imdbId.trim().isEmpty);
  final needsTmdb = settings.tmdbMetadataMatchEnabled &&
      settings.tmdbReadAccessToken.trim().isNotEmpty &&
      (target.needsMetadataMatch ||
          target.imdbId.trim().isEmpty ||
          target.backdropUrl.trim().isEmpty ||
          target.logoUrl.trim().isEmpty);
  final needsImdb =
      _shouldUseStandaloneImdbRating(settings) && target.needsImdbRatingMatch;
  return needsWmdb || needsTmdb || needsImdb;
}

String _detailMetadataQuery(MediaDetailTarget target) {
  final raw =
      target.searchQuery.trim().isEmpty ? target.title : target.searchQuery;
  return raw.trim();
}

bool _prefersSeriesMetadata(MediaDetailTarget target) {
  final itemType = target.itemType.trim().toLowerCase();
  return itemType == 'series' || itemType == 'season' || itemType == 'episode';
}

bool _needsRatingLabel(MediaDetailTarget target, {required String keyword}) {
  return !_hasRatingLabelKeyword(target.ratingLabels, keyword);
}

bool _hasRatingLabelKeyword(Iterable<String> labels, String keyword) {
  final normalizedKeyword = keyword.trim().toLowerCase();
  if (normalizedKeyword.isEmpty) {
    return false;
  }
  return labels.any(
    (label) => label.trim().toLowerCase().contains(normalizedKeyword),
  );
}

bool _shouldUseStandaloneImdbRating(AppSettings settings) {
  return settings.imdbRatingMatchEnabled &&
      (!settings.tmdbMetadataMatchEnabled ||
          settings.tmdbReadAccessToken.trim().isEmpty);
}

bool _isEpisodeLikeTarget(MediaDetailTarget target) {
  return target.itemType.trim().toLowerCase() == 'episode' &&
      target.seasonNumber != null &&
      target.seasonNumber! >= 0 &&
      target.episodeNumber != null &&
      target.episodeNumber! > 0;
}

Future<String> _resolveTmdbBackdropForTarget({
  required AppSettings settings,
  required TmdbMetadataClient tmdbMetadataClient,
  required MediaDetailTarget target,
  required TmdbMetadataMatch match,
}) async {
  if (_isEpisodeLikeTarget(target) &&
      match.isSeries &&
      match.tmdbId > 0 &&
      settings.tmdbReadAccessToken.trim().isNotEmpty) {
    try {
      final stillUrl = await tmdbMetadataClient.fetchEpisodeStillUrl(
        seriesId: match.tmdbId,
        seasonNumber: target.seasonNumber!,
        episodeNumber: target.episodeNumber!,
        readAccessToken: settings.tmdbReadAccessToken.trim(),
      );
      if (stillUrl.trim().isNotEmpty) {
        return stillUrl.trim();
      }
    } catch (_) {
      // Ignore episode still failures and keep the title-level backdrop.
    }
  }
  return match.backdropUrl.trim();
}

String _resolveTmdbBannerForTarget({
  required MediaDetailTarget target,
  required TmdbMetadataMatch match,
  required String resolvedBackdropUrl,
}) {
  if (!_isEpisodeLikeTarget(target)) {
    return '';
  }
  final seriesBackdrop = match.backdropUrl.trim();
  if (seriesBackdrop.isEmpty || seriesBackdrop == resolvedBackdropUrl.trim()) {
    return '';
  }
  return seriesBackdrop;
}

List<String> _resolveTmdbExtraBackdropUrlsForTarget({
  required MediaDetailTarget target,
  required TmdbMetadataMatch match,
  required String resolvedBackdropUrl,
}) {
  final bannerUrl = _resolveTmdbBannerForTarget(
    target: target,
    match: match,
    resolvedBackdropUrl: resolvedBackdropUrl,
  );
  return _mergeUniqueImageUrls([
    if (bannerUrl.isNotEmpty) bannerUrl,
    ...match.extraBackdropUrls,
  ])
      .where((item) => item != resolvedBackdropUrl.trim())
      .toList(growable: false);
}

Future<MediaDetailTarget> _resolveAutomaticMetadataIfNeeded({
  required AppSettings settings,
  required MediaDetailTarget target,
  required WmdbMetadataClient wmdbMetadataClient,
  required TmdbMetadataClient tmdbMetadataClient,
  required ImdbRatingClient imdbRatingClient,
  bool forceSearch = false,
  bool forceReplace = false,
}) async {
  var nextTarget = target;
  final initialQuery = _detailMetadataQuery(target);
  final traceKey = _detailTraceKey(target);
  final preferredImdbId = _resolvePreferredImdbId(
    target.imdbId,
    initialQuery,
  );
  var imdbIdMetadataMatched = false;

  if (preferredImdbId.isNotEmpty &&
      settings.tmdbMetadataMatchEnabled &&
      settings.tmdbReadAccessToken.trim().isNotEmpty) {
    try {
      DebugTraceOnce.logMetadata(
        traceKey,
        'tmdb',
        'request imdbId=$preferredImdbId preferSeries=${_prefersSeriesMetadata(nextTarget)}',
      );
      final tmdbMatch = await tmdbMetadataClient.matchByImdbId(
        imdbId: preferredImdbId,
        readAccessToken: settings.tmdbReadAccessToken.trim(),
        preferSeries: _prefersSeriesMetadata(nextTarget),
      );
      if (tmdbMatch != null) {
        imdbIdMetadataMatched = true;
        DebugTraceOnce.logMetadata(
          traceKey,
          'tmdb',
          'matched title=${tmdbMatch.title} imdbId=${tmdbMatch.imdbId}',
        );
        final resolvedBackdropUrl = await _resolveTmdbBackdropForTarget(
          settings: settings,
          tmdbMetadataClient: tmdbMetadataClient,
          target: nextTarget,
          match: tmdbMatch,
        );
        nextTarget = _applyMetadataMatchToDetailTarget(
          nextTarget,
          MetadataMatchResult(
            provider: MetadataMatchProvider.tmdb,
            title: tmdbMatch.title,
            originalTitle: tmdbMatch.originalTitle,
            posterUrl: tmdbMatch.posterUrl,
            backdropUrl: resolvedBackdropUrl,
            logoUrl: tmdbMatch.logoUrl,
            bannerUrl: _resolveTmdbBannerForTarget(
              target: nextTarget,
              match: tmdbMatch,
              resolvedBackdropUrl: resolvedBackdropUrl,
            ),
            extraBackdropUrls: _resolveTmdbExtraBackdropUrlsForTarget(
              target: nextTarget,
              match: tmdbMatch,
              resolvedBackdropUrl: resolvedBackdropUrl,
            ),
            overview: tmdbMatch.overview,
            year: tmdbMatch.year,
            durationLabel: tmdbMatch.durationLabel,
            genres: tmdbMatch.genres,
            directors: tmdbMatch.directors,
            directorProfiles: tmdbMatch.directorProfiles
                .map(
                  (item) => MetadataPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                  ),
                )
                .toList(),
            actors: tmdbMatch.actors,
            actorProfiles: tmdbMatch.actorProfiles
                .map(
                  (item) => MetadataPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                  ),
                )
                .toList(),
            platforms: tmdbMatch.platforms,
            platformProfiles: tmdbMatch.platformProfiles
                .map(
                  (item) => MetadataPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                  ),
                )
                .toList(),
            ratingLabels: tmdbMatch.ratingLabels,
            imdbId: tmdbMatch.imdbId,
            tmdbId: '${tmdbMatch.tmdbId}',
          ),
          replaceExisting: forceReplace,
        );
      } else {
        DebugTraceOnce.logMetadata(traceKey, 'tmdb', 'no match');
      }
    } catch (_) {
      DebugTraceOnce.logMetadata(traceKey, 'tmdb', 'failed');
    }
  }

  if (settings.wmdbMetadataMatchEnabled &&
      !imdbIdMetadataMatched &&
      (forceSearch ||
          nextTarget.needsMetadataMatch ||
          _needsRatingLabel(nextTarget, keyword: '豆瓣') ||
          nextTarget.needsImdbRatingMatch ||
          nextTarget.doubanId.trim().isEmpty ||
          nextTarget.imdbId.trim().isEmpty)) {
    try {
      DebugTraceOnce.logMetadata(
        traceKey,
        'wmdb',
        'request query=$initialQuery doubanId=${nextTarget.doubanId}',
      );
      final wmdbMatch = nextTarget.doubanId.trim().isNotEmpty
          ? await wmdbMetadataClient.matchByDoubanId(
              doubanId: nextTarget.doubanId,
            )
          : await wmdbMetadataClient.matchTitle(
              query: initialQuery,
              year: nextTarget.year,
              preferSeries: _prefersSeriesMetadata(nextTarget),
              actors: nextTarget.actors,
            );
      if (wmdbMatch != null) {
        DebugTraceOnce.logMetadata(
          traceKey,
          'wmdb',
          'matched title=${wmdbMatch.title} imdbId=${wmdbMatch.imdbId} '
              'ratings=${wmdbMatch.ratingLabels.join(' | ')}',
        );
        nextTarget = _applyMetadataMatchToDetailTarget(
          nextTarget,
          wmdbMatch,
          replaceExisting: forceReplace,
        );
      } else {
        DebugTraceOnce.logMetadata(traceKey, 'wmdb', 'no match');
      }
    } catch (_) {
      DebugTraceOnce.logMetadata(traceKey, 'wmdb', 'failed');
      // Ignore WMDB failures and continue.
    }
  }

  if (settings.tmdbMetadataMatchEnabled &&
      settings.tmdbReadAccessToken.trim().isNotEmpty &&
      !imdbIdMetadataMatched &&
      (forceSearch || nextTarget.imdbId.trim().isEmpty)) {
    try {
      final currentQuery = _detailMetadataQuery(nextTarget);
      DebugTraceOnce.logMetadata(
        traceKey,
        'tmdb',
        'request query=${currentQuery.isEmpty ? initialQuery : currentQuery} '
            'year=${nextTarget.year} preferSeries=${_prefersSeriesMetadata(nextTarget)}',
      );
      final tmdbMatch = await tmdbMetadataClient.matchTitle(
        query: currentQuery.isEmpty ? initialQuery : currentQuery,
        readAccessToken: settings.tmdbReadAccessToken.trim(),
        year: nextTarget.year,
        preferSeries: _prefersSeriesMetadata(nextTarget),
      );
      if (tmdbMatch != null) {
        DebugTraceOnce.logMetadata(
          traceKey,
          'tmdb',
          'matched title=${tmdbMatch.title} imdbId=${tmdbMatch.imdbId}',
        );
        final resolvedBackdropUrl = await _resolveTmdbBackdropForTarget(
          settings: settings,
          tmdbMetadataClient: tmdbMetadataClient,
          target: nextTarget,
          match: tmdbMatch,
        );
        nextTarget = _applyMetadataMatchToDetailTarget(
          nextTarget,
          MetadataMatchResult(
            provider: MetadataMatchProvider.tmdb,
            title: tmdbMatch.title,
            originalTitle: tmdbMatch.originalTitle,
            posterUrl: tmdbMatch.posterUrl,
            backdropUrl: resolvedBackdropUrl,
            logoUrl: tmdbMatch.logoUrl,
            bannerUrl: _resolveTmdbBannerForTarget(
              target: nextTarget,
              match: tmdbMatch,
              resolvedBackdropUrl: resolvedBackdropUrl,
            ),
            extraBackdropUrls: _resolveTmdbExtraBackdropUrlsForTarget(
              target: nextTarget,
              match: tmdbMatch,
              resolvedBackdropUrl: resolvedBackdropUrl,
            ),
            overview: tmdbMatch.overview,
            year: tmdbMatch.year,
            durationLabel: tmdbMatch.durationLabel,
            genres: tmdbMatch.genres,
            directors: tmdbMatch.directors,
            directorProfiles: tmdbMatch.directorProfiles
                .map(
                  (item) => MetadataPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                  ),
                )
                .toList(),
            actors: tmdbMatch.actors,
            actorProfiles: tmdbMatch.actorProfiles
                .map(
                  (item) => MetadataPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                  ),
                )
                .toList(),
            platforms: tmdbMatch.platforms,
            platformProfiles: tmdbMatch.platformProfiles
                .map(
                  (item) => MetadataPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                  ),
                )
                .toList(),
            ratingLabels: tmdbMatch.ratingLabels,
            imdbId: tmdbMatch.imdbId,
            tmdbId: '${tmdbMatch.tmdbId}',
          ),
          replaceExisting: forceReplace,
        );
      } else {
        DebugTraceOnce.logMetadata(traceKey, 'tmdb', 'no match');
      }
    } catch (_) {
      DebugTraceOnce.logMetadata(traceKey, 'tmdb', 'failed');
      // Ignore TMDB failures and continue.
    }
  }

  if (_shouldUseStandaloneImdbRating(settings) &&
      (forceSearch || nextTarget.needsImdbRatingMatch)) {
    try {
      final currentQuery = _detailMetadataQuery(nextTarget);
      DebugTraceOnce.logMetadata(
        traceKey,
        'imdb',
        'request query=${currentQuery.isEmpty ? initialQuery : currentQuery} '
            'year=${nextTarget.year} imdbId=${nextTarget.imdbId}',
      );
      final ratingMatch = await imdbRatingClient.matchRating(
        query: currentQuery.isEmpty ? initialQuery : currentQuery,
        year: nextTarget.year,
        preferSeries: _prefersSeriesMetadata(nextTarget),
        imdbId: nextTarget.imdbId,
      );
      if (ratingMatch != null) {
        DebugTraceOnce.logMetadata(
          traceKey,
          'imdb',
          'matched rating=${ratingMatch.ratingLabel} imdbId=${ratingMatch.imdbId}',
        );
        final nextRatings = [...nextTarget.ratingLabels];
        final nextRatingLabel = ratingMatch.ratingLabel.trim();
        final hasSameRating = nextRatings.any(
          (label) => label.toLowerCase() == nextRatingLabel.toLowerCase(),
        );
        if (nextRatingLabel.isNotEmpty && !hasSameRating) {
          nextRatings.add(nextRatingLabel);
        }
        nextTarget = nextTarget.copyWith(
          ratingLabels: nextRatings,
          imdbId: forceReplace
              ? _firstNonEmpty(ratingMatch.imdbId, nextTarget.imdbId)
              : (nextTarget.imdbId.trim().isEmpty
                  ? ratingMatch.imdbId
                  : nextTarget.imdbId),
        );
      } else {
        DebugTraceOnce.logMetadata(traceKey, 'imdb', 'no match');
      }
    } catch (_) {
      DebugTraceOnce.logMetadata(traceKey, 'imdb', 'failed');
      // Ignore IMDb failures and continue.
    }
  }

  return nextTarget;
}

String _resolvePreferredImdbId(String currentImdbId, String query) {
  final normalizedCurrent = _normalizeImdbId(currentImdbId);
  if (normalizedCurrent.isNotEmpty) {
    return normalizedCurrent;
  }
  return _extractImdbIdFromText(query);
}

String _extractImdbIdFromText(String value) {
  final match =
      RegExp(r'\btt\d{7,9}\b', caseSensitive: false).firstMatch(value);
  return _normalizeImdbId(match?.group(0) ?? '');
}

String _normalizeImdbId(String value) {
  final trimmed = value.trim().toLowerCase();
  if (!RegExp(r'^tt\d{7,9}$').hasMatch(trimmed)) {
    return '';
  }
  return trimmed;
}

String _detailTraceKey(MediaDetailTarget target) {
  final id = [
    target.title.trim(),
    target.searchQuery.trim(),
    target.sourceId.trim(),
    target.itemId.trim(),
    target.doubanId.trim(),
    target.tmdbId.trim(),
  ].where((item) => item.isNotEmpty).join('|');
  return id.isEmpty ? 'detail' : id;
}

MediaDetailTarget _mergeCachedDetailTarget({
  required MediaDetailTarget current,
  required MediaDetailTarget cached,
}) {
  final preferCachedResourceState = _hasResolvedLocalResourceState(cached) &&
      !_hasResolvedLocalResourceState(current);
  final preferCachedAvailability =
      _shouldPreferCachedAvailability(current, cached) ||
          preferCachedResourceState;
  final preferCachedSourceContext =
      _shouldPreferCachedSourceContext(current, cached) ||
          preferCachedResourceState;
  return current.copyWith(
    posterUrl: current.posterUrl.trim().isNotEmpty
        ? current.posterUrl
        : cached.posterUrl,
    posterHeaders: current.posterHeaders.isNotEmpty
        ? current.posterHeaders
        : cached.posterHeaders,
    backdropUrl: current.backdropUrl.trim().isNotEmpty
        ? current.backdropUrl
        : cached.backdropUrl,
    backdropHeaders: current.backdropHeaders.isNotEmpty
        ? current.backdropHeaders
        : cached.backdropHeaders,
    logoUrl:
        current.logoUrl.trim().isNotEmpty ? current.logoUrl : cached.logoUrl,
    logoHeaders: current.logoHeaders.isNotEmpty
        ? current.logoHeaders
        : cached.logoHeaders,
    bannerUrl: current.bannerUrl.trim().isNotEmpty
        ? current.bannerUrl
        : cached.bannerUrl,
    bannerHeaders: current.bannerHeaders.isNotEmpty
        ? current.bannerHeaders
        : cached.bannerHeaders,
    extraBackdropUrls: _mergeUniqueImageUrls([
      ...current.extraBackdropUrls,
      ...cached.extraBackdropUrls,
    ]),
    extraBackdropHeaders: current.extraBackdropHeaders.isNotEmpty
        ? current.extraBackdropHeaders
        : cached.extraBackdropHeaders,
    overview: current.hasUsefulOverview ? current.overview : cached.overview,
    year: current.year > 0 ? current.year : cached.year,
    durationLabel: current.durationLabel.trim().isNotEmpty
        ? current.durationLabel
        : cached.durationLabel,
    ratingLabels: _mergeLabels(current.ratingLabels, cached.ratingLabels),
    genres: current.genres.isNotEmpty ? current.genres : cached.genres,
    directors:
        current.directors.isNotEmpty ? current.directors : cached.directors,
    directorProfiles: current.directorProfiles.isNotEmpty
        ? current.directorProfiles
        : cached.directorProfiles,
    actors: current.actors.isNotEmpty ? current.actors : cached.actors,
    actorProfiles: current.actorProfiles.isNotEmpty
        ? current.actorProfiles
        : cached.actorProfiles,
    platforms:
        current.platforms.isNotEmpty ? current.platforms : cached.platforms,
    platformProfiles: current.platformProfiles.isNotEmpty
        ? current.platformProfiles
        : cached.platformProfiles,
    availabilityLabel: preferCachedAvailability
        ? (cached.availabilityLabel.trim().isNotEmpty
            ? cached.availabilityLabel
            : current.availabilityLabel)
        : (current.availabilityLabel.trim().isNotEmpty
            ? current.availabilityLabel
            : cached.availabilityLabel),
    searchQuery: current.searchQuery.trim().isNotEmpty
        ? current.searchQuery
        : cached.searchQuery,
    playbackTarget: _mergeCachedPlaybackTarget(
      current.playbackTarget,
      cached.playbackTarget,
    ),
    itemId: current.itemId.trim().isNotEmpty ? current.itemId : cached.itemId,
    sourceId:
        current.sourceId.trim().isNotEmpty ? current.sourceId : cached.sourceId,
    itemType: preferCachedResourceState
        ? (cached.itemType.trim().isNotEmpty
            ? cached.itemType
            : current.itemType)
        : (current.itemType.trim().isNotEmpty
            ? current.itemType
            : cached.itemType),
    sectionId: current.sectionId.trim().isNotEmpty
        ? current.sectionId
        : cached.sectionId,
    sectionName: current.sectionName.trim().isNotEmpty
        ? current.sectionName
        : cached.sectionName,
    resourcePath: current.resourcePath.trim().isNotEmpty
        ? current.resourcePath
        : cached.resourcePath,
    doubanId:
        current.doubanId.trim().isNotEmpty ? current.doubanId : cached.doubanId,
    imdbId: current.imdbId.trim().isNotEmpty ? current.imdbId : cached.imdbId,
    tmdbId: current.tmdbId.trim().isNotEmpty ? current.tmdbId : cached.tmdbId,
    tvdbId: current.tvdbId.trim().isNotEmpty ? current.tvdbId : cached.tvdbId,
    wikidataId: current.wikidataId.trim().isNotEmpty
        ? current.wikidataId
        : cached.wikidataId,
    tmdbSetId: current.tmdbSetId.trim().isNotEmpty
        ? current.tmdbSetId
        : cached.tmdbSetId,
    providerIds: current.providerIds.isNotEmpty
        ? current.providerIds
        : cached.providerIds,
    sourceKind: preferCachedSourceContext
        ? (cached.sourceKind ?? current.sourceKind)
        : (current.sourceKind ?? cached.sourceKind),
    sourceName: preferCachedSourceContext
        ? (cached.sourceName.trim().isNotEmpty
            ? cached.sourceName
            : current.sourceName)
        : (current.sourceName.trim().isNotEmpty
            ? current.sourceName
            : cached.sourceName),
    seasonNumber: preferCachedResourceState
        ? (cached.seasonNumber ?? current.seasonNumber)
        : (current.seasonNumber ?? cached.seasonNumber),
    episodeNumber: preferCachedResourceState
        ? (cached.episodeNumber ?? current.episodeNumber)
        : (current.episodeNumber ?? cached.episodeNumber),
  );
}

bool _hasResolvedLocalResourceState(MediaDetailTarget target) {
  if (target.playbackTarget?.canPlay == true) {
    return true;
  }
  if (target.sourceId.trim().isNotEmpty && target.itemId.trim().isNotEmpty) {
    return true;
  }
  if (!_isUnavailableAvailabilityLabel(target.availabilityLabel) &&
      (target.sourceName.trim().isNotEmpty ||
          target.resourcePath.trim().isNotEmpty)) {
    return true;
  }
  return false;
}

bool _shouldPreferCachedAvailability(
  MediaDetailTarget current,
  MediaDetailTarget cached,
) {
  final cachedAvailability = cached.availabilityLabel.trim();
  if (cachedAvailability.isEmpty ||
      _isUnavailableAvailabilityLabel(cachedAvailability)) {
    return false;
  }
  final currentAvailability = current.availabilityLabel.trim();
  return currentAvailability.isEmpty ||
      _isUnavailableAvailabilityLabel(currentAvailability);
}

bool _shouldPreferCachedSourceContext(
  MediaDetailTarget current,
  MediaDetailTarget cached,
) {
  if (!_hasResolvedLocalResourceState(cached)) {
    return false;
  }
  final currentHasResolvedIdentity =
      current.sourceId.trim().isNotEmpty && current.itemId.trim().isNotEmpty;
  if (!currentHasResolvedIdentity) {
    return true;
  }
  if (current.sourceKind == null && cached.sourceKind != null) {
    return true;
  }
  if (current.sourceName.trim().isEmpty &&
      cached.sourceName.trim().isNotEmpty) {
    return true;
  }
  return false;
}

PlaybackTarget? _mergeCachedPlaybackTarget(
  PlaybackTarget? current,
  PlaybackTarget? cached,
) {
  if (current == null) {
    return cached;
  }
  if (cached == null) {
    return current;
  }
  return PlaybackTarget(
    title: current.title.trim().isNotEmpty ? current.title : cached.title,
    sourceId:
        current.sourceId.trim().isNotEmpty ? current.sourceId : cached.sourceId,
    streamUrl: current.streamUrl.trim().isNotEmpty
        ? current.streamUrl
        : cached.streamUrl,
    sourceName: current.sourceName.trim().isNotEmpty
        ? current.sourceName
        : cached.sourceName,
    sourceKind: current.sourceKind,
    actualAddress: current.actualAddress.trim().isNotEmpty
        ? current.actualAddress
        : cached.actualAddress,
    itemId: current.itemId.trim().isNotEmpty ? current.itemId : cached.itemId,
    itemType:
        current.itemType.trim().isNotEmpty ? current.itemType : cached.itemType,
    year: current.year > 0 ? current.year : cached.year,
    seriesId:
        current.seriesId.trim().isNotEmpty ? current.seriesId : cached.seriesId,
    seriesTitle: current.seriesTitle.trim().isNotEmpty
        ? current.seriesTitle
        : cached.seriesTitle,
    preferredMediaSourceId: current.preferredMediaSourceId.trim().isNotEmpty
        ? current.preferredMediaSourceId
        : cached.preferredMediaSourceId,
    subtitle:
        current.subtitle.trim().isNotEmpty ? current.subtitle : cached.subtitle,
    headers: current.headers.isNotEmpty ? current.headers : cached.headers,
    container: current.container.trim().isNotEmpty
        ? current.container
        : cached.container,
    videoCodec: current.videoCodec.trim().isNotEmpty
        ? current.videoCodec
        : cached.videoCodec,
    audioCodec: current.audioCodec.trim().isNotEmpty
        ? current.audioCodec
        : cached.audioCodec,
    seasonNumber: current.seasonNumber ?? cached.seasonNumber,
    episodeNumber: current.episodeNumber ?? cached.episodeNumber,
    width: current.width ?? cached.width,
    height: current.height ?? cached.height,
    bitrate: current.bitrate ?? cached.bitrate,
    fileSizeBytes: current.fileSizeBytes ?? cached.fileSizeBytes,
  );
}

bool _hasMetadataChanged(
  MediaDetailTarget current,
  MediaDetailTarget next,
) {
  return current.posterUrl != next.posterUrl ||
      current.backdropUrl != next.backdropUrl ||
      current.logoUrl != next.logoUrl ||
      current.bannerUrl != next.bannerUrl ||
      !_sameStrings(current.extraBackdropUrls, next.extraBackdropUrls) ||
      current.overview != next.overview ||
      current.year != next.year ||
      current.durationLabel != next.durationLabel ||
      !_sameStrings(current.ratingLabels, next.ratingLabels) ||
      !_sameStrings(current.genres, next.genres) ||
      !_sameStrings(current.directors, next.directors) ||
      !_samePeople(
        current.directorProfiles,
        next.directorProfiles,
      ) ||
      !_sameStrings(current.actors, next.actors) ||
      !_samePeople(
        current.actorProfiles,
        next.actorProfiles,
      ) ||
      !_sameStrings(current.platforms, next.platforms) ||
      !_samePeople(
        current.platformProfiles,
        next.platformProfiles,
      ) ||
      current.doubanId != next.doubanId ||
      current.imdbId != next.imdbId ||
      current.tmdbId != next.tmdbId ||
      current.tvdbId != next.tvdbId ||
      current.wikidataId != next.wikidataId ||
      current.tmdbSetId != next.tmdbSetId ||
      !_sameMaps(current.providerIds, next.providerIds);
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _samePeople(
  List<MediaPersonProfile> left,
  List<MediaPersonProfile> right,
) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index].name != right[index].name ||
        left[index].avatarUrl != right[index].avatarUrl) {
      return false;
    }
  }
  return true;
}

Future<MetadataMatchResult?> _tryPreferredMetadataMatch({
  required MetadataMatchResolver metadataMatchResolver,
  required AppSettings settings,
  required MediaDetailTarget target,
  required String query,
}) async {
  try {
    return await metadataMatchResolver.match(
      settings: settings,
      request: MetadataMatchRequest(
        query: query,
        doubanId: target.doubanId,
        year: target.year,
        preferSeries: _prefersSeriesMetadata(target),
        actors: target.actors,
      ),
    );
  } catch (_) {
    return null;
  }
}

Future<List<_LibraryMatchCandidate>> _findAllLibraryMatchCandidates({
  required MediaRepository mediaRepository,
  required NasMediaIndexer nasMediaIndexer,
  required List<MediaSourceConfig> allowedSources,
  required _LibraryMatchTaskController controller,
  required MediaDetailTarget target,
  required String query,
  MetadataMatchResult? metadataMatch,
  void Function(List<_LibraryMatchCandidate> matches)? onProgress,
}) async {
  const detailLibraryMatchLimit = 2000;
  const maxMatches = 32;
  const maxConcurrentTasks = 4;
  final titles = _buildManualMatchTitles(
    target: target,
    query: query,
    metadataMatch: metadataMatch,
  );
  final year = _resolveManualMatchYear(target, metadataMatch);

  final byId = <String, _LibraryMatchCandidate>{};
  void upsert(_LibraryMatchCandidate c) {
    final ex = byId[c.item.id];
    if (ex == null || c.score > ex.score) {
      byId[c.item.id] = c;
    }
  }

  List<_LibraryMatchCandidate> snapshot() {
    final out = byId.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (out.length <= maxMatches) {
      return out;
    }
    return out.take(maxMatches).toList(growable: false);
  }

  List<_LibraryMatchCandidate> buildCandidates(List<MediaItem> items) {
    controller.throwIfCancelled();
    final matches = <_LibraryMatchCandidate>[];
    final doubanId = _resolveManualMatchDoubanId(target, metadataMatch);
    final imdbId = _resolveManualMatchImdbId(target, metadataMatch);
    final tmdbId = _resolveManualMatchTmdbId(target, metadataMatch);
    final tvdbId = _resolveManualMatchTvdbId(target);
    final wikidataId = _resolveManualMatchWikidataId(target);
    final hasExternalIds = doubanId.trim().isNotEmpty ||
        imdbId.trim().isNotEmpty ||
        tmdbId.trim().isNotEmpty ||
        tvdbId.trim().isNotEmpty ||
        wikidataId.trim().isNotEmpty;
    final exactMatchedItems = listMediaItemsMatchingExternalIds(
      items,
      doubanId: doubanId,
      imdbId: imdbId,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      wikidataId: wikidataId,
    );
    for (final exactMatched in exactMatchedItems) {
      matches.add(
        _LibraryMatchCandidate(
          item: exactMatched,
          matchReason: _externalIdMatchReason(
            exactMatched,
            doubanId: doubanId,
            imdbId: imdbId,
            tmdbId: tmdbId,
            tvdbId: tvdbId,
            wikidataId: wikidataId,
          ),
          score: 1e9,
        ),
      );
    }
    if (hasExternalIds) {
      return matches;
    }
    for (final scored in listScoredMediaItemsMatchingTitles(
      items,
      titles: titles,
      year: year,
      maxResults: maxMatches,
    )) {
      controller.throwIfCancelled();
      matches.add(
        _LibraryMatchCandidate(
          item: scored.item,
          matchReason: _titleMatchReason(year),
          score: scored.score,
        ),
      );
    }
    return matches;
  }

  final taskFactories = <Future<List<_LibraryMatchCandidate>> Function()>[];
  final allowedEmbySources = allowedSources
      .where((source) => source.kind == MediaSourceKind.emby)
      .toList(growable: false);
  for (final source in allowedEmbySources) {
    controller.throwIfCancelled();
    List<MediaCollection> collections;
    try {
      collections = await mediaRepository.fetchCollections(
        kind: MediaSourceKind.emby,
        sourceId: source.id,
      );
      controller.throwIfCancelled();
    } catch (_) {
      collections = const [];
    }
    if (collections.isEmpty) {
      continue;
    }

    final rankedCollections = collections.toList()
      ..sort((left, right) {
        final rightScore = _scoreManualMatchCollection(
          right,
          target,
          metadataMatch: metadataMatch,
        );
        final leftScore = _scoreManualMatchCollection(
          left,
          target,
          metadataMatch: metadataMatch,
        );
        final scoreDelta = rightScore.compareTo(leftScore);
        if (scoreDelta != 0) {
          return scoreDelta;
        }
        return left.title.compareTo(right.title);
      });
    for (final collection in rankedCollections) {
      taskFactories.add(() async {
        controller.throwIfCancelled();
        try {
          final items = await mediaRepository.fetchLibrary(
            kind: MediaSourceKind.emby,
            sourceId: collection.sourceId,
            sectionId: collection.id,
            limit: detailLibraryMatchLimit,
          );
          controller.throwIfCancelled();
          return buildCandidates(items);
        } on _LibraryMatchCancelledException {
          rethrow;
        } catch (_) {
          return const <_LibraryMatchCandidate>[];
        }
      });
    }
  }

  final allowedNasSources = allowedSources
      .where((source) => source.kind == MediaSourceKind.nas)
      .toList(growable: false);
  for (final source in allowedNasSources) {
    taskFactories.add(() async {
      controller.throwIfCancelled();
      try {
        final nasLibrary = await nasMediaIndexer.loadCachedLibraryMatchItems(
          source,
          doubanId: _resolveManualMatchDoubanId(target, metadataMatch),
          imdbId: _resolveManualMatchImdbId(target, metadataMatch),
          tmdbId: _resolveManualMatchTmdbId(target, metadataMatch),
          tvdbId: _resolveManualMatchTvdbId(target),
          wikidataId: _resolveManualMatchWikidataId(target),
        );
        controller.throwIfCancelled();
        return buildCandidates(nasLibrary);
      } on _LibraryMatchCancelledException {
        rethrow;
      } catch (_) {
        return const <_LibraryMatchCandidate>[];
      }
    });
  }

  if (taskFactories.isEmpty) {
    return snapshot();
  }

  var nextTaskIndex = 0;
  Future<void> runWorker() async {
    while (true) {
      controller.throwIfCancelled();
      if (nextTaskIndex >= taskFactories.length) {
        return;
      }
      final taskIndex = nextTaskIndex++;
      final matches = await taskFactories[taskIndex]();
      controller.throwIfCancelled();
      if (matches.isEmpty) {
        continue;
      }
      for (final match in matches) {
        upsert(match);
      }
      onProgress?.call(snapshot());
    }
  }

  final workerCount = math.min(maxConcurrentTasks, taskFactories.length);
  await Future.wait(List.generate(workerCount, (_) => runWorker()));
  return snapshot();
}

class _LibraryMatchTaskController {
  bool _isCancelled = false;

  bool get cancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const _LibraryMatchCancelledException();
    }
  }
}

class _LibraryMatchCancelledException implements Exception {
  const _LibraryMatchCancelledException();
}

List<MediaSourceConfig> _resolveLibraryMatchSources(AppSettings settings) {
  final availableSources = settings.mediaSources
      .where(
        (source) =>
            source.enabled &&
            (source.kind == MediaSourceKind.emby ||
                source.kind == MediaSourceKind.nas),
      )
      .toList(growable: false);
  final selectedIds = settings.libraryMatchSourceIds.toSet();
  if (selectedIds.isEmpty) {
    return availableSources;
  }
  final selectedSources = availableSources
      .where((source) => selectedIds.contains(source.id))
      .toList(growable: false);
  return selectedSources.isEmpty ? availableSources : selectedSources;
}

List<MediaDetailTarget> _candidatesToMergedTargets(
  MediaDetailTarget current,
  List<_LibraryMatchCandidate> candidates,
  String query,
) {
  return candidates
      .map(
        (c) => _mergeMatchedLibraryTarget(
          current: current,
          matched: MediaDetailTarget.fromMediaItem(
            c.item,
            availabilityLabel: _matchedAvailabilityLabel(
              item: c.item,
              matchReason: c.matchReason,
            ),
            searchQuery: query,
          ),
        ),
      )
      .toList();
}

String _matchedAvailabilityLabel({
  required MediaItem item,
  required String matchReason,
}) {
  final base = '${item.sourceKind.label} · ${item.sourceName}';
  final suffix = matchReason.isEmpty ? '' : ' · $matchReason';
  if (item.isPlayable) {
    return '资源已就绪：$base$suffix';
  }
  return '已匹配：$base$suffix';
}

String _libraryMatchOptionLabel(MediaDetailTarget t) {
  final source = t.sourceName.trim();
  final title = t.title.trim();
  final section = t.sectionName.trim();
  final tail = section.isEmpty ? title : '$title · $section';
  if (source.isEmpty) {
    return tail;
  }
  return '$source · $tail';
}

String _movieVariantOptionSubtitle(MediaDetailTarget target) {
  final playback = target.playbackTarget;
  final parts = <String>[];
  final availability =
      _availabilityFeedbackLabel(target.availabilityLabel).trim();
  if (availability.isNotEmpty && availability != '无') {
    parts.add(availability);
  }
  final format = playback?.formatLabel.trim() ?? '';
  if (format.isNotEmpty) {
    parts.add(format);
  }
  final resolution = playback?.resolutionLabel.trim() ?? '';
  if (resolution.isNotEmpty) {
    parts.add(resolution);
  }
  final fileSize = playback?.fileSizeLabel.trim() ?? '';
  if (fileSize.isNotEmpty) {
    parts.add(fileSize);
  }
  if (parts.isNotEmpty) {
    return parts.join(' · ');
  }
  final actualAddress = playback?.actualAddress.trim() ?? '';
  if (actualAddress.isNotEmpty) {
    return actualAddress;
  }
  return target.resourcePath.trim();
}

class _LibraryMatchCandidate {
  const _LibraryMatchCandidate({
    required this.item,
    required this.matchReason,
    required this.score,
  });

  final MediaItem item;
  final String matchReason;
  final double score;
}

List<String> _buildManualMatchTitles({
  required MediaDetailTarget target,
  required String query,
  MetadataMatchResult? metadataMatch,
}) {
  final seen = <String>{};
  final titles = <String>[];
  for (final raw in [
    target.title,
    query,
    if (metadataMatch != null) ...metadataMatch.titlesForMatching,
  ]) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      titles.add(trimmed);
    }
  }
  return titles;
}

int _resolveManualMatchYear(
  MediaDetailTarget target,
  MetadataMatchResult? metadataMatch,
) {
  if (target.year > 0) {
    return target.year;
  }
  return metadataMatch?.year ?? 0;
}

String _externalIdMatchReason(
  MediaItem item, {
  required String doubanId,
  required String imdbId,
  required String tmdbId,
  required String tvdbId,
  required String wikidataId,
}) {
  final reasons = <String>[];
  final normalizedDoubanId = doubanId.trim();
  final normalizedImdbId = imdbId.trim().toLowerCase();
  final normalizedTmdbId = tmdbId.trim();
  final normalizedTvdbId = tvdbId.trim();
  final normalizedWikidataId = wikidataId.trim().toUpperCase();

  if (normalizedDoubanId.isNotEmpty &&
      item.doubanId.trim() == normalizedDoubanId) {
    reasons.add('豆瓣 ID');
  }
  if (normalizedImdbId.isNotEmpty &&
      item.imdbId.trim().toLowerCase() == normalizedImdbId) {
    reasons.add('IMDb ID');
  }
  if (normalizedTmdbId.isNotEmpty && item.tmdbId.trim() == normalizedTmdbId) {
    reasons.add('TMDB ID');
  }
  if (normalizedTvdbId.isNotEmpty && item.tvdbId.trim() == normalizedTvdbId) {
    reasons.add('TVDB ID');
  }
  if (normalizedWikidataId.isNotEmpty &&
      item.wikidataId.trim().toUpperCase() == normalizedWikidataId) {
    reasons.add('Wikidata ID');
  }

  if (reasons.isEmpty) {
    return '按外部 ID 匹配';
  }
  if (reasons.length == 1) {
    return '按 ${reasons.first} 匹配';
  }
  return '按 ${reasons.join(' / ')} 匹配';
}

String _titleMatchReason(int year) {
  return year > 0 ? '按标题 + 年份匹配' : '按标题匹配';
}

String _resolveManualMatchDoubanId(
  MediaDetailTarget target,
  MetadataMatchResult? metadataMatch,
) {
  final current = target.doubanId.trim();
  if (current.isNotEmpty) {
    return current;
  }
  return metadataMatch?.doubanId.trim() ?? '';
}

String _resolveManualMatchImdbId(
  MediaDetailTarget target,
  MetadataMatchResult? metadataMatch,
) {
  final current = target.imdbId.trim();
  if (current.isNotEmpty) {
    return current;
  }
  return metadataMatch?.imdbId.trim() ?? '';
}

String _resolveManualMatchTmdbId(
  MediaDetailTarget target,
  MetadataMatchResult? metadataMatch,
) {
  final current = target.tmdbId.trim();
  if (current.isNotEmpty) {
    return current;
  }
  return metadataMatch?.tmdbId.trim() ?? '';
}

String _resolveManualMatchTvdbId(MediaDetailTarget target) {
  final current = target.tvdbId.trim();
  if (current.isNotEmpty) {
    return current;
  }
  return target.providerIds['Tvdb']?.trim() ??
      target.providerIds['TVDb']?.trim() ??
      target.providerIds['tvdb']?.trim() ??
      '';
}

String _resolveManualMatchWikidataId(MediaDetailTarget target) {
  final current = target.wikidataId.trim();
  if (current.isNotEmpty) {
    return current;
  }
  return target.providerIds['Wikidata']?.trim() ??
      target.providerIds['WikiData']?.trim() ??
      target.providerIds['wikidata']?.trim() ??
      '';
}

int _scoreManualMatchCollection(
  MediaCollection collection,
  MediaDetailTarget target, {
  MetadataMatchResult? metadataMatch,
}) {
  final category = _resolveManualMatchCategory(
    target,
    metadataMatch: metadataMatch,
  );
  final label =
      '${collection.title} ${collection.subtitle}'.trim().toLowerCase();
  final isMovieSection = _containsAnyKeyword(label, _movieSectionKeywords);
  final isSeriesSection = _containsAnyKeyword(label, _seriesSectionKeywords);
  final isAnimationSection =
      _containsAnyKeyword(label, _animationSectionKeywords);
  final isVarietySection = _containsAnyKeyword(label, _varietySectionKeywords);

  return switch (category) {
    _ManualMatchCategory.movie => isMovieSection
        ? 300
        : isAnimationSection
            ? 150
            : isSeriesSection || isVarietySection
                ? 40
                : 0,
    _ManualMatchCategory.series => isSeriesSection
        ? 300
        : isAnimationSection || isVarietySection
            ? 220
            : isMovieSection
                ? 40
                : 0,
    _ManualMatchCategory.animation => isAnimationSection
        ? 340
        : isSeriesSection
            ? 260
            : isMovieSection
                ? 140
                : 0,
    _ManualMatchCategory.variety => isVarietySection
        ? 340
        : isSeriesSection
            ? 260
            : isMovieSection
                ? 40
                : 0,
    _ManualMatchCategory.unknown => isMovieSection ||
            isSeriesSection ||
            isAnimationSection ||
            isVarietySection
        ? 80
        : 0,
  };
}

_ManualMatchCategory _resolveManualMatchCategory(
  MediaDetailTarget target, {
  MetadataMatchResult? metadataMatch,
}) {
  final itemType = target.itemType.trim().toLowerCase();
  final signals = <String>[
    itemType,
    ...target.genres,
    if (metadataMatch != null) ...metadataMatch.genres,
  ].join(' ').toLowerCase();

  if (_containsAnyKeyword(signals, _animationCategoryKeywords)) {
    return _ManualMatchCategory.animation;
  }
  if (_containsAnyKeyword(signals, _varietyCategoryKeywords)) {
    return _ManualMatchCategory.variety;
  }
  if (itemType == 'movie') {
    return _ManualMatchCategory.movie;
  }
  if (itemType == 'series' || itemType == 'season' || itemType == 'episode') {
    return _ManualMatchCategory.series;
  }
  if (_containsAnyKeyword(signals, _seriesCategoryKeywords)) {
    return _ManualMatchCategory.series;
  }
  if (_containsAnyKeyword(signals, _movieCategoryKeywords)) {
    return _ManualMatchCategory.movie;
  }
  return _ManualMatchCategory.unknown;
}

bool _containsAnyKeyword(String value, List<String> keywords) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  for (final keyword in keywords) {
    if (normalized.contains(keyword)) {
      return true;
    }
  }
  return false;
}

enum _ManualMatchCategory {
  movie,
  series,
  animation,
  variety,
  unknown,
}

const List<String> _movieCategoryKeywords = [
  '电影',
  'movie',
  'film',
  '院线',
  '影院',
];

const List<String> _seriesCategoryKeywords = [
  '剧',
  '剧集',
  '电视剧',
  '连续剧',
  'tv',
  'series',
  'season',
  'episode',
];

const List<String> _animationCategoryKeywords = [
  '动画',
  '动漫',
  '番剧',
  'anime',
  'animation',
  'cartoon',
];

const List<String> _varietyCategoryKeywords = [
  '综艺',
  '真人秀',
  '脱口秀',
  '选秀',
  'variety',
  'talk show',
];

const List<String> _movieSectionKeywords = [
  '电影',
  'movie',
  'movies',
  'film',
  '影院',
];

const List<String> _seriesSectionKeywords = [
  '剧集',
  '电视剧',
  '连续剧',
  'tv',
  'series',
  'show',
  'shows',
];

const List<String> _animationSectionKeywords = [
  '动画',
  '动漫',
  '番剧',
  'anime',
  'animation',
];

const List<String> _varietySectionKeywords = [
  '综艺',
  '真人秀',
  '脱口秀',
  'variety',
];

MediaDetailTarget _mergeMatchedLibraryTarget({
  required MediaDetailTarget current,
  required MediaDetailTarget matched,
}) {
  return matched.copyWith(
    title: current.title,
    posterUrl: _firstNonEmpty(matched.posterUrl, current.posterUrl),
    posterHeaders: matched.posterUrl.trim().isNotEmpty
        ? matched.posterHeaders
        : (current.posterHeaders.isNotEmpty
            ? current.posterHeaders
            : matched.posterHeaders),
    backdropUrl: _firstNonEmpty(matched.backdropUrl, current.backdropUrl),
    backdropHeaders: matched.backdropUrl.trim().isNotEmpty
        ? matched.backdropHeaders
        : (current.backdropHeaders.isNotEmpty
            ? current.backdropHeaders
            : matched.backdropHeaders),
    logoUrl: _firstNonEmpty(matched.logoUrl, current.logoUrl),
    logoHeaders: matched.logoUrl.trim().isNotEmpty
        ? matched.logoHeaders
        : (current.logoHeaders.isNotEmpty
            ? current.logoHeaders
            : matched.logoHeaders),
    bannerUrl: _firstNonEmpty(matched.bannerUrl, current.bannerUrl),
    bannerHeaders: matched.bannerUrl.trim().isNotEmpty
        ? matched.bannerHeaders
        : (current.bannerHeaders.isNotEmpty
            ? current.bannerHeaders
            : matched.bannerHeaders),
    extraBackdropUrls: _mergeUniqueImageUrls([
      ...matched.extraBackdropUrls,
      ...current.extraBackdropUrls,
    ]),
    extraBackdropHeaders: matched.extraBackdropUrls.isNotEmpty
        ? matched.extraBackdropHeaders
        : (current.extraBackdropHeaders.isNotEmpty
            ? current.extraBackdropHeaders
            : matched.extraBackdropHeaders),
    overview: current.hasUsefulOverview ? current.overview : matched.overview,
    year: current.year > 0 ? current.year : matched.year,
    durationLabel: current.durationLabel.trim().isNotEmpty
        ? current.durationLabel
        : matched.durationLabel,
    genres: current.genres.isNotEmpty ? current.genres : matched.genres,
    directors:
        current.directors.isNotEmpty ? current.directors : matched.directors,
    directorProfiles: current.directorProfiles.isNotEmpty
        ? current.directorProfiles
        : matched.directorProfiles,
    actors: current.actors.isNotEmpty ? current.actors : matched.actors,
    actorProfiles: current.actorProfiles.isNotEmpty
        ? current.actorProfiles
        : matched.actorProfiles,
    platforms:
        current.platforms.isNotEmpty ? current.platforms : matched.platforms,
    platformProfiles: current.platformProfiles.isNotEmpty
        ? current.platformProfiles
        : matched.platformProfiles,
    ratingLabels: _mergeLabels(
      matched.ratingLabels,
      current.ratingLabels,
    ),
    doubanId: current.doubanId,
    imdbId: current.imdbId,
    tmdbId: current.tmdbId.trim().isNotEmpty ? current.tmdbId : matched.tmdbId,
    tvdbId: current.tvdbId.trim().isNotEmpty ? current.tvdbId : matched.tvdbId,
    wikidataId: current.wikidataId.trim().isNotEmpty
        ? current.wikidataId
        : matched.wikidataId,
    tmdbSetId: current.tmdbSetId.trim().isNotEmpty
        ? current.tmdbSetId
        : matched.tmdbSetId,
    providerIds: current.providerIds.isNotEmpty
        ? current.providerIds
        : matched.providerIds,
  );
}

MediaDetailTarget _applyMetadataMatchToDetailTarget(
  MediaDetailTarget target,
  MetadataMatchResult match, {
  bool replaceExisting = false,
}) {
  final filteredMatchRatingLabels = _filterSupplementalRatingLabels(
    existing: target.ratingLabels,
    supplemental: match.ratingLabels,
  );
  final resolvedDirectorProfiles = match.directorProfiles.isNotEmpty
      ? _toMediaPersonProfiles(match.directorProfiles)
      : const <MediaPersonProfile>[];
  final resolvedActorProfiles = match.actorProfiles.isNotEmpty
      ? _toMediaPersonProfiles(match.actorProfiles)
      : const <MediaPersonProfile>[];
  final resolvedPlatformProfiles = match.platformProfiles.isNotEmpty
      ? _toMediaPersonProfiles(match.platformProfiles)
      : const <MediaPersonProfile>[];
  final shouldReplaceCompanies = match.provider == MetadataMatchProvider.tmdb;
  return target.copyWith(
    posterUrl: replaceExisting
        ? _firstNonEmpty(match.posterUrl, target.posterUrl)
        : (target.posterUrl.trim().isNotEmpty
            ? target.posterUrl
            : match.posterUrl),
    posterHeaders: replaceExisting
        ? (match.posterUrl.trim().isNotEmpty
            ? const <String, String>{}
            : target.posterHeaders)
        : target.posterHeaders,
    backdropUrl: replaceExisting
        ? _firstNonEmpty(match.backdropUrl, target.backdropUrl)
        : (target.backdropUrl.trim().isNotEmpty
            ? target.backdropUrl
            : match.backdropUrl),
    backdropHeaders: replaceExisting
        ? (match.backdropUrl.trim().isNotEmpty
            ? const <String, String>{}
            : target.backdropHeaders)
        : target.backdropHeaders,
    logoUrl: replaceExisting
        ? _firstNonEmpty(match.logoUrl, target.logoUrl)
        : (target.logoUrl.trim().isNotEmpty ? target.logoUrl : match.logoUrl),
    logoHeaders: replaceExisting
        ? (match.logoUrl.trim().isNotEmpty
            ? const <String, String>{}
            : target.logoHeaders)
        : target.logoHeaders,
    bannerUrl: replaceExisting
        ? _firstNonEmpty(match.bannerUrl, target.bannerUrl)
        : (target.bannerUrl.trim().isNotEmpty
            ? target.bannerUrl
            : match.bannerUrl),
    bannerHeaders: replaceExisting
        ? (match.bannerUrl.trim().isNotEmpty
            ? const <String, String>{}
            : target.bannerHeaders)
        : target.bannerHeaders,
    extraBackdropUrls: replaceExisting
        ? (match.extraBackdropUrls.isNotEmpty
            ? _mergeUniqueImageUrls(match.extraBackdropUrls)
            : target.extraBackdropUrls)
        : _mergeUniqueImageUrls([
            ...target.extraBackdropUrls,
            ...match.extraBackdropUrls,
          ]),
    extraBackdropHeaders: replaceExisting
        ? (match.extraBackdropUrls.isNotEmpty
            ? const <String, String>{}
            : target.extraBackdropHeaders)
        : target.extraBackdropHeaders,
    overview: replaceExisting
        ? _firstNonEmpty(match.overview, target.overview)
        : (target.hasUsefulOverview
            ? target.overview
            : (match.overview.trim().isNotEmpty
                ? match.overview
                : target.overview)),
    year: replaceExisting
        ? (match.year > 0 ? match.year : target.year)
        : (target.year > 0 ? target.year : match.year),
    durationLabel: replaceExisting
        ? _firstNonEmpty(match.durationLabel, target.durationLabel)
        : (match.durationLabel.trim().isNotEmpty
            ? (target.durationLabel.trim().isNotEmpty
                ? target.durationLabel
                : match.durationLabel)
            : target.durationLabel),
    genres: replaceExisting
        ? (match.genres.isNotEmpty ? match.genres : target.genres)
        : (target.genres.isNotEmpty ? target.genres : match.genres),
    directors: replaceExisting
        ? (match.directors.isNotEmpty ? match.directors : target.directors)
        : (target.directors.isNotEmpty ? target.directors : match.directors),
    directorProfiles: replaceExisting
        ? (resolvedDirectorProfiles.isNotEmpty
            ? resolvedDirectorProfiles
            : target.directorProfiles)
        : (target.directorProfiles.isNotEmpty
            ? target.directorProfiles
            : resolvedDirectorProfiles.isNotEmpty
                ? resolvedDirectorProfiles
                : target.directorProfiles),
    actors: replaceExisting
        ? (match.actors.isNotEmpty ? match.actors : target.actors)
        : (target.actors.isNotEmpty ? target.actors : match.actors),
    actorProfiles: replaceExisting
        ? (resolvedActorProfiles.isNotEmpty
            ? resolvedActorProfiles
            : target.actorProfiles)
        : (target.actorProfiles.isNotEmpty
            ? target.actorProfiles
            : resolvedActorProfiles.isNotEmpty
                ? resolvedActorProfiles
                : target.actorProfiles),
    platforms: shouldReplaceCompanies
        ? match.platforms
        : (replaceExisting
            ? (match.platforms.isNotEmpty ? match.platforms : target.platforms)
            : (target.platforms.isNotEmpty
                ? target.platforms
                : match.platforms)),
    platformProfiles: shouldReplaceCompanies
        ? resolvedPlatformProfiles
        : (replaceExisting
            ? (resolvedPlatformProfiles.isNotEmpty
                ? resolvedPlatformProfiles
                : target.platformProfiles)
            : (target.platformProfiles.isNotEmpty
                ? target.platformProfiles
                : resolvedPlatformProfiles.isNotEmpty
                    ? resolvedPlatformProfiles
                    : target.platformProfiles)),
    ratingLabels: _mergeLabels(target.ratingLabels, filteredMatchRatingLabels),
    doubanId: replaceExisting
        ? _firstNonEmpty(match.doubanId, target.doubanId)
        : (target.doubanId.trim().isNotEmpty
            ? target.doubanId
            : match.doubanId),
    imdbId: replaceExisting
        ? _firstNonEmpty(match.imdbId, target.imdbId)
        : (target.imdbId.trim().isNotEmpty ? target.imdbId : match.imdbId),
    tmdbId: replaceExisting
        ? _firstNonEmpty(match.tmdbId, target.tmdbId)
        : (target.tmdbId.trim().isNotEmpty ? target.tmdbId : match.tmdbId),
  );
}

List<MediaPersonProfile> _toMediaPersonProfiles(
  List<MetadataPersonProfile> profiles,
) {
  return profiles
      .map(
        (item) => MediaPersonProfile(
          name: item.name,
          avatarUrl: item.avatarUrl,
        ),
      )
      .toList(growable: false);
}

bool _sameMaps(Map<String, String> left, Map<String, String> right) {
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

String _firstNonEmpty(String primary, String fallback) {
  final primaryTrimmed = primary.trim();
  if (primaryTrimmed.isNotEmpty) {
    return primaryTrimmed;
  }
  return fallback.trim();
}

List<String> _mergeLabels(List<String> primary, List<String> secondary) {
  final seen = <String>{};
  final merged = <String>[];
  for (final value in [...primary, ...secondary]) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      merged.add(trimmed);
    }
  }
  return merged;
}

List<String> _mergeUniqueImageUrls(Iterable<String> values) {
  final seen = <String>{};
  final merged = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    merged.add(trimmed);
  }
  return merged;
}

final seriesBrowserProvider =
    FutureProvider.autoDispose.family<_SeriesBrowserState?, MediaDetailTarget>((
  ref,
  target,
) async {
  if (!target.isSeries ||
      target.sourceId.trim().isEmpty ||
      target.itemId.trim().isEmpty) {
    return null;
  }

  final repository = ref.read(mediaRepositoryProvider);
  final children = await repository.fetchChildren(
    sourceId: target.sourceId,
    parentId: target.itemId,
    sectionId: target.sectionId,
    sectionName: target.sectionName,
  );

  final seasons = children
      .where((item) => item.itemType.trim().toLowerCase() == 'season')
      .toList();
  if (seasons.isEmpty) {
    final episodes = children
        .where((item) => item.itemType.trim().toLowerCase() == 'episode')
        .toList();
    if (episodes.isEmpty) {
      return null;
    }
    return _SeriesBrowserState(
      groups: [
        _EpisodeGroup(
          id: 'all',
          title: '全部剧集',
          seasonNumber: null,
          episodes: _sortEpisodes(episodes),
        ),
      ],
    );
  }

  final seasonEpisodes = await Future.wait(
    seasons.map(
      (season) => repository.fetchChildren(
        sourceId: target.sourceId,
        parentId: season.id,
        sectionId: target.sectionId,
        sectionName: target.sectionName,
      ),
    ),
  );

  final groups = <_EpisodeGroup>[];
  for (var index = 0; index < seasons.length; index++) {
    final season = seasons[index];
    final episodes = seasonEpisodes[index]
        .where((item) => item.itemType.trim().toLowerCase() == 'episode')
        .toList();
    if (episodes.isEmpty) {
      continue;
    }
    groups.add(
      _EpisodeGroup(
        id: season.id,
        title: season.title,
        seasonNumber: season.seasonNumber,
        episodes: _sortEpisodes(episodes),
      ),
    );
  }

  return groups.isEmpty ? null : _SeriesBrowserState(groups: groups);
});

class MediaDetailPage extends ConsumerStatefulWidget {
  const MediaDetailPage({super.key, required this.target});

  final MediaDetailTarget target;

  @override
  ConsumerState<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends ConsumerState<MediaDetailPage> {
  String _selectedSeasonId = '';
  MediaDetailTarget? _manualOverrideTarget;
  bool _isMatchingLocalResource = false;
  bool _isRefreshingMetadata = false;
  List<MediaDetailTarget> _libraryMatchChoices = const [];
  int _selectedLibraryMatchIndex = 0;
  List<CachedSubtitleSearchOption> _subtitleSearchChoices = const [];
  int _selectedSubtitleSearchIndex = -1;
  bool _isSearchingSubtitles = false;
  String? _busySubtitleResultId;
  String? _subtitleSearchStatusMessage;
  int _detailSessionId = 0;
  _LibraryMatchTaskController? _activeLibraryMatchController;
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();

  @override
  void initState() {
    super.initState();
    _startDetailTasks();
  }

  @override
  void didUpdateWidget(covariant MediaDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.itemId != widget.target.itemId ||
        oldWidget.target.title != widget.target.title ||
        oldWidget.target.searchQuery != widget.target.searchQuery) {
      _cancelActiveLibraryMatch();
      _selectedSeasonId = '';
      _manualOverrideTarget = null;
      _isMatchingLocalResource = false;
      _isRefreshingMetadata = false;
      _libraryMatchChoices = const [];
      _selectedLibraryMatchIndex = 0;
      _subtitleSearchChoices = const [];
      _selectedSubtitleSearchIndex = -1;
      _isSearchingSubtitles = false;
      _busySubtitleResultId = null;
      _subtitleSearchStatusMessage = null;
      _startDetailTasks();
    }
  }

  @override
  void dispose() {
    _cancelActiveLibraryMatch();
    _detailSessionId += 1;
    _tvFocusMemoryController.dispose();
    super.dispose();
  }

  void _cancelActiveLibraryMatch() {
    _activeLibraryMatchController?.cancel();
    _activeLibraryMatchController = null;
  }

  void _startDetailTasks() {
    final sessionId = ++_detailSessionId;
    Future<void>.microtask(() async {
      if (ref.read(backgroundWorkSuspendedProvider)) {
        return;
      }
      if (!_isSessionActive(sessionId)) {
        return;
      }

      await _restoreCachedDetailState(sessionId);
      if (!_isSessionActive(sessionId)) {
        return;
      }

      final currentTarget = _manualOverrideTarget ?? widget.target;
      unawaited(ref.read(enrichedDetailTargetProvider(currentTarget).future));
      if (currentTarget.isSeries) {
        unawaited(ref.read(seriesBrowserProvider(currentTarget).future));
      }

      final settings = ref.read(appSettingsProvider);
      if (!settings.detailAutoLibraryMatchEnabled ||
          ref.read(backgroundWorkSuspendedProvider)) {
        return;
      }

      final resolved =
          await ref.read(enrichedDetailTargetProvider(widget.target).future);
      if (!_isSessionActive(sessionId) ||
          _manualOverrideTarget != null ||
          ref.read(backgroundWorkSuspendedProvider)) {
        return;
      }
      if (!_shouldAutoMatchLocalResource(resolved)) {
        return;
      }
      await _matchLocalResource(
        resolved,
        sessionId: sessionId,
        showFeedback: false,
      );
    });
  }

  bool _isSessionActive(int sessionId) {
    return mounted && _detailSessionId == sessionId;
  }

  bool _isLibraryMatchActive(
    int sessionId,
    _LibraryMatchTaskController controller,
  ) {
    return _isSessionActive(sessionId) &&
        identical(_activeLibraryMatchController, controller) &&
        !controller.cancelled;
  }

  Future<void> _restoreCachedDetailState(int sessionId) async {
    final cachedState = await ref
        .read(localStorageCacheRepositoryProvider)
        .loadDetailState(widget.target);
    if (!_isSessionActive(sessionId) || cachedState == null) {
      return;
    }
    final cachedChoices = cachedState.libraryMatchChoices;
    setState(() {
      if (cachedChoices.length > 1) {
        final selectedIndex = cachedState.selectedLibraryMatchIndex.clamp(
          0,
          cachedChoices.length - 1,
        );
        _libraryMatchChoices = cachedChoices;
        _selectedLibraryMatchIndex = selectedIndex;
        _manualOverrideTarget = cachedChoices[selectedIndex];
      }
      _subtitleSearchChoices = cachedState.subtitleSearchChoices;
      _selectedSubtitleSearchIndex = _normalizeSubtitleSearchIndex(
        cachedState.selectedSubtitleSearchIndex,
        choices: cachedState.subtitleSearchChoices,
      );
    });
  }

  Future<void> _matchLocalResource(
    MediaDetailTarget currentTarget, {
    int? sessionId,
    bool showFeedback = true,
  }) async {
    final activeSessionId = sessionId ?? _detailSessionId;
    if (_isMatchingLocalResource || !_isSessionActive(activeSessionId)) {
      return;
    }

    final controller = _LibraryMatchTaskController();
    _cancelActiveLibraryMatch();
    _activeLibraryMatchController = controller;
    setState(() {
      _isMatchingLocalResource = true;
      _libraryMatchChoices = const [];
      _selectedLibraryMatchIndex = 0;
    });

    try {
      final settings = ref.read(appSettingsProvider);
      final query = currentTarget.searchQuery.trim().isEmpty
          ? currentTarget.title
          : currentTarget.searchQuery;
      final metadataMatch = await _tryPreferredMetadataMatch(
        metadataMatchResolver: ref.read(metadataMatchResolverProvider),
        settings: settings,
        target: currentTarget,
        query: query,
      );
      controller.throwIfCancelled();
      if (!_isLibraryMatchActive(activeSessionId, controller)) {
        throw const _LibraryMatchCancelledException();
      }
      final allowedSources = _resolveLibraryMatchSources(settings);

      final candidates = await _findAllLibraryMatchCandidates(
        mediaRepository: ref.read(mediaRepositoryProvider),
        nasMediaIndexer: ref.read(nasMediaIndexerProvider),
        allowedSources: allowedSources,
        controller: controller,
        target: currentTarget,
        query: query,
        metadataMatch: metadataMatch,
        onProgress: (partialCandidates) {
          if (!_isLibraryMatchActive(activeSessionId, controller)) {
            return;
          }
          final partialMerged = _candidatesToMergedTargets(
            currentTarget,
            partialCandidates,
            query,
          );
          if (partialMerged.isEmpty) {
            return;
          }
          setState(() {
            if (partialMerged.length == 1) {
              _libraryMatchChoices = const [];
              _selectedLibraryMatchIndex = 0;
              _manualOverrideTarget = partialMerged.first;
            } else {
              _libraryMatchChoices = partialMerged;
              _selectedLibraryMatchIndex = 0;
              _manualOverrideTarget = partialMerged.first;
            }
          });
        },
      );

      controller.throwIfCancelled();
      if (!_isLibraryMatchActive(activeSessionId, controller)) {
        throw const _LibraryMatchCancelledException();
      }

      final merged = _candidatesToMergedTargets(
        currentTarget,
        candidates,
        query,
      );

      setState(() {
        _isMatchingLocalResource = false;
        if (merged.isEmpty) {
          _libraryMatchChoices = const [];
          _selectedLibraryMatchIndex = 0;
        } else if (merged.length == 1) {
          _libraryMatchChoices = const [];
          _manualOverrideTarget = merged.first;
          _selectedLibraryMatchIndex = 0;
        } else {
          _libraryMatchChoices = merged;
          _selectedLibraryMatchIndex = 0;
          _manualOverrideTarget = merged.first;
        }
      });

      unawaited(
        ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
              seedTarget: currentTarget,
              resolvedTarget: merged.isEmpty ? currentTarget : merged.first,
              libraryMatchChoices:
                  merged.length > 1 ? merged : const <MediaDetailTarget>[],
              selectedLibraryMatchIndex: 0,
            ),
      );

      if (!_isLibraryMatchActive(activeSessionId, controller) ||
          !showFeedback) {
        return;
      }

      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      if (merged.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('没有找到可匹配的本地资源')),
        );
        return;
      }

      if (merged.length == 1) {
        final matched = merged.first;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              matched.availabilityLabel.trim().isNotEmpty
                  ? '已匹配到 ${_availabilityFeedbackLabel(matched.availabilityLabel)}'
                  : '已匹配到 ${matched.sourceKind?.label ?? '资源'} · ${matched.sourceName}',
            ),
          ),
        );
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('匹配到 ${merged.length} 个本地资源，可在下方选择'),
        ),
      );
    } on _LibraryMatchCancelledException {
      return;
    } finally {
      final isCurrentController =
          identical(_activeLibraryMatchController, controller);
      if (isCurrentController) {
        _activeLibraryMatchController = null;
      }
      if (mounted && isCurrentController && _isMatchingLocalResource) {
        setState(() {
          _isMatchingLocalResource = false;
        });
      }
    }
  }

  Future<void> _refreshMetadata(
    MediaDetailTarget currentTarget, {
    int? sessionId,
    bool showFeedback = true,
  }) async {
    final activeSessionId = sessionId ?? _detailSessionId;
    if (_isRefreshingMetadata || !_isSessionActive(activeSessionId)) {
      return;
    }

    setState(() {
      _isRefreshingMetadata = true;
    });

    final settings = ref.read(appSettingsProvider);
    final nextTarget = await _resolveAutomaticMetadataIfNeeded(
      settings: settings,
      target: currentTarget,
      wmdbMetadataClient: ref.read(wmdbMetadataClientProvider),
      tmdbMetadataClient: ref.read(tmdbMetadataClientProvider),
      imdbRatingClient: ref.read(imdbRatingClientProvider),
      forceSearch: true,
      forceReplace: true,
    );
    final changed = _hasMetadataChanged(currentTarget, nextTarget);

    if (!_isSessionActive(activeSessionId)) {
      return;
    }

    setState(() {
      _isRefreshingMetadata = false;
      if (changed) {
        _manualOverrideTarget = nextTarget;
      }
    });

    if (changed) {
      unawaited(
        ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
              seedTarget: currentTarget,
              resolvedTarget: nextTarget,
            ),
      );
    }

    if (!showFeedback) {
      return;
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(changed ? '已更新影片信息' : '没有可更新的信息'),
      ),
    );
  }

  Future<void> _openMetadataIndexManager(
      MediaDetailTarget currentTarget) async {
    if (!_canManageMetadataIndex(currentTarget)) {
      return;
    }
    final updatedTarget = await context.pushNamed<MediaDetailTarget>(
      'metadata-index',
      extra: currentTarget,
    );
    if (!mounted || updatedTarget == null) {
      return;
    }

    setState(() {
      _manualOverrideTarget = updatedTarget;
    });

    unawaited(
      ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: updatedTarget,
          ),
    );
  }

  int get _currentLibraryMatchIndex {
    if (_libraryMatchChoices.isEmpty) {
      return 0;
    }
    return _selectedLibraryMatchIndex.clamp(
      0,
      _libraryMatchChoices.length - 1,
    );
  }

  void _applySelectedLibraryMatchIndex(int index) {
    if (_libraryMatchChoices.isEmpty) {
      return;
    }
    final resolvedIndex = index.clamp(0, _libraryMatchChoices.length - 1);
    final resolvedTarget = _libraryMatchChoices[resolvedIndex];
    setState(() {
      _selectedLibraryMatchIndex = resolvedIndex;
      _manualOverrideTarget = resolvedTarget;
    });
    unawaited(
      ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: resolvedTarget,
            libraryMatchChoices: _libraryMatchChoices,
            selectedLibraryMatchIndex: resolvedIndex,
          ),
    );
  }

  Future<void> _openPlaybackEnginePicker(PlaybackEngine currentEngine) async {
    final selection = await showSettingsOptionDialog<PlaybackEngine>(
      context: context,
      title: '选择播放器',
      options: PlaybackEngine.values,
      currentValue: currentEngine,
      labelBuilder: (engine) => engine.label,
    );
    if (selection == null) {
      return;
    }
    await _setPlaybackEngine(selection, currentEngine: currentEngine);
  }

  Future<void> _setPlaybackEngine(
    PlaybackEngine selection, {
    required PlaybackEngine currentEngine,
  }) async {
    if (selection == currentEngine) {
      return;
    }
    await ref.read(settingsControllerProvider.notifier).setPlaybackEngine(
          selection,
        );
  }

  Future<void> _openTelevisionLibraryMatchPicker() async {
    if (_libraryMatchChoices.length <= 1 || _isMatchingLocalResource) {
      return;
    }

    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    final selectedIndex = _currentLibraryMatchIndex;
    final optionFocusNodes = List<FocusNode>.generate(
      _libraryMatchChoices.length,
      (index) => FocusNode(
        debugLabel: 'detail-library-match-option-$index',
      ),
    );
    final closeFocusNode = FocusNode(debugLabel: 'detail-library-match-close');
    try {
      final nextIndex = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          final dialog = AlertDialog(
            title: const Text('选择本地资源'),
            content: SizedBox(
              width: 460,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.58,
                ),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _libraryMatchChoices.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final candidate = _libraryMatchChoices[index];
                      final isSelected = index == selectedIndex;
                      return TvFocusableAction(
                        focusNode: optionFocusNodes[index],
                        focusId: 'detail:resource:library-option:$index',
                        autofocus: index ==
                            (selectedIndex.clamp(
                                0, optionFocusNodes.length - 1)),
                        onPressed: () => Navigator.of(dialogContext).pop(index),
                        borderRadius: BorderRadius.circular(18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _libraryMatchOptionLabel(candidate),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (candidate.availabilityLabel
                                          .trim()
                                          .isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            candidate.availabilityLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF9DB0CF),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            actions: [
              TvAdaptiveButton(
                label: '关闭',
                icon: Icons.close_rounded,
                onPressed: () => Navigator.of(dialogContext).pop(),
                focusNode: closeFocusNode,
                autofocus: optionFocusNodes.isEmpty,
                variant: TvButtonVariant.outlined,
                focusId: 'detail:resource:library-close',
              ),
            ],
          );
          return wrapTelevisionDialogBackHandling(
            enabled: isTelevision,
            dialogContext: dialogContext,
            inputFocusNodes: const <FocusNode>[],
            contentFocusNodes: optionFocusNodes,
            actionFocusNodes: [closeFocusNode],
            child: dialog,
          );
        },
      );
      if (!mounted || nextIndex == null || nextIndex == selectedIndex) {
        return;
      }
      _applySelectedLibraryMatchIndex(nextIndex);
    } finally {
      for (final focusNode in optionFocusNodes) {
        focusNode.dispose();
      }
      closeFocusNode.dispose();
    }
  }

  bool _shouldShowPlayableVariantSwitcher(MediaDetailTarget target) {
    final itemType = target.itemType.trim().toLowerCase();
    return target.isPlayable &&
        itemType != 'series' &&
        itemType != 'season' &&
        _libraryMatchChoices.length > 1 &&
        _libraryMatchChoices.any((choice) => choice.isPlayable);
  }

  Widget _buildPlayableVariantSwitcherBlock(MediaDetailTarget target) {
    final currentIndex = _currentLibraryMatchIndex;
    return _DetailBlock(
      title: '播放版本',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '匹配到多个可播放文件或来源，可切换当前播放版本。',
            style: TextStyle(
              color: Color(0xFF90A0BD),
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < _libraryMatchChoices.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final candidate = _libraryMatchChoices[index];
                final isSelected = index == currentIndex;
                return StarflowSelectionTile(
                  title: _libraryMatchOptionLabel(candidate),
                  subtitle: _movieVariantOptionSubtitle(candidate),
                  onPressed: _isMatchingLocalResource
                      ? null
                      : () {
                          if (index == currentIndex) {
                            return;
                          }
                          _applySelectedLibraryMatchIndex(index);
                        },
                  focusId: 'detail:resource:playable-variant:$index',
                  trailing: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  int _normalizeSubtitleSearchIndex(
    int index, {
    List<CachedSubtitleSearchOption>? choices,
  }) {
    final resolvedChoices = choices ?? _subtitleSearchChoices;
    if (resolvedChoices.isEmpty) {
      return -1;
    }
    return index.clamp(-1, resolvedChoices.length - 1);
  }

  int get _currentSubtitleSearchIndex {
    return _normalizeSubtitleSearchIndex(_selectedSubtitleSearchIndex);
  }

  CachedSubtitleSearchOption? get _selectedSubtitleSearchChoice {
    final index = _currentSubtitleSearchIndex;
    if (index < 0 || index >= _subtitleSearchChoices.length) {
      return null;
    }
    return _subtitleSearchChoices[index];
  }

  MediaDetailTarget _decorateTargetWithSelectedSubtitle(
      MediaDetailTarget target) {
    final playbackTarget = target.playbackTarget;
    if (playbackTarget == null) {
      return target;
    }
    final selection = _selectedSubtitleSearchChoice?.selection;
    final decoratedPlayback = playbackTarget.copyWith(
      externalSubtitleFilePath:
          selection?.subtitleFilePath?.trim().isNotEmpty == true
              ? selection!.subtitleFilePath!.trim()
              : '',
      externalSubtitleDisplayName:
          selection?.subtitleFilePath?.trim().isNotEmpty == true
              ? selection!.displayName.trim()
              : '',
    );
    return target.copyWith(playbackTarget: decoratedPlayback);
  }

  Future<void> _searchSubtitlesForDetail(
    MediaDetailTarget target, {
    bool showFeedback = true,
  }) async {
    final playbackTarget = target.playbackTarget;
    final query = playbackTarget == null
        ? ''
        : buildSubtitleSearchQuery(playbackTarget).trim();
    subtitleSearchTrace(
      'detail.search.start',
      fields: {
        'title': target.title.trim(),
        'showFeedback': showFeedback,
        'isPlayable': target.isPlayable,
        'query': query,
        'playbackTitle': playbackTarget?.title.trim() ?? '',
        'seriesTitle': playbackTarget?.seriesTitle.trim() ?? '',
        'season': playbackTarget?.seasonNumber,
        'episode': playbackTarget?.episodeNumber,
      },
    );
    if (playbackTarget == null || !target.isPlayable) {
      subtitleSearchTrace(
        'detail.search.skip-unplayable',
        fields: {
          'hasPlaybackTarget': playbackTarget != null,
          'isPlayable': target.isPlayable,
        },
      );
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前资源还不能直接播放，暂时无法搜索字幕')),
        );
      }
      return;
    }
    if (_isSearchingSubtitles) {
      subtitleSearchTrace('detail.search.skip-already-searching');
      return;
    }

    final sources = ref.read(appSettingsProvider).onlineSubtitleSources;
    if (sources.isEmpty) {
      subtitleSearchTrace('detail.search.skip-empty-sources');
      if (mounted) {
        setState(() {
          _subtitleSearchStatusMessage = '请先在设置里启用至少一个在线字幕来源';
        });
      }
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置里启用至少一个在线字幕来源')),
        );
      }
      return;
    }

    if (query.isEmpty) {
      subtitleSearchTrace(
        'detail.search.skip-empty-query',
        fields: {
          'playbackTitle': playbackTarget.title.trim(),
          'seriesTitle': playbackTarget.seriesTitle.trim(),
        },
      );
      if (mounted) {
        setState(() {
          _subtitleSearchStatusMessage = '缺少片名信息，暂时无法搜索字幕';
        });
      }
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缺少片名信息，暂时无法搜索字幕')),
        );
      }
      return;
    }

    final previousChoices = _subtitleSearchChoices;
    final previousSelectedId = _selectedSubtitleSearchChoice?.result.id;

    if (mounted) {
      setState(() {
        _isSearchingSubtitles = true;
        _subtitleSearchStatusMessage = null;
      });
    }

    try {
      final results = await ref.read(onlineSubtitleRepositoryProvider).search(
            query,
            sources: sources,
            maxResults: 10,
          );
      subtitleSearchTrace(
        'detail.search.repository-finished',
        fields: {
          'query': query,
          'sources': sources.map((item) => item.name).join('/'),
          'count': results.length,
          'downloadable': results.where((item) => item.canDownload).length,
          'autoLoadable': results.where((item) => item.canAutoLoad).length,
          'sample': _detailSubtitleResultSample(results),
        },
      );
      final nextChoices = _mergeSubtitleSearchChoices(
        previousChoices: previousChoices,
        results: results,
      );
      final statusMessage = _buildSubtitleSearchStatusMessage(
        results: results,
        usableChoices: nextChoices,
      );
      subtitleSearchTrace(
        'detail.search.filtered',
        fields: {
          'query': query,
          'rawCount': results.length,
          'usableCount': nextChoices.length,
          'filteredOut': results.length - nextChoices.length,
          'notDownloadable': results.where((item) => !item.canDownload).length,
          'notAutoLoadable': results.where((item) => !item.canAutoLoad).length,
          'sample': _detailSubtitleChoiceSample(nextChoices),
        },
      );
      final nextSelectedIndex = previousSelectedId == null
          ? -1
          : nextChoices
              .indexWhere((item) => item.result.id == previousSelectedId);
      if (!mounted) {
        return;
      }
      setState(() {
        _subtitleSearchChoices = nextChoices;
        _selectedSubtitleSearchIndex = _normalizeSubtitleSearchIndex(
          nextSelectedIndex,
          choices: nextChoices,
        );
        _isSearchingSubtitles = false;
        _subtitleSearchStatusMessage = statusMessage;
      });
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: target,
            subtitleSearchChoices: nextChoices,
            selectedSubtitleSearchIndex: _selectedSubtitleSearchIndex,
          );
      if (!showFeedback || !mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextChoices.isEmpty ? statusMessage! : '已找到 ${nextChoices.length} 条可用字幕',
          ),
        ),
      );
    } catch (error, stackTrace) {
      subtitleSearchTrace(
        'detail.search.failed',
        fields: {
          'query': query,
          'sources': sources.map((item) => item.name).join('/'),
        },
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isSearchingSubtitles = false;
        _subtitleSearchStatusMessage = '$error';
      });
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('字幕搜索失败：$error')),
        );
      }
    }
  }

  List<CachedSubtitleSearchOption> _mergeSubtitleSearchChoices({
    required List<CachedSubtitleSearchOption> previousChoices,
    required List<SubtitleSearchResult> results,
  }) {
    final previousById = <String, CachedSubtitleSearchOption>{
      for (final choice in previousChoices) choice.result.id: choice,
    };
    return results
        .where((item) => item.canAutoLoad && item.canDownload)
        .take(10)
        .map(
          (result) =>
              previousById[result.id]?.copyWith(result: result) ??
              CachedSubtitleSearchOption(result: result),
        )
        .toList(growable: false);
  }

  String? _buildSubtitleSearchStatusMessage({
    required List<SubtitleSearchResult> results,
    required List<CachedSubtitleSearchOption> usableChoices,
  }) {
    if (usableChoices.isNotEmpty) {
      return null;
    }
    if (results.isEmpty) {
      return '没有找到可直接加载的字幕结果';
    }

    final autoLoadableOnlyCount = results
        .where((item) => item.canAutoLoad && !item.canDownload)
        .length;
    if (autoLoadableOnlyCount > 0) {
      return '已搜到 $autoLoadableOnlyCount 条字幕，但当前来源暂不支持应用内直接下载';
    }

    final downloadOnlyCount = results
        .where((item) => item.canDownload && !item.canAutoLoad)
        .length;
    if (downloadOnlyCount > 0) {
      return '已搜到 $downloadOnlyCount 条字幕，但当前结果暂不能自动挂载播放';
    }

    return '没有找到可直接加载的字幕结果';
  }

  Future<void> _applySelectedSubtitleSearchIndex(
    MediaDetailTarget target,
    int index,
  ) async {
    if (_isSearchingSubtitles || _subtitleSearchChoices.isEmpty) {
      return;
    }
    final resolvedIndex = _normalizeSubtitleSearchIndex(index);
    if (resolvedIndex < 0) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedSubtitleSearchIndex = -1;
      });
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: target,
            subtitleSearchChoices: _subtitleSearchChoices,
            selectedSubtitleSearchIndex: -1,
          );
      return;
    }

    final choice = _subtitleSearchChoices[resolvedIndex];
    if (choice.selection?.canApply == true) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedSubtitleSearchIndex = resolvedIndex;
      });
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: target,
            subtitleSearchChoices: _subtitleSearchChoices,
            selectedSubtitleSearchIndex: resolvedIndex,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('播放时会自动加载这条外挂字幕')),
        );
      }
      return;
    }

    if (_busySubtitleResultId != null) {
      subtitleSearchTrace(
        'detail.download.skip-busy',
        fields: {
          'busyResultId': _busySubtitleResultId,
          'requestedResultId': choice.result.id,
        },
      );
      return;
    }

    if (mounted) {
      setState(() {
        _busySubtitleResultId = choice.result.id;
        _subtitleSearchStatusMessage = null;
      });
    }

    try {
      subtitleSearchTrace(
        'detail.download.start',
        fields: {
          'resultId': choice.result.id,
          'source': choice.result.source.name,
          'title': choice.result.title,
          'packageKind': choice.result.packageKind.name,
        },
      );
      final download = await ref
          .read(onlineSubtitleRepositoryProvider)
          .download(choice.result);
      final selection = SubtitleSearchSelection(
        cachedPath: download.cachedPath,
        displayName: download.displayName,
        subtitleFilePath: download.subtitleFilePath,
      );
      if (!selection.canApply) {
        throw StateError('字幕已缓存，但当前结果暂不能直接挂载播放');
      }
      final nextChoices = [
        for (var i = 0; i < _subtitleSearchChoices.length; i++)
          if (i == resolvedIndex)
            _subtitleSearchChoices[i].copyWith(selection: selection)
          else
            _subtitleSearchChoices[i],
      ];
      if (!mounted) {
        return;
      }
      setState(() {
        _subtitleSearchChoices = nextChoices;
        _selectedSubtitleSearchIndex = resolvedIndex;
        _busySubtitleResultId = null;
      });
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: target,
            subtitleSearchChoices: nextChoices,
            selectedSubtitleSearchIndex: resolvedIndex,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('字幕已缓存，播放时会自动加载')),
        );
      }
      subtitleSearchTrace(
        'detail.download.finished',
        fields: {
          'resultId': choice.result.id,
          'subtitleFilePath': selection.subtitleFilePath ?? '',
        },
      );
    } catch (error, stackTrace) {
      subtitleSearchTrace(
        'detail.download.failed',
        fields: {
          'resultId': choice.result.id,
          'source': choice.result.source.name,
        },
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _busySubtitleResultId = null;
        _subtitleSearchStatusMessage = '$error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载字幕失败：$error')),
      );
    }
  }

  String _subtitleSearchChoiceLabel(CachedSubtitleSearchOption choice) {
    final parts = <String>[
      if (choice.result.title.trim().isNotEmpty) choice.result.title.trim(),
      if (choice.result.summaryLine.trim().isNotEmpty)
        choice.result.summaryLine.trim(),
      if (choice.selection?.canApply == true) '已缓存',
    ];
    return parts.join(' · ');
  }

  String _detailSubtitleResultSample(List<SubtitleSearchResult> results) {
    if (results.isEmpty) {
      return '';
    }
    return results
        .take(3)
        .map((item) => '${item.providerLabel}:${item.title}')
        .join(' | ');
  }

  String _detailSubtitleChoiceSample(
    List<CachedSubtitleSearchOption> choices,
  ) {
    if (choices.isEmpty) {
      return '';
    }
    return choices
        .take(3)
        .map((item) => '${item.result.providerLabel}:${item.result.title}')
        .join(' | ');
  }

  Future<void> _openTelevisionSubtitlePicker(MediaDetailTarget target) async {
    if (_subtitleSearchChoices.isEmpty || _isSearchingSubtitles) {
      return;
    }

    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    final selectedIndex = _currentSubtitleSearchIndex;
    final optionFocusNodes = List<FocusNode>.generate(
      _subtitleSearchChoices.length + 1,
      (index) => FocusNode(
        debugLabel: 'detail-subtitle-option-$index',
      ),
    );
    final closeFocusNode = FocusNode(debugLabel: 'detail-subtitle-close');
    try {
      final nextIndex = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          final dialog = AlertDialog(
            title: const Text('选择外挂字幕'),
            content: SizedBox(
              width: 500,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.58,
                ),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _subtitleSearchChoices.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final subtitleIndex = index - 1;
                      final isNone = subtitleIndex < 0;
                      final isSelected = subtitleIndex == selectedIndex;
                      final choice =
                          isNone ? null : _subtitleSearchChoices[subtitleIndex];
                      final title = isNone
                          ? '不加载外挂字幕'
                          : _subtitleSearchChoiceLabel(choice!);
                      return TvFocusableAction(
                        focusNode: optionFocusNodes[index],
                        focusId: 'detail:subtitle:option:$index',
                        autofocus: index ==
                            (selectedIndex + 1).clamp(
                              0,
                              optionFocusNodes.length - 1,
                            ),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(subtitleIndex),
                        borderRadius: BorderRadius.circular(18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (choice != null &&
                                          choice.result.detailLine
                                              .trim()
                                              .isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            choice.result.detailLine,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF9DB0CF),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            actions: [
              TvAdaptiveButton(
                label: '关闭',
                icon: Icons.close_rounded,
                onPressed: () => Navigator.of(dialogContext).pop(),
                focusNode: closeFocusNode,
                variant: TvButtonVariant.outlined,
                focusId: 'detail:subtitle:close',
              ),
            ],
          );
          return wrapTelevisionDialogBackHandling(
            enabled: isTelevision,
            dialogContext: dialogContext,
            inputFocusNodes: const <FocusNode>[],
            contentFocusNodes: optionFocusNodes,
            actionFocusNodes: [closeFocusNode],
            child: dialog,
          );
        },
      );
      if (!mounted || nextIndex == null || nextIndex == selectedIndex) {
        return;
      }
      await _applySelectedSubtitleSearchIndex(target, nextIndex);
    } finally {
      for (final focusNode in optionFocusNodes) {
        focusNode.dispose();
      }
      closeFocusNode.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final seedTarget = _manualOverrideTarget ?? widget.target;
    final targetAsync = ref.watch(enrichedDetailTargetProvider(seedTarget));
    final target = targetAsync.valueOrNull ?? seedTarget;
    final playbackTargetDecorated = _decorateTargetWithSelectedSubtitle(target);
    final seriesAsync = ref.watch(seriesBrowserProvider(target));
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final playbackEngine = ref.watch(
      appSettingsProvider.select((settings) => settings.playbackEngine),
    );

    return TvFocusMemoryScope(
      controller: _tvFocusMemoryController,
      scopeId: 'detail',
      enabled: isTelevision,
      child: Scaffold(
        backgroundColor: const Color(0xFF030914),
        body: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF07121F),
                    Color(0xFF08101A),
                    Color(0xFF030914),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _HeroSection(target: playbackTargetDecorated),
                  Padding(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (target.isSeries)
                          seriesAsync.when(
                            data: (browser) {
                              if (browser == null || browser.groups.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final selectedGroup =
                                  _resolveSelectedGroup(browser.groups);
                              return _DetailBlock(
                                title: '剧集',
                                child: _EpisodeBrowser(
                                  seriesTarget: target,
                                  groups: browser.groups,
                                  selectedGroupId: selectedGroup.id,
                                  onSeasonSelected: (groupId) {
                                    setState(() {
                                      _selectedSeasonId = groupId;
                                    });
                                  },
                                ),
                              );
                            },
                            loading: () => const _DetailBlock(
                              title: '剧集',
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white),
                                ),
                              ),
                            ),
                            error: (error, stackTrace) => _DetailBlock(
                              title: '剧集',
                              child: Text(
                                '加载剧集失败：$error',
                                style: const TextStyle(
                                  color: Color(0xFF90A0BD),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        if (target.overview.trim().isNotEmpty)
                          _DetailBlock(
                            title: _overviewSectionTitle(target),
                            child: Text(
                              target.overview,
                              style: const TextStyle(
                                color: Color(0xFFDCE6F8),
                                fontSize: 15,
                                height: 1.7,
                              ),
                            ),
                          ),
                        if (_buildDetailGalleryImages(target).isNotEmpty)
                          _DetailBlock(
                            title: '剧照',
                            child: _DetailImageGallery(
                              images: _buildDetailGalleryImages(target),
                            ),
                          ),
                        if (target.resolvedDirectorProfiles.isNotEmpty ||
                            target.resolvedActorProfiles.isNotEmpty)
                          _DetailBlock(
                            title: '演职员',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (target
                                    .resolvedDirectorProfiles.isNotEmpty) ...[
                                  const _InfoLabel('导演'),
                                  const SizedBox(height: 10),
                                  _PersonRail(
                                    people: target.resolvedDirectorProfiles,
                                    focusScopePrefix: 'detail:director',
                                    onPersonTap: (person) {
                                      context.pushNamed(
                                        'person-credits',
                                        extra: PersonCreditsPageTarget(
                                          person: person,
                                          role: PersonCreditsRole.director,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                if (target
                                        .resolvedDirectorProfiles.isNotEmpty &&
                                    target.resolvedActorProfiles.isNotEmpty)
                                  const SizedBox(height: 18),
                                if (target
                                    .resolvedActorProfiles.isNotEmpty) ...[
                                  const _InfoLabel('演员'),
                                  const SizedBox(height: 10),
                                  _PersonRail(
                                    people: target.resolvedActorProfiles,
                                    focusScopePrefix: 'detail:actor',
                                    onPersonTap: (person) {
                                      context.pushNamed(
                                        'person-credits',
                                        extra: PersonCreditsPageTarget(
                                          person: person,
                                          role: PersonCreditsRole.actor,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        if (target.resolvedPlatformProfiles.isNotEmpty)
                          _DetailBlock(
                            title: '公司',
                            child: _PlatformRail(
                              platforms: target.resolvedPlatformProfiles,
                            ),
                          ),
                        if (target.sourceName.trim().isNotEmpty ||
                            target.availabilityLabel.trim().isNotEmpty ||
                            _buildResourceFacts(target).isNotEmpty)
                          _DetailBlock(
                            title: '资源信息',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (target.availabilityLabel.trim().isNotEmpty)
                                  _FactRow(
                                    label: '状态',
                                    value: target.availabilityLabel,
                                  ),
                                if (_libraryMatchChoices.length > 1 &&
                                    !_shouldShowPlayableVariantSwitcher(
                                      target,
                                    )) ...[
                                  const SizedBox(height: 12),
                                  const _InfoLabel('本地资源'),
                                  const SizedBox(height: 8),
                                  if (isTelevision)
                                    TvSelectionTile(
                                      title: '本地资源',
                                      value: _libraryMatchOptionLabel(
                                        _libraryMatchChoices[
                                            _currentLibraryMatchIndex],
                                      ),
                                      onPressed: _isMatchingLocalResource
                                          ? null
                                          : _openTelevisionLibraryMatchPicker,
                                      focusId:
                                          'detail:resource:library-selector',
                                    )
                                  else
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        value: _currentLibraryMatchIndex,
                                        isExpanded: true,
                                        dropdownColor: const Color(0xFF142235),
                                        iconEnabledColor: Colors.white70,
                                        style: const TextStyle(
                                          color: Color(0xFFDCE6F8),
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                        items: List.generate(
                                          _libraryMatchChoices.length,
                                          (i) {
                                            return DropdownMenuItem<int>(
                                              value: i,
                                              child: Text(
                                                _libraryMatchOptionLabel(
                                                  _libraryMatchChoices[i],
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            );
                                          },
                                        ),
                                        onChanged: _isMatchingLocalResource
                                            ? null
                                            : (i) {
                                                if (i == null) {
                                                  return;
                                                }
                                                _applySelectedLibraryMatchIndex(
                                                  i,
                                                );
                                              },
                                      ),
                                    ),
                                ],
                                if (target.isPlayable) ...[
                                  const SizedBox(height: 12),
                                  const _InfoLabel('播放器'),
                                  const SizedBox(height: 8),
                                  if (isTelevision)
                                    TvSelectionTile(
                                      title: '播放器',
                                      value: playbackEngine.label,
                                      onPressed: () =>
                                          _openPlaybackEnginePicker(
                                        playbackEngine,
                                      ),
                                      focusId:
                                          'detail:resource:playback-engine',
                                    )
                                  else
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<PlaybackEngine>(
                                        value: playbackEngine,
                                        isExpanded: true,
                                        dropdownColor: const Color(0xFF142235),
                                        iconEnabledColor: Colors.white70,
                                        style: const TextStyle(
                                          color: Color(0xFFDCE6F8),
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                        items: PlaybackEngine.values
                                            .map(
                                              (engine) => DropdownMenuItem<
                                                  PlaybackEngine>(
                                                value: engine,
                                                child: Text(
                                                  engine.label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(growable: false),
                                        onChanged: (selection) {
                                          if (selection == null) {
                                            return;
                                          }
                                          unawaited(
                                            _setPlaybackEngine(
                                              selection,
                                              currentEngine: playbackEngine,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                                if (target.isPlayable) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: isTelevision
                                        ? TvAdaptiveButton(
                                            label: _isSearchingSubtitles
                                                ? '搜索字幕中...'
                                                : (_subtitleSearchChoices
                                                        .isEmpty
                                                    ? '搜索字幕'
                                                    : '刷新字幕'),
                                            icon: Icons.subtitles_rounded,
                                            focusId:
                                                'detail:resource:search-subtitle',
                                            onPressed: _isSearchingSubtitles
                                                ? null
                                                : () =>
                                                    _searchSubtitlesForDetail(
                                                      target,
                                                    ),
                                            variant: TvButtonVariant.text,
                                          )
                                        : TextButton.icon(
                                            onPressed: _isSearchingSubtitles
                                                ? null
                                                : () =>
                                                    _searchSubtitlesForDetail(
                                                      target,
                                                    ),
                                            icon: _isSearchingSubtitles
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.subtitles_rounded,
                                                    size: 16,
                                                  ),
                                            label: Text(
                                              _isSearchingSubtitles
                                                  ? '搜索字幕中...'
                                                  : (_subtitleSearchChoices
                                                          .isEmpty
                                                      ? '搜索字幕'
                                                      : '刷新字幕'),
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 0,
                                                vertical: 0,
                                              ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                  ),
                                  if (_subtitleSearchChoices.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const _InfoLabel('外挂字幕'),
                                    const SizedBox(height: 8),
                                    if (isTelevision)
                                      TvSelectionTile(
                                        title: '外挂字幕',
                                        value: _currentSubtitleSearchIndex < 0
                                            ? '不加载外挂字幕'
                                            : _subtitleSearchChoiceLabel(
                                                _subtitleSearchChoices[
                                                    _currentSubtitleSearchIndex],
                                              ),
                                        onPressed: _busySubtitleResultId != null
                                            ? null
                                            : () =>
                                                _openTelevisionSubtitlePicker(
                                                  target,
                                                ),
                                        focusId:
                                            'detail:resource:subtitle-selector',
                                      )
                                    else
                                      DropdownButtonHideUnderline(
                                        child: DropdownButton<int>(
                                          value: _currentSubtitleSearchIndex,
                                          isExpanded: true,
                                          dropdownColor:
                                              const Color(0xFF142235),
                                          iconEnabledColor: Colors.white70,
                                          style: const TextStyle(
                                            color: Color(0xFFDCE6F8),
                                            fontSize: 14,
                                            height: 1.35,
                                          ),
                                          items: [
                                            const DropdownMenuItem<int>(
                                              value: -1,
                                              child: Text('不加载外挂字幕'),
                                            ),
                                            ...List.generate(
                                              _subtitleSearchChoices.length,
                                              (i) => DropdownMenuItem<int>(
                                                value: i,
                                                child: Text(
                                                  _subtitleSearchChoiceLabel(
                                                    _subtitleSearchChoices[i],
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ],
                                          onChanged:
                                              (_busySubtitleResultId != null ||
                                                      _isSearchingSubtitles)
                                                  ? null
                                                  : (i) {
                                                      if (i == null) {
                                                        return;
                                                      }
                                                      unawaited(
                                                        _applySelectedSubtitleSearchIndex(
                                                          target,
                                                          i,
                                                        ),
                                                      );
                                                    },
                                        ),
                                      ),
                                  ],
                                  if (_subtitleSearchStatusMessage
                                          ?.trim()
                                          .isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _subtitleSearchStatusMessage!,
                                      style: const TextStyle(
                                        color: Color(0xFF9DB0CF),
                                        fontSize: 13,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ],
                                if (_canShowManualResourceMatchButton(
                                    target)) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: isTelevision
                                        ? TvAdaptiveButton(
                                            label: _isMatchingLocalResource
                                                ? '匹配中...'
                                                : '重新匹配资源',
                                            icon: Icons.link_rounded,
                                            focusId:
                                                'detail:resource:match-library',
                                            onPressed: _isMatchingLocalResource
                                                ? null
                                                : () =>
                                                    _matchLocalResource(target),
                                            variant: TvButtonVariant.text,
                                          )
                                        : TextButton.icon(
                                            onPressed: _isMatchingLocalResource
                                                ? null
                                                : () =>
                                                    _matchLocalResource(target),
                                            icon: _isMatchingLocalResource
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.link_rounded,
                                                    size: 16,
                                                  ),
                                            label: Text(
                                              _isMatchingLocalResource
                                                  ? '匹配中...'
                                                  : '重新匹配资源',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 0,
                                                vertical: 0,
                                              ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                  ),
                                ],
                                if (_canManageMetadataIndex(target)) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: isTelevision
                                        ? TvAdaptiveButton(
                                            label: '建立/管理索引',
                                            icon: Icons.manage_search_rounded,
                                            focusId:
                                                'detail:resource:metadata-index',
                                            onPressed: () =>
                                                _openMetadataIndexManager(
                                                    target),
                                            variant: TvButtonVariant.text,
                                          )
                                        : TextButton.icon(
                                            onPressed: () =>
                                                _openMetadataIndexManager(
                                                    target),
                                            icon: const Icon(
                                              Icons.manage_search_rounded,
                                              size: 16,
                                            ),
                                            label: const Text('建立/管理索引'),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 0,
                                                vertical: 0,
                                              ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                  ),
                                ],
                                if (_canManuallyRefreshMetadata(target)) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: isTelevision
                                        ? TvAdaptiveButton(
                                            label: _isRefreshingMetadata
                                                ? '更新中...'
                                                : '手动更新信息',
                                            icon: Icons.refresh_rounded,
                                            focusId:
                                                'detail:resource:refresh-metadata',
                                            onPressed: _isRefreshingMetadata
                                                ? null
                                                : () =>
                                                    _refreshMetadata(target),
                                            variant: TvButtonVariant.text,
                                          )
                                        : TextButton.icon(
                                            onPressed: _isRefreshingMetadata
                                                ? null
                                                : () =>
                                                    _refreshMetadata(target),
                                            icon: _isRefreshingMetadata
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(
                                                    Icons.refresh_rounded,
                                                    size: 16,
                                                  ),
                                            label: Text(
                                              _isRefreshingMetadata
                                                  ? '更新中...'
                                                  : '手动更新信息',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 0,
                                                vertical: 0,
                                              ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                  ),
                                ],
                                if (target.sourceName.trim().isNotEmpty) ...[
                                  if (target.availabilityLabel
                                      .trim()
                                      .isNotEmpty)
                                    const SizedBox(height: 12),
                                  _FactRow(
                                    label: '来源',
                                    value: target.sourceKind == null
                                        ? target.sourceName
                                        : '${target.sourceKind!.label} · ${target.sourceName}',
                                  ),
                                ],
                                for (final fact
                                    in _buildResourceFacts(target)) ...[
                                  const SizedBox(height: 12),
                                  _FactRow(
                                    label: fact.label,
                                    value: fact.value,
                                    selectable: fact.selectable,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        if (_shouldShowPlayableVariantSwitcher(target))
                          _buildPlayableVariantSwitcherBlock(target),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                leadingColor: Colors.white,
                onBack: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _EpisodeGroup _resolveSelectedGroup(List<_EpisodeGroup> groups) {
    if (_selectedSeasonId.trim().isNotEmpty) {
      for (final group in groups) {
        if (group.id == _selectedSeasonId) {
          return group;
        }
      }
    }
    return groups.first;
  }
}

bool _shouldShowLocalResourceMatcher(MediaDetailTarget target) {
  return target.canManuallyMatchLibraryResource;
}

bool _shouldAutoMatchLocalResource(MediaDetailTarget target) {
  final availability = target.availabilityLabel.trim();
  return !target.isPlayable &&
      target.needsLibraryMatch &&
      (availability.isEmpty || availability == '无');
}

bool _canShowManualResourceMatchButton(MediaDetailTarget target) {
  if (_shouldShowLocalResourceMatcher(target)) {
    return true;
  }
  if (_isUnavailableAvailabilityLabel(target.availabilityLabel)) {
    return true;
  }
  if (target.sourceId.trim().isNotEmpty || target.itemId.trim().isNotEmpty) {
    return true;
  }
  return target.title.trim().isNotEmpty || target.searchQuery.trim().isNotEmpty;
}

bool _canManageMetadataIndex(MediaDetailTarget target) {
  return target.sourceKind == MediaSourceKind.nas &&
      target.sourceId.trim().isNotEmpty &&
      target.itemId.trim().isNotEmpty;
}

bool _canManuallyRefreshMetadata(MediaDetailTarget target) {
  if (target.sourceKind == MediaSourceKind.nas &&
      target.sourceId.trim().isNotEmpty) {
    return false;
  }
  return target.title.trim().isNotEmpty || target.searchQuery.trim().isNotEmpty;
}

List<_ResourceFact> _buildResourceFacts(MediaDetailTarget target) {
  final playback = target.playbackTarget;
  final facts = <_ResourceFact>[];
  final streamUrl = playback?.streamUrl.trim() ?? '';
  final actualAddress = playback?.actualAddress.trim() ?? '';
  final resourcePath = target.resourcePath.trim();
  final displayAddress = actualAddress.isNotEmpty
      ? actualAddress
      : resourcePath.isNotEmpty
          ? resourcePath
          : streamUrl;
  final format = playback?.formatLabel.trim() ?? '';
  final fileSize = playback?.fileSizeLabel.trim() ?? '';
  final resolution = playback?.resolutionLabel.trim() ?? '';
  final bitrate = playback?.bitrateLabel.trim() ?? '';
  final duration = target.durationLabel.trim();
  final sectionName = target.sectionName.trim();

  if (displayAddress.isNotEmpty) {
    facts.add(
      _ResourceFact(
        label: '地址',
        value: displayAddress,
        selectable: true,
      ),
    );
  }
  if (format.isNotEmpty) {
    facts.add(_ResourceFact(label: '格式', value: format));
  }
  if (fileSize.isNotEmpty) {
    facts.add(_ResourceFact(label: '大小', value: fileSize));
  }
  if (_isMeaningfulDurationLabel(duration)) {
    facts.add(_ResourceFact(label: '时长', value: duration));
  }
  if (resolution.isNotEmpty) {
    facts.add(_ResourceFact(label: '清晰度', value: resolution));
  }
  if (bitrate.isNotEmpty) {
    facts.add(_ResourceFact(label: '码率', value: bitrate));
  }
  if (sectionName.isNotEmpty) {
    facts.add(_ResourceFact(label: '分区', value: sectionName));
  }

  return facts;
}

bool _isMeaningfulDurationLabel(String label) {
  final trimmed = label.trim();
  return trimmed.isNotEmpty && trimmed != '时长未知' && trimmed != '文件';
}

String _overviewSectionTitle(MediaDetailTarget target) {
  if (target.itemType.trim().toLowerCase() == 'episode') {
    final seriesTitle = target.playbackTarget?.seriesTitle.trim() ?? '';
    if (seriesTitle.isNotEmpty) {
      return seriesTitle;
    }
  }
  final title = target.title.trim();
  if (title.isNotEmpty) {
    return title;
  }
  final query = target.searchQuery.trim();
  if (query.isNotEmpty) {
    return query;
  }
  return '剧情简介';
}

String _availabilityFeedbackLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.startsWith('资源已就绪：')) {
    return trimmed.substring('资源已就绪：'.length).trim();
  }
  if (trimmed.startsWith('已匹配：')) {
    return trimmed.substring('已匹配：'.length).trim();
  }
  return trimmed;
}

bool _isUnavailableAvailabilityLabel(String label) {
  return _availabilityFeedbackLabel(label) == '无';
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.target});

  final MediaDetailTarget target;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isCompact = screenWidth < 760;
    final heroHeight = math.max(560.0, math.min(screenHeight * 0.76, 760.0));
    final hasHeroLogo = target.logoUrl.trim().isNotEmpty;
    final metadata = <String>[
      ...target.ratingLabels.where((item) => item.trim().isNotEmpty),
      if (target.year > 0) '${target.year}',
      if (target.durationLabel.trim().isNotEmpty) target.durationLabel,
      ...target.genres.take(3).where((item) => item.trim().isNotEmpty),
    ];
    final peopleLine = <String>[
      if (target.directors.isNotEmpty)
        '导演 ${target.directors.take(2).join(' / ')}',
      if (target.actors.isNotEmpty) '演员 ${target.actors.take(3).join(' / ')}',
    ].join('  ·  ');

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          _BackdropImage(
            imageUrl: _resolvePrimaryBackdropAsset(target).url,
            imageHeaders: _resolvePrimaryBackdropAsset(target).headers,
            fallbackSources: _buildPrimaryBackdropFallbackSources(target),
          ),
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FractionallySizedBox(
                widthFactor: isCompact ? 1 : (hasHeroLogo ? 0.76 : 0.64),
                heightFactor: isCompact ? 0.74 : 0.84,
                alignment: Alignment.bottomLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: isCompact
                          ? const Alignment(-0.72, 0.96)
                          : const Alignment(-0.96, 0.96),
                      radius: isCompact ? 1.22 : 1.08,
                      colors: [
                        Colors.black.withValues(
                          alpha: hasHeroLogo ? 0.82 : 0.74,
                        ),
                        Colors.black.withValues(
                          alpha: hasHeroLogo ? 0.44 : 0.32,
                        ),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.5, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Padding(
              padding: EdgeInsets.only(top: kToolbarHeight),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final content = _HeroContent(
                    target: target,
                    metadata: metadata,
                    peopleLine: peopleLine,
                  );

                  if (isCompact) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [content],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [Expanded(child: content)],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroContent extends ConsumerWidget {
  const _HeroContent({
    required this.target,
    required this.metadata,
    required this.peopleLine,
  });

  final MediaDetailTarget target;
  final List<String> metadata;
  final String peopleLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final hasLogo = target.logoUrl.trim().isNotEmpty;
    final resumeEntry =
        ref.watch(playbackResumeForDetailTargetProvider(target)).valueOrNull;
    final showResumeAction =
        resumeEntry != null && (target.isSeries || resumeEntry.canResume);
    final primaryPlaybackTarget = _resolvePrimaryPlaybackTarget(
        target, resumeEntry,
        preferResume: showResumeAction);
    final primaryPlaybackLabel = showResumeAction ? '继续播放' : '立即播放';
    final canSearchResource = target.searchQuery.trim().isNotEmpty;
    final searchAutofocus = primaryPlaybackTarget == null && canSearchResource;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: hasLogo ? 760 : 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasLogo && metadata.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metadata
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (!hasLogo && metadata.isNotEmpty) const SizedBox(height: 14),
          if (hasLogo)
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 520,
                maxHeight: 148,
              ),
              child: AppNetworkImage(
                target.logoUrl,
                headers: target.logoHeaders,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorBuilder: (context, error, stackTrace) {
                  return Text(
                    target.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 38,
                          height: 1.04,
                        ),
                  );
                },
              ),
            )
          else
            Text(
              target.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 38,
                    height: 1.04,
                  ),
            ),
          if (hasLogo && metadata.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metadata
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (peopleLine.trim().isNotEmpty) ...[
            SizedBox(height: hasLogo ? 14 : 12),
            Text(
              peopleLine,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD7E2F8),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
          SizedBox(height: hasLogo ? 24 : 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (primaryPlaybackTarget != null)
                isTelevision
                    ? TvAdaptiveButton(
                        label: primaryPlaybackLabel,
                        icon: Icons.play_arrow_rounded,
                        focusId: 'detail:hero:play',
                        autofocus: true,
                        onPressed: () {
                          context.pushNamed('player',
                              extra: primaryPlaybackTarget);
                        },
                      )
                    : FilledButton.icon(
                        onPressed: () {
                          context.pushNamed('player',
                              extra: primaryPlaybackTarget);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF081120),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 15,
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(primaryPlaybackLabel),
                      ),
              if (!target.isPlayable && target.searchQuery.trim().isNotEmpty)
                isTelevision
                    ? TvAdaptiveButton(
                        label: '搜索资源',
                        icon: Icons.search_rounded,
                        focusId: 'detail:hero:search',
                        autofocus: searchAutofocus,
                        onPressed: () {
                          context.pushNamed(
                            'detail-search',
                            queryParameters: {'q': target.searchQuery},
                          );
                        },
                      )
                    : FilledButton.icon(
                        onPressed: () {
                          context.pushNamed(
                            'detail-search',
                            queryParameters: {'q': target.searchQuery},
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF081120),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 15,
                          ),
                        ),
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('搜索资源'),
                      ),
              if (target.isPlayable && target.searchQuery.trim().isNotEmpty)
                isTelevision
                    ? TvAdaptiveButton(
                        label: '搜索资源',
                        icon: Icons.search_rounded,
                        focusId: 'detail:hero:search',
                        autofocus: searchAutofocus,
                        onPressed: () {
                          context.pushNamed(
                            'detail-search',
                            queryParameters: {'q': target.searchQuery},
                          );
                        },
                        variant: TvButtonVariant.outlined,
                      )
                    : OutlinedButton.icon(
                        onPressed: () {
                          context.pushNamed(
                            'detail-search',
                            queryParameters: {'q': target.searchQuery},
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.24),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 15,
                          ),
                        ),
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('搜索资源'),
                      ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackdropImage extends StatelessWidget {
  const _BackdropImage({
    required this.imageUrl,
    this.imageHeaders = const {},
    this.fallbackSources = const [],
  });

  final String imageUrl;
  final Map<String, String> imageHeaders;
  final List<AppNetworkImageSource> fallbackSources;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return const ColoredBox(color: Color(0xFF0A1423));
    }

    return AppNetworkImage(
      imageUrl,
      headers: imageHeaders,
      fallbackSources: fallbackSources,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (context, error, stackTrace) {
        return const ColoredBox(color: Color(0xFF0A1423));
      },
    );
  }
}

class _SeriesBrowserState {
  const _SeriesBrowserState({required this.groups});

  final List<_EpisodeGroup> groups;
}

class _EpisodeGroup {
  const _EpisodeGroup({
    required this.id,
    required this.title,
    required this.seasonNumber,
    required this.episodes,
  });

  final String id;
  final String title;
  final int? seasonNumber;
  final List<MediaItem> episodes;

  String get label {
    if (seasonNumber != null && seasonNumber! > 0) {
      return '第 $seasonNumber 季';
    }
    return title;
  }
}

List<MediaItem> _sortEpisodes(List<MediaItem> items) {
  final sorted = [...items]..sort((left, right) {
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
    });
  return sorted;
}

class _EpisodeBrowser extends StatelessWidget {
  const _EpisodeBrowser({
    required this.seriesTarget,
    required this.groups,
    required this.selectedGroupId,
    required this.onSeasonSelected,
  });

  final MediaDetailTarget seriesTarget;
  final List<_EpisodeGroup> groups;
  final String selectedGroupId;
  final ValueChanged<String> onSeasonSelected;

  @override
  Widget build(BuildContext context) {
    _EpisodeGroup selectedGroup = groups.first;
    for (final group in groups) {
      if (group.id == selectedGroupId) {
        selectedGroup = group;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groups.length > 1) ...[
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: groups.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final group = groups[index];
                final selected = group.id == selectedGroup.id;
                return _SeasonChip(
                  label: group.label,
                  selected: selected,
                  focusId: 'detail:season:${group.id}',
                  autofocus: index == 0,
                  onTap: () => onSeasonSelected(group.id),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 272,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: selectedGroup.episodes.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final episode = selectedGroup.episodes[index];
              return SizedBox(
                width: 292,
                child: _EpisodeCard(
                  item: episode,
                  seriesTarget: seriesTarget,
                  focusId:
                      'detail:episode:${episode.id.isNotEmpty ? episode.id : '${episode.seasonNumber ?? 0}-${episode.episodeNumber ?? index}'}',
                  autofocus: index == 0,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.focusId,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusableAction(
      onPressed: onTap,
      focusId: focusId,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(999),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF081120) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeCard extends ConsumerWidget {
  const _EpisodeCard({
    required this.item,
    required this.seriesTarget,
    this.focusId,
    this.autofocus = false,
  });

  final MediaItem item;
  final MediaDetailTarget seriesTarget;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackEntry =
        ref.watch(playbackEntryForMediaItemProvider(item)).valueOrNull;
    final badgeText = _episodeBadgeText(item, playbackEntry);
    final summary = _episodeSummary(item);
    final onPlay = item.isPlayable
        ? () {
            context.pushNamed(
              'player',
              extra: item.isPlayable
                  ? _itemToPlaybackTarget(
                      item,
                      seriesTarget: seriesTarget,
                    )
                  : null,
            );
          }
        : null;
    void onOpenDetail() {
      context.pushNamed(
        'detail',
        extra: _episodeToDetailTarget(
          item,
          seriesTarget: seriesTarget,
        ),
      );
    }

    final effectiveFocusId = focusId?.trim() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvFocusableAction(
            onPressed: onPlay,
            focusId: effectiveFocusId.isEmpty ? null : '$effectiveFocusId:play',
            autofocus: autofocus && onPlay != null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _EpisodeArtwork(item: item),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.18),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.12),
                            Colors.black.withValues(alpha: 0.58),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomCenter,
                          stops: const [0, 0.34, 0.62, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 46,
                      top: 14,
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          shadows: [
                            Shadow(
                              color: Color(0xAA000000),
                              blurRadius: 16,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 214),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.46),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Icon(
                        item.isPlayable
                            ? Icons.play_circle_fill_rounded
                            : Icons.lock_outline_rounded,
                        color: item.isPlayable
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.42),
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: TvFocusableAction(
              onPressed: onOpenDetail,
              focusId:
                  effectiveFocusId.isEmpty ? null : '$effectiveFocusId:detail',
              autofocus: autofocus && onPlay == null,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
              visualStyle: TvFocusVisualStyle.subtle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Text(
                  summary,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD7E0F1),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _episodeBadgeText(
    MediaItem item,
    PlaybackProgressEntry? playbackEntry,
  ) {
    final entries = <String>[
      item.episodeNumber != null ? '第 ${item.episodeNumber} 集' : '剧集',
      if (item.durationLabel.trim().isNotEmpty && item.durationLabel != '时长未知')
        item.durationLabel,
      if (_progressLabel(item, playbackEntry).trim().isNotEmpty)
        _progressLabel(item, playbackEntry),
    ];
    return entries.join(' · ');
  }

  String _episodeSummary(MediaItem item) {
    if (item.overview.trim().isNotEmpty) {
      return item.overview;
    }
    final fallback = <String>[
      if (item.seasonNumber != null && item.episodeNumber != null)
        '第 ${item.seasonNumber} 季 第 ${item.episodeNumber} 集',
      if (item.durationLabel.trim().isNotEmpty && item.durationLabel != '时长未知')
        item.durationLabel,
      if (!item.isPlayable) '当前没有可直接播放的资源',
    ];
    if (fallback.isEmpty) {
      return '暂无简介';
    }
    return fallback.join(' · ');
  }

  String _progressLabel(
    MediaItem item,
    PlaybackProgressEntry? playbackEntry,
  ) {
    final progress = playbackEntry?.progress ?? item.playbackProgress;
    if (progress == null || progress <= 0) {
      return '';
    }
    if (progress >= 0.995) {
      return '已看完';
    }
    return '已看 ${(progress * 100).round()}%';
  }
}

class _EpisodeArtwork extends StatelessWidget {
  const _EpisodeArtwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final artwork = _resolveEpisodeArtworkAsset(item);
    if (artwork.url.isNotEmpty) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: AppNetworkImage(
          artwork.url,
          headers: artwork.headers,
          fallbackSources: _buildEpisodeArtworkFallbackSources(item),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _EpisodeArtworkFallback(
            item: item,
          ),
        ),
      );
    }
    return _EpisodeArtworkFallback(item: item);
  }
}

class _EpisodeArtworkFallback extends StatelessWidget {
  const _EpisodeArtworkFallback({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        gradient: LinearGradient(
          colors: [
            Color(0xFF24324B),
            Color(0xFF101B2E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          item.isPlayable
              ? Icons.play_circle_outline_rounded
              : Icons.movie_outlined,
          color: Colors.white.withValues(alpha: 0.78),
          size: 34,
        ),
      ),
    );
  }
}

PlaybackTarget? _resolvePrimaryPlaybackTarget(
  MediaDetailTarget target,
  PlaybackProgressEntry? resumeEntry, {
  required bool preferResume,
}) {
  if (resumeEntry != null && preferResume) {
    final targetSubtitle = target.playbackTarget;
    if (targetSubtitle == null) {
      return resumeEntry.target;
    }
    return resumeEntry.target.copyWith(
      externalSubtitleFilePath: targetSubtitle.externalSubtitleFilePath,
      externalSubtitleDisplayName: targetSubtitle.externalSubtitleDisplayName,
    );
  }
  return target.playbackTarget;
}

PlaybackTarget _itemToPlaybackTarget(
  MediaItem item, {
  MediaDetailTarget? seriesTarget,
}) {
  final base = PlaybackTarget.fromMediaItem(item);
  if (seriesTarget == null) {
    return base;
  }
  final isSeriesLike = seriesTarget.itemType.trim().toLowerCase() == 'series';
  if (!isSeriesLike) {
    return base;
  }
  return base.copyWith(
    seriesId: seriesTarget.itemId,
    seriesTitle: seriesTarget.title,
  );
}

MediaDetailTarget _episodeToDetailTarget(
  MediaItem item, {
  required MediaDetailTarget seriesTarget,
}) {
  final seriesQuery = seriesTarget.searchQuery.trim().isNotEmpty
      ? seriesTarget.searchQuery.trim()
      : seriesTarget.title.trim();
  final target = MediaDetailTarget.fromMediaItem(
    item,
    searchQuery: seriesQuery.isNotEmpty ? seriesQuery : item.title,
  );
  final useOwnPoster = target.posterUrl.trim().isNotEmpty;
  final useOwnBackdrop = target.backdropUrl.trim().isNotEmpty;
  final useOwnLogo = target.logoUrl.trim().isNotEmpty;
  final useOwnBanner = target.bannerUrl.trim().isNotEmpty;
  final useOwnExtraBackdrops = target.extraBackdropUrls.isNotEmpty;
  return target.copyWith(
    playbackTarget: item.isPlayable
        ? _itemToPlaybackTarget(item, seriesTarget: seriesTarget)
        : target.playbackTarget,
    posterUrl: useOwnPoster ? target.posterUrl : seriesTarget.posterUrl,
    posterHeaders:
        useOwnPoster ? target.posterHeaders : seriesTarget.posterHeaders,
    backdropUrl: useOwnBackdrop ? target.backdropUrl : seriesTarget.backdropUrl,
    backdropHeaders:
        useOwnBackdrop ? target.backdropHeaders : seriesTarget.backdropHeaders,
    logoUrl: useOwnLogo ? target.logoUrl : seriesTarget.logoUrl,
    logoHeaders: useOwnLogo ? target.logoHeaders : seriesTarget.logoHeaders,
    bannerUrl: useOwnBanner ? target.bannerUrl : seriesTarget.bannerUrl,
    bannerHeaders:
        useOwnBanner ? target.bannerHeaders : seriesTarget.bannerHeaders,
    extraBackdropUrls: useOwnExtraBackdrops
        ? target.extraBackdropUrls
        : seriesTarget.extraBackdropUrls,
    extraBackdropHeaders: useOwnExtraBackdrops
        ? target.extraBackdropHeaders
        : seriesTarget.extraBackdropHeaders,
    doubanId: target.doubanId.trim().isNotEmpty
        ? target.doubanId
        : seriesTarget.doubanId,
    imdbId:
        target.imdbId.trim().isNotEmpty ? target.imdbId : seriesTarget.imdbId,
    tmdbId:
        target.tmdbId.trim().isNotEmpty ? target.tmdbId : seriesTarget.tmdbId,
    tvdbId:
        target.tvdbId.trim().isNotEmpty ? target.tvdbId : seriesTarget.tvdbId,
    wikidataId: target.wikidataId.trim().isNotEmpty
        ? target.wikidataId
        : seriesTarget.wikidataId,
    tmdbSetId: target.tmdbSetId.trim().isNotEmpty
        ? target.tmdbSetId
        : seriesTarget.tmdbSetId,
    providerIds: target.providerIds.isNotEmpty
        ? target.providerIds
        : seriesTarget.providerIds,
  );
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoLabel extends StatelessWidget {
  const _InfoLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF8FA0BD),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PersonRail extends StatelessWidget {
  const _PersonRail({
    required this.people,
    required this.focusScopePrefix,
    required this.onPersonTap,
  });

  final List<MediaPersonProfile> people;
  final String focusScopePrefix;
  final ValueChanged<MediaPersonProfile> onPersonTap;

  @override
  Widget build(BuildContext context) {
    final visiblePeople = people
        .where((item) => item.name.trim().isNotEmpty)
        .toList(growable: false);
    if (visiblePeople.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: visiblePeople.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final person = visiblePeople[index];
          return TvFocusableAction(
            onPressed: () => onPersonTap(person),
            focusId: '$focusScopePrefix:${person.name}',
            autofocus: index == 0,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 86,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PersonAvatar(person: person),
                  const SizedBox(height: 10),
                  Text(
                    person.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.person});

  final MediaPersonProfile person;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = person.avatarUrl.trim();
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF162233),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl.isEmpty
          ? Center(
              child: Text(
                _personInitial(person.name),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : AppNetworkImage(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Text(
                    _personInitial(person.name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PlatformRail extends StatelessWidget {
  const _PlatformRail({required this.platforms});

  final List<MediaPersonProfile> platforms;

  @override
  Widget build(BuildContext context) {
    final visiblePlatforms = platforms
        .where(
          (item) =>
              item.name.trim().isNotEmpty && item.avatarUrl.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (visiblePlatforms.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 24,
      runSpacing: 18,
      children: visiblePlatforms
          .map((platform) => _PlatformLogo(platform: platform))
          .toList(growable: false),
    );
  }
}

class _PlatformLogo extends StatelessWidget {
  const _PlatformLogo({required this.platform});

  final MediaPersonProfile platform;

  @override
  Widget build(BuildContext context) {
    final logoUrl = platform.avatarUrl.trim();
    if (logoUrl.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: 108,
      height: 34,
      child: AppNetworkImage(
        logoUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

String _personInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8FA0BD),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: selectable
              ? SelectableText(
                  value,
                  style: const TextStyle(
                    color: Color(0xFFE6EDFD),
                    fontSize: 14,
                    height: 1.5,
                  ),
                )
              : Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFFE6EDFD),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ResourceFact {
  const _ResourceFact({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;
}

class _DetailImageAsset {
  const _DetailImageAsset({
    required this.url,
    this.headers = const {},
  });

  final String url;
  final Map<String, String> headers;
}

class _DetailImageGallery extends StatelessWidget {
  const _DetailImageGallery({required this.images});

  final List<_DetailImageAsset> images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 164,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: images.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final image = images[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: SizedBox(
                width: 268,
                child: AppNetworkImage(
                  image.url,
                  headers: image.headers,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const ColoredBox(color: Color(0xFF0D192A));
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

_DetailImageAsset _resolvePrimaryBackdropAsset(MediaDetailTarget target) {
  if (target.backdropUrl.trim().isNotEmpty) {
    return _DetailImageAsset(
      url: target.backdropUrl.trim(),
      headers: target.backdropHeaders,
    );
  }
  if (target.bannerUrl.trim().isNotEmpty) {
    return _DetailImageAsset(
      url: target.bannerUrl.trim(),
      headers: target.bannerHeaders,
    );
  }
  if (target.extraBackdropUrls.isNotEmpty) {
    return _DetailImageAsset(
      url: target.extraBackdropUrls.first,
      headers: target.extraBackdropHeaders,
    );
  }
  if (target.posterUrl.trim().isNotEmpty) {
    return _DetailImageAsset(
      url: target.posterUrl.trim(),
      headers: target.posterHeaders,
    );
  }
  return const _DetailImageAsset(url: '');
}

List<AppNetworkImageSource> _buildPrimaryBackdropFallbackSources(
  MediaDetailTarget target,
) {
  final sources = <AppNetworkImageSource>[];
  final seen = <String>{target.backdropUrl.trim()};

  void add(String url, Map<String, String> headers) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !seen.add(trimmedUrl)) {
      return;
    }
    sources.add(
      AppNetworkImageSource(
        url: trimmedUrl,
        headers: headers,
      ),
    );
  }

  add(target.bannerUrl, target.bannerHeaders);
  for (final url in target.extraBackdropUrls) {
    add(url, target.extraBackdropHeaders);
  }
  add(target.posterUrl, target.posterHeaders);
  return sources;
}

List<_DetailImageAsset> _buildDetailGalleryImages(MediaDetailTarget target) {
  final seen = <String>{};
  final images = <_DetailImageAsset>[];

  void add(String url, Map<String, String> headers) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      return;
    }
    images.add(_DetailImageAsset(url: trimmed, headers: headers));
  }

  add(target.backdropUrl, target.backdropHeaders);
  add(target.bannerUrl, target.bannerHeaders);
  for (final url in target.extraBackdropUrls) {
    add(url, target.extraBackdropHeaders);
  }
  return images;
}

_DetailImageAsset _resolveEpisodeArtworkAsset(MediaItem item) {
  if (item.backdropUrl.trim().isNotEmpty) {
    return _DetailImageAsset(
      url: item.backdropUrl.trim(),
      headers: item.backdropHeaders,
    );
  }
  if (item.bannerUrl.trim().isNotEmpty) {
    return _DetailImageAsset(
      url: item.bannerUrl.trim(),
      headers: item.bannerHeaders,
    );
  }
  if (item.extraBackdropUrls.isNotEmpty) {
    return _DetailImageAsset(
      url: item.extraBackdropUrls.first,
      headers: item.extraBackdropHeaders,
    );
  }
  if (item.posterUrl.trim().isNotEmpty) {
    return _DetailImageAsset(
      url: item.posterUrl.trim(),
      headers: item.posterHeaders,
    );
  }
  return const _DetailImageAsset(url: '');
}

List<AppNetworkImageSource> _buildEpisodeArtworkFallbackSources(
  MediaItem item,
) {
  final sources = <AppNetworkImageSource>[];
  final seen = <String>{item.backdropUrl.trim()};

  void add(String url, Map<String, String> headers) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !seen.add(trimmedUrl)) {
      return;
    }
    sources.add(
      AppNetworkImageSource(
        url: trimmedUrl,
        headers: headers,
      ),
    );
  }

  add(item.bannerUrl, item.bannerHeaders);
  for (final url in item.extraBackdropUrls) {
    add(url, item.extraBackdropHeaders);
  }
  add(item.posterUrl, item.posterHeaders);
  return sources;
}
