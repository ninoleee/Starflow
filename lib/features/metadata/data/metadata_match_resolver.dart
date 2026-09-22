import 'package:starflow/core/logging/app_logger.dart';
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
    final providers = _orderedEnabledProviders(settings);
    Object? lastError;
    StackTrace? lastStackTrace;
    var hadDefinitiveNoMatch = false;
    var attemptedProviders = 0;
    for (final provider in providers) {
      final attempt = switch (provider) {
        MetadataMatchProvider.tmdb =>
          await _matchTmdbProvider(settings: settings, request: request),
        MetadataMatchProvider.wmdb =>
          await _matchWmdbProvider(settings: settings, request: request),
      };
      if (!attempt.wasAttempted) {
        continue;
      }
      attemptedProviders += 1;
      if (attempt.result != null) {
        return attempt.result;
      }
      if (attempt.error != null) {
        lastError = attempt.error;
        lastStackTrace = attempt.stackTrace;
        continue;
      }
      hadDefinitiveNoMatch = true;
    }

    if (!hadDefinitiveNoMatch &&
        attemptedProviders > 0 &&
        lastError != null &&
        lastStackTrace != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }

    return null;
  }

  List<MetadataMatchProvider> _orderedEnabledProviders(AppSettings settings) {
    final preferred = settings.metadataMatchPriority;
    return preferred == MetadataMatchProvider.wmdb
        ? const [MetadataMatchProvider.wmdb, MetadataMatchProvider.tmdb]
        : const [MetadataMatchProvider.tmdb, MetadataMatchProvider.wmdb];
  }

  Future<_ResolverAttempt> _matchTmdbProvider({
    required AppSettings settings,
    required MetadataMatchRequest request,
  }) async {
    final token = settings.tmdbReadAccessToken.trim();
    if (!settings.tmdbMetadataMatchEnabled || token.isEmpty) {
      return const _ResolverAttempt.skipped();
    }
    final imdbId = request.imdbId.trim().toLowerCase();
    final mode = imdbId.isNotEmpty ? 'imdbId' : 'title';
    try {
      final match = imdbId.isNotEmpty
          ? await _tmdbMetadataClient.matchByImdbId(
              imdbId: imdbId,
              readAccessToken: token,
              preferSeries: request.preferSeries,
            )
          : await _tmdbMetadataClient.matchTitle(
              query: request.query,
              readAccessToken: token,
              year: request.year,
              preferSeries: request.preferSeries,
            );
      if (match == null) {
        return const _ResolverAttempt.noMatch();
      }
      final result = _mapTmdbMatch(match);
      return _ResolverAttempt.matched(result);
    } catch (error, stackTrace) {
      appLogError('metadata', 'resolver.provider.failed',
          fields: <String, Object?>{
            'provider': MetadataMatchProvider.tmdb.name,
            'mode': mode,
            'query': request.query,
            'imdbId': imdbId,
          },
          error: error,
          stackTrace: stackTrace);
      return _ResolverAttempt.failed(error, stackTrace);
    }
  }

  Future<_ResolverAttempt> _matchWmdbProvider({
    required AppSettings settings,
    required MetadataMatchRequest request,
  }) async {
    if (!settings.wmdbMetadataMatchEnabled) {
      return const _ResolverAttempt.skipped();
    }
    final doubanId = request.doubanId.trim();
    final mode = doubanId.isNotEmpty ? 'doubanId' : 'title';
    try {
      final match = doubanId.isNotEmpty
          ? await _wmdbMetadataClient.matchByDoubanId(doubanId: doubanId)
          : await _wmdbMetadataClient.matchTitle(
              query: request.query,
              year: request.year,
              preferSeries: request.preferSeries,
              actors: request.actors,
            );
      if (match == null) {
        return const _ResolverAttempt.noMatch();
      }
      return _ResolverAttempt.matched(match);
    } catch (error, stackTrace) {
      appLogError('metadata', 'resolver.provider.failed',
          fields: <String, Object?>{
            'provider': MetadataMatchProvider.wmdb.name,
            'mode': mode,
            'query': request.query,
            'doubanId': doubanId,
          },
          error: error,
          stackTrace: stackTrace);
      return _ResolverAttempt.failed(error, stackTrace);
    }
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
              tmdbId: item.tmdbId,
            ),
          )
          .toList(),
      actors: match.actors,
      actorProfiles: match.actorProfiles
          .map(
            (item) => MetadataPersonProfile(
              name: item.name,
              avatarUrl: item.avatarUrl,
              tmdbId: item.tmdbId,
            ),
          )
          .toList(),
      platforms: match.platforms,
      platformProfiles: match.platformProfiles
          .map(
            (item) => MetadataPersonProfile(
              name: item.name,
              avatarUrl: item.avatarUrl,
              tmdbId: item.tmdbId,
            ),
          )
          .toList(),
      ratingLabels: match.ratingLabels,
      imdbId: match.imdbId,
      tmdbId: '${match.tmdbId}',
    );
  }
}

class _ResolverAttempt {
  const _ResolverAttempt._({
    required this.wasAttempted,
    this.result,
    this.error,
    this.stackTrace,
  });

  const _ResolverAttempt.skipped() : this._(wasAttempted: false);

  const _ResolverAttempt.noMatch() : this._(wasAttempted: true);

  const _ResolverAttempt.matched(MetadataMatchResult result)
      : this._(wasAttempted: true, result: result);

  const _ResolverAttempt.failed(Object error, StackTrace stackTrace)
      : this._(
          wasAttempted: true,
          error: error,
          stackTrace: stackTrace,
        );

  final bool wasAttempted;
  final MetadataMatchResult? result;
  final Object? error;
  final StackTrace? stackTrace;
}
