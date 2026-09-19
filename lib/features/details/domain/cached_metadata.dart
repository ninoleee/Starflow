import 'package:starflow/core/utils/media_rating_labels.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';

/// Cache decorations never replace playable identity or episode structure.
MediaDetailTarget overlayCachedMetadata(
  MediaDetailTarget current,
  MediaDetailTarget cached, {
  bool preserveEpisodeOverview = false,
}) =>
    current.copyWith(
      title: cached.title.trim().isNotEmpty ? cached.title : current.title,
      overview: preserveEpisodeOverview || current.hasUsefulOverview
          ? current.overview
          : cached.overview,
      durationLabel: current.durationLabel.trim().isNotEmpty
          ? current.durationLabel
          : cached.durationLabel,
      ratingLabels:
          mergeDistinctRatingLabels(cached.ratingLabels, current.ratingLabels),
      ratingCount:
          cached.ratingCount > 0 ? cached.ratingCount : current.ratingCount,
      genres: current.genres.isNotEmpty ? current.genres : cached.genres,
      directors:
          current.directors.isNotEmpty ? current.directors : cached.directors,
      directorProfiles: mergeMediaPersonProfiles(
          current.directorProfiles, cached.directorProfiles),
      actors: current.actors.isNotEmpty ? current.actors : cached.actors,
      actorProfiles:
          mergeMediaPersonProfiles(current.actorProfiles, cached.actorProfiles),
      platforms:
          current.platforms.isNotEmpty ? current.platforms : cached.platforms,
      platformProfiles: current.platformProfiles.isNotEmpty
          ? current.platformProfiles
          : cached.platformProfiles,
      doubanId: current.doubanId.trim().isNotEmpty
          ? current.doubanId
          : cached.doubanId,
      imdbId: current.imdbId.trim().isNotEmpty ? current.imdbId : cached.imdbId,
      tmdbId: current.tmdbId.trim().isNotEmpty ? current.tmdbId : cached.tmdbId,
    );
