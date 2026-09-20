import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/application/detail_library_match_service.dart';
import 'package:starflow/features/details/application/detail_online_resource_update_service.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_title_matcher.dart';
import 'package:starflow/features/library/domain/tmdb_media_identity.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/search/domain/search_models.dart';

void main() {
  const service = DetailLibraryMatchService();
  const target = MediaDetailTarget(
      title: 'Probe',
      posterUrl: '',
      overview: '',
      itemType: 'movie',
      tmdbId: '123',
      year: 1999);

  for (final type in ['tv', 'series', 'season', 'episode', 'show']) {
    test('movie rejects $type collision even with matching title/IMDb', () {
      final candidates = service.buildManualMatchCandidates(
        target: target.copyWith(imdbId: 'tt123'),
        items: [_item(type, title: 'Probe').copyWith(imdbId: 'tt123')],
        titles: ['Probe'],
        year: 1999,
      );
      expect(candidates, isEmpty);
    });
  }

  test('TV rejects movie numeric collision', () {
    expect(
        service.buildManualMatchCandidates(
          target: target.copyWith(itemType: 'series'),
          items: [_item('movie')],
          titles: ['Probe'],
          year: 1999,
        ),
        isEmpty);
  });

  test('typed match retains exact ID and reason despite different title', () {
    final matches = service.buildManualMatchCandidates(
        target: target, items: [_item('movie')], titles: ['Probe'], year: 1999);
    expect(matches.single.score, 1e9);
    expect(matches.single.matchReason, contains('TMDB ID'));
    expect(
        matchMediaItemByExternalIds([_item('tv'), _item('movie')],
                tmdbId: '123', tmdbMediaType: TmdbMediaType.movie)
            ?.itemType,
        'movie');
  });

  for (final type in TmdbMediaType.values) {
    test('$type filters every external ID path but keeps unknown types', () {
      final items = [
        for (final itemType in ['movie', 'tv', ''])
          _item(itemType).copyWith(
            doubanId: '123',
            imdbId: 'tt123',
            tvdbId: '123',
            wikidataId: 'Q123',
          ),
      ];
      final paths = [
        listMediaItemsMatchingExternalIds(items,
            tmdbMediaType: type, doubanId: '123'),
        listMediaItemsMatchingExternalIds(items,
            tmdbMediaType: type, imdbId: 'tt123'),
        listMediaItemsMatchingExternalIds(items,
            tmdbMediaType: type, tvdbId: '123'),
        listMediaItemsMatchingExternalIds(items,
            tmdbMediaType: type, wikidataId: 'Q123'),
      ];
      for (final matches in paths) {
        expect(matches.map((item) => item.itemType), [type.name, '']);
      }
      expect(
          listMediaItemsMatchingExternalIds(items,
                  tmdbMediaType: type, tmdbId: '123')
              .map((item) => item.itemType),
          [type.name]);
    });
  }

  for (final type in ['', 'video', 'unknown']) {
    test('legacy $type type falls back to titles, not a bare TMDB ID', () {
      final legacy = _item(type, title: 'Probe');
      final matches = service.buildManualMatchCandidates(
          target: target, items: [legacy], titles: ['Probe'], year: 1999);
      expect(matches.single.score, lessThan(1e9));
      expect(matches.single.matchReason, isNot(contains('TMDB')));
      expect(
          service.buildManualMatchCandidates(
              target: target,
              items: [_item(type)],
              titles: ['Probe'],
              year: 1999),
          isEmpty);
      expect(matchMediaItemByExternalIds([legacy], tmdbId: '123'), isNull);
      expect(
          matchMediaItemByExternalIds([legacy.copyWith(imdbId: 'tt123')],
              tmdbId: '123', imdbId: 'tt123'),
          isNotNull);
      expect(MediaItem.fromJson(legacy.toJson()).itemType, type);
    });
  }

  test('metadata fallback carries its own type; cannot type an existing ID',
      () {
    const metadata = MetadataMatchResult(
        provider: MetadataMatchProvider.tmdb,
        title: 'Probe',
        tmdbId: '123',
        mediaType: MetadataMediaType.movie);
    final legacyTarget = target.copyWith(itemType: '');
    expect(
        service.buildManualMatchCandidates(
            target: legacyTarget,
            metadataMatch: metadata,
            items: [_item('movie')],
            titles: ['Probe'],
            year: 1999),
        isEmpty);
    final matches = service.buildManualMatchCandidates(
        target: legacyTarget.copyWith(tmdbId: ''),
        metadataMatch: metadata,
        items: [_item('movie')],
        titles: ['Probe'],
        year: 1999);
    expect(matches.single.score, 1e9);
  });

  test(
      'online favorites use typed TMDB, unknown favorites retain title fallback',
      () {
    const updates = DetailOnlineResourceUpdateService();
    SearchResult favorite(String type, String title) => SearchResult(
          id: type,
          title: title,
          posterUrl: '',
          providerId: 'p',
          providerName: '',
          quality: '',
          sizeLabel: '',
          seeders: 0,
          summary: '',
          resourceUrl: 'https://pan.quark.cn/s/probe',
          tmdbId: '123',
          metadataMediaType: type,
        );
    expect(
        updates.resolveFavoriteMatches(
            target: target,
            favorites: [favorite('tv', 'Probe'), favorite('', 'Unrelated')]),
        isEmpty);
    final typed = updates.resolveFavoriteMatches(
        target: target, favorites: [favorite('movie', 'Unrelated')]);
    expect(typed.single.score, 400);
    final legacy = updates.resolveFavoriteMatches(
        target: target, favorites: [favorite('', 'Probe')]);
    expect(legacy.single.score, lessThan(400));
  });
}

MediaItem _item(String type, {String title = 'Unrelated'}) => MediaItem(
      id: type,
      title: title,
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '',
      genres: const [],
      sourceId: 's',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      streamUrl: '',
      itemType: type,
      tmdbId: '123',
      addedAt: DateTime.utc(2026, 9, 20),
    );
