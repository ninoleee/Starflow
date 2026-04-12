import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/debug_trace_once.dart';
import 'package:starflow/features/details/application/detail_enrichment_settings.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/data/emby_api_client.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

final detailTargetResolverProvider =
    Provider<DetailTargetResolver>((ref) => DetailTargetResolver(ref));

class DetailTargetResolver {
  DetailTargetResolver(this._ref);

  final Ref _ref;
  DetailEnrichmentSettings get _settings =>
      _ref.read(detailEnrichmentSettingsProvider);
  LocalStorageCacheRepository get _detailCache =>
      _ref.read(localStorageCacheRepositoryProvider);

  Future<MediaDetailTarget> resolve({
    required MediaDetailTarget target,
    required bool backgroundWorkSuspended,
  }) async {
    if (backgroundWorkSuspended) {
      final cachedTarget = await _detailCache.loadDetailTarget(target);
      return normalizeRatingLabelsInTarget(
        cachedTarget == null
            ? target
            : _mergeCachedDetailTarget(target, cachedTarget),
      );
    }
    return _resolveDetailTargetIfNeeded(target: target);
  }

  Future<MediaDetailTarget> resolveMetadataOnly({
    required MediaDetailTarget target,
    required bool backgroundWorkSuspended,
  }) async {
    if (backgroundWorkSuspended) {
      final cachedTarget = await _detailCache.loadDetailTarget(target);
      return normalizeRatingLabelsInTarget(
        cachedTarget == null
            ? target
            : _mergeCachedDetailTarget(target, cachedTarget),
      );
    }
    return _resolveMetadataOnlyIfNeeded(target: target);
  }

  Future<MediaDetailTarget> _resolveDetailTargetIfNeeded({
    required MediaDetailTarget target,
  }) async {
    final nextTarget = await _resolveMetadataOnlyIfNeeded(target: target);
    final traceKey = _detailTraceKey(target);
    final playback = nextTarget.playbackTarget;
    if (playback == null) {
      DebugTraceOnce.logMetadata(
        traceKey,
        'playback-resolve',
        'skipped no playback target',
      );
      return nextTarget;
    }

    final shouldResolve =
        _shouldResolvePlaybackTarget(playback, settings: _settings);
    if (!shouldResolve) {
      DebugTraceOnce.logMetadata(
        traceKey,
        'playback-resolve',
        'skipped streamReady=${playback.streamUrl.trim().isNotEmpty} '
            'format=${playback.formatLabel.trim().isNotEmpty} '
            'resolution=${playback.resolutionLabel.trim().isNotEmpty} '
            'fileSize=${playback.fileSizeLabel.trim().isNotEmpty}',
      );
      return nextTarget;
    }

    try {
      final resolvedPlayback = await _resolvePlayback(
        target: playback,
        settings: _settings,
        traceKey: traceKey,
      );
      final updatedTarget =
          nextTarget.copyWith(playbackTarget: resolvedPlayback);
      DebugTraceOnce.logMetadata(
        traceKey,
        'playback-resolve',
        'success format=${resolvedPlayback.formatLabel} '
            'resolution=${resolvedPlayback.resolutionLabel} '
            'size=${resolvedPlayback.fileSizeLabel}',
      );
      await _persistResolvedTarget(target, updatedTarget);
      DebugTraceOnce.logMetadata(
        traceKey,
        'done',
        'final poster=${updatedTarget.posterUrl.trim().isNotEmpty} '
            'backdrop=${updatedTarget.backdropUrl.trim().isNotEmpty} '
            'logo=${updatedTarget.logoUrl.trim().isNotEmpty} '
            'ratings=${updatedTarget.ratingLabels.join(' | ')}',
      );
      return updatedTarget;
    } catch (_) {
      DebugTraceOnce.logMetadata(traceKey, 'playback-resolve', 'failed');
      return nextTarget;
    }
  }

