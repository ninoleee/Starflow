import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/storage/application/local_storage_cache_revision.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

class LibraryVisiblePageItemsResult {
  const LibraryVisiblePageItemsResult({
    required this.totalItems,
    required this.items,
  });

  final int totalItems;
  final List<MediaItem> items;
}

const Set<LocalStorageDetailCacheChangedField>
    libraryPresentationCacheChangedFields = {
  LocalStorageDetailCacheChangedField.artwork,
  LocalStorageDetailCacheChangedField.summary,
  LocalStorageDetailCacheChangedField.ratings,
  LocalStorageDetailCacheChangedField.availability,
  LocalStorageDetailCacheChangedField.playback,
  LocalStorageDetailCacheChangedField.structure,
};

Future<List<MediaItem>> resolveLibraryItemsWithCachedDetails({
  required List<MediaItem> items,
  required LocalStorageCacheRepository localStorageCacheRepository,
  List<MediaDetailTarget>? seedTargets,
}) async {
  if (items.isEmpty) {
    return const <MediaItem>[];
  }

  final resolvedSeedTargets = seedTargets ??
      items.map(MediaDetailTarget.fromMediaItem).toList(growable: false);
  final cachedTargets =
      await localStorageCacheRepository.loadDetailTargetsBatch(
    resolvedSeedTargets,
  );

  List<MediaItem>? resolved;
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final cachedTarget = cachedTargets[index];
    final mergedItem = cachedTarget == null
        ? item
        : _mergeCachedLibraryItem(item, cachedTarget);
    if (resolved == null && identical(mergedItem, item)) {
      continue;
    }
    resolved ??= items.take(index).toList(growable: true);
    resolved.add(mergedItem);
  }

  return resolved == null ? items : List<MediaItem>.unmodifiable(resolved);
}

MediaItem mergeLibraryItemWithCachedDetails({
  required MediaItem item,
  MediaDetailTarget? cachedTarget,
}) {
  if (cachedTarget == null) {
    return item;
  }
  return _mergeCachedLibraryItem(item, cachedTarget);
}

class LibraryItemOverlayRequest {
  LibraryItemOverlayRequest(MediaItem item)
      : this._(MediaDetailTarget.fromMediaItem(item));

  LibraryItemOverlayRequest._(this.seedTarget)
      : _identity = _LibraryItemOverlayIdentity.fromTarget(seedTarget),
        cacheScope = LocalStorageDetailCacheScope(
          lookupKeys: {
            ...LocalStorageCacheRepository.buildLookupKeys(seedTarget),
          },
        );

  final MediaDetailTarget seedTarget;
  final _LibraryItemOverlayIdentity _identity;
  final LocalStorageDetailCacheScope cacheScope;

  @override
  bool operator ==(Object other) =>
      other is LibraryItemOverlayRequest && other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;
}

class _LibraryItemOverlayIdentity {
  const _LibraryItemOverlayIdentity({
    required this.sourceKind,
    required this.sourceId,
    required this.itemId,
    required this.itemType,
    required this.sectionId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.doubanId,
    required this.imdbId,
    required this.tmdbId,
    required this.tvdbId,
    required this.wikidataId,
    required this.tmdbSetId,
    required this.title,
    required this.year,
  });

  factory _LibraryItemOverlayIdentity.fromTarget(MediaDetailTarget target) {
    return _LibraryItemOverlayIdentity(
      sourceKind: target.sourceKind,
      sourceId: target.sourceId.trim(),
      itemId: target.itemId.trim(),
      itemType: target.itemType.trim(),
      sectionId: target.sectionId.trim(),
      seasonNumber: target.seasonNumber,
      episodeNumber: target.episodeNumber,
      doubanId: target.doubanId.trim(),
      imdbId: target.imdbId.trim().toLowerCase(),
      tmdbId: target.tmdbId.trim(),
      tvdbId: target.tvdbId.trim(),
      wikidataId: target.wikidataId.trim().toUpperCase(),
      tmdbSetId: target.tmdbSetId.trim(),
      title: target.title.trim(),
      year: target.year,
    );
  }

