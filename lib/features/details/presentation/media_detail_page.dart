import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/utils/debug_trace_once.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/metadata_match_resolver.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final enrichedDetailTargetProvider =
    FutureProvider.autoDispose.family<MediaDetailTarget, MediaDetailTarget>((
  ref,
  target,
) async {
  final settings = ref.watch(appSettingsProvider);
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
      (target.needsMetadataMatch || target.imdbId.trim().isEmpty);
  final needsImdb =
      settings.imdbRatingMatchEnabled && target.needsImdbRatingMatch;
  return needsWmdb || needsTmdb || needsImdb;
}

String _detailMetadataQuery(MediaDetailTarget target) {
  final raw =
      target.searchQuery.trim().isEmpty ? target.title : target.searchQuery;
  return raw.trim();
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

Future<MediaDetailTarget> _resolveAutomaticMetadataIfNeeded({
  required AppSettings settings,
  required MediaDetailTarget target,
  required WmdbMetadataClient wmdbMetadataClient,
  required TmdbMetadataClient tmdbMetadataClient,
  required ImdbRatingClient imdbRatingClient,
}) async {
  var nextTarget = target;
  final initialQuery = _detailMetadataQuery(target);
  final traceKey = _detailTraceKey(target);

  if (settings.wmdbMetadataMatchEnabled &&
      (nextTarget.needsMetadataMatch ||
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
              preferSeries: nextTarget.isSeries,
              actors: nextTarget.actors,
            );
      if (wmdbMatch != null) {
        DebugTraceOnce.logMetadata(
          traceKey,
          'wmdb',
          'matched title=${wmdbMatch.title} imdbId=${wmdbMatch.imdbId} '
              'ratings=${wmdbMatch.ratingLabels.join(' | ')}',
        );
        nextTarget = _applyManualMetadataMatch(nextTarget, wmdbMatch);
      } else {
        DebugTraceOnce.logMetadata(traceKey, 'wmdb', 'no match');
      }
    } catch (_) {
      DebugTraceOnce.logMetadata(traceKey, 'wmdb', 'failed');
      // Ignore WMDB failures and continue.
    }
  }

  if (settings.tmdbMetadataMatchEnabled &&
      settings.tmdbReadAccessToken.trim().isNotEmpty) {
    try {
      final currentQuery = _detailMetadataQuery(nextTarget);
      DebugTraceOnce.logMetadata(
        traceKey,
        'tmdb',
        'request query=${currentQuery.isEmpty ? initialQuery : currentQuery} '
            'year=${nextTarget.year} preferSeries=${nextTarget.isSeries}',
      );
      final tmdbMatch = await tmdbMetadataClient.matchTitle(
        query: currentQuery.isEmpty ? initialQuery : currentQuery,
        readAccessToken: settings.tmdbReadAccessToken.trim(),
        year: nextTarget.year,
        preferSeries: nextTarget.isSeries,
      );
      if (tmdbMatch != null) {
        DebugTraceOnce.logMetadata(
          traceKey,
          'tmdb',
          'matched title=${tmdbMatch.title} imdbId=${tmdbMatch.imdbId}',
        );
        nextTarget = _applyManualMetadataMatch(
          nextTarget,
          MetadataMatchResult(
            provider: MetadataMatchProvider.tmdb,
            title: tmdbMatch.title,
            originalTitle: tmdbMatch.originalTitle,
            posterUrl: tmdbMatch.posterUrl,
            overview: tmdbMatch.overview,
            year: tmdbMatch.year,
            durationLabel: tmdbMatch.durationLabel,
            genres: tmdbMatch.genres,
            directors: tmdbMatch.directors,
            actors: tmdbMatch.actors,
            actorProfiles: tmdbMatch.actorProfiles
                .map(
                  (item) => MetadataPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                  ),
                )
                .toList(),
            imdbId: tmdbMatch.imdbId,
          ),
        );
      } else {
        DebugTraceOnce.logMetadata(traceKey, 'tmdb', 'no match');
      }
    } catch (_) {
      DebugTraceOnce.logMetadata(traceKey, 'tmdb', 'failed');
      // Ignore TMDB failures and continue.
    }
  }

  if (settings.imdbRatingMatchEnabled && nextTarget.needsImdbRatingMatch) {
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
        preferSeries: nextTarget.isSeries,
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
          imdbId: nextTarget.imdbId.trim().isEmpty
              ? ratingMatch.imdbId
              : nextTarget.imdbId,
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

String _detailTraceKey(MediaDetailTarget target) {
  final id = [
    target.title.trim(),
    target.searchQuery.trim(),
    target.sourceId.trim(),
    target.itemId.trim(),
    target.doubanId.trim(),
  ].where((item) => item.isNotEmpty).join('|');
  return id.isEmpty ? 'detail' : id;
}

MediaDetailTarget _mergeCachedDetailTarget({
  required MediaDetailTarget current,
  required MediaDetailTarget cached,
}) {
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
    extraBackdropUrls: current.extraBackdropUrls.isNotEmpty
        ? current.extraBackdropUrls
        : cached.extraBackdropUrls,
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
    actors: current.actors.isNotEmpty ? current.actors : cached.actors,
    actorProfiles: current.actorProfiles.isNotEmpty
        ? current.actorProfiles
        : cached.actorProfiles,
    availabilityLabel: current.availabilityLabel.trim().isNotEmpty
        ? current.availabilityLabel
        : cached.availabilityLabel,
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
    itemType:
        current.itemType.trim().isNotEmpty ? current.itemType : cached.itemType,
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
    sourceKind: current.sourceKind ?? cached.sourceKind,
    sourceName: current.sourceName.trim().isNotEmpty
        ? current.sourceName
        : cached.sourceName,
  );
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
      current.overview != next.overview ||
      current.year != next.year ||
      current.durationLabel != next.durationLabel ||
      !_sameStrings(current.ratingLabels, next.ratingLabels) ||
      !_sameStrings(current.genres, next.genres) ||
      !_sameStrings(current.directors, next.directors) ||
      !_sameStrings(current.actors, next.actors) ||
      current.doubanId != next.doubanId ||
      current.imdbId != next.imdbId;
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
        preferSeries: target.isSeries,
        actors: target.actors,
      ),
    );
  } catch (_) {
    return null;
  }
}