  Future<MediaDetailTarget> _resolveMetadataOnlyIfNeeded({
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
    final cachedState = await _detailCache.loadDetailState(target);
    final cachedTarget = cachedState?.target;
    final refreshStatus =
        cachedState?.metadataRefreshStatus ?? DetailMetadataRefreshStatus.never;
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
    var nextTarget = normalizeRatingLabelsInTarget(
      cachedTarget == null
          ? target
          : _mergeCachedDetailTarget(target, cachedTarget),
    );
    if (refreshStatus != DetailMetadataRefreshStatus.never) {
      DebugTraceOnce.logMetadata(
        traceKey,
        'auto-enrich',
        'skipped refreshStatus=${refreshStatus.name}',
      );
    } else if (_shouldAutoEnrichMetadataTarget(
        target: nextTarget, settings: _settings)) {
      DebugTraceOnce.logMetadata(
        traceKey,
        'auto-enrich',
        'enabled query=${_detailMetadataQuery(nextTarget)} '
            'needsMetadata=${nextTarget.needsMetadataMatch} '
            'needsImdb=${nextTarget.needsImdbRatingMatch} ',
      );
      nextTarget = await _resolveAutomaticMetadataIfNeeded(
        settings: _settings,
        target: nextTarget,
        wmdbMetadataClient: _ref.read(wmdbMetadataClientProvider),
        tmdbMetadataClient: _ref.read(tmdbMetadataClientProvider),
        traceKey: traceKey,
      );
    } else {
      DebugTraceOnce.logMetadata(traceKey, 'auto-enrich', 'skipped');
    }

    await _persistResolvedTarget(target, nextTarget);
    DebugTraceOnce.logMetadata(
      traceKey,
      'metadata-done',
      'final poster=${nextTarget.posterUrl.trim().isNotEmpty} '
          'backdrop=${nextTarget.backdropUrl.trim().isNotEmpty} '
          'logo=${nextTarget.logoUrl.trim().isNotEmpty} '
          'ratings=${nextTarget.ratingLabels.join(' | ')}',
    );
    return nextTarget;
  }

  Future<void> _persistResolvedTarget(
    MediaDetailTarget seed,
    MediaDetailTarget resolved,
  ) async {
    try {
      await _detailCache.saveDetailTarget(
        seedTarget: seed,
        resolvedTarget: resolved,
      );
    } catch (_) {
      // ignore
    }
  }

  Future<PlaybackTarget> _resolvePlayback({
    required PlaybackTarget target,
    required DetailEnrichmentSettings settings,
    required String traceKey,
  }) async {
    if (target.sourceKind == MediaSourceKind.emby) {
      return _resolveEmbyPlayback(target, settings, traceKey);
    }
    if (target.sourceKind == MediaSourceKind.nas) {
      return _resolveNasPlayback(target, settings, traceKey);
    }
    return _resolveQuarkPlayback(target, settings, traceKey);
  }

  Future<PlaybackTarget> _resolveEmbyPlayback(
    PlaybackTarget target,
    DetailEnrichmentSettings settings,
    String traceKey,
  ) async {
    MediaSourceConfig? source;
    for (final candidate in settings.mediaSources) {
      if (candidate.id == target.sourceId) {
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
      throw const _PlaybackResolutionException();
    }
    return _ref
        .read(embyApiClientProvider)
        .resolvePlaybackTarget(source: source, target: target);
  }

  Future<PlaybackTarget> _resolveQuarkPlayback(
    PlaybackTarget target,
    DetailEnrichmentSettings settings,
    String traceKey,
  ) async {
    final cookie = settings.quarkCookie.trim();
    if (cookie.isEmpty) {
      DebugTraceOnce.logMetadata(
        traceKey,
        'playback-resolve',
        'skipped missing quark cookie',
      );
      throw const _PlaybackResolutionException();
    }
    final resolved = await _ref
        .read(quarkSaveClientProvider)
        .resolveDownload(cookie: cookie, fid: target.itemId);
    return target.copyWith(
      streamUrl: resolved.url,
      headers: resolved.headers,
      fileSizeBytes: resolved.fileSizeBytes ?? target.fileSizeBytes,
    );
  }

  Future<PlaybackTarget> _resolveNasPlayback(
    PlaybackTarget target,
    DetailEnrichmentSettings settings,
    String traceKey,
  ) async {
    MediaSourceConfig? source;
    for (final candidate in settings.mediaSources) {
      if (candidate.id == target.sourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null || source.kind != MediaSourceKind.nas) {
      DebugTraceOnce.logMetadata(
        traceKey,
        'playback-resolve',
        'skipped no active nas source',
      );
      throw const _PlaybackResolutionException();
    }
    return _ref
        .read(webDavNasClientProvider)
        .resolvePlaybackTarget(source: source, target: target);
  }

  bool _shouldResolvePlaybackTarget(
    PlaybackTarget target, {
    required DetailEnrichmentSettings settings,
  }) {
    final needsEmby = target.sourceKind == MediaSourceKind.emby &&
        target.itemId.trim().isNotEmpty &&
        (target.streamUrl.trim().isEmpty ||
            target.formatLabel.trim().isEmpty ||
            target.resolutionLabel.trim().isEmpty ||
            target.fileSizeLabel.trim().isEmpty);
    final needsQuark = target.sourceKind == MediaSourceKind.quark &&
        target.itemId.trim().isNotEmpty &&
        target.streamUrl.trim().isEmpty;
    final needsNas = target.sourceKind == MediaSourceKind.nas &&
        target.sourceId.trim().isNotEmpty &&
        target.needsResolution;
    return needsEmby || needsQuark || needsNas;
  }
}

String _detailMetadataQuery(MediaDetailTarget target) {
  final raw =
      target.searchQuery.trim().isEmpty ? target.title : target.searchQuery;
  return raw.trim();
}

bool _shouldAutoEnrichMetadataTarget({
  required MediaDetailTarget target,
  required DetailEnrichmentSettings settings,
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
          target.backdropUrl.trim().isEmpty ||
          target.logoUrl.trim().isEmpty);
  return needsWmdb || needsTmdb;
}

Future<MediaDetailTarget> _resolveAutomaticMetadataIfNeeded({
  required DetailEnrichmentSettings settings,
  required MediaDetailTarget target,
  required WmdbMetadataClient wmdbMetadataClient,
  required TmdbMetadataClient tmdbMetadataClient,
  required String traceKey,
}) async {
  var nextTarget = target;
  final initialQuery = _detailMetadataQuery(target);
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
              preferSeries: _prefersSeriesMetadata(nextTarget),
              actors: nextTarget.actors,
            );
      if (wmdbMatch != null) {
        nextTarget = _applyMetadataMatchToDetailTarget(
          nextTarget,
          wmdbMatch,
        );
      }
    } catch (_) {
      // ignore
    }
  }
  return normalizeRatingLabelsInTarget(nextTarget);
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
  return labels
      .any((label) => label.trim().toLowerCase().contains(normalizedKeyword));
}

