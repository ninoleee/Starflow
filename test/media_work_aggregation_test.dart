import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/application/detail_page_actions.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/library/application/library_cached_items.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/domain/media_work_aggregation.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

MediaItem resource(
  String source, {
  String title = 'A Show',
  String type = 'series',
  int year = 2020,
  String tmdb = '',
  String imdb = '',
  String id = 'same-local-id',
}) =>
    MediaItem(
      id: id,
      title: title,
      overview: '',
      posterUrl: '',
      year: year,
      durationLabel: '',
      genres: const [],
      sourceId: source,
      sourceName: source,
      sourceKind: MediaSourceKind.nas,
      itemType: type,
      streamUrl: type == 'movie' ? 'https://$source/$id' : '',
      streamHeaders: {'Authorization': source},
      actualAddress: '/$source/$id',
      tmdbId: tmdb,
      imdbId: imdb,
      addedAt: DateTime(2026),
    );

void main() {
  test('typed series IDs merge cards but retain independent resource records',
      () {
    final a = resource('a', tmdb: '100');
    final b = resource('b', title: 'Translated', year: 2021, tmdb: '100');
    final cards = aggregateMediaWorks([a, b]);
    expect(cards, hasLength(1));
    expect(cards.single.workResources, [a, b]);
    expect(cards.single.workResources[1], same(b));
    expect(a.workResources, isEmpty);
    expect(cards.single.toJson(), a.toJson());
    expect(MediaItem.fromJson(cards.single.toJson()).workResources, isEmpty);
    expect(aggregateMediaWorks(cards).single.workResources, [a, b]);
  });

  test('IMDb is normalized and ID bridges join previously separate groups', () {
    final a = resource('a', tmdb: '100');
    final b = resource('b', imdb: ' TT100 ');
    final bridge = resource('c', tmdb: '100', imdb: 'tt100');
    final other = resource('d', tmdb: '200', title: 'Other');
    final cards = aggregateMediaWorks([a, other, b, bridge]);
    expect(cards.map((item) => item.sourceId), ['a', 'd']);
    expect(cards.first.workResources, [a, b, bridge]);
  });

  test('fallback needs exact normalized title, same type and known year', () {
    final a = resource('a');
    final b = resource('b', title: ' A.Show ');
    final remake = resource('c', year: 2024);
    final unknown = resource('d', year: 0);
    final movie = resource('e', type: 'movie');
    final cards = aggregateMediaWorks([a, b, remake, unknown, movie]);
    expect(cards, hasLength(4));
    expect(cards.first.workResources, [a, b]);
    expect(aggregateMediaWorks([unknown, unknown.copyWith(sourceId: 'f')]),
        hasLength(2));
  });

  test('known ID conflicts and ambiguous title-only bridges never merge', () {
    final a = resource('a', tmdb: '100');
    final b = resource('b', tmdb: '200');
    final unknown = resource('c');
    for (final items in [
      [unknown, a, b],
      [a, unknown, b],
      [b, a, unknown]
    ]) {
      expect(aggregateMediaWorks(items), hasLength(3));
    }
    expect(
        aggregateMediaWorks([
          a.copyWith(imdbId: 'tt1'),
          b.copyWith(imdbId: 'tt1'),
        ]),
        hasLength(2));
  });

  test('title fallback can attach unidentified resources to one known work',
      () {
    final a = resource('a', tmdb: '100');
    final b = resource('b');
    expect(aggregateMediaWorks([b, a]).single.workResources, [b, a]);
  });

  test('season, episode and unknown IDs are not whole-work identities', () {
    final items = [
      resource('a', tmdb: '100'),
      resource('b', type: 'movie', tmdb: '100'),
      resource('c', type: 'season', tmdb: '100'),
      resource('d', type: 'episode', tmdb: '100'),
      resource('e', type: '', tmdb: '100'),
      resource('f', type: 'episode', tmdb: '100'),
    ];
    expect(aggregateMediaWorks(items), items);
  });

  test('movie editions retain streams, headers, paths and version IDs', () {
    final a = resource('a', type: 'movie', imdb: 'tt1');
    final b = a.copyWith(
        id: 'cut-4k',
        streamUrl: 'https://a/4k',
        preferredMediaSourceId: 'director',
        width: 3840);
    final c = resource('c', type: 'movie', imdb: 'tt1');
    final card = aggregateMediaWorks([a, b, c]).single;
    final target = MediaDetailTarget.fromMediaItem(card);
    expect(target.workResources, hasLength(3));
    expect(target.workResources[1].playbackTarget?.preferredMediaSourceId,
        'director');
    expect(target.workResources[2].playbackTarget?.headers,
        {'Authorization': 'c'});
    expect(target.workResources[2].resourcePath, c.actualAddress);
    expect(
        target.copyWith(title: 'Updated').workResources, target.workResources);
    expect(MediaDetailTarget.fromJson(target.toJson()).workResources, isEmpty);
    expect(
        mergeLibraryItemWithCachedDetails(
                item: card, cachedTarget: target.copyWith(title: 'Updated'))
            .workResources,
        [a, b, c]);
  });

  test('pagination counts works rather than resources', () {
    final cards = aggregateMediaWorks([
      resource('a', tmdb: '1'),
      resource('b', tmdb: '1'),
      resource('c', tmdb: '2'),
      resource('d', tmdb: '3'),
    ]);
    expect(
        visibleLibraryPageItems(items: cards, page: 1, pageSize: 2)
            .single
            .sourceId,
        'd');
  });

  test('detail restore uses fresh membership and remembers selected source',
      () {
    final a = resource('a', tmdb: '1');
    final b = resource('b', tmdb: '1');
    final target =
        MediaDetailTarget.fromMediaItem(aggregateMediaWorks([a, b]).single);
    final stale = MediaDetailTarget.fromMediaItem(resource('stale', tmdb: '2'));
    final plan = DetailCachedStateRestorer().buildPlan(
      pageSeedTarget: target,
      cachedState: CachedDetailState(
          target: target.workResources[1],
          libraryMatchChoices: [stale, target.workResources[1]]),
    );
    expect(plan.libraryMatchChoices.map((item) => item.sourceId), ['a', 'b']);
    expect(plan.manualOverrideTarget?.sourceId, 'b');
    expect(plan.manualOverrideTarget?.itemType, 'series');
    final noCachePlan = DetailCachedStateRestorer().buildPlan(
        pageSeedTarget: target, cachedState: CachedDetailState(target: target));
    expect(noCachePlan.libraryMatchChoices, hasLength(2));
    expect(noCachePlan.selectedLibraryMatchIndex, 0);
  });
}