Future<List<_LibraryMatchCandidate>> _findAllLibraryMatchCandidates({
  required MediaRepository mediaRepository,
  required MediaDetailTarget target,
  required String query,
  MetadataMatchResult? metadataMatch,
}) async {
  const detailLibraryMatchLimit = 2000;
  const maxMatches = 32;
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

  List<MediaCollection> collections;
  try {
    collections = await mediaRepository.fetchCollections(
      kind: MediaSourceKind.emby,
    );
  } catch (_) {
    collections = const [];
  }

  if (collections.isNotEmpty) {
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

    final imdbId = _resolveManualMatchImdbId(target, metadataMatch);
    for (final collection in rankedCollections) {
      try {
        final items = await mediaRepository.fetchLibrary(
          kind: MediaSourceKind.emby,
          sourceId: collection.sourceId,
          sectionId: collection.id,
          limit: detailLibraryMatchLimit,
        );
        final exactMatched = matchMediaItemByExternalIds(
          items,
          imdbId: imdbId,
        );
        if (exactMatched != null) {
          upsert(
            _LibraryMatchCandidate(
              item: exactMatched,
              matchReason: _externalIdMatchReason(
                exactMatched,
                imdbId: imdbId,
              ),
              score: 1e9,
            ),
          );
        }
        for (final scored in listScoredMediaItemsMatchingTitles(
          items,
          titles: titles,
          year: year,
          maxResults: maxMatches,
        )) {
          upsert(
            _LibraryMatchCandidate(
              item: scored.item,
              matchReason: _titleMatchReason(year),
              score: scored.score,
            ),
          );
        }
      } catch (_) {}
    }
  }

  try {
    final nasLibrary = await mediaRepository.fetchLibrary(
      kind: MediaSourceKind.nas,
      limit: detailLibraryMatchLimit,
    );
    for (final scored in listScoredMediaItemsMatchingTitles(
      nasLibrary,
      titles: titles,
      year: year,
      maxResults: maxMatches,
    )) {
      upsert(
        _LibraryMatchCandidate(
          item: scored.item,
          matchReason: _titleMatchReason(year),
          score: scored.score,
        ),
      );
    }
  } catch (_) {}

  final out = byId.values.toList()..sort((a, b) => b.score.compareTo(a.score));
  if (out.length <= maxMatches) {
    return out;
  }
  return out.take(maxMatches).toList();
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
  required String imdbId,
}) {
  final reasons = <String>[];
  final normalizedImdbId = imdbId.trim().toLowerCase();

  if (normalizedImdbId.isNotEmpty &&
      item.imdbId.trim().toLowerCase() == normalizedImdbId) {
    reasons.add('IMDb ID');
  }

  if (reasons.isEmpty) {
    return '按外部 ID 匹配';
  }
  if (reasons.length == 1) {
    return '按 ${reasons.first} 匹配';
  }
  return '按 ${reasons.join(' + ')} 匹配';
}

