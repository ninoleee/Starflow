import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starflow/features/details/application/detail_enrichment_settings.dart';
import 'package:starflow/features/details/application/detail_metadata_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/data/douban_api_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';

void main() {
  const target = MediaDetailTarget(title: 'Movie', posterUrl: '', overview: '');
  DetailEnrichmentSettings settings({bool wmdb = true, bool tmdb = true}) =>
      DetailEnrichmentSettings(
        mediaSources: const [],
        quarkCookie: '',
        wmdbMetadataMatchEnabled: wmdb,
        tmdbMetadataMatchEnabled: tmdb,
        tmdbReadAccessToken: 'token',
        imdbRatingMatchEnabled: false,
      );

  Future<DetailMetadataResult> resolve({
    required _Wmdb wmdb,
    required _Tmdb tmdb,
    DetailEnrichmentSettings? config,
    MediaDetailTarget seed = target,
    bool force = false,
  }) =>
      resolveDetailMetadata(
        settings: config ?? settings(),
        target: seed,
        wmdbMetadataClient: wmdb,
        tmdbMetadataClient: tmdb,
        traceKey: 'test',
        forceSearch: force,
        forceReplace: force,
      );

  test('disabled providers are skipped without calls', () async {
    final wmdb = _Wmdb();
    final tmdb = _Tmdb();
    final result = await resolve(
        wmdb: wmdb, tmdb: tmdb, config: settings(wmdb: false, tmdb: false));
    expect(result.outcome, DetailMetadataOutcome.skipped);
    expect(wmdb.calls + tmdb.calls, 0);
  });

  test('no match is distinct from failed requests', () async {
    final result = await resolve(wmdb: _Wmdb(), tmdb: _Tmdb());
    expect(result.outcome, DetailMetadataOutcome.noMatch);
    expect(result.hasFailure, isFalse);
    final failure =
        await resolve(wmdb: _Wmdb(fail: true), tmdb: _Tmdb(fail: true));
    expect(failure.outcome, DetailMetadataOutcome.failed);
    expect(failure.target.title, target.title);
  });

  test('partial failure keeps metadata supplied by the working provider',
      () async {
    final result = await resolve(
      wmdb: _Wmdb(
          match: const MetadataMatchResult(
        provider: MetadataMatchProvider.wmdb,
        title: 'Movie',
        overview: 'Resolved overview',
        ratingLabels: ['IMDb 8.6'],
      )),
      tmdb: _Tmdb(fail: true),
    );
    expect(result.outcome, DetailMetadataOutcome.partialFailure);
    expect(result.target.overview, 'Resolved overview');
    expect(result.target.ratingLabels, ['IMDb 8.6']);
  });

  test('background fills gaps but forced refresh replaces existing artwork',
      () async {
    const match = MetadataMatchResult(
      provider: MetadataMatchProvider.wmdb,
      title: 'Movie',
      posterUrl: 'https://new.test/poster',
      overview: 'New overview',
      ratingLabels: ['IMDb 8.6'],
    );
    final seed = target.copyWith(
        posterUrl: 'https://old.test/poster',
        overview: 'Existing overview',
        ratingLabels: ['IMDb 0']);
    final background = await resolve(
        wmdb: _Wmdb(match: match),
        tmdb: _Tmdb(),
        config: settings(tmdb: false),
        seed: seed);
    expect(background.outcome, DetailMetadataOutcome.succeeded);
    expect(background.target.posterUrl, seed.posterUrl);
    expect(background.target.ratingLabels, ['IMDb 8.6']);
    final forced = await resolve(
        wmdb: _Wmdb(match: match),
        tmdb: _Tmdb(),
        config: settings(tmdb: false),
        seed: seed,
        force: true);
    expect(forced.target.posterUrl, match.posterUrl);
    expect(forced.target.overview, match.overview);
  });

  test('NAS background enrichment remains index-owned', () async {
    final wmdb = _Wmdb();
    final seed =
        target.copyWith(sourceId: 'nas', sourceKind: MediaSourceKind.nas);
    final result = await resolve(
        wmdb: wmdb, tmdb: _Tmdb(), config: settings(tmdb: false), seed: seed);
    expect(result.outcome, DetailMetadataOutcome.skipped);
    expect(wmdb.calls, 0);
    await resolve(
        wmdb: wmdb,
        tmdb: _Tmdb(),
        config: settings(tmdb: false),
        seed: seed,
        force: true);
    expect(wmdb.calls, 1);
  });

  test('rating request failure retains a successful metadata match', () async {
    final result = await resolveDetailMetadata(
      settings: settings(tmdb: false),
      target: target,
      wmdbMetadataClient: _Wmdb(
        match: const MetadataMatchResult(
          provider: MetadataMatchProvider.wmdb,
          title: 'Movie',
          doubanId: '123',
          overview: 'Resolved overview',
        ),
      ),
      tmdbMetadataClient: _Tmdb(),
      doubanApiClient:
          DoubanApiClient(MockClient((_) async => http.Response('', 403))),
      traceKey: 'test',
    );
    expect(result.outcome, DetailMetadataOutcome.partialFailure);
    expect(result.target.overview, 'Resolved overview');
    expect(result.target.doubanId, '123');
  });

  test('forced metadata never overwrites episode structure or overview',
      () async {
    final seed = target.copyWith(
        itemType: 'episode',
        seasonNumber: 1,
        episodeNumber: 2,
        overview: 'Episode overview');
    final result = await resolve(
        wmdb: _Wmdb(
            match: const MetadataMatchResult(
          provider: MetadataMatchProvider.wmdb,
          title: 'Series',
          mediaType: MetadataMediaType.series,
          overview: 'Series overview',
        )),
        tmdb: _Tmdb(),
        config: settings(tmdb: false),
        seed: seed,
        force: true);
    expect(result.target.itemType, 'episode');
    expect(result.target.overview, seed.overview);
    expect(result.target.episodeNumber, 2);
  });

  for (final stillFails in [false, true]) {
    test('TMDB episode artwork preserves series fallback: $stillFails',
        () async {
      final tmdb = _Tmdb(match: _seriesMatch, stillFails: stillFails);
      final result = await resolve(
        wmdb: _Wmdb(),
        tmdb: tmdb,
        config: settings(wmdb: false),
        seed: target.copyWith(
          itemType: 'episode',
          seasonNumber: 1,
          episodeNumber: 2,
          overview: 'Episode overview',
        ),
        force: true,
      );
      expect(result.outcome, DetailMetadataOutcome.succeeded);
      expect(tmdb.stillCalls, 1);
      expect(result.target.tmdbId, '123');
      expect(result.target.itemType, 'episode');
      expect(result.target.overview, 'Episode overview');
      expect(result.target.posterUrl, _seriesMatch.posterUrl);
      expect(result.target.backdropUrl,
          stillFails ? _seriesMatch.backdropUrl : 'https://tmdb.test/still');
      expect(result.target.bannerUrl,
          stillFails ? isEmpty : _seriesMatch.backdropUrl);
      expect(result.target.extraBackdropUrls, [
        if (!stillFails) _seriesMatch.backdropUrl,
        'https://tmdb.test/extra',
      ]);
    });
  }
}

