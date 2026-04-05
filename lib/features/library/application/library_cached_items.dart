import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

Future<List<MediaItem>> resolveLibraryItemsWithCachedDetails({
  required List<MediaItem> items,
  required LocalStorageCacheRepository localStorageCacheRepository,
}) async {
  final resolved = <MediaItem>[];
  for (final item in items) {
    final seedTarget = MediaDetailTarget.fromMediaItem(item);
    final cachedTarget =
        await localStorageCacheRepository.loadDetailTarget(seedTarget);
    if (cachedTarget == null) {
      resolved.add(item);
      continue;
    }
    resolved.add(_mergeCachedLibraryItem(item, cachedTarget));
  }
  return resolved;
}

MediaItem _mergeCachedLibraryItem(
  MediaItem item,
  MediaDetailTarget cached,
) {
  return item.copyWith(
    posterUrl:
        item.posterUrl.trim().isNotEmpty ? item.posterUrl : cached.posterUrl,
    posterHeaders: item.posterHeaders.isNotEmpty
        ? item.posterHeaders
        : cached.posterHeaders,
    backdropUrl: item.backdropUrl.trim().isNotEmpty
        ? item.backdropUrl
        : cached.backdropUrl,
    backdropHeaders: item.backdropHeaders.isNotEmpty
        ? item.backdropHeaders
        : cached.backdropHeaders,
    logoUrl: item.logoUrl.trim().isNotEmpty ? item.logoUrl : cached.logoUrl,
    logoHeaders:
        item.logoHeaders.isNotEmpty ? item.logoHeaders : cached.logoHeaders,
    bannerUrl:
        item.bannerUrl.trim().isNotEmpty ? item.bannerUrl : cached.bannerUrl,
    bannerHeaders: item.bannerHeaders.isNotEmpty
        ? item.bannerHeaders
        : cached.bannerHeaders,
    extraBackdropUrls: item.extraBackdropUrls.isNotEmpty
        ? item.extraBackdropUrls
        : cached.extraBackdropUrls,
    extraBackdropHeaders: item.extraBackdropHeaders.isNotEmpty
        ? item.extraBackdropHeaders
        : cached.extraBackdropHeaders,
    overview: item.overview.trim().isNotEmpty ? item.overview : cached.overview,
    durationLabel: item.durationLabel.trim().isNotEmpty
        ? item.durationLabel
        : cached.durationLabel,
    genres: item.genres.isNotEmpty ? item.genres : cached.genres,
    directors: item.directors.isNotEmpty ? item.directors : cached.directors,
    actors: item.actors.isNotEmpty ? item.actors : cached.actors,
    doubanId: item.doubanId.trim().isNotEmpty ? item.doubanId : cached.doubanId,
    imdbId: item.imdbId.trim().isNotEmpty ? item.imdbId : cached.imdbId,
    ratingLabels:
        item.ratingLabels.isNotEmpty ? item.ratingLabels : cached.ratingLabels,
  );
}
