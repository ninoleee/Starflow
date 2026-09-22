import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/features/details/application/detail_enrichment_settings.dart';
import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/application/douban_rating_stats_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';

enum DetailMetadataOutcome {
  skipped,
  noMatch,
  succeeded,
  partialFailure,
  failed
}

class DetailMetadataResult {
  const DetailMetadataResult({required this.target, required this.outcome});

  final MediaDetailTarget target;
  final DetailMetadataOutcome outcome;

  bool get hasFailure =>
      outcome == DetailMetadataOutcome.failed ||
      outcome == DetailMetadataOutcome.partialFailure;
}

String _detailMetadataQuery(MediaDetailTarget target) {
  final raw =
      target.searchQuery.trim().isEmpty ? target.title : target.searchQuery;
  return raw.trim();
}

class _DetailAutomaticMetadataNeeds {
  const _DetailAutomaticMetadataNeeds({
    required this.needsWmdb,
    required this.needsTmdb,
  });

  final bool needsWmdb;
  final bool needsTmdb;
}

_DetailAutomaticMetadataNeeds _resolveDetailAutomaticMetadataNeeds({
  required MediaDetailTarget target,
  required DetailEnrichmentSettings settings,
  bool forceSearch = false,
}) {
  final query = _detailMetadataQuery(target);
  final canUseTmdb = settings.tmdbMetadataMatchEnabled &&
      settings.tmdbReadAccessToken.trim().isNotEmpty &&
      query.isNotEmpty;
  if (!forceSearch &&
      target.sourceKind == MediaSourceKind.nas &&
      target.sourceId.trim().isNotEmpty) {
    return _DetailAutomaticMetadataNeeds(
      needsWmdb: false,
      needsTmdb: canUseTmdb && target.needsPersonProfileMatch,
    );
  }
  if (query.isEmpty && target.doubanId.trim().isEmpty) {
    return const _DetailAutomaticMetadataNeeds(
      needsWmdb: false,
      needsTmdb: false,
    );
  }
  final needsWmdb = settings.wmdbMetadataMatchEnabled &&
      (forceSearch ||
          target.needsMetadataMatch ||
          !hasUsableRatingForSource(
              target.ratingLabels, MediaRatingSource.douban) ||
          target.needsImdbRatingMatch ||
          target.doubanId.trim().isEmpty ||
          target.imdbId.trim().isEmpty);
  final needsTmdb = canUseTmdb &&
      (forceSearch ||
          target.needsMetadataMatch ||
          target.needsPersonProfileMatch ||
          target.backdropUrl.trim().isEmpty ||
          target.logoUrl.trim().isEmpty);
  return _DetailAutomaticMetadataNeeds(
    needsWmdb: needsWmdb,
    needsTmdb: needsTmdb,
  );
}