  final MediaSourceKind? sourceKind;
  final String sourceId;
  final String itemId;
  final String itemType;
  final String sectionId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String doubanId;
  final String imdbId;
  final String tmdbId;
  final String tvdbId;
  final String wikidataId;
  final String tmdbSetId;
  final String title;
  final int year;

  @override
  bool operator ==(Object other) {
    return other is _LibraryItemOverlayIdentity &&
        other.sourceKind == sourceKind &&
        other.sourceId == sourceId &&
        other.itemId == itemId &&
        other.itemType == itemType &&
        other.sectionId == sectionId &&
        other.seasonNumber == seasonNumber &&
        other.episodeNumber == episodeNumber &&
        other.doubanId == doubanId &&
        other.imdbId == imdbId &&
        other.tmdbId == tmdbId &&
        other.tvdbId == tvdbId &&
        other.wikidataId == wikidataId &&
        other.tmdbSetId == tmdbSetId &&
        other.title == title &&
        other.year == year;
  }

  @override
  int get hashCode => Object.hash(
        sourceKind,
        sourceId,
        itemId,
        itemType,
        sectionId,
        seasonNumber,
        episodeNumber,
        doubanId,
        imdbId,
        tmdbId,
        tvdbId,
        wikidataId,
        tmdbSetId,
        title,
        year,
      );
}

final libraryCachedDetailTargetProvider =
    Provider.autoDispose.family<MediaDetailTarget?, LibraryItemOverlayRequest>((
  ref,
  request,
) {
  final liveOverlayEnabled = ref.watch(
    effectivePerformanceLiveItemHeroOverlayEnabledProvider,
  );
  if (!liveOverlayEnabled) {
    return null;
  }
  final cacheScope = request.cacheScope;
  if (!cacheScope.isEmpty) {
    ref.watch(
      localStorageDetailCacheChangeProvider.select(
        (state) => state.revisionForScope(
          cacheScope,
          changedFields: libraryPresentationCacheChangedFields,
        ),
      ),
    );
  }
  final cachedTarget = ref
      .read(localStorageCacheRepositoryProvider)
      .peekDetailTarget(request.seedTarget);
  return cachedTarget;
});

List<MediaItem> visibleLibraryPageItems({
  required List<MediaItem> items,
  required int page,
  required int pageSize,
}) {
  if (items.isEmpty) {
    return const <MediaItem>[];
  }
  final safePageSize = math.max(1, pageSize);
  final totalPages = (items.length / safePageSize).ceil();
  final safePage = totalPages <= 0 ? 0 : page.clamp(0, totalPages - 1);
  return items
      .skip(safePage * safePageSize)
      .take(safePageSize)
      .toList(growable: false);
}

Future<LibraryVisiblePageItemsResult>
    resolveVisibleLibraryPageItemsWithCachedDetails({
  required List<MediaItem> items,
  required int page,
  required int pageSize,
  required LocalStorageCacheRepository localStorageCacheRepository,
}) async {
  final visibleItems = visibleLibraryPageItems(
    items: items,
    page: page,
    pageSize: pageSize,
  );
  if (visibleItems.isEmpty) {
    return LibraryVisiblePageItemsResult(
      totalItems: items.length,
      items: const <MediaItem>[],
    );
  }
  final seedTargets =
      visibleItems.map(MediaDetailTarget.fromMediaItem).toList(growable: false);
  final resolvedItems = await resolveLibraryItemsWithCachedDetails(
    items: visibleItems,
    localStorageCacheRepository: localStorageCacheRepository,
    seedTargets: seedTargets,
  );
  return LibraryVisiblePageItemsResult(
    totalItems: items.length,
    items: resolvedItems,
  );
}