String _titleMatchReason(int year) {
  return year > 0 ? '按标题 + 年份匹配' : '按标题匹配';
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
    posterUrl: _firstNonEmpty(current.posterUrl, matched.posterUrl),
    posterHeaders: current.posterHeaders.isNotEmpty
        ? current.posterHeaders
        : matched.posterHeaders,
    backdropUrl: _firstNonEmpty(current.backdropUrl, matched.backdropUrl),
    backdropHeaders: current.backdropHeaders.isNotEmpty
        ? current.backdropHeaders
        : matched.backdropHeaders,
    logoUrl: _firstNonEmpty(current.logoUrl, matched.logoUrl),
    logoHeaders: current.logoHeaders.isNotEmpty
        ? current.logoHeaders
        : matched.logoHeaders,
    bannerUrl: _firstNonEmpty(current.bannerUrl, matched.bannerUrl),
    bannerHeaders: current.bannerHeaders.isNotEmpty
        ? current.bannerHeaders
        : matched.bannerHeaders,
    extraBackdropUrls: current.extraBackdropUrls.isNotEmpty
        ? current.extraBackdropUrls
        : matched.extraBackdropUrls,
    extraBackdropHeaders: current.extraBackdropHeaders.isNotEmpty
        ? current.extraBackdropHeaders
        : matched.extraBackdropHeaders,
    overview: current.hasUsefulOverview ? current.overview : matched.overview,
    year: current.year > 0 ? current.year : matched.year,
    durationLabel: current.durationLabel.trim().isNotEmpty
        ? current.durationLabel
        : matched.durationLabel,
    genres: current.genres.isNotEmpty ? current.genres : matched.genres,
    directors:
        current.directors.isNotEmpty ? current.directors : matched.directors,
    actors: current.actors.isNotEmpty ? current.actors : matched.actors,
    actorProfiles: current.actorProfiles.isNotEmpty
        ? current.actorProfiles
        : matched.actorProfiles,
    ratingLabels: _mergeLabels(
      matched.ratingLabels,
      current.ratingLabels,
    ),
    doubanId: current.doubanId,
    imdbId: current.imdbId,
  );
}

