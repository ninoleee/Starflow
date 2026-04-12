import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/utils/metadata_search_trace.dart';
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
    final providers = _orderedEnabledProviders(settings);
    metadataSearchTrace(
      'resolver.match.start',
      fields: <String, Object?>{
        'query': request.query,
        'doubanId': request.doubanId,
        'imdbId': request.imdbId,
        'year': request.year,
        'preferSeries': request.preferSeries,
        'providers': providers.map((item) => item.name).join('/'),
      },
    );
    for (final provider in providers) {
      switch (provider) {
        case MetadataMatchProvider.tmdb:
          final token = settings.tmdbReadAccessToken.trim();
          if (!settings.tmdbMetadataMatchEnabled || token.isEmpty) {
            continue;
          }
          metadataSearchTrace(
            'resolver.provider.start',
            fields: <String, Object?>{
              'provider': provider.name,
              'mode': 'title',
              'query': request.query,
              'year': request.year,
              'preferSeries': request.preferSeries,
            },
          );
          try {
            final match = await _tmdbMetadataClient.matchTitle(
              query: request.query,
              readAccessToken: token,
              year: request.year,
              preferSeries: request.preferSeries,
            );
            if (match != null) {
              final result = _mapTmdbMatch(match);
              metadataSearchTrace(
                'resolver.provider.match',
                fields: <String, Object?>{
                  'provider': provider.name,
                  'mode': 'title',
                  'query': request.query,
                  'title': result.title,
                  'imdbId': result.imdbId,
                  'tmdbId': result.tmdbId,
                },
              );
              return result;
            }
            metadataSearchTrace(
              'resolver.provider.no-match',
              fields: <String, Object?>{
                'provider': provider.name,
                'mode': 'title',
                'query': request.query,
              },
            );
          } catch (error, stackTrace) {
            metadataSearchTrace(
              'resolver.provider.failed',
              fields: <String, Object?>{
                'provider': provider.name,
                'mode': 'title',
                'query': request.query,
              },
              error: error,
              stackTrace: stackTrace,
            );
            rethrow;
          }
        case MetadataMatchProvider.wmdb:
          if (!settings.wmdbMetadataMatchEnabled) {
            continue;
          }
          final doubanId = request.doubanId.trim();
          metadataSearchTrace(
            'resolver.provider.start',
            fields: <String, Object?>{
              'provider': provider.name,
              'mode': doubanId.isNotEmpty ? 'doubanId' : 'title',
              'query': request.query,
              'doubanId': doubanId,
              'year': request.year,
              'preferSeries': request.preferSeries,
              'firstActor': request.actors.isEmpty ? '' : request.actors.first,
            },
          );
          try {
            final match = doubanId.isNotEmpty
                ? await _wmdbMetadataClient.matchByDoubanId(doubanId: doubanId)
                : await _wmdbMetadataClient.matchTitle(
                    query: request.query,
                    year: request.year,
                    preferSeries: request.preferSeries,
                    actors: request.actors,
                  );
            if (match != null) {
              metadataSearchTrace(
                'resolver.provider.match',
                fields: <String, Object?>{
                  'provider': provider.name,
                  'mode': doubanId.isNotEmpty ? 'doubanId' : 'title',
                  'query': request.query,
                  'doubanId': match.doubanId,
                  'imdbId': match.imdbId,
                  'tmdbId': match.tmdbId,
                  'title': match.title,
                },
              );
              return match;
            }
            metadataSearchTrace(
              'resolver.provider.no-match',
              fields: <String, Object?>{
                'provider': provider.name,
                'mode': doubanId.isNotEmpty ? 'doubanId' : 'title',
                'query': request.query,
                'doubanId': doubanId,
              },
            );
          } catch (error, stackTrace) {
            metadataSearchTrace(
              'resolver.provider.failed',
              fields: <String, Object?>{
                'provider': provider.name,
                'mode': doubanId.isNotEmpty ? 'doubanId' : 'title',
                'query': request.query,
                'doubanId': doubanId,
              },
              error: error,
              stackTrace: stackTrace,
            );
            rethrow;
          }
      }
    }

    metadataSearchTrace(
      'resolver.match.no-result',
      fields: <String, Object?>{
        'query': request.query,
        'doubanId': request.doubanId,
        'imdbId': request.imdbId,
      },
    );
    return null;
  }

  List<MetadataMatchProvider> _orderedEnabledProviders(AppSettings settings) {
    final preferred = settings.metadataMatchPriority;
    return preferred == MetadataMatchProvider.wmdb
        ? const [MetadataMatchProvider.wmdb, MetadataMatchProvider.tmdb]
        : const [MetadataMatchProvider.tmdb, MetadataMatchProvider.wmdb];
  }

  MetadataMatchResult _mapTmdbMatch(TmdbMetadataMatch match) {
    return MetadataMatchResult(
      provider: MetadataMatchProvider.tmdb,
      mediaType:
          match.isSeries ? MetadataMediaType.series : MetadataMediaType.movie,
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