bool visibleLibraryPageSegmentChanged({
  required List<MediaItem> previousItems,
  required List<MediaItem> nextItems,
  required int page,
  required int pageSize,
}) {
  final previousVisible = visibleLibraryPageItems(
    items: previousItems,
    page: page,
    pageSize: pageSize,
  );
  final nextVisible = visibleLibraryPageItems(
    items: nextItems,
    page: page,
    pageSize: pageSize,
  );
  if (previousVisible.length != nextVisible.length) {
    return true;
  }
  for (var index = 0; index < previousVisible.length; index++) {
    if (!_libraryGridMediaItemsVisuallyEquivalent(
      previousVisible[index],
      nextVisible[index],
    )) {
      return true;
    }
  }
  return false;
}

void pruneRetainedVisiblePageCacheEntries<K, V>({
  required Map<K, V> entries,
  required K currentRequest,
  required int Function(K request) pageOf,
  required bool Function(K entry, K currentRequest) isSameScope,
  int keepRadius = 1,
}) {
  entries.removeWhere((key, _) {
    if (!isSameScope(key, currentRequest)) {
      return true;
    }
    return (pageOf(key) - pageOf(currentRequest)).abs() > keepRadius;
  });
}

MediaItem _mergeCachedLibraryItem(
  MediaItem item,
  MediaDetailTarget cached,
) {
  final resolvedTitle =
      cached.title.trim().isNotEmpty ? cached.title : item.title;
  final resolvedOriginalTitle = cached.title.trim().isNotEmpty &&
          item.originalTitle.trim().isEmpty &&
          cached.title.trim() != item.title.trim()
      ? item.title
      : item.originalTitle;
  final resolvedSortTitle =
      cached.title.trim().isNotEmpty ? cached.title : item.sortTitle;
  final resolvedPosterUrl =
      cached.posterUrl.trim().isNotEmpty ? cached.posterUrl : item.posterUrl;
  final resolvedPosterHeaders = cached.posterUrl.trim().isNotEmpty
      ? (cached.posterHeaders.isNotEmpty
          ? cached.posterHeaders
          : item.posterHeaders)
      : (item.posterHeaders.isNotEmpty
          ? item.posterHeaders
          : cached.posterHeaders);
  final resolvedBackdropUrl = item.backdropUrl.trim().isNotEmpty
      ? item.backdropUrl
      : cached.backdropUrl;
  final resolvedBackdropHeaders = item.backdropHeaders.isNotEmpty
      ? item.backdropHeaders
      : cached.backdropHeaders;
  final resolvedLogoUrl =
      item.logoUrl.trim().isNotEmpty ? item.logoUrl : cached.logoUrl;
  final resolvedLogoHeaders =
      item.logoHeaders.isNotEmpty ? item.logoHeaders : cached.logoHeaders;
  final resolvedBannerUrl =
      item.bannerUrl.trim().isNotEmpty ? item.bannerUrl : cached.bannerUrl;
  final resolvedBannerHeaders =
      item.bannerHeaders.isNotEmpty ? item.bannerHeaders : cached.bannerHeaders;
  final resolvedExtraBackdropUrls = item.extraBackdropUrls.isNotEmpty
      ? item.extraBackdropUrls
      : cached.extraBackdropUrls;
  final resolvedExtraBackdropHeaders = item.extraBackdropHeaders.isNotEmpty
      ? item.extraBackdropHeaders
      : cached.extraBackdropHeaders;
  final resolvedOverview =
      item.overview.trim().isNotEmpty ? item.overview : cached.overview;
  final resolvedDurationLabel = item.durationLabel.trim().isNotEmpty
      ? item.durationLabel
      : cached.durationLabel;
  final resolvedGenres = item.genres.isNotEmpty ? item.genres : cached.genres;
  final resolvedDirectors =
      item.directors.isNotEmpty ? item.directors : cached.directors;
  final resolvedActors = item.actors.isNotEmpty ? item.actors : cached.actors;
  final resolvedDoubanId =
      item.doubanId.trim().isNotEmpty ? item.doubanId : cached.doubanId;
  final resolvedImdbId =
      item.imdbId.trim().isNotEmpty ? item.imdbId : cached.imdbId;
  final resolvedTmdbId =
      item.tmdbId.trim().isNotEmpty ? item.tmdbId : cached.tmdbId;
  final resolvedRatingLabels =
      mergeDistinctRatingLabels(cached.ratingLabels, item.ratingLabels);

  final hasChanges = resolvedTitle != item.title ||
      resolvedOriginalTitle != item.originalTitle ||
      resolvedSortTitle != item.sortTitle ||
      resolvedPosterUrl != item.posterUrl ||
      !_sameStringMap(resolvedPosterHeaders, item.posterHeaders) ||
      resolvedBackdropUrl != item.backdropUrl ||
      !_sameStringMap(resolvedBackdropHeaders, item.backdropHeaders) ||
      resolvedLogoUrl != item.logoUrl ||
      !_sameStringMap(resolvedLogoHeaders, item.logoHeaders) ||
      resolvedBannerUrl != item.bannerUrl ||
      !_sameStringMap(resolvedBannerHeaders, item.bannerHeaders) ||
      !_sameStringList(resolvedExtraBackdropUrls, item.extraBackdropUrls) ||
      !_sameStringMap(
        resolvedExtraBackdropHeaders,
        item.extraBackdropHeaders,
      ) ||
      resolvedOverview != item.overview ||
      resolvedDurationLabel != item.durationLabel ||
      !_sameStringList(resolvedGenres, item.genres) ||
      !_sameStringList(resolvedDirectors, item.directors) ||
      !_sameStringList(resolvedActors, item.actors) ||
      resolvedDoubanId != item.doubanId ||
      resolvedImdbId != item.imdbId ||
      resolvedTmdbId != item.tmdbId ||
      !_sameStringList(resolvedRatingLabels, item.ratingLabels);
  if (!hasChanges) {
    return item;
  }

  return item.copyWith(
    title: resolvedTitle,
    originalTitle: resolvedOriginalTitle,
    sortTitle: resolvedSortTitle,
    posterUrl: resolvedPosterUrl,
    posterHeaders: resolvedPosterHeaders,
    backdropUrl: resolvedBackdropUrl,
    backdropHeaders: resolvedBackdropHeaders,
    logoUrl: resolvedLogoUrl,
    logoHeaders: resolvedLogoHeaders,
    bannerUrl: resolvedBannerUrl,
    bannerHeaders: resolvedBannerHeaders,
    extraBackdropUrls: resolvedExtraBackdropUrls,
    extraBackdropHeaders: resolvedExtraBackdropHeaders,
    overview: resolvedOverview,
    durationLabel: resolvedDurationLabel,
    genres: resolvedGenres,
    directors: resolvedDirectors,
    actors: resolvedActors,
    doubanId: resolvedDoubanId,
    imdbId: resolvedImdbId,
    tmdbId: resolvedTmdbId,
    ratingLabels: resolvedRatingLabels,
  );
}

bool _sameStringList(Iterable<String> left, Iterable<String> right) {
  if (identical(left, right)) {
    return true;
  }
  final leftList = left is List<String> ? left : left.toList(growable: false);
  final rightList =
      right is List<String> ? right : right.toList(growable: false);
  if (leftList.length != rightList.length) {
    return false;
  }
  for (var index = 0; index < leftList.length; index++) {
    if (leftList[index] != rightList[index]) {
      return false;
    }
  }
  return true;
}

bool _sameStringMap(Map<String, String> left, Map<String, String> right) {
  if (identical(left, right)) {
    return true;
  }
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

bool _libraryGridMediaItemsVisuallyEquivalent(MediaItem a, MediaItem b) {
  if (a.id != b.id) {
    return false;
  }
  if (a.title != b.title || a.year != b.year) {
    return false;
  }
  if (a.durationLabel != b.durationLabel) {
    return false;
  }
  if (a.posterUrl != b.posterUrl) {
    return false;
  }
  if (!mapEquals(a.posterHeaders, b.posterHeaders)) {
    return false;
  }
  if (!listEquals(a.ratingLabels, b.ratingLabels)) {
    return false;
  }
  return true;
}