bool _isEpisodeLikeTarget(MediaDetailTarget target) {
  return target.itemType.trim().toLowerCase() == 'episode' &&
      target.seasonNumber != null &&
      target.seasonNumber! >= 0 &&
      target.episodeNumber != null &&
      target.episodeNumber! > 0;
}

MediaDetailTarget normalizeRatingLabelsInTarget(MediaDetailTarget target) {
  return target.copyWith(
      ratingLabels: _mergeLabels(const [], target.ratingLabels));
}

MediaDetailTarget _mergeCachedDetailTarget(
  MediaDetailTarget current,
  MediaDetailTarget cached,
) {
  final preferCachedResourceState =
      _homeHasResolvedLocalResourceState(cached) &&
          !_homeHasResolvedLocalResourceState(current);
  final preferCachedAvailability =
      _homeShouldPreferCachedAvailability(current, cached) ||
          preferCachedResourceState;
  final preferCachedSourceContext =
      _homeShouldPreferCachedSourceContext(current, cached) ||
          preferCachedResourceState;
  final resolvedPosterUrl =
      cached.posterUrl.trim().isNotEmpty ? cached.posterUrl : current.posterUrl;
  final resolvedPosterHeaders = cached.posterUrl.trim().isNotEmpty
      ? (cached.posterHeaders.isNotEmpty
          ? cached.posterHeaders
          : current.posterHeaders)
      : (current.posterHeaders.isNotEmpty
          ? current.posterHeaders
          : cached.posterHeaders);
  final ignoreCachedEpisodeOverview = _isEpisodeLikeTarget(current) &&
      !current.hasUsefulOverview &&
      current.sourceId.trim() == cached.sourceId.trim() &&
      current.itemId.trim() == cached.itemId.trim();
  return current.copyWith(
    title: cached.title.trim().isNotEmpty ? cached.title : current.title,
    posterUrl: resolvedPosterUrl,
    posterHeaders: resolvedPosterHeaders,
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
    overview: ignoreCachedEpisodeOverview
        ? current.overview
        : (current.hasUsefulOverview ? current.overview : cached.overview),
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
    doubanId:
        current.doubanId.trim().isNotEmpty ? current.doubanId : cached.doubanId,
    imdbId: current.imdbId.trim().isNotEmpty ? current.imdbId : cached.imdbId,
    tmdbId: current.tmdbId.trim().isNotEmpty ? current.tmdbId : cached.tmdbId,
    availabilityLabel: preferCachedAvailability
        ? (cached.availabilityLabel.trim().isNotEmpty
            ? cached.availabilityLabel
            : current.availabilityLabel)
        : (current.availabilityLabel.trim().isNotEmpty
            ? current.availabilityLabel
            : cached.availabilityLabel),
    playbackTarget: _mergeCachedPlaybackTarget(
      current.playbackTarget,
      cached.playbackTarget,
      preferCachedSourceContext: preferCachedSourceContext,
    ),
    itemId: preferCachedSourceContext
        ? (cached.itemId.trim().isNotEmpty ? cached.itemId : current.itemId)
        : (current.itemId.trim().isNotEmpty ? current.itemId : cached.itemId),
    sourceId: preferCachedSourceContext
        ? (cached.sourceId.trim().isNotEmpty
            ? cached.sourceId
            : current.sourceId)
        : (current.sourceId.trim().isNotEmpty
            ? current.sourceId
            : cached.sourceId),
    itemType: preferCachedSourceContext
        ? (cached.itemType.trim().isNotEmpty
            ? cached.itemType
            : current.itemType)
        : (current.itemType.trim().isNotEmpty
            ? current.itemType
            : cached.itemType),
    seasonNumber: preferCachedSourceContext
        ? (cached.seasonNumber ?? current.seasonNumber)
        : (current.seasonNumber ?? cached.seasonNumber),
    episodeNumber: preferCachedSourceContext
        ? (cached.episodeNumber ?? current.episodeNumber)
        : (current.episodeNumber ?? cached.episodeNumber),
    sectionId: preferCachedSourceContext
        ? (cached.sectionId.trim().isNotEmpty
            ? cached.sectionId
            : current.sectionId)
        : (current.sectionId.trim().isNotEmpty
            ? current.sectionId
            : cached.sectionId),
    sectionName: preferCachedSourceContext
        ? (cached.sectionName.trim().isNotEmpty
            ? cached.sectionName
            : current.sectionName)
        : (current.sectionName.trim().isNotEmpty
            ? current.sectionName
            : cached.sectionName),
    resourcePath: preferCachedSourceContext
        ? (cached.resourcePath.trim().isNotEmpty
            ? cached.resourcePath
            : current.resourcePath)
        : (current.resourcePath.trim().isNotEmpty
            ? current.resourcePath
            : cached.resourcePath),
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
  );
}

