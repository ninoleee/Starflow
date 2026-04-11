import 'dart:async';
import 'dart:math' as math;

export 'package:starflow/features/details/presentation/detail_page_providers.dart'
    show enrichedDetailTargetProvider;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';
import 'package:starflow/core/navigation/retained_async_controller.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/debug_trace_once.dart';
import 'package:starflow/core/utils/subtitle_search_trace.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/application/detail_enrichment_settings.dart';
import 'package:starflow/features/details/application/detail_external_episode_variant_service.dart';
import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/application/detail_page_actions.dart';
import 'package:starflow/features/details/application/detail_page_controller.dart';
import 'package:starflow/features/details/application/detail_subtitle_controller.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/detail_page_providers.dart';
import 'package:starflow/features/details/presentation/person_credits_page.dart';
import 'package:starflow/features/details/presentation/widgets/detail_episode_browser.dart';
import 'package:starflow/features/details/presentation/widgets/detail_hero_section.dart';
import 'package:starflow/features/details/presentation/widgets/detail_resource_info_section.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/details/presentation/widgets/detail_television_picker_dialog.dart';
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
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

const DetailLibraryMatchService _detailLibraryMatchService =
    DetailLibraryMatchService();
const DetailSubtitleController _detailSubtitleController =
    DetailSubtitleController();
final DetailCachedStateRestorer _detailCachedStateRestorer =
    DetailCachedStateRestorer();

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

