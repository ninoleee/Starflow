import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/storage/app_preferences_store.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/search/application/search_favorite_metadata_service.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/presentation/search_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _settings = AppSettings(
  mediaSources: [],
  searchProviders: [],
  doubanAccount: DoubanAccountConfig(enabled: false),
  homeModules: [],
);
const _favorite = SearchResult(
  id: 'favorite',
  title: 'Saved title',
  posterUrl: '',
  providerId: 'provider',
  providerName: 'Provider',
  quality: '',
  sizeLabel: '',
  seeders: 0,
  summary: '',
  resourceUrl: 'https://example.com/resource',
  favoriteFolderName: 'Saved folder',
  tmdbId: '123',
);
const _match = MetadataMatchResult(
  provider: MetadataMatchProvider.tmdb,
  title: 'Matched title',
  tmdbId: '123',
  posterUrl: 'https://example.com/poster.jpg',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('backfills existing TMDB favorite without altering saved metadata',
      () async {
    var calls = 0;
    final service = SearchFavoriteMetadataService(
      resolveMatch: ({required settings, required request}) async {
        calls++;
        expect(request.query, 'Saved folder');
        return _match;
      },
    );
    final result = await service.enrichPoster(
      result: _favorite,
      settings: _settings,
    );
    expect(result.toJson(), {
      ..._favorite.toJson(),
      'posterUrl': _match.posterUrl,
    });
    await service.enrichPoster(result: result, settings: _settings);
    expect(calls, 1);
  });

  test('preserves existing poster and authentication headers', () async {
    final original = _favorite.copyWith(
      posterUrl: 'https://example.com/auth.jpg',
      posterHeaders: const {'Authorization': 'Bearer test'},
    );
    final service = SearchFavoriteMetadataService(
      resolveMatch: ({required settings, required request}) async {
        fail('Existing poster must not trigger matching');
      },
    );
    final result = await service.enrichPoster(
      result: original,
      settings: _settings,
    );
    expect(result.toJson(), original.toJson());
    expect(SearchResult.fromJson(result.toJson()).posterHeaders,
        original.posterHeaders);
  });

  test('reuses detail poster with headers without matching', () async {
    final original = _favorite.copyWith(
      detailTarget: const MediaDetailTarget(
        title: 'Detail',
        posterUrl: 'https://example.com/detail.jpg',
        posterHeaders: {'Authorization': 'Bearer detail'},
        overview: '',
      ),
    );
    final service = SearchFavoriteMetadataService(
      resolveMatch: ({required settings, required request}) async {
        fail('Detail artwork must not trigger matching');
      },
    );
    final result = await service.enrichPoster(
      result: original,
      settings: _settings,
    );
    expect(result.posterUrl, original.detailTarget!.posterUrl);
    expect(result.posterHeaders, original.detailTarget!.posterHeaders);
  });

  for (final fails in [false, true]) {
    test('keeps original favorite when matching fails: $fails', () async {
      final service = SearchFavoriteMetadataService(
        resolveMatch: ({required settings, required request}) async {
          if (fails) throw StateError('offline');
          return null;
        },
      );
      final result = await service.enrichPoster(
        result: _favorite,
        settings: _settings,
      );
      expect(result.toJson(), _favorite.toJson());
    });
  }

  test('rejects artwork matched to a conflicting TMDB identity', () async {
    final service = SearchFavoriteMetadataService(
      resolveMatch: ({required settings, required request}) async => _match,
    );
    final result = await service.enrichPoster(
      result: _favorite.copyWith(tmdbId: '456'),
      settings: _settings,
    );
    expect(result.posterUrl, isEmpty);
    expect(result.tmdbId, '456');
  });

  test('poster persistence merges current fields and cannot restore removal',
      () async {
    final repository = await _repository();
    await repository.saveFavoriteResults([_favorite]);
    final enriched = _favorite.copyWith(posterUrl: _match.posterUrl);
    final rename = repository.saveFavoriteResults([
      _favorite.copyWith(title: 'New name'),
    ]);
    final update = repository.updateFavoritePoster(enriched);
    await Future.wait([rename, update]);
    final saved = (await repository.loadFavoriteResults()).single;
    expect(saved.title, 'New name');
    expect(saved.posterUrl, _match.posterUrl);
    final remove = repository.saveFavoriteResults([]);
    final lateUpdate = repository.updateFavoritePoster(enriched);
    await Future.wait([remove, lateUpdate]);
    expect(await repository.loadFavoriteResults(), isEmpty);
  });

  for (final isTelevision in [false, true]) {
    testWidgets('favorites page backfills and persists (TV: $isTelevision)',
        (tester) async {
      final repository = await _repository();
      await repository.saveFavoriteResults([_favorite]);
      var calls = 0;
      final pending = Completer<MetadataMatchResult?>();
      final service = SearchFavoriteMetadataService(
        resolveMatch: ({required settings, required request}) {
          calls++;
          return pending.future;
        },
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => isTelevision),
          appSettingsProvider.overrideWithValue(_settings),
          searchPreferencesRepositoryProvider.overrideWithValue(repository),
          searchFavoriteMetadataServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: SearchPage(favoritesOnly: true)),
      ));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Saved title'), findsWidgets);
      pending.complete(_match);
      await tester.pumpAndSettle();
      expect((await repository.loadFavoriteResults()).single.posterUrl,
          _match.posterUrl);
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('inactive page stops its queue and retries on return',
      (tester) async {
    final repository = await _repository();
    await repository.saveFavoriteResults([
      _favorite,
      SearchResult.fromJson({
        ..._favorite.toJson(),
        'id': 'second',
        'resourceUrl': 'https://example.com/second',
      }),
    ]);
    var calls = 0;
    final pending = Completer<MetadataMatchResult?>();
    final active = ValueNotifier(true);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => false),
        appSettingsProvider.overrideWithValue(_settings),
        searchPreferencesRepositoryProvider.overrideWithValue(repository),
        searchFavoriteMetadataServiceProvider.overrideWithValue(
          SearchFavoriteMetadataService(
            resolveMatch: ({required settings, required request}) {
              calls++;
              return calls == 1 ? pending.future : Future.value(null);
            },
          ),
        ),
      ],
      child: MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, enabled, child) => TickerMode(
            enabled: enabled,
            child: child!,
          ),
          child: const SearchPage(favoritesOnly: true),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(calls, 1);
    active.value = false;
    await tester.pumpAndSettle();
    pending.complete(_match);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect((await repository.loadFavoriteResults()).first.posterUrl, isEmpty);
    active.value = true;
    await tester.pumpAndSettle();
    expect(calls, 3);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    active.dispose();
  });

  testWidgets('unfavoriting while artwork is pending does not restore it',
      (tester) async {
    final repository = await _repository();
    await repository.saveFavoriteResults([_favorite]);
    final pending = Completer<MetadataMatchResult?>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => false),
        appSettingsProvider.overrideWithValue(_settings),
        searchPreferencesRepositoryProvider.overrideWithValue(repository),
        searchFavoriteMetadataServiceProvider.overrideWithValue(
          SearchFavoriteMetadataService(
            resolveMatch: ({required settings, required request}) =>
                pending.future,
          ),
        ),
      ],
      child: const MaterialApp(home: SearchPage(favoritesOnly: true)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();
    pending.complete(_match);
    await tester.pumpAndSettle();
    expect(await repository.loadFavoriteResults(), isEmpty);
    expect(find.text('Saved title'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposed favorites page ignores pending artwork',
      (tester) async {
    final repository = await _repository();
    await repository.saveFavoriteResults([_favorite]);
    final pending = Completer<MetadataMatchResult?>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWith((ref) => false),
        appSettingsProvider.overrideWithValue(_settings),
        searchPreferencesRepositoryProvider.overrideWithValue(repository),
        searchFavoriteMetadataServiceProvider.overrideWithValue(
          SearchFavoriteMetadataService(
            resolveMatch: ({required settings, required request}) =>
                pending.future,
          ),
        ),
      ],
      child: const MaterialApp(home: SearchPage(favoritesOnly: true)),
    ));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_match);
    await tester.pumpAndSettle();
    expect((await repository.loadFavoriteResults()).single.posterUrl, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<SearchPreferencesRepository> _repository() async {
  SharedPreferences.setMockInitialValues({});
  return SearchPreferencesRepository(
    preferences: AppPreferencesStore(
      sharedPreferences: await SharedPreferences.getInstance(),
    ),
  );
}
