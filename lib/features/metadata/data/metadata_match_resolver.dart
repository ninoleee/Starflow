import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

final metadataMatchResolverProvider = Provider<MetadataMatchResolver>((ref) {
  return MetadataMatchResolver(
    tmdbMetadataClient: ref.read(tmdbMetadataClientProvider),
    wmdbMetadataClient: ref.read(wmdbMetadataClientProvider),
  );
});

class MetadataMatchResolver {
  const MetadataMatchResolver({
    required TmdbMetadataClient tmdbMetadataClient,
    required WmdbMetadataClient wmdbMetadataClient,
  })  : _tmdbMetadataClient = tmdbMetadataClient,
        _wmdbMetadataClient = wmdbMetadataClient;

  final TmdbMetadataClient _tmdbMetadataClient;
  final WmdbMetadataClient _wmdbMetadataClient;

  Future<MetadataMatchResult?> match({
    required AppSettings settings,
    required MetadataMatchRequest request,
  }) async {
    final normalizedImdbId = request.imdbId.trim();
    if (normalizedImdbId.isNotEmpty &&
        settings.tmdbMetadataMatchEnabled &&
        settings.tmdbReadAccessToken.trim().isNotEmpty) {
      final match = await _tmdbMetadataClient.matchByImdbId(
        imdbId: normalizedImdbId,
        readAccessToken: settings.tmdbReadAccessToken.trim(),
        preferSeries: request.preferSeries,
      );
      if (match != null) {
        return MetadataMatchResult(
          provider: MetadataMatchProvider.tmdb,
          title: match.title,
          originalTitle: match.originalTitle,
          posterUrl: match.posterUrl,
          backdropUrl: match.backdropUrl,
          logoUrl: match.logoUrl,
          extraBackdropUrls: match.extraBackdropUrls,
          overview: match.overview,
          year: match.year,
          durationLabel: match.durationLabel,
          genres: match.genres,
          directors: match.directors,
          directorProfiles: match.directorProfiles
              .map(
                (item) => MetadataPersonProfile(
                  name: item.name,
                  avatarUrl: item.avatarUrl,
                ),
              )
              .toList(),
          actors: match.actors,
          actorProfiles: match.actorProfiles
              .map(
                (item) => MetadataPersonProfile(
                  name: item.name,
                  avatarUrl: item.avatarUrl,
                ),
              )
              .toList(),
          platforms: match.platforms,
          platformProfiles: match.platformProfiles
              .map(
                (item) => MetadataPersonProfile(
                  name: item.name,
                  avatarUrl: item.avatarUrl,
                ),
              )
              .toList(),
          ratingLabels: match.ratingLabels,
          imdbId: match.imdbId,
          tmdbId: '${match.tmdbId}',
        );
      }
    }

    for (final provider in _orderedEnabledProviders(settings)) {
      switch (provider) {
        case MetadataMatchProvider.tmdb:
          final token = settings.tmdbReadAccessToken.trim();
          if (!settings.tmdbMetadataMatchEnabled || token.isEmpty) {
            continue;
          }
          final match = await _tmdbMetadataClient.matchTitle(
            query: request.query,
            readAccessToken: token,
            year: request.year,
            preferSeries: request.preferSeries,
          );
          if (match != null) {
            return MetadataMatchResult(
              provider: MetadataMatchProvider.tmdb,
              title: match.title,
              originalTitle: match.originalTitle,
              posterUrl: match.posterUrl,
              backdropUrl: match.backdropUrl,
              logoUrl: match.logoUrl,
              extraBackdropUrls: match.extraBackdropUrls,
              overview: match.overview,
              year: match.year,
              durationLabel: match.durationLabel,
              genres: match.genres,
              directors: match.directors,
              directorProfiles: match.directorProfiles
                  .map(
                    (item) => MetadataPersonProfile(
                      name: item.name,
                      avatarUrl: item.avatarUrl,
                    ),
                  )
                  .toList(),
              actors: match.actors,
              actorProfiles: match.actorProfiles
                  .map(
                    (item) => MetadataPersonProfile(
                      name: item.name,
                      avatarUrl: item.avatarUrl,
                    ),
                  )
                  .toList(),
              platforms: match.platforms,
              platformProfiles: match.platformProfiles
                  .map(
                    (item) => MetadataPersonProfile(
                      name: item.name,
                      avatarUrl: item.avatarUrl,
                    ),
                  )
                  .toList(),
              ratingLabels: match.ratingLabels,
              imdbId: match.imdbId,
              tmdbId: '${match.tmdbId}',
            );
          }
        case MetadataMatchProvider.wmdb:
          if (!settings.wmdbMetadataMatchEnabled) {
            continue;
          }
          final doubanId = request.doubanId.trim();
          final match = doubanId.isNotEmpty
              ? await _wmdbMetadataClient.matchByDoubanId(doubanId: doubanId)
              : await _wmdbMetadataClient.matchTitle(
                  query: request.query,
                  year: request.year,
                  preferSeries: request.preferSeries,
                  actors: request.actors,
                );
          if (match != null) {
            return match;
          }
      }
    }

    return null;
  }

  List<MetadataMatchProvider> _orderedEnabledProviders(AppSettings settings) {
    final preferred = settings.metadataMatchPriority;
    return preferred == MetadataMatchProvider.wmdb
        ? const [MetadataMatchProvider.wmdb, MetadataMatchProvider.tmdb]
        : const [MetadataMatchProvider.tmdb, MetadataMatchProvider.wmdb];
  }
}
