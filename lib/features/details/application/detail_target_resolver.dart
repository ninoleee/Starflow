import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/details/domain/cached_metadata.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/features/details/application/detail_metadata_service.dart';
import 'package:starflow/features/details/application/detail_enrichment_settings.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/domain/cached_artwork.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
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
    bool forceMetadataRefresh = false,
  }) async {
    return (await resolveMetadataResult(
      target: target,
      backgroundWorkSuspended: backgroundWorkSuspended,
      forceMetadataRefresh: forceMetadataRefresh,
    ))
        .target;
  }

  Future<DetailMetadataResult> resolveMetadataResult({
    required MediaDetailTarget target,
    required bool backgroundWorkSuspended,
    bool forceMetadataRefresh = false,
  }) async {
    if (backgroundWorkSuspended) {
      final cachedTarget = await _detailCache.loadDetailTarget(target);
      return DetailMetadataResult(
          target: normalizeRatingLabelsInTarget(
            cachedTarget == null
                ? target
                : _mergeCachedDetailTarget(target, cachedTarget),
          ),
          outcome: DetailMetadataOutcome.skipped);
    }
    return _resolveMetadataOnlyIfNeeded(
      target: target,
      forceMetadataRefresh: forceMetadataRefresh,
    );
  }

  Future<MediaDetailTarget> _resolveDetailTargetIfNeeded({
    required MediaDetailTarget target,
  }) async {
    final nextTarget = (await _resolveMetadataOnlyIfNeeded(
      target: target,
    ))
        .target;
    final traceKey = _detailTraceKey(target);
    final playback = nextTarget.playbackTarget;
    if (playback == null) {
      await _persistResolvedTarget(target, nextTarget);
      return nextTarget;
    }

    final shouldResolve =
        _shouldResolvePlaybackTarget(playback, settings: _settings);
    if (!shouldResolve) {
      await _persistResolvedTarget(target, nextTarget);
      return nextTarget;
    }

    try {
      final resolvedPlayback = await _resolvePlayback(
        target: playback,
        settings: _settings,
      );
      final updatedTarget =
          nextTarget.copyWith(playbackTarget: resolvedPlayback);
      await _persistResolvedTarget(target, updatedTarget);
      return updatedTarget;
    } catch (error, stackTrace) {
      appLogError('metadata', 'detail.playback-resolve',
          fields: {'key': traceKey, 'message': 'failed'},
          error: error,
          stackTrace: stackTrace);
      await _persistResolvedTarget(target, nextTarget);
      return nextTarget;
    }
  }

  Future<DetailMetadataResult> _resolveMetadataOnlyIfNeeded({
    required MediaDetailTarget target,
    bool forceMetadataRefresh = false,
  }) async {
    final traceKey = _detailTraceKey(target);
    final cachedState = await _detailCache.loadDetailState(target);
    final cachedTarget = cachedState?.target;
    final currentTarget = normalizeRatingLabelsInTarget(
      cachedTarget == null
          ? target
          : _mergeCachedDetailTarget(target, cachedTarget),
    );
    final result = await resolveDetailMetadata(
      settings: _settings,
      target: currentTarget,
      wmdbMetadataClient: _ref.read(wmdbMetadataClientProvider),
      tmdbMetadataClient: _ref.read(tmdbMetadataClientProvider),
      doubanApiClient: _ref.read(doubanApiClientProvider),
      doubanCookie: _doubanSessionCookie,
      forceRatingRefresh: forceMetadataRefresh,
      traceKey: traceKey,
    );
    final nextTarget = result.target;
    _updateRatingCount(currentTarget, nextTarget);

    return result;
  }

  String get _doubanSessionCookie {
    final account = _ref.read(appSettingsProvider).doubanAccount;
    return account.enabled ? account.sessionCookie.trim() : '';
  }

  void _updateRatingCount(
      MediaDetailTarget target, MediaDetailTarget enriched) {
    final previousCount = target.ratingCount;
    if (enriched.ratingCount > previousCount &&
        enriched.sourceId.trim().isNotEmpty &&
        enriched.itemId.trim().isNotEmpty) {
      unawaited(
        _ref
            .read(mediaRepositoryProvider)
            .updateRatingCount(
              sourceId: enriched.sourceId,
              itemId: enriched.itemId,
              resourcePath: enriched.resourcePath,
              ratingCount: enriched.ratingCount,
            )
            .catchError((_) {}),
      );
    }
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
    } catch (error, stackTrace) {
      appLogError('metadata', 'detail.cache-save',
          fields: {'key': _detailTraceKey(seed), 'message': 'failed'},
          error: error,
          stackTrace: stackTrace);
    }
  }

  Future<PlaybackTarget> _resolvePlayback({
    required PlaybackTarget target,
    required DetailEnrichmentSettings settings,
  }) async {
    if (target.sourceKind.isMediaServer) {
      return _resolveEmbyPlayback(target, settings);
    }
    if (target.sourceKind == MediaSourceKind.nas) {
      return _resolveNasPlayback(target, settings);
    }
    return _resolveQuarkPlayback(target, settings);
  }

  Future<PlaybackTarget> _resolveEmbyPlayback(
    PlaybackTarget target,
    DetailEnrichmentSettings settings,
  ) async {
    MediaSourceConfig? source;
    for (final candidate in settings.mediaSources) {
      if (candidate.id == target.sourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null || !source.hasActiveSession) {
      throw const _PlaybackResolutionException();
    }
    return _ref
        .read(mediaServerClientProvider(source.kind))
        .resolvePlaybackTarget(source: source, target: target);
  }

  Future<PlaybackTarget> _resolveQuarkPlayback(
    PlaybackTarget target,
    DetailEnrichmentSettings settings,
  ) async {
    final cookie = settings.quarkCookie.trim();
    if (cookie.isEmpty) {
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
  ) async {
    MediaSourceConfig? source;
    for (final candidate in settings.mediaSources) {
      if (candidate.id == target.sourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null || source.kind != MediaSourceKind.nas) {
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
    final needsEmby = target.sourceKind.isMediaServer &&
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

MediaDetailTarget normalizeRatingLabelsInTarget(MediaDetailTarget target) {
  return target.copyWith(
      ratingLabels: mergeDistinctRatingLabels(const [], target.ratingLabels));
}

MediaDetailTarget mergeCachedDetailArtwork(
  MediaDetailTarget current,
  MediaDetailTarget cached,
) {
  return overlayCachedArtwork(current, cached);
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
  final ignoreCachedEpisodeOverview = isEpisodeMetadataTarget(current) &&
      !current.hasUsefulOverview &&
      current.sourceId.trim() == cached.sourceId.trim() &&
      current.itemId.trim() == cached.itemId.trim();
  final decorated = overlayCachedMetadata(current, cached,
      preserveEpisodeOverview: ignoreCachedEpisodeOverview);
  return mergeCachedDetailArtwork(decorated, cached).copyWith(
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

  Map<String, String> preferIdentityHeaders({
    required String currentValue,
    required Map<String, String> currentHeaders,
    required String cachedValue,
    required Map<String, String> cachedHeaders,
  }) {
    if (preferCachedSourceContext && cachedValue.trim().isNotEmpty) {
      return cachedHeaders;
    }
    if (!preferCachedSourceContext && currentValue.trim().isNotEmpty) {
      return currentHeaders;
    }
    return preferCachedSourceContext ? currentHeaders : cachedHeaders;
  }

  T? preferNullableIdentity<T>(T? currentValue, T? cachedValue) {
    if (preferCachedSourceContext) {
      return cachedValue ?? currentValue;
    }
    return currentValue ?? cachedValue;
  }

  final hasTransportIdentityConflict =
      _hasPlaybackResourceIdentityConflict(current, cached);
  final canReuseCachedTransport = !hasTransportIdentityConflict &&
      (preferCachedSourceContext ||
          _samePlaybackResourceIdentity(current, cached));

  String preferTransportString(String currentValue, String cachedValue) {
    if (!canReuseCachedTransport) {
      return currentValue;
    }
    return currentValue.trim().isNotEmpty ? currentValue : cachedValue;
  }

  T? preferTransportValue<T>(T? currentValue, T? cachedValue) {
    if (!canReuseCachedTransport) {
      return currentValue;
    }
    return currentValue ?? cachedValue;
  }

  return current.copyWith(
    title: cached.title.trim().isNotEmpty ? cached.title : current.title,
    sourceId: preferIdentity(current.sourceId, cached.sourceId),
    sourceName: preferIdentity(current.sourceName, cached.sourceName),
    sourceKind: preferNullableIdentity(current.sourceKind, cached.sourceKind),
    actualAddress: preferTransportString(
      current.actualAddress,
      cached.actualAddress,
    ),
    itemId: preferIdentity(current.itemId, cached.itemId),
    itemType: preferIdentity(current.itemType, cached.itemType),
    year: current.year > 0 ? current.year : cached.year,
    seriesId: preferIdentity(current.seriesId, cached.seriesId),
    seriesTitle: cached.seriesTitle.trim().isNotEmpty
        ? cached.seriesTitle
        : current.seriesTitle,
    preferredMediaSourceId: preferTransportString(
      current.preferredMediaSourceId,
      cached.preferredMediaSourceId,
    ),
    posterUrl: preferIdentity(current.posterUrl, cached.posterUrl),
    posterHeaders: preferIdentityHeaders(
      currentValue: current.posterUrl,
      currentHeaders: current.posterHeaders,
      cachedValue: cached.posterUrl,
      cachedHeaders: cached.posterHeaders,
    ),
    backdropUrl: preferIdentity(current.backdropUrl, cached.backdropUrl),
    backdropHeaders: preferIdentityHeaders(
      currentValue: current.backdropUrl,
      currentHeaders: current.backdropHeaders,
      cachedValue: cached.backdropUrl,
      cachedHeaders: cached.backdropHeaders,
    ),
    subtitle: preferTransportString(current.subtitle, cached.subtitle),
    headers: canReuseCachedTransport && current.headers.isEmpty
        ? cached.headers
        : current.headers,
    streamUrl: preferTransportString(current.streamUrl, cached.streamUrl),
    container: preferTransportString(current.container, cached.container),
    videoCodec: preferTransportString(current.videoCodec, cached.videoCodec),
    audioCodec: preferTransportString(current.audioCodec, cached.audioCodec),
    seasonNumber: current.seasonNumber ?? cached.seasonNumber,
    episodeNumber: current.episodeNumber ?? cached.episodeNumber,
    width: preferTransportValue(current.width, cached.width),
    height: preferTransportValue(current.height, cached.height),
    bitrate: preferTransportValue(current.bitrate, cached.bitrate),
    fileSizeBytes:
        preferTransportValue(current.fileSizeBytes, cached.fileSizeBytes),
  );
}

bool _samePlaybackResourceIdentity(
  PlaybackTarget current,
  PlaybackTarget cached,
) {
  if (_hasPlaybackResourceIdentityConflict(current, cached)) {
    return false;
  }
  return current.preferredMediaSourceId.trim().isNotEmpty ||
      current.itemId.trim().isNotEmpty ||
      _playbackResourceAddressKey(current.actualAddress).isNotEmpty;
}

bool _hasPlaybackResourceIdentityConflict(
  PlaybackTarget current,
  PlaybackTarget cached,
) {
  final currentPreferredMediaSourceId = current.preferredMediaSourceId.trim();
  if (currentPreferredMediaSourceId.isNotEmpty &&
      cached.preferredMediaSourceId.trim() != currentPreferredMediaSourceId) {
    return true;
  }

  final currentItemId = current.itemId.trim();
  if (currentItemId.isNotEmpty && cached.itemId.trim() != currentItemId) {
    return true;
  }

  final currentSourceId = current.sourceId.trim();
  if (currentSourceId.isNotEmpty && cached.sourceId.trim() != currentSourceId) {
    return true;
  }
  if (current.sourceKind != cached.sourceKind) {
    return true;
  }

  final currentAddress = _playbackResourceAddressKey(current.actualAddress);
  final cachedAddress = _playbackResourceAddressKey(cached.actualAddress);
  if (currentAddress.isNotEmpty &&
      cachedAddress.isNotEmpty &&
      currentAddress != cachedAddress) {
    return true;
  }
  return false;
}

String _playbackResourceAddressKey(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
        '${uri.path.replaceAll('\\', '/')}';
  }
  return trimmed.replaceAll('\\', '/');
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

class _PlaybackResolutionException implements Exception {
  const _PlaybackResolutionException();
}