MediaDetailTarget _applyManualMetadataMatch(
  MediaDetailTarget target,
  MetadataMatchResult match,
) {
  final filteredMatchRatingLabels = _filterSupplementalRatingLabels(
    existing: target.ratingLabels,
    supplemental: match.ratingLabels,
  );
  return target.copyWith(
    posterUrl:
        target.posterUrl.trim().isNotEmpty ? target.posterUrl : match.posterUrl,
    posterHeaders: target.posterHeaders,
    overview: target.hasUsefulOverview
        ? target.overview
        : (match.overview.trim().isNotEmpty ? match.overview : target.overview),
    year: target.year > 0 ? target.year : match.year,
    durationLabel: match.durationLabel.trim().isNotEmpty
        ? (target.durationLabel.trim().isNotEmpty
            ? target.durationLabel
            : match.durationLabel)
        : target.durationLabel,
    genres: target.genres.isNotEmpty ? target.genres : match.genres,
    directors: target.directors.isNotEmpty ? target.directors : match.directors,
    actors: target.actors.isNotEmpty ? target.actors : match.actors,
    actorProfiles: target.actorProfiles.isNotEmpty
        ? target.actorProfiles
        : match.actorProfiles.isNotEmpty
            ? match.actorProfiles
                .map(
                  (item) => MediaPersonProfile(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                  ),
                )
                .toList()
            : target.actorProfiles,
    ratingLabels: _mergeLabels(target.ratingLabels, filteredMatchRatingLabels),
    doubanId:
        target.doubanId.trim().isNotEmpty ? target.doubanId : match.doubanId,
    imdbId: target.imdbId.trim().isNotEmpty ? target.imdbId : match.imdbId,
  );
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
  int _detailSessionId = 0;

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
      _selectedSeasonId = '';
      _manualOverrideTarget = null;
      _isMatchingLocalResource = false;
      _isRefreshingMetadata = false;
      _libraryMatchChoices = const [];
      _selectedLibraryMatchIndex = 0;
      _startDetailTasks();
    }
  }

  @override
  void dispose() {
    _detailSessionId += 1;
    super.dispose();
  }

  void _startDetailTasks() {
    final sessionId = ++_detailSessionId;
    Future<void>.microtask(() async {
      if (!_isSessionActive(sessionId)) {
        return;
      }

      final currentTarget = _manualOverrideTarget ?? widget.target;
      unawaited(ref.read(enrichedDetailTargetProvider(currentTarget).future));
      if (currentTarget.isSeries) {
        unawaited(ref.read(seriesBrowserProvider(currentTarget).future));
      }

      final resolved =
          await ref.read(enrichedDetailTargetProvider(widget.target).future);
      if (!_isSessionActive(sessionId) || _manualOverrideTarget != null) {
        return;
      }
      if (!_shouldShowLocalResourceMatcher(resolved)) {
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

  Future<void> _matchLocalResource(
    MediaDetailTarget currentTarget, {
    int? sessionId,
    bool showFeedback = true,
  }) async {
    final activeSessionId = sessionId ?? _detailSessionId;
    if (_isMatchingLocalResource || !_isSessionActive(activeSessionId)) {
      return;
    }

    setState(() {
      _isMatchingLocalResource = true;
      _libraryMatchChoices = const [];
      _selectedLibraryMatchIndex = 0;
    });

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

    final candidates = await _findAllLibraryMatchCandidates(
      mediaRepository: ref.read(mediaRepositoryProvider),
      target: currentTarget,
      query: query,
      metadataMatch: metadataMatch,
    );

    if (!_isSessionActive(activeSessionId)) {
      return;
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

    if (merged.length == 1) {
      unawaited(
        ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
              seedTarget: currentTarget,
              resolvedTarget: merged.first,
            ),
      );
    }

    if (!_isSessionActive(activeSessionId) || !showFeedback) {
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
  }

  Future<void> _refreshMetadata(
    MediaDetailTarget currentTarget, {
    int? sessionId,
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

  @override
  Widget build(BuildContext context) {
    final seedTarget = _manualOverrideTarget ?? widget.target;
    final targetAsync = ref.watch(enrichedDetailTargetProvider(seedTarget));
    final target = targetAsync.valueOrNull ?? seedTarget;
    final seriesAsync = ref.watch(seriesBrowserProvider(target));

    return Scaffold(
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
                _HeroSection(target: target),
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
                          title: '剧情简介',
                          child: Text(
                            target.overview,
                            style: const TextStyle(
                              color: Color(0xFFDCE6F8),
                              fontSize: 15,
                              height: 1.7,
                            ),
                          ),
                        ),
                      if (target.directors.isNotEmpty ||
                          target.resolvedActorProfiles.isNotEmpty)
                        _DetailBlock(
                          title: '演职员',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (target.directors.isNotEmpty) ...[
                                const _InfoLabel('导演'),
                                const SizedBox(height: 10),
                                _NameRail(names: target.directors),
                              ],
                              if (target.directors.isNotEmpty &&
                                  target.resolvedActorProfiles.isNotEmpty)
                                const SizedBox(height: 18),
                              if (target.resolvedActorProfiles.isNotEmpty) ...[
                                const _InfoLabel('演员'),
                                const SizedBox(height: 10),
                                _ActorRail(
                                  actors: target.resolvedActorProfiles,
                                ),
                              ],
                            ],
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
                              if (_libraryMatchChoices.length > 1) ...[
                                const SizedBox(height: 12),
                                const _InfoLabel('本地资源'),
                                const SizedBox(height: 8),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _selectedLibraryMatchIndex.clamp(
                                      0,
                                      _libraryMatchChoices.length - 1,
                                    ),
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
                                            setState(() {
                                              _selectedLibraryMatchIndex = i;
                                              _manualOverrideTarget =
                                                  _libraryMatchChoices[i];
                                            });
                                            unawaited(
                                              ref
                                                  .read(
                                                    localStorageCacheRepositoryProvider,
                                                  )
                                                  .saveDetailTarget(
                                                    seedTarget: widget.target,
                                                    resolvedTarget:
                                                        _libraryMatchChoices[i],
                                                  ),
                                            );
                                          },
                                  ),
                                ),
                              ],
                              if (_shouldShowLocalResourceMatcher(target) ||
                                  _libraryMatchChoices.length > 1) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _isMatchingLocalResource
                                        ? null
                                        : () => _matchLocalResource(target),
                                    icon: _isMatchingLocalResource
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
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
                                          : _libraryMatchChoices.length > 1
                                              ? '重新匹配本地资源'
                                              : '匹配本地资源',
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 0,
                                        vertical: 0,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
                              if (_canManageMetadataIndex(target)) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        _openMetadataIndexManager(target),
                                    icon: const Icon(
                                      Icons.manage_search_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('建立/管理索引'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 0,
                                        vertical: 0,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
                              if (_canManuallyRefreshMetadata(target)) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _isRefreshingMetadata
                                        ? null
                                        : () => _refreshMetadata(target),
                                    icon: _isRefreshingMetadata
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 0,
                                        vertical: 0,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
                              if (target.sourceName.trim().isNotEmpty) ...[
                                if (target.availabilityLabel.trim().isNotEmpty)
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
  final availability = target.availabilityLabel.trim();
  return target.needsLibraryMatch &&
      !target.isPlayable &&
      (availability.isEmpty || availability == '无');
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

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.target});

  final MediaDetailTarget target;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = math.max(560.0, math.min(screenHeight * 0.76, 760.0));
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
            imageUrl: target.backdropUrl.trim().isNotEmpty
                ? target.backdropUrl
                : target.posterUrl,
            imageHeaders: target.backdropUrl.trim().isNotEmpty
                ? target.backdropHeaders
                : target.posterHeaders,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.22),
                  const Color(0xFF030914),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.52),
                  Colors.black.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
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
                  final isCompact = constraints.maxWidth < 760;
                  final poster = _PosterArt(
                    posterUrl: target.posterUrl,
                    posterHeaders: target.posterHeaders,
                  );
                  final content = _HeroContent(
                    target: target,
                    metadata: metadata,
                    peopleLine: peopleLine,
                  );

                  if (isCompact) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        poster,
                        const SizedBox(height: 18),
                        content,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      poster,
                      const SizedBox(width: 24),
                      Expanded(child: content),
                    ],
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

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.target,
    required this.metadata,
    required this.peopleLine,
  });

  final MediaDetailTarget target;
  final List<String> metadata;
  final String peopleLine;

  @override
  Widget build(BuildContext context) {
    final hasLogo = target.logoUrl.trim().isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (metadata.isNotEmpty)
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
          if (metadata.isNotEmpty) const SizedBox(height: 14),
          if (hasLogo)
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 320,
                maxHeight: 92,
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
          if (peopleLine.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
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
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (target.isPlayable)
                FilledButton.icon(
                  onPressed: () {
                    context.pushNamed('player', extra: target.playbackTarget);
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
                  label: const Text('立即播放'),
                ),
              if (!target.isPlayable && target.searchQuery.trim().isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    context.goNamed(
                      'search',
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
                OutlinedButton.icon(
                  onPressed: () {
                    context.goNamed(
                      'search',
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
  });

  final String imageUrl;
  final Map<String, String> imageHeaders;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return const ColoredBox(color: Color(0xFF0A1423));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        AppNetworkImage(
          imageUrl,
          headers: imageHeaders,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) {
            return const ColoredBox(color: Color(0xFF0A1423));
          },
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF081120).withValues(alpha: 0.28),
          ),
        ),
      ],
    );
  }
}