const _seriesMatch = TmdbMetadataMatch(
  tmdbId: 123,
  isSeries: true,
  title: 'Series',
  originalTitle: '',
  posterUrl: 'https://tmdb.test/poster',
  backdropUrl: 'https://tmdb.test/series',
  logoUrl: '',
  extraBackdropUrls: ['https://tmdb.test/series', 'https://tmdb.test/extra'],
  overview: 'Series overview',
  year: 2026,
  durationLabel: '',
  genres: [],
  directors: [],
  directorProfiles: [],
  actors: [],
  actorProfiles: [],
  platforms: [],
  platformProfiles: [],
  ratingLabels: [],
  imdbId: '',
);

class _Wmdb extends WmdbMetadataClient {
  _Wmdb({this.fail = false, this.match})
      : super(MockClient((_) async => http.Response('', 500)));
  final bool fail;
  final MetadataMatchResult? match;
  int calls = 0;
  @override
  Future<MetadataMatchResult?> matchTitle(
      {required String query,
      int year = 0,
      bool preferSeries = false,
      List<String> actors = const []}) async {
    calls++;
    if (fail) throw StateError('WMDB unavailable');
    return match;
  }
}

class _Tmdb extends TmdbMetadataClient {
  _Tmdb({this.fail = false, this.match, this.stillFails = false})
      : super(MockClient((_) async => http.Response('', 500)));
  final bool fail;
  final TmdbMetadataMatch? match;
  final bool stillFails;
  int calls = 0;
  int stillCalls = 0;
  @override
  Future<TmdbMetadataMatch?> matchTitle(
      {required String query,
      required String readAccessToken,
      int year = 0,
      bool preferSeries = false}) async {
    calls++;
    if (fail) throw StateError('TMDB unavailable');
    return match;
  }

  @override
  Future<String> fetchEpisodeStillUrl({
    required int seriesId,
    required int seasonNumber,
    required int episodeNumber,
    required String readAccessToken,
  }) async {
    stillCalls++;
    expect(seriesId, 123);
    expect(seasonNumber, 1);
    expect(episodeNumber, 2);
    if (stillFails) throw StateError('Episode artwork unavailable');
    return 'https://tmdb.test/still';
  }
}
