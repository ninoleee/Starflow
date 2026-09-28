import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/discovery/domain/douban_browse_models.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';

void main() {
  test('movie, series and variety filters are saved independently and cleared',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SearchPreferencesRepository();
    addTearDown(repository.dispose);
    await repository.saveBrowseQuery(const DoubanBrowseQuery(
        year: 2023, region: '美国', sort: DoubanBrowseSort.rating));
    await repository.saveBrowseQuery(const DoubanBrowseQuery(
        category: DoubanBrowseCategory.series,
        year: 2020,
        genre: '悬疑',
        minRating: 8,
        minRatingCount: 30000));
    await repository.saveBrowseQuery(const DoubanBrowseQuery(
        category: DoubanBrowseCategory.variety, genre: '真人秀'));
    await repository.saveBrowseMode(true);
    await repository.saveBrowseType(DoubanBrowseCategory.variety);
    expect(await repository.loadBrowseMode(), true);
    expect(await repository.loadBrowseType(), DoubanBrowseCategory.variety);
    final movie = await repository.loadBrowseQuery(DoubanBrowseCategory.movie);
    final tv = await repository.loadBrowseQuery(DoubanBrowseCategory.series);
    final variety =
        await repository.loadBrowseQuery(DoubanBrowseCategory.variety);
    expect(movie.year, 2023);
    expect(movie.region, '美国');
    expect(tv.year, 2020);
    expect(tv.genre, '悬疑');
    expect(tv.minRating, 8);
    expect(tv.minRatingCount, 30000);
    expect(variety.genre, '真人秀');
    final summary = await repository.inspectSummary();
    expect(summary.totalBytes, greaterThan(0));
    await repository.clear();
    expect(await repository.loadBrowseMode(), false);
    expect(await repository.loadBrowseType(), DoubanBrowseCategory.movie);
    expect((await repository.loadBrowseQuery(DoubanBrowseCategory.series)).year,
        null);
  });

  test('old tv filters load as series without leaking into variety', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppPreferencesStore();
    await store.setString(
        SearchPreferencesRepository.browseTypePreferenceKey, 'tv');
    await store.setString(
        SearchPreferencesRepository.browseFiltersPreferenceKey,
        '{"tv":{"type":"tv","genre":"悬疑","rating":8,"sort":"S"}}');
    final repository = SearchPreferencesRepository(preferences: store);
    addTearDown(repository.dispose);
    expect(await repository.loadBrowseType(), DoubanBrowseCategory.series);
    expect(
        (await repository.loadBrowseQuery(DoubanBrowseCategory.series)).genre,
        '悬疑');
    expect(
        (await repository.loadBrowseQuery(DoubanBrowseCategory.variety)).genre,
        isEmpty);
  });
}