class _PosterArt extends StatelessWidget {
  const _PosterArt({
    required this.posterUrl,
    this.posterHeaders = const {},
  });

  final String posterUrl;
  final Map<String, String> posterHeaders;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 0.69,
          child: Container(
            color: const Color(0xFF0D192A),
            child: posterUrl.trim().isEmpty
                ? const Icon(
                    Icons.movie_creation_outlined,
                    size: 42,
                    color: Colors.white70,
                  )
                : AppNetworkImage(
                    posterUrl,
                    headers: posterHeaders,
                    fit: BoxFit.cover,
                    cacheWidth: 720,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(
                          Icons.movie_creation_outlined,
                          size: 42,
                          color: Colors.white70,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
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
    required this.groups,
    required this.selectedGroupId,
    required this.onSeasonSelected,
  });

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
                child: _EpisodeCard(item: episode),
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
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
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

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final badgeText = _episodeBadgeText(item);
    final summary = _episodeSummary(item);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: item.isPlayable
            ? () {
                context.pushNamed(
                  'player',
                  extra: item.isPlayable ? _itemToPlaybackTarget(item) : null,
                );
              }
            : null,
        child: Ink(
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
              AspectRatio(
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _episodeBadgeText(MediaItem item) {
    final entries = <String>[
      item.episodeNumber != null ? '第 ${item.episodeNumber} 集' : '剧集',
      if (item.durationLabel.trim().isNotEmpty && item.durationLabel != '时长未知')
        item.durationLabel,
      if (_progressLabel(item).trim().isNotEmpty) _progressLabel(item),
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

  String _progressLabel(MediaItem item) {
    final progress = item.playbackProgress;
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
    if (item.posterUrl.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: AppNetworkImage(
          item.posterUrl,
          headers: item.posterHeaders,
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

PlaybackTarget _itemToPlaybackTarget(MediaItem item) {
  return PlaybackTarget.fromMediaItem(item);
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

class _NameRail extends StatelessWidget {
  const _NameRail({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: names
          .where((item) => item.trim().isNotEmpty)
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Text(
                item,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ActorRail extends StatelessWidget {
  const _ActorRail({required this.actors});

  final List<MediaPersonProfile> actors;

  @override
  Widget build(BuildContext context) {
    final visibleActors = actors
        .where((item) => item.name.trim().isNotEmpty)
        .toList(growable: false);
    if (visibleActors.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: visibleActors.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final actor = visibleActors[index];
          return SizedBox(
            width: 86,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ActorAvatar(actor: actor),
                const SizedBox(height: 10),
                Text(
                  actor.name,
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
          );
        },
      ),
    );
  }
}

class _ActorAvatar extends StatelessWidget {
  const _ActorAvatar({required this.actor});

  final MediaPersonProfile actor;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = actor.avatarUrl.trim();
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
                _actorInitial(actor.name),
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
                    _actorInitial(actor.name),
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

String _actorInitial(String name) {
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