bool _shouldUseStandaloneImdbRating(DetailEnrichmentSettings settings) {
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
  required DetailEnrichmentSettings settings,
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
  required DetailEnrichmentSettings settings,
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
        final nextRatingLabel = ratingMatch.ratingLabel.trim();
        nextTarget = nextTarget.copyWith(
          ratingLabels: _mergeLabels(
            nextTarget.ratingLabels,
            nextRatingLabel.isEmpty ? const [] : [nextRatingLabel],
          ),
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

  return _normalizeRatingLabelsInTarget(nextTarget);
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

  final allowedQuarkSources = allowedSources
      .where((source) => source.kind == MediaSourceKind.quark)
      .toList(growable: false);
  for (final source in allowedQuarkSources) {
    taskFactories.add(() async {
      controller.throwIfCancelled();
      try {
        final items = await mediaRepository.fetchLibrary(
          kind: MediaSourceKind.quark,
          sourceId: source.id,
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
  return _detailLibraryMatchService.resolveLibraryMatchSources(settings);
}

List<MediaDetailTarget> _candidatesToMergedTargets(
  MediaDetailTarget current,
  List<_LibraryMatchCandidate> candidates,
  String query,
) {
  final mappedCandidates = candidates
      .map(
        (item) => DetailLibraryMatchCandidate(
          item: item.item,
          matchReason: item.matchReason,
          score: item.score,
        ),
      )
      .toList(growable: false);
  return _detailLibraryMatchService.candidatesToMergedTargets(
    current,
    mappedCandidates,
    query,
  );
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
  return _detailLibraryMatchService.buildManualMatchTitles(
    target: target,
    query: query,
    metadataMatch: metadataMatch,
  );
}

int _resolveManualMatchYear(
  MediaDetailTarget target,
  MetadataMatchResult? metadataMatch,
) {
  return _detailLibraryMatchService.resolveManualMatchYear(
    target,
    metadataMatch,
  );
}

String _externalIdMatchReason(
  MediaItem item, {
  required String doubanId,
  required String imdbId,
  required String tmdbId,
  required String tvdbId,
  required String wikidataId,
}) {
  return _detailLibraryMatchService.externalIdMatchReason(
    item,
    doubanId: doubanId,
    imdbId: imdbId,
    tmdbId: tmdbId,
    tvdbId: tvdbId,
    wikidataId: wikidataId,
  );
}

String _titleMatchReason(int year) {
  return _detailLibraryMatchService.titleMatchReason(year);
}

String _resolveManualMatchDoubanId(
  MediaDetailTarget target,
  MetadataMatchResult? metadataMatch,
) {
  return _detailLibraryMatchService.resolveManualMatchDoubanId(
    target,
    metadataMatch,
  );
}

String _resolveManualMatchImdbId(
  MediaDetailTarget target,
  MetadataMatchResult? metadataMatch,
) {
  return _detailLibraryMatchService.resolveManualMatchImdbId(
    target,
    metadataMatch,
  );
}

String _resolveManualMatchTmdbId(
  MediaDetailTarget target,
  MetadataMatchResult? metadataMatch,
) {
  return _detailLibraryMatchService.resolveManualMatchTmdbId(
    target,
    metadataMatch,
  );
}

String _resolveManualMatchTvdbId(MediaDetailTarget target) {
  return _detailLibraryMatchService.resolveManualMatchTvdbId(target);
}

String _resolveManualMatchWikidataId(MediaDetailTarget target) {
  return _detailLibraryMatchService.resolveManualMatchWikidataId(target);
}

int _scoreManualMatchCollection(
  MediaCollection collection,
  MediaDetailTarget target, {
  MetadataMatchResult? metadataMatch,
}) {
  return _detailLibraryMatchService.scoreManualMatchCollection(
    collection,
    target,
    metadataMatch: metadataMatch,
  );
}

MediaDetailTarget _applyMetadataMatchToDetailTarget(
  MediaDetailTarget target,
  MetadataMatchResult match, {
  bool replaceExisting = false,
}) {
  return _detailLibraryMatchService.applyMetadataMatchToDetailTarget(
    target,
    match,
    replaceExisting: replaceExisting,
  );
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

String _firstNonEmpty(String primary, String fallback) {
  final primaryTrimmed = primary.trim();
  if (primaryTrimmed.isNotEmpty) {
    return primaryTrimmed;
  }
  return fallback.trim();
}

MediaDetailTarget _normalizeRatingLabelsInTarget(MediaDetailTarget target) {
  return target.copyWith(
    ratingLabels: _mergeLabels(const [], target.ratingLabels),
  );
}

List<String> _mergeLabels(List<String> primary, List<String> secondary) {
  final seen = <String>{};
  final merged = <String>[];
  for (final value in [...primary, ...secondary]) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final key = _labelMergeKey(trimmed);
    if (seen.add(key)) {
      merged.add(trimmed);
    }
  }
  return merged;
}

String _labelMergeKey(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('豆瓣') || normalized.contains('douban')) {
    return 'rating:douban';
  }
  if (normalized.contains('imdb')) {
    return 'rating:imdb';
  }
  if (normalized.contains('tmdb')) {
    return 'rating:tmdb';
  }
  return normalized;
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

class MediaDetailPage extends ConsumerStatefulWidget {
  const MediaDetailPage({super.key, required this.target});

  final MediaDetailTarget target;

  @override
  ConsumerState<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends ConsumerState<MediaDetailPage>
    with PageActivityMixin<MediaDetailPage> {
  String _selectedSeasonId = '';
  bool _isRefreshingMetadata = false;
  _LibraryMatchTaskController? _activeLibraryMatchController;
  late final DetailPageController _pageController;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _heroArtworkFocusNode =
      FocusNode(debugLabel: 'detail-hero-artwork');
  final FocusNode _heroPlayFocusNode =
      FocusNode(debugLabel: 'detail-hero-play');
  final TvFocusMemoryController _tvFocusMemoryController =
      TvFocusMemoryController();
  final RetainedAsyncController<MediaDetailTarget> _retainedTargetAsync =
      RetainedAsyncController<MediaDetailTarget>();
  final RetainedAsyncController<DetailSeriesBrowserState?>
      _retainedSeriesAsync =
      RetainedAsyncController<DetailSeriesBrowserState?>();

  int get _detailSessionId => _pageController.detailSessionId;
  MediaDetailTarget? get _manualOverrideTarget =>
      _pageController.manualOverrideTarget;
  bool get _isMatchingLocalResource => _pageController.isMatchingLocalResource;
  List<MediaDetailTarget> get _libraryMatchChoices =>
      _pageController.libraryMatchChoices;
  int get _selectedLibraryMatchIndex =>
      _pageController.selectedLibraryMatchIndex;
  List<CachedSubtitleSearchOption> get _subtitleSearchChoices =>
      _pageController.subtitleSearchChoices;
  bool get _isSearchingSubtitles => _pageController.isSearchingSubtitles;
  String? get _busySubtitleResultId => _pageController.busySubtitleResultId;
  DetailLibraryMatchViewState get _libraryMatchView =>
      _pageController.libraryMatchView;
  DetailSubtitleSearchViewState get _subtitleSearchView =>
      _pageController.subtitleSearchView;

  @override
  void initState() {
    super.initState();
    _pageController = DetailPageController();
    _pageController.addListener(_handlePageControllerChanged);
    _heroArtworkFocusNode.addListener(_handleHeroArtworkFocusChanged);
  }

  @override
  void didUpdateWidget(covariant MediaDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.itemId != widget.target.itemId ||
        oldWidget.target.title != widget.target.title ||
        oldWidget.target.searchQuery != widget.target.searchQuery) {
      _cancelDetailTasks(additionalTargets: [oldWidget.target]);
      _selectedSeasonId = '';
      _isRefreshingMetadata = false;
      _pageController.resetForTargetChange();
      _retainedTargetAsync.clear();
      _retainedSeriesAsync.clear();
      if (isPageVisible) {
        _startDetailTasks();
      }
    }
  }

  @override
  void dispose() {
    _cancelActiveLibraryMatch();
    _heroArtworkFocusNode.removeListener(_handleHeroArtworkFocusChanged);
    _pageController.removeListener(_handlePageControllerChanged);
    _pageController.dispose();
    _heroArtworkFocusNode.dispose();
    _heroPlayFocusNode.dispose();
    _scrollController.dispose();
    _tvFocusMemoryController.dispose();
    super.dispose();
  }

  @override
  void onPageBecameActive() {
    _startDetailTasks();
  }

  @override
  void onPageBecameInactive() {
    _cancelDetailTasks(invalidateProviders: false);
    if (!mounted) {
      return;
    }
    setState(() {
      _isRefreshingMetadata = false;
    });
    _updateLibraryMatchView(isMatching: false);
    _updateSubtitleSearchView(
      isSearching: false,
      busyResultId: null,
    );
  }

  void _cancelActiveLibraryMatch() {
    _activeLibraryMatchController?.cancel();
    _activeLibraryMatchController = null;
  }

  void _cancelDetailTasks({
    bool invalidateProviders = true,
    Iterable<MediaDetailTarget> additionalTargets = const [],
  }) {
    _cancelActiveLibraryMatch();
    _pageController.cancelDetailTasks();
    if (!invalidateProviders) {
      return;
    }
    _invalidateDetailProviders(additionalTargets: additionalTargets);
  }

  void _invalidateDetailProviders({
    Iterable<MediaDetailTarget> additionalTargets = const [],
  }) {
    final targets = dedupeDetailInvalidationTargets(
      seedTarget: widget.target,
      manualOverrideTarget: _manualOverrideTarget,
      additionalTargets: additionalTargets,
    );
    for (final target in targets) {
      ref.invalidate(enrichedDetailTargetProvider(target));
      if (target.isSeries) {
        ref.invalidate(detailSeriesBrowserProvider(target));
      }
    }
  }

  void _updateLibraryMatchView({
    List<MediaDetailTarget>? choices,
    int? selectedIndex,
    bool? isMatching,
  }) {
    _pageController.updateLibraryMatchView(
      choices: choices,
      selectedIndex: selectedIndex,
      isMatching: isMatching,
    );
  }

  void _updateSubtitleSearchView({
    List<CachedSubtitleSearchOption>? choices,
    int? selectedIndex,
    bool? isSearching,
    Object? busyResultId = detailPageViewStateUnchanged,
    Object? statusMessage = detailPageViewStateUnchanged,
  }) {
    _pageController.updateSubtitleSearchView(
      choices: choices,
      selectedIndex: selectedIndex,
      isSearching: isSearching,
      busyResultId: busyResultId,
      statusMessage: statusMessage,
    );
  }

  void _handlePageControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _handleHeroArtworkFocusChanged() {
    if (!mounted ||
        (!_heroArtworkFocusNode.hasFocus &&
            !_heroArtworkFocusNode.hasPrimaryFocus)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          (!_heroArtworkFocusNode.hasFocus &&
              !_heroArtworkFocusNode.hasPrimaryFocus)) {
        return;
      }
      final position = _scrollController.position;
      final targetOffset = position.minScrollExtent;
      if ((position.pixels - targetOffset).abs() < 1) {
        return;
      }
      unawaited(
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _startDetailTasks() {
    final initialPlan = buildDetailStartupPlan(
      isPageVisible: isPageVisible,
      backgroundWorkSuspended: ref.read(backgroundEnrichmentSuspendedProvider),
      pageSeedTarget: widget.target,
      manualOverrideTarget: _manualOverrideTarget,
      hasSubtitleChoices: _subtitleSearchChoices.isNotEmpty,
      hasOnlineSubtitleSources: false,
      detailAutoLibraryMatchEnabled: false,
    );
    if (!initialPlan.shouldStart) {
      return;
    }
    final sessionId = _pageController.startNewSession();
    Future<void>.microtask(() async {
      if (!_isSessionActive(sessionId)) {
        return;
      }

      await _restoreCachedDetailState(sessionId);
      if (!_isSessionActive(sessionId)) {
        return;
      }

      final restoredTarget = _manualOverrideTarget ?? widget.target;
      await _restoreIndexedEpisodeVariantChoices(
        sessionId,
        restoredTarget,
      );
      if (!_isSessionActive(sessionId)) {
        return;
      }

      final onlineSubtitleSources = ref.read(
        appSettingsProvider
            .select((settings) => settings.onlineSubtitleSources),
      );
      final detailAutoLibraryMatchEnabled = ref.read(
        appSettingsProvider.select(
          (settings) => settings.detailAutoLibraryMatchEnabled,
        ),
      );
      final runtimePlan = buildDetailStartupPlan(
        isPageVisible: isPageVisible,
        backgroundWorkSuspended:
            ref.read(backgroundEnrichmentSuspendedProvider),
        pageSeedTarget: widget.target,
        manualOverrideTarget: _manualOverrideTarget,
        hasSubtitleChoices: _subtitleSearchChoices.isNotEmpty,
        hasOnlineSubtitleSources: onlineSubtitleSources.isNotEmpty,
        detailAutoLibraryMatchEnabled: detailAutoLibraryMatchEnabled,
      );
      if (runtimePlan.shouldRunInitialSubtitleSearch) {
        await _searchSubtitlesForDetail(
          runtimePlan.effectiveTarget,
          showFeedback: false,
        );
        if (!_isSessionActive(sessionId)) {
          return;
        }
      }

      final currentTarget = runtimePlan.effectiveTarget;
      if (runtimePlan.shouldWarmEnrichedTarget) {
        unawaited(ref.read(enrichedDetailTargetProvider(currentTarget).future));
      }
      if (runtimePlan.shouldWarmSeriesBrowser) {
        unawaited(ref.read(detailSeriesBrowserProvider(currentTarget).future));
      }

      if (!runtimePlan.shouldAttemptAutoLibraryMatch) {
        return;
      }

      final resolved = await ref.read(
        enrichedDetailTargetProvider(runtimePlan.resolveTargetForAutoMatch)
            .future,
      );
      if (!_isSessionActive(sessionId) ||
          _manualOverrideTarget != null ||
          ref.read(backgroundEnrichmentSuspendedProvider)) {
        return;
      }
      if (!shouldAutoMatchDetailLocalResource(resolved)) {
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
    return _pageController.isSessionActive(
      sessionId,
      isMounted: mounted,
      isPageVisible: isPageVisible,
    );
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
    final restorePlan = _detailCachedStateRestorer.buildPlan(
      pageSeedTarget: widget.target,
      cachedState: cachedState,
    );
    _updateLibraryMatchView(
      choices: restorePlan.libraryMatchChoices,
      selectedIndex: restorePlan.selectedLibraryMatchIndex,
      isMatching: false,
    );
    _updateSubtitleSearchView(
      choices: restorePlan.subtitleSearchChoices,
      selectedIndex: restorePlan.selectedSubtitleSearchIndex,
      isSearching: false,
      busyResultId: null,
      statusMessage: null,
    );
    final manualOverrideTarget = restorePlan.manualOverrideTarget;
    if (manualOverrideTarget == null) {
      return;
    }
    _pageController.setManualOverrideTarget(manualOverrideTarget);
  }

  Future<void> _restoreIndexedEpisodeVariantChoices(
    int sessionId,
    MediaDetailTarget currentTarget,
  ) async {
    if (_libraryMatchChoices.length > 1) {
      return;
    }

    final variantState =
        await ref.read(detailExternalEpisodeVariantServiceProvider).loadChoices(
              target: currentTarget,
              settings: ref.read(appSettingsProvider),
              nasMediaIndexer: ref.read(nasMediaIndexerProvider),
            );
    if (!_isSessionActive(sessionId) ||
        variantState == null ||
        variantState.choices.length <= 1) {
      return;
    }

    final selectedIndex = variantState.selectedIndex.clamp(
      0,
      variantState.choices.length - 1,
    );
    final selectedTarget = variantState.choices[selectedIndex];
    _updateLibraryMatchView(
      choices: variantState.choices,
      selectedIndex: selectedIndex,
      isMatching: false,
    );
    _pageController.setManualOverrideTarget(selectedTarget);
    await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
          seedTarget: widget.target,
          resolvedTarget: selectedTarget,
          libraryMatchChoices: variantState.choices,
          selectedLibraryMatchIndex: selectedIndex,
        );
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
    _updateLibraryMatchView(
      choices: const [],
      selectedIndex: 0,
      isMatching: true,
    );

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
          _updateLibraryMatchView(
            choices: partialMerged.length > 1
                ? partialMerged
                : const <MediaDetailTarget>[],
            selectedIndex: 0,
            isMatching: true,
          );
          _pageController.setManualOverrideTarget(partialMerged.first);
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

      _updateLibraryMatchView(
        choices: merged.length > 1 ? merged : const <MediaDetailTarget>[],
        selectedIndex: 0,
        isMatching: false,
      );
      if (merged.length == 1 || merged.length > 1) {
        _pageController.setManualOverrideTarget(merged.first);
      }

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
        _updateLibraryMatchView(isMatching: false);
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

    var changed = false;
    try {
      final settings = ref.read(detailEnrichmentSettingsProvider);
      final nextTarget = await _resolveAutomaticMetadataIfNeeded(
        settings: settings,
        target: currentTarget,
        wmdbMetadataClient: ref.read(wmdbMetadataClientProvider),
        tmdbMetadataClient: ref.read(tmdbMetadataClientProvider),
        imdbRatingClient: ref.read(imdbRatingClientProvider),
        forceSearch: true,
        forceReplace: true,
      );
      changed = _hasMetadataChanged(currentTarget, nextTarget);

      if (!_isSessionActive(activeSessionId)) {
        return;
      }

      if (changed) {
        _pageController.setManualOverrideTarget(nextTarget);
      }

      if (changed) {
        unawaited(
          ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
                seedTarget: currentTarget,
                resolvedTarget: nextTarget,
              ),
        );
      }
    } catch (error) {
      if (!_isSessionActive(activeSessionId) || !showFeedback || !mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新影片信息失败：$error')),
      );
      return;
    } finally {
      if (_isSessionActive(activeSessionId) && _isRefreshingMetadata) {
        setState(() {
          _isRefreshingMetadata = false;
        });
      }
    }

    if (!_isSessionActive(activeSessionId) || !showFeedback || !mounted) {
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
    if (!canManageDetailMetadataIndex(currentTarget)) {
      return;
    }
    final updatedTarget = await context.pushNamed<MediaDetailTarget>(
      'metadata-index',
      extra: currentTarget,
    );
    if (!mounted || updatedTarget == null) {
      return;
    }

    _pageController.setManualOverrideTarget(updatedTarget);

    unawaited(
      ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: updatedTarget,
          ),
    );
  }

  int get _currentLibraryMatchIndex {
    return _pageController.currentLibraryMatchIndex;
  }

  void _applySelectedLibraryMatchIndex(int index) {
    final resolvedTarget =
        _pageController.applySelectedLibraryMatchIndex(index);
    if (resolvedTarget == null) {
      return;
    }
    final resolvedIndex = _selectedLibraryMatchIndex;
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
    await _openTelevisionLibraryMatchPickerDialog(
      title: '选择本地资源',
      labelBuilder: detailLibraryMatchOptionLabel,
    );
  }

  Future<void> _openTelevisionPlayableVariantPicker() async {
    await _openTelevisionLibraryMatchPickerDialog(
      title: '选择播放版本',
      labelBuilder: detailPlayableVariantOptionLabel,
    );
  }

  Future<void> _openTelevisionLibraryMatchPickerDialog({
    required String title,
    required String Function(MediaDetailTarget target) labelBuilder,
  }) async {
    if (_libraryMatchChoices.length <= 1 || _isMatchingLocalResource) {
      return;
    }

    final selectedIndex = _currentLibraryMatchIndex;
    final nextIndex = await showDetailTelevisionPickerDialog<int>(
      context: context,
      enabled: ref.read(isTelevisionProvider).value ?? false,
      title: title,
      selectedValue: selectedIndex,
      optionDebugLabelPrefix: 'detail-library-match-option',
      closeFocusDebugLabel: 'detail-library-match-close',
      closeFocusId: 'detail:resource:library-close',
      options: [
        for (var index = 0; index < _libraryMatchChoices.length; index++)
          DetailTelevisionPickerOption<int>(
            value: index,
            title: labelBuilder(_libraryMatchChoices[index]),
            subtitle: _libraryMatchChoices[index].availabilityLabel,
            focusId: 'detail:resource:library-option:$index',
          ),
      ],
    );
    if (!mounted || nextIndex == null || nextIndex == selectedIndex) {
      return;
    }
    _applySelectedLibraryMatchIndex(nextIndex);
  }

  int _normalizeSubtitleSearchIndex(
    int index, {
    List<CachedSubtitleSearchOption>? choices,
  }) {
    return _pageController.normalizeSubtitleSearchIndex(
      index,
      choices: choices ?? _subtitleSearchChoices,
    );
  }

  int get _currentSubtitleSearchIndex {
    return _pageController.currentSubtitleSearchIndex;
  }

  DetailSubtitleSearchViewData get _currentSubtitleSearchViewData {
    final subtitleView = _subtitleSearchView;
    return DetailSubtitleSearchViewData(
      choices: subtitleView.choices,
      selectedIndex: subtitleView.selectedIndex,
      isSearching: subtitleView.isSearching,
      busyResultId: subtitleView.busyResultId,
      statusMessage: subtitleView.statusMessage,
    );
  }

  void _applySubtitleSearchViewData(DetailSubtitleSearchViewData viewData) {
    _updateSubtitleSearchView(
      choices: viewData.choices,
      selectedIndex: viewData.selectedIndex,
      isSearching: viewData.isSearching,
      busyResultId: viewData.busyResultId,
      statusMessage: viewData.statusMessage,
    );
  }

  MediaDetailTarget _decorateTargetWithSelectedSubtitle(
      MediaDetailTarget target) {
    return _detailSubtitleController.decorateTargetWithSelectedSubtitle(
      target,
      viewData: _currentSubtitleSearchViewData,
    );
  }

  Future<void> _searchSubtitlesForDetail(
    MediaDetailTarget target, {
    bool showFeedback = true,
  }) async {
    final activeSessionId = _detailSessionId;
    final messenger = ScaffoldMessenger.maybeOf(context);
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
        messenger?.showSnackBar(
          const SnackBar(content: Text('当前资源还不能直接播放，暂时无法搜索字幕')),
        );
      }
      return;
    }
    if (!_isSessionActive(activeSessionId)) {
      return;
    }
    if (_isSearchingSubtitles) {
      subtitleSearchTrace('detail.search.skip-already-searching');
      return;
    }

    final sources = ref.read(
      appSettingsProvider.select((settings) => settings.onlineSubtitleSources),
    );
    if (sources.isEmpty) {
      subtitleSearchTrace('detail.search.skip-empty-sources');
      if (_isSessionActive(activeSessionId)) {
        _updateSubtitleSearchView(
          statusMessage: '请先在设置里启用至少一个在线字幕来源',
        );
      }
      if (showFeedback && _isSessionActive(activeSessionId)) {
        messenger?.showSnackBar(
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
      if (_isSessionActive(activeSessionId)) {
        _updateSubtitleSearchView(
          statusMessage: '缺少片名信息，暂时无法搜索字幕',
        );
      }
      if (showFeedback && _isSessionActive(activeSessionId)) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('缺少片名信息，暂时无法搜索字幕')),
        );
      }
      return;
    }

    final currentViewData = _currentSubtitleSearchViewData;

    if (_isSessionActive(activeSessionId)) {
      _applySubtitleSearchViewData(
        currentViewData.copyWith(
          isSearching: true,
          statusMessage: null,
        ),
      );
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
      final resolveResult = _detailSubtitleController.resolveSearchResults(
        currentViewData: _currentSubtitleSearchViewData,
        results: results,
        maxChoices: 10,
      );
      final nextChoices = resolveResult.usableChoices;
      final statusMessage = resolveResult.statusMessage;
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
      if (!_isSessionActive(activeSessionId)) {
        return;
      }
      _applySubtitleSearchViewData(resolveResult.nextViewData);
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: target,
            subtitleSearchChoices: nextChoices,
            selectedSubtitleSearchIndex:
                resolveResult.nextViewData.selectedIndex,
          );
      if (!showFeedback || !_isSessionActive(activeSessionId)) {
        return;
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            nextChoices.isEmpty
                ? statusMessage!
                : '已找到 ${nextChoices.length} 条可用字幕',
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
      if (!_isSessionActive(activeSessionId)) {
        return;
      }
      _applySubtitleSearchViewData(
        _currentSubtitleSearchViewData.copyWith(
          isSearching: false,
          statusMessage: '$error',
        ),
      );
      if (showFeedback) {
        messenger?.showSnackBar(
          SnackBar(content: Text('字幕搜索失败：$error')),
        );
      }
    }
  }

  Future<void> _applySelectedSubtitleSearchIndex(
    MediaDetailTarget target,
    int index,
  ) async {
    final activeSessionId = _detailSessionId;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!_isSessionActive(activeSessionId)) {
      return;
    }
    final currentViewData = _currentSubtitleSearchViewData;
    final decision = _detailSubtitleController.decideSelectionAction(
      currentViewData: currentViewData,
      requestedIndex: index,
    );
    if (decision is DetailSubtitleSelectionIgnored) {
      if (decision.reason == 'busy-downloading') {
        subtitleSearchTrace(
          'detail.download.skip-busy',
          fields: {
            'busyResultId': _busySubtitleResultId,
          },
        );
      }
      return;
    }

    if (_isSessionActive(activeSessionId)) {
      _applySubtitleSearchViewData(decision.nextViewData);
    }

    if (decision is DetailSubtitleSelectionCleared) {
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: target,
            subtitleSearchChoices: decision.nextViewData.choices,
            selectedSubtitleSearchIndex: decision.persistedSelectedIndex,
          );
      return;
    }

    if (decision is DetailSubtitleSelectionUseCached) {
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: target,
            subtitleSearchChoices: decision.nextViewData.choices,
            selectedSubtitleSearchIndex: decision.persistedSelectedIndex,
          );
      if (_isSessionActive(activeSessionId)) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('播放时会自动加载这条外挂字幕')),
        );
      }
      return;
    }

    final downloadDecision = decision as DetailSubtitleSelectionNeedsDownload;
    final choice = downloadDecision.selectedOption;

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
      final selection =
          _detailSubtitleController.selectionFromDownloadResult(download);
      if (!selection.canApply) {
        throw StateError('字幕已缓存，但当前结果暂不能直接挂载播放');
      }
      if (!_isSessionActive(activeSessionId)) {
        return;
      }
      final nextViewData =
          _detailSubtitleController.applyDownloadedSelectionSuccess(
        currentViewData: downloadDecision.nextViewData,
        selectionIndex: downloadDecision.selectionIndex,
        selection: selection,
      );
      _applySubtitleSearchViewData(nextViewData);
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: target,
            subtitleSearchChoices: nextViewData.choices,
            selectedSubtitleSearchIndex: nextViewData.selectedIndex,
          );
      if (_isSessionActive(activeSessionId)) {
        messenger?.showSnackBar(
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
      if (!_isSessionActive(activeSessionId)) {
        return;
      }
      _applySubtitleSearchViewData(
        _detailSubtitleController.applyDownloadedSelectionFailure(
          currentViewData: _currentSubtitleSearchViewData,
          error: error,
        ),
      );
      messenger?.showSnackBar(
        SnackBar(content: Text('加载字幕失败：$error')),
      );
    }
  }

  String _subtitleSearchChoiceLabel(CachedSubtitleSearchOption choice) {
    return _detailSubtitleController.subtitleSearchChoiceLabel(choice);
  }

  String _detailSubtitleResultSample(List<SubtitleSearchResult> results) {
    return _detailSubtitleController.subtitleResultSample(results);
  }

  String _detailSubtitleChoiceSample(
    List<CachedSubtitleSearchOption> choices,
  ) {
    return _detailSubtitleController.subtitleChoiceSample(choices);
  }

  Future<void> _openTelevisionSubtitlePicker(MediaDetailTarget target) async {
    if (_subtitleSearchChoices.isEmpty || _isSearchingSubtitles) {
      return;
    }

    final selectedIndex = _currentSubtitleSearchIndex;
    final nextIndex = await showDetailTelevisionPickerDialog<int>(
      context: context,
      enabled: ref.read(isTelevisionProvider).value ?? false,
      title: '选择外挂字幕',
      selectedValue: selectedIndex,
      optionDebugLabelPrefix: 'detail-subtitle-option',
      closeFocusDebugLabel: 'detail-subtitle-close',
      closeFocusId: 'detail:subtitle:close',
      width: 500,
      titleMaxLines: 3,
      options: [
        const DetailTelevisionPickerOption<int>(
          value: -1,
          title: '不加载外挂字幕',
          focusId: 'detail:subtitle:option:0',
        ),
        for (var index = 0; index < _subtitleSearchChoices.length; index++)
          DetailTelevisionPickerOption<int>(
            value: index,
            title: _subtitleSearchChoiceLabel(_subtitleSearchChoices[index]),
            subtitle: _subtitleSearchChoices[index].result.detailLine,
            focusId: 'detail:subtitle:option:${index + 1}',
          ),
      ],
    );
    if (!mounted || nextIndex == null || nextIndex == selectedIndex) {
      return;
    }
    await _applySelectedSubtitleSearchIndex(target, nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    final seedTarget = _manualOverrideTarget ?? widget.target;
    final watchedTargetAsync = isPageVisible
        ? ref.watch(enrichedDetailTargetProvider(seedTarget))
        : null;
    final targetAsync = _retainedTargetAsync.resolve(
      activeValue: watchedTargetAsync,
      fallbackValue: AsyncValue.data(seedTarget),
    );
    final target = targetAsync.value ?? seedTarget;
    if (!target.isSeries) {
      _retainedSeriesAsync.clear();
    }
    final watchedSeriesAsync = target.isSeries && isPageVisible
        ? ref.watch(detailSeriesBrowserProvider(target))
        : null;
    final seriesAsync = target.isSeries
        ? _retainedSeriesAsync.resolve(
            activeValue: watchedSeriesAsync,
            fallbackValue: const AsyncLoading<DetailSeriesBrowserState?>(),
          )
        : const AsyncData<DetailSeriesBrowserState?>(
            null,
          );
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final performanceSlimDetailHeroEnabled = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.performanceSlimDetailHeroEnabled,
      ),
    );
    final playbackEngine = ref.watch(
      appSettingsProvider.select((settings) => settings.playbackEngine),
    );

    return TvPageFocusScope(
      controller: _tvFocusMemoryController,
      scopeId: _detailFocusScopeId(widget.target),
      isTelevision: isTelevision,
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
                controller: _scrollController,
                padding: EdgeInsets.zero,
                children: [
                  DetailHeroSection(
                    target: _decorateTargetWithSelectedSubtitle(target),
                    simplifyVisualEffects: performanceSlimDetailHeroEnabled,
                    isTelevision: isTelevision,
                    artworkFocusNode: _heroArtworkFocusNode,
                    playFocusNode: _heroPlayFocusNode,
                  ),
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
                              final selectedGroup = resolveSelectedEpisodeGroup(
                                groups: browser.groups,
                                selectedGroupId: _selectedSeasonId,
                              );
                              return DetailBlock(
                                title: '剧集',
                                child: DetailEpisodeBrowser(
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
                            loading: () => const DetailBlock(
                              title: '剧集',
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white),
                                ),
                              ),
                            ),
                            error: (error, stackTrace) => DetailBlock(
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
                          DetailBlock(
                            title: _overviewSectionTitle(
                              currentTarget: target,
                              pageTarget: widget.target,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_episodeDetailSubtitleLine(
                                  currentTarget: target,
                                  pageTarget: widget.target,
                                )
                                    case final episodeTitle?) ...[
                                  Text(
                                    episodeTitle,
                                    style: const TextStyle(
                                      color: Color(0xFFF1F5FF),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                Text(
                                  target.overview,
                                  style: const TextStyle(
                                    color: Color(0xFFDCE6F8),
                                    fontSize: 15,
                                    height: 1.7,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (target.overview.trim().isEmpty &&
                            _episodeDetailSubtitleLine(
                                  currentTarget: target,
                                  pageTarget: widget.target,
                                ) !=
                                null)
                          DetailBlock(
                            title: _overviewSectionTitle(
                              currentTarget: target,
                              pageTarget: widget.target,
                            ),
                            child: Text(
                              _episodeDetailSubtitleLine(
                                currentTarget: target,
                                pageTarget: widget.target,
                              )!,
                              style: const TextStyle(
                                color: Color(0xFFF1F5FF),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                              ),
                            ),
                          ),
                        if (buildDetailGalleryImages(target).isNotEmpty)
                          DetailBlock(
                            title: '剧照',
                            child: DetailImageGallery(
                              images: buildDetailGalleryImages(target),
                            ),
                          ),
                        if (target.resolvedDirectorProfiles.isNotEmpty ||
                            target.resolvedActorProfiles.isNotEmpty)
                          DetailBlock(
                            title: '演职员',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (target
                                    .resolvedDirectorProfiles.isNotEmpty) ...[
                                  const InfoLabel('导演'),
                                  const SizedBox(height: 10),
                                  PersonRail(
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
                                  const InfoLabel('演员'),
                                  const SizedBox(height: 10),
                                  PersonRail(
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
                          DetailBlock(
                            title: '公司',
                            child: PlatformRail(
                              platforms: target.resolvedPlatformProfiles,
                            ),
                          ),
                        if (shouldShowDetailResourceInfo(target))
                          DetailBlock(
                            title: '资源信息',
                            child: DetailResourceInfoSection(
                              target: target,
                              isTelevision: isTelevision,
                              playbackEngine: playbackEngine,
                              libraryView: _libraryMatchView,
                              subtitleView: _subtitleSearchView,
                              selectedSubtitleIndex:
                                  _normalizeSubtitleSearchIndex(
                                _subtitleSearchView.selectedIndex,
                                choices: _subtitleSearchView.choices,
                              ),
                              isRefreshingMetadata: _isRefreshingMetadata,
                              subtitleChoiceLabelBuilder:
                                  _subtitleSearchChoiceLabel,
                              onSearchOnline: () {
                                context.pushNamed(
                                  'detail-search',
                                  queryParameters: {
                                    'q': target.searchQuery,
                                  },
                                );
                              },
                              onOpenTelevisionPlayableVariantPicker:
                                  _openTelevisionPlayableVariantPicker,
                              onLibraryMatchSelected:
                                  _applySelectedLibraryMatchIndex,
                              onOpenTelevisionLibraryMatchPicker:
                                  _openTelevisionLibraryMatchPicker,
                              onMatchLocalResource: _libraryMatchView.isMatching
                                  ? null
                                  : () => _matchLocalResource(target),
                              onOpenPlaybackEnginePicker: () =>
                                  _openPlaybackEnginePicker(playbackEngine),
                              onPlaybackEngineSelected: (selection) {
                                unawaited(
                                  _setPlaybackEngine(
                                    selection,
                                    currentEngine: playbackEngine,
                                  ),
                                );
                              },
                              onSearchSubtitles: _subtitleSearchView.isSearching
                                  ? null
                                  : () => _searchSubtitlesForDetail(target),
                              onOpenTelevisionSubtitlePicker: () =>
                                  _openTelevisionSubtitlePicker(target),
                              onSubtitleSelected: (index) {
                                unawaited(
                                  _applySelectedSubtitleSearchIndex(
                                    target,
                                    index,
                                  ),
                                );
                              },
                              onOpenMetadataIndexManager: () =>
                                  _openMetadataIndexManager(target),
                              onRefreshMetadata: _isRefreshingMetadata
                                  ? null
                                  : () => _refreshMetadata(target),
                            ),
                          ),
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
}

String _detailFocusScopeId(MediaDetailTarget target) {
  return buildTvFocusScopeId(
    prefix: 'detail',
    segments: [
      target.sourceKind?.name,
      target.sourceId,
      target.sectionId,
      target.itemId,
      target.tmdbId,
      target.imdbId,
      target.doubanId,
      target.tvdbId,
      target.wikidataId,
      target.tmdbSetId,
      target.itemType,
      if (target.seasonNumber != null) 'season-${target.seasonNumber}',
      if (target.episodeNumber != null) 'episode-${target.episodeNumber}',
      if (target.year > 0) target.year,
      target.searchQuery,
      target.title,
    ],
  );
}

String _overviewSectionTitle({
  required MediaDetailTarget currentTarget,
  required MediaDetailTarget pageTarget,
}) {
  final pageItemType = pageTarget.itemType.trim().toLowerCase();
  final seriesTitle = currentTarget.playbackTarget?.seriesTitle.trim() ?? '';
  if (pageItemType == 'episode') {
    if (seriesTitle.isNotEmpty) {
      return seriesTitle;
    }
    final query = currentTarget.searchQuery.trim();
    if (query.isNotEmpty) {
      return query;
    }
  }
  final pageTitle = pageTarget.title.trim();
  if (pageTitle.isNotEmpty) {
    return pageTitle;
  }
  if (seriesTitle.isNotEmpty) {
    return seriesTitle;
  }
  final title = currentTarget.title.trim();
  if (title.isNotEmpty) {
    return title;
  }
  final query = currentTarget.searchQuery.trim();
  if (query.isNotEmpty) {
    return query;
  }
  return '剧情简介';
}

String? _episodeDetailSubtitleLine({
  required MediaDetailTarget currentTarget,
  required MediaDetailTarget pageTarget,
}) {
  if (pageTarget.itemType.trim().toLowerCase() != 'episode') {
    return null;
  }
  final episodeTitle = currentTarget.title.trim().isNotEmpty
      ? currentTarget.title.trim()
      : (currentTarget.playbackTarget?.title.trim() ?? pageTarget.title.trim());
  if (episodeTitle.isEmpty) {
    return null;
  }
  final primaryTitle = _overviewSectionTitle(
    currentTarget: currentTarget,
    pageTarget: pageTarget,
  );
  if (episodeTitle == primaryTitle) {
    return null;
  }
  return episodeTitle;
}

String _availabilityFeedbackLabel(String label) {
  return _detailLibraryMatchService.availabilityFeedbackLabel(label);
}