PlaybackTarget? _mergeCachedPlaybackTarget(
  PlaybackTarget? current,
  PlaybackTarget? cached, {
  required bool preferCachedSourceContext,
}) {
  if (current == null) {
    return cached;
  }
  if (cached == null) {
    return current;
  }

  String preferIdentity(String currentValue, String cachedValue) {
    if (preferCachedSourceContext) {
      return cachedValue.trim().isNotEmpty ? cachedValue : currentValue;
    }
    return currentValue.trim().isNotEmpty ? currentValue : cachedValue;
  }

  T? preferNullableIdentity<T>(T? currentValue, T? cachedValue) {
    if (preferCachedSourceContext) {
      return cachedValue ?? currentValue;
    }
    return currentValue ?? cachedValue;
  }

  return current.copyWith(
    title: cached.title.trim().isNotEmpty ? cached.title : current.title,
    sourceId: preferIdentity(current.sourceId, cached.sourceId),
    sourceName: preferIdentity(current.sourceName, cached.sourceName),
    sourceKind: preferNullableIdentity(current.sourceKind, cached.sourceKind),
    actualAddress: current.actualAddress.trim().isNotEmpty
        ? current.actualAddress
        : cached.actualAddress,
    itemId: preferIdentity(current.itemId, cached.itemId),
    itemType: preferIdentity(current.itemType, cached.itemType),
    year: current.year > 0 ? current.year : cached.year,
    seriesId: preferIdentity(current.seriesId, cached.seriesId),
    seriesTitle: cached.seriesTitle.trim().isNotEmpty
        ? cached.seriesTitle
        : current.seriesTitle,
    preferredMediaSourceId: current.preferredMediaSourceId.trim().isNotEmpty
        ? current.preferredMediaSourceId
        : cached.preferredMediaSourceId,
    subtitle:
        current.subtitle.trim().isNotEmpty ? current.subtitle : cached.subtitle,
    headers: current.headers.isNotEmpty ? current.headers : cached.headers,
    streamUrl: current.streamUrl.trim().isNotEmpty
        ? current.streamUrl
        : cached.streamUrl,
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

String _detailTraceKey(MediaDetailTarget target) {
  final id = [
    target.title.trim(),
    target.itemId.trim(),
    target.sourceId.trim(),
    target.searchQuery.trim(),
  ].join('|');
  return id.isEmpty ? 'detail' : id;
}

bool _homeHasResolvedLocalResourceState(MediaDetailTarget target) {
  if (target.playbackTarget?.canPlay == true) {
    return true;
  }
  if (target.sourceId.trim().isNotEmpty && target.itemId.trim().isNotEmpty) {
    return true;
  }
  final availability = target.availabilityLabel.trim();
  if (availability.isNotEmpty &&
      availability != '无' &&
      (target.sourceName.trim().isNotEmpty ||
          target.resourcePath.trim().isNotEmpty)) {
    return true;
  }
  return false;
}

bool _homeShouldPreferCachedAvailability(
  MediaDetailTarget seed,
  MediaDetailTarget cached,
) {
  final cachedAvailability = cached.availabilityLabel.trim();
  if (cachedAvailability.isEmpty || cachedAvailability == '无') {
    return false;
  }
  final seedAvailability = seed.availabilityLabel.trim();
  return seedAvailability.isEmpty || seedAvailability == '无';
}

bool _homeShouldPreferCachedSourceContext(
  MediaDetailTarget seed,
  MediaDetailTarget cached,
) {
  if (!_homeHasResolvedLocalResourceState(cached)) {
    return false;
  }
  final seedHasResolvedIdentity =
      seed.sourceId.trim().isNotEmpty && seed.itemId.trim().isNotEmpty;
  if (!seedHasResolvedIdentity) {
    return true;
  }
  if (seed.sourceKind == null && cached.sourceKind != null) {
    return true;
  }
  if (seed.sourceName.trim().isEmpty && cached.sourceName.trim().isNotEmpty) {
    return true;
  }
  return false;
}

List<String> _mergeLabels(List<String> initial, Iterable<String> next) {
  final seen = <String>{};
  final merged = <String>[];
  for (final label in initial) {
    final cleaned = label.trim();
    if (cleaned.isEmpty) {
      continue;
    }
    final key = _labelMergeKey(cleaned);
    if (seen.add(key)) {
      merged.add(cleaned);
    }
  }
  for (final label in next) {
    final cleaned = label.trim();
    if (cleaned.isEmpty) {
      continue;
    }
    final key = _labelMergeKey(cleaned);
    if (seen.add(key)) {
      merged.add(cleaned);
    }
  }
  return merged.toList(growable: false);
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
  final preserveEpisodeOverview = _isEpisodeLikeTarget(target);

  String pickString(String current, String incoming) {
    if (replaceExisting) {
      return _firstNonEmpty(incoming, current);
    }
    return current.trim().isNotEmpty ? current : incoming;
  }

  List<T> pickList<T>(List<T> current, List<T> incoming) {
    if (replaceExisting) {
      return incoming.isNotEmpty ? incoming : current;
    }
    return current.isNotEmpty ? current : incoming;
  }

  return target.copyWith(
    posterUrl: pickString(target.posterUrl, match.posterUrl),
    posterHeaders: replaceExisting && match.posterUrl.trim().isNotEmpty
        ? const <String, String>{}
        : target.posterHeaders,
    backdropUrl: pickString(target.backdropUrl, match.backdropUrl),
    backdropHeaders: replaceExisting && match.backdropUrl.trim().isNotEmpty
        ? const <String, String>{}
        : target.backdropHeaders,
    logoUrl: pickString(target.logoUrl, match.logoUrl),
    logoHeaders: replaceExisting && match.logoUrl.trim().isNotEmpty
        ? const <String, String>{}
        : target.logoHeaders,
    bannerUrl: pickString(target.bannerUrl, match.bannerUrl),
    bannerHeaders: replaceExisting && match.bannerUrl.trim().isNotEmpty
        ? const <String, String>{}
        : target.bannerHeaders,
    extraBackdropUrls: replaceExisting
        ? (match.extraBackdropUrls.isNotEmpty
            ? _mergeUniqueImageUrls(match.extraBackdropUrls)
            : target.extraBackdropUrls)
        : _mergeUniqueImageUrls([
            ...target.extraBackdropUrls,
            ...match.extraBackdropUrls,
          ]),
    extraBackdropHeaders: replaceExisting && match.extraBackdropUrls.isNotEmpty
        ? const <String, String>{}
        : target.extraBackdropHeaders,
    overview: preserveEpisodeOverview
        ? target.overview
        : replaceExisting
            ? _firstNonEmpty(match.overview, target.overview)
            : (target.hasUsefulOverview
                ? target.overview
                : pickString('', match.overview)),
    year: replaceExisting
        ? (match.year > 0 ? match.year : target.year)
        : (target.year > 0 ? target.year : match.year),
    durationLabel: pickString(target.durationLabel, match.durationLabel),
    genres: pickList(target.genres, match.genres),
    directors: pickList(target.directors, match.directors),
    directorProfiles:
        pickList(target.directorProfiles, resolvedDirectorProfiles),
    actors: pickList(target.actors, match.actors),
    actorProfiles: pickList(target.actorProfiles, resolvedActorProfiles),
    platforms: shouldReplaceCompanies
        ? match.platforms
        : pickList(target.platforms, match.platforms),
    platformProfiles: shouldReplaceCompanies
        ? resolvedPlatformProfiles
        : pickList(target.platformProfiles, resolvedPlatformProfiles),
    ratingLabels: _mergeLabels(target.ratingLabels, filteredMatchRatingLabels),
    doubanId: pickString(target.doubanId, match.doubanId),
    imdbId: pickString(target.imdbId, match.imdbId),
    tmdbId: pickString(target.tmdbId, match.tmdbId),
    itemType: pickString(target.itemType, match.mediaType.toItemType),
  );
}

String _firstNonEmpty(String first, String fallback) {
  return first.trim().isNotEmpty ? first : fallback;
}

List<String> _mergeUniqueImageUrls(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    result.add(trimmed);
  }
  return result;
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

List<MediaPersonProfile> _toMediaPersonProfiles(
  Iterable<MetadataPersonProfile> profiles,
) {
  return profiles
      .where((item) => item.name.trim().isNotEmpty)
      .map(
        (item) => MediaPersonProfile(
          name: item.name.trim(),
          avatarUrl: item.avatarUrl.trim(),
        ),
      )
      .toList(growable: false);
}

class _PlaybackResolutionException implements Exception {
  const _PlaybackResolutionException();
}