Future<DetailMetadataResult> resolveDetailMetadata({
  required DetailEnrichmentSettings settings,
  required MediaDetailTarget target,
  required WmdbMetadataClient wmdbMetadataClient,
  required TmdbMetadataClient tmdbMetadataClient,
  required String traceKey,
  DoubanApiClient? doubanApiClient,
  String doubanCookie = '',
  bool forceSearch = false,
  bool forceReplace = false,
  bool forceRatingRefresh = false,
}) async {
  var nextTarget = target;
  var attempts = 0;
  var failures = 0;
  var matches = 0;
  Future<void> enrichRating() async {
    if (doubanApiClient == null) return;
    attempts += 1;
    try {
      final enriched = await enrichDetailTargetWithDoubanRatingStats(
        target: nextTarget,
        doubanApiClient: doubanApiClient,
        cookie: doubanCookie,
        propagateErrors: true,
      );
      if (!identical(enriched, nextTarget)) matches += 1;
      nextTarget = enriched;
    } catch (error, stackTrace) {
      failures += 1;
      appLogWarning('metadata.refresh', 'Douban rating refresh failed',
          error: error, stackTrace: stackTrace);
    }
  }

  final initialDoubanId = target.doubanId.trim();
  if (initialDoubanId.isNotEmpty &&
      (forceSearch ||
          forceRatingRefresh ||
          !hasUsableRatingForSource(
              target.ratingLabels, MediaRatingSource.douban))) {
    await enrichRating();
  }
  var metadataNeeds = _resolveDetailAutomaticMetadataNeeds(
    target: nextTarget,
    settings: settings,
    forceSearch: forceSearch,
  );
  final initialQuery = _detailMetadataQuery(target);
  if (metadataNeeds.needsWmdb) {
    attempts += 1;
    try {
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
        matches += 1;
        nextTarget =
            const DetailLibraryMatchService().applyMetadataMatchToDetailTarget(
          nextTarget,
          wmdbMatch,
          replaceExisting: forceReplace,
        );
      }
    } catch (error, stackTrace) {
      failures += 1;
      appLogError('metadata', 'detail.wmdb',
          fields: {'key': traceKey, 'message': 'failed'},
          error: error,
          stackTrace: stackTrace);
    }
    metadataNeeds = _resolveDetailAutomaticMetadataNeeds(
      target: nextTarget,
      settings: settings,
      forceSearch: forceSearch,
    );
  }

  if (metadataNeeds.needsTmdb) {
    attempts += 1;
    try {
      final currentQuery = _detailMetadataQuery(nextTarget);
      final tmdbMatch = await tmdbMetadataClient.matchTitle(
        query: currentQuery,
        readAccessToken: settings.tmdbReadAccessToken.trim(),
        year: nextTarget.year,
        preferSeries: _prefersSeriesMetadata(nextTarget),
      );
      if (tmdbMatch != null) {
        matches += 1;
        final resolvedBackdropUrl = await _resolveTmdbBackdropForTarget(
          settings: settings,
          tmdbMetadataClient: tmdbMetadataClient,
          target: nextTarget,
          match: tmdbMatch,
        );
        nextTarget =
            const DetailLibraryMatchService().applyMetadataMatchToDetailTarget(
          nextTarget,
          MetadataMatchResult(
            provider: MetadataMatchProvider.tmdb,
            mediaType: tmdbMatch.isSeries
                ? MetadataMediaType.series
                : MetadataMediaType.movie,
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
                    tmdbId: item.tmdbId,
                  ),
                )
                .toList(growable: false),
            actors: tmdbMatch.actors,
            actorProfiles: tmdbMatch.actorProfiles
                .map(
                  (item) => MetadataPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                    tmdbId: item.tmdbId,
                  ),
                )
                .toList(growable: false),
            platforms: tmdbMatch.platforms,
            platformProfiles: tmdbMatch.platformProfiles
                .map(
                  (item) => MetadataPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                    tmdbId: item.tmdbId,
                  ),
                )
                .toList(growable: false),
            ratingLabels: tmdbMatch.ratingLabels,
            imdbId: tmdbMatch.imdbId,
            tmdbId: '${tmdbMatch.tmdbId}',
          ),
          replaceExisting: forceReplace,
        );
      }
    } catch (error, stackTrace) {
      failures += 1;
      appLogError('metadata', 'detail.tmdb',
          fields: {'key': traceKey, 'message': 'failed'},
          error: error,
          stackTrace: stackTrace);
    }
  }
  if (nextTarget.doubanId.trim().isNotEmpty &&
      nextTarget.doubanId.trim() != initialDoubanId) {
    await enrichRating();
  }
  return DetailMetadataResult(
    target: nextTarget.copyWith(
      ratingLabels:
          mergeDistinctRatingLabels(const [], nextTarget.ratingLabels),
    ),
    outcome: attempts == 0
        ? DetailMetadataOutcome.skipped
        : failures == attempts
            ? DetailMetadataOutcome.failed
            : failures > 0
                ? DetailMetadataOutcome.partialFailure
                : matches == 0
                    ? DetailMetadataOutcome.noMatch
                    : DetailMetadataOutcome.succeeded,
  );
}

bool _prefersSeriesMetadata(MediaDetailTarget target) {
  final itemType = target.itemType.trim().toLowerCase();
  return itemType == 'series' || itemType == 'season' || itemType == 'episode';
}

Future<String> _resolveTmdbBackdropForTarget({
  required DetailEnrichmentSettings settings,
  required TmdbMetadataClient tmdbMetadataClient,
  required MediaDetailTarget target,
  required TmdbMetadataMatch match,
}) async {
  if (isEpisodeMetadataTarget(target) &&
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
  if (!isEpisodeMetadataTarget(target)) {
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
  return const DetailLibraryMatchService()
      .mergeUniqueImageUrls([
        if (bannerUrl.isNotEmpty) bannerUrl,
        ...match.extraBackdropUrls,
      ])
      .where((item) => item != resolvedBackdropUrl.trim())
      .toList(growable: false);
}

bool isEpisodeMetadataTarget(MediaDetailTarget target) {
  return target.itemType.trim().toLowerCase() == 'episode' &&
      target.seasonNumber != null &&
      target.seasonNumber! >= 0 &&
      target.episodeNumber != null &&
      target.episodeNumber! > 0;
}
