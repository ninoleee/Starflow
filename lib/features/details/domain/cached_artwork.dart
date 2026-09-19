import 'package:starflow/features/details/domain/media_detail_models.dart';

/// An artwork URL and its request headers always come from the same owner.
/// Lists retain live backdrops; detail views prefer the enriched cache.
MediaDetailTarget overlayCachedArtwork(
  MediaDetailTarget current,
  MediaDetailTarget cached, {
  bool preserveLiveSecondaryArtwork = false,
}) {
  final poster = cached.posterUrl.trim().isNotEmpty ? cached : current;
  final preferred = preserveLiveSecondaryArtwork ? current : cached;
  final fallback = preserveLiveSecondaryArtwork ? cached : current;
  final backdrop =
      preferred.backdropUrl.trim().isNotEmpty ? preferred : fallback;
  final logo = preferred.logoUrl.trim().isNotEmpty ? preferred : fallback;
  final banner = preferred.bannerUrl.trim().isNotEmpty ? preferred : fallback;
  final extra = preferred.extraBackdropUrls.isNotEmpty ? preferred : fallback;
  return current.copyWith(
    posterUrl: poster.posterUrl,
    posterHeaders: poster.posterHeaders,
    backdropUrl: backdrop.backdropUrl,
    backdropHeaders: backdrop.backdropHeaders,
    logoUrl: logo.logoUrl,
    logoHeaders: logo.logoHeaders,
    bannerUrl: banner.bannerUrl,
    bannerHeaders: banner.bannerHeaders,
    extraBackdropUrls: extra.extraBackdropUrls,
    extraBackdropHeaders: extra.extraBackdropHeaders,
  );
}
