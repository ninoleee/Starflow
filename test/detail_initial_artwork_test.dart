import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/features/details/application/detail_target_resolver.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/details/presentation/widgets/detail_hero_section.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';

const _seed = MediaDetailTarget(
  title: 'Movie',
  posterUrl: 'https://old.example/poster.jpg',
  backdropUrl: 'https://old.example/backdrop.jpg',
  logoUrl: 'https://old.example/logo.png',
  bannerUrl: 'https://old.example/banner.jpg',
  extraBackdropUrls: ['https://old.example/extra.jpg'],
  overview: '',
  sourceId: 'library',
  itemId: 'movie',
  itemType: 'movie',
);

final _cached = _seed.copyWith(
  posterUrl: 'https://cached.example/poster.jpg',
  backdropUrl: 'https://cached.example/backdrop.jpg',
  backdropHeaders: const {'X-Artwork': 'cached'},
  logoUrl: 'https://cached.example/logo.png',
  bannerUrl: 'https://cached.example/banner.jpg',
  extraBackdropUrls: const ['https://cached.example/extra.jpg'],
);

final _settings = AppSettings.fromJson({
  'mediaSources': const [],
  'searchProviders': const [],
  'homeModules': const [],
  'tmdbMetadataMatchEnabled': false,
  'wmdbMetadataMatchEnabled': false,
  'imdbRatingMatchEnabled': false,
  'detailAutoLibraryMatchEnabled': false,
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'cached artwork keeps URL and headers together without changing identity',
      () {
    final seed = _seed.copyWith(
      posterHeaders: const {'Authorization': 'old'},
      backdropHeaders: const {'Authorization': 'old'},
      logoHeaders: const {'Authorization': 'old'},
      bannerHeaders: const {'Authorization': 'old'},
      extraBackdropHeaders: const {'Authorization': 'old'},
    );
    final merged = mergeCachedDetailArtwork(
      seed,
      _cached.copyWith(sourceId: 'other-library', itemId: 'other-movie'),
    );

    _expectCachedArtwork(merged);
    expect(merged.posterHeaders, isEmpty);
    expect(merged.logoHeaders, isEmpty);
    expect(merged.bannerHeaders, isEmpty);
    expect(merged.extraBackdropHeaders, isEmpty);
    expect(merged.sourceId, seed.sourceId);
    expect(merged.itemId, seed.itemId);
    expect(merged.playbackTarget, seed.playbackTarget);

    final missing = mergeCachedDetailArtwork(
        seed,
        const MediaDetailTarget(
          title: 'Movie',
          posterUrl: '',
          overview: '',
        ));
    expect(missing.posterUrl, seed.posterUrl);
    expect(missing.posterHeaders, seed.posterHeaders);
    expect(missing.backdropUrl, seed.backdropUrl);
    expect(missing.backdropHeaders, seed.backdropHeaders);
    expect(missing.logoUrl, seed.logoUrl);
    expect(missing.logoHeaders, seed.logoHeaders);
    expect(missing.bannerUrl, seed.bannerUrl);
    expect(missing.bannerHeaders, seed.bannerHeaders);
    expect(missing.extraBackdropUrls, seed.extraBackdropUrls);
    expect(missing.extraBackdropHeaders, seed.extraBackdropHeaders);
  });

  for (final television in [false, true]) {
    testWidgets('warm cache supplies first-frame artwork (TV=$television)',
        (tester) async {
      final cache = LocalStorageCacheRepository();
      await cache.saveDetailTargetsBatchInMemory([
        DetailTargetCacheSaveRequest(
            seedTarget: _seed, resolvedTarget: _cached),
      ]);
      await _mount(tester, cache, television: television);

      _expectCachedArtwork(_hero(tester).target);
      _expectNoOldImageRequests(tester);
      await tester.pump(const Duration(milliseconds: 50));
      _expectCachedArtwork(_hero(tester).target);
      await _unmount(tester);
    });

    for (final delay in [Duration.zero, const Duration(milliseconds: 400)]) {
      testWidgets(
          'cold cache displays artwork before enrichment (TV=$television, delay=$delay)',
          (tester) async {
        final pending = Completer<CachedDetailState?>();
        final cache = _ControlledCache(pending.future);
        await _mount(tester, cache, television: television);

        expect(cache.reads, 1);
        final initial = _hero(tester).target;
        expect(initial.posterUrl, isEmpty);
        expect(initial.backdropUrl, isEmpty);
        expect(initial.logoUrl, isEmpty);
        expect(initial.bannerUrl, isEmpty);
        expect(initial.extraBackdropUrls, isEmpty);
        _expectNoOldImageRequests(tester);

        await tester.pump(delay);
        await tester.pump(delay);
        expect(_hero(tester).target.backdropUrl, isEmpty);
        _expectNoOldImageRequests(tester);
        pending.complete(CachedDetailState(target: _cached));
        await tester.pump();
        await tester.pump();
        _expectCachedArtwork(_hero(tester).target);
        _expectNoOldImageRequests(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        _expectCachedArtwork(_hero(tester).target);
        expect(cache.reads, 1);
        await _unmount(tester);
      });
    }
  }

  for (final fail in [false, true]) {
    testWidgets('cache miss/error releases seed artwork (error=$fail)',
        (tester) async {
      final pending = Completer<CachedDetailState?>();
      await _mount(tester, _ControlledCache(pending.future));
      expect(_hero(tester).target.backdropUrl, isEmpty);

      if (fail) {
        pending.completeError(StateError('cache unavailable'));
      } else {
        pending.complete(null);
      }
      await tester.pump();
      expect(_hero(tester).target, same(_seed));
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets('late cache result cannot replace a newer source target',
      (tester) async {
    final pending = Completer<CachedDetailState?>();
    final cache = _ControlledCache(pending.future);
    final target = ValueNotifier(_seed);
    addTearDown(target.dispose);
    await _mount(tester, cache, target: target);
    final newSeed = _seed.copyWith(sourceId: 'new-library');
    final newCached = newSeed.copyWith(
      backdropUrl: 'https://new.example/backdrop.jpg',
    );
    cache.warmState = CachedDetailState(target: newCached);
    target.value = newSeed;
    await tester.pump();
    expect(_hero(tester).target.backdropUrl, newCached.backdropUrl);

    pending.complete(CachedDetailState(target: _cached));
    await tester.pump();
    expect(_hero(tester).target.backdropUrl, newCached.backdropUrl);
    expect(_hero(tester).target.sourceId, 'new-library');
    await _unmount(tester);
  });

  testWidgets('first frame uses the cached choice preferred by entry source',
      (tester) async {
    final preferred = _cached.copyWith(sourceKind: MediaSourceKind.emby);
    final other = preferred.copyWith(
      sourceId: 'other-library',
      itemId: 'other-movie',
      backdropUrl: 'https://other.example/backdrop.jpg',
    );
    final cache = _ControlledCache(Future.value(null))
      ..warmState = CachedDetailState(
        target: other,
        libraryMatchChoices: [other, preferred],
        selectedLibraryMatchIndex: 0,
      );
    await _mount(tester, cache);
    _expectCachedArtwork(_hero(tester).target);
    expect(_hero(tester).target.sourceId, _seed.sourceId);
    expect(cache.reads, 0);
    await _unmount(tester);
  });

  testWidgets('late cache result is ignored after page disposal',
      (tester) async {
    final pending = Completer<CachedDetailState?>();
    await _mount(tester, _ControlledCache(pending.future));
    await _unmount(tester);
    pending.complete(CachedDetailState(target: _cached));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'changing an episode resets initial artwork with the same item id',
      (tester) async {
    final pending = Completer<CachedDetailState?>();
    final cache = _ControlledCache(pending.future);
    final first = _seed.copyWith(
      itemType: 'episode',
      seasonNumber: 1,
      episodeNumber: 1,
    );
    final target = ValueNotifier(first);
    addTearDown(target.dispose);
    await _mount(tester, cache, target: target);
    final second = first.copyWith(episodeNumber: 2);
    final secondCached = second.copyWith(
      backdropUrl: 'https://cached.example/episode-2.jpg',
    );
    cache.warmState = CachedDetailState(target: secondCached);
    target.value = second;
    await tester.pump();
    expect(_hero(tester).target.backdropUrl, secondCached.backdropUrl);

    pending.complete(CachedDetailState(target: first));
    await tester.pump();
    expect(_hero(tester).target.backdropUrl, secondCached.backdropUrl);
    expect(_hero(tester).target.episodeNumber, 2);
    await _unmount(tester);
  });

  test('resolver retains cached artwork when merging the original entry',
      () async {
    final cache = LocalStorageCacheRepository();
    await cache.saveDetailTargetsBatchInMemory([
      DetailTargetCacheSaveRequest(seedTarget: _seed, resolvedTarget: _cached),
    ]);
    final container = ProviderContainer(overrides: [
      appSettingsProvider.overrideWithValue(_settings),
      localStorageCacheRepositoryProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);
    final resolved = await container
        .read(detailTargetResolverProvider)
        .resolveMetadataOnly(target: _seed, backgroundWorkSuspended: false);
    _expectCachedArtwork(resolved);
  });
}

Future<void> _mount(
  WidgetTester tester,
  LocalStorageCacheRepository cache, {
  bool television = true,
  ValueNotifier<MediaDetailTarget>? target,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final enrichment = Completer<MediaDetailTarget>();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      isTelevisionProvider.overrideWith((ref) => television),
      appSettingsProvider.overrideWithValue(_settings),
      localStorageCacheRepositoryProvider.overrideWithValue(cache),
      enrichedDetailTargetProvider
          .overrideWith((ref, seed) => enrichment.future),
    ],
    child: MaterialApp(
      home: target == null
          ? const MediaDetailPage(target: _seed)
          : ValueListenableBuilder<MediaDetailTarget>(
              valueListenable: target,
              builder: (context, seed, _) => MediaDetailPage(target: seed),
            ),
    ),
  ));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

DetailHeroSection _hero(WidgetTester tester) =>
    tester.widget<DetailHeroSection>(find.byType(DetailHeroSection));

void _expectCachedArtwork(MediaDetailTarget target) {
  expect(target.posterUrl, _cached.posterUrl);
  expect(target.backdropUrl, _cached.backdropUrl);
  expect(target.backdropHeaders, _cached.backdropHeaders);
  expect(target.logoUrl, _cached.logoUrl);
  expect(target.bannerUrl, _cached.bannerUrl);
  expect(target.extraBackdropUrls, _cached.extraBackdropUrls);
}

void _expectNoOldImageRequests(WidgetTester tester) {
  final urls = tester
      .widgetList<AppNetworkImage>(find.byType(AppNetworkImage))
      .expand(
          (image) => [image.url, ...image.fallbackSources.map((s) => s.url)]);
  expect(urls.where((url) => url.contains('old.example')), isEmpty);
}

class _ControlledCache extends LocalStorageCacheRepository {
  _ControlledCache(this.pending);

  final Future<CachedDetailState?> pending;
  CachedDetailState? warmState;
  int reads = 0;

  @override
  CachedDetailState? peekDetailState(MediaDetailTarget seedTarget,
          {bool allowStructuralMismatch = false}) =>
      warmState;

  @override
  Future<CachedDetailState?> loadDetailState(MediaDetailTarget seedTarget,
      {bool allowStructuralMismatch = false}) {
    reads += 1;
    return pending;
  }
}
