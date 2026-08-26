import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/presentation/home_page.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/library/presentation/widgets/library_paged_grid.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  testWidgets('single-item TV Hero moves left back to the menu',
      (tester) async {
    var menuRequestCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_homeSettings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => const HomeResolvedSectionsState(
              sections: [_singleHeroSection],
            ),
          ),
        ],
        child: MaterialApp(
          home: TvMenuButtonScope(
            onMenuButtonPressed: () => menuRequestCount += 1,
            child: const HomePage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    final hero = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:hero-item-1',
      ),
    );
    hero.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(menuRequestCount, 1);
  });

  testWidgets('main library grid can opt out of a second autofocus candidate',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_homeSettings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LibraryPagedGrid(
              pageItems: [_mediaItem],
              totalItems: 1,
              currentPage: 0,
              onPageChanged: (_) {},
              isTelevision: true,
              autofocusFirstItem: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
        tester.widget<MediaPosterTile>(find.byType(MediaPosterTile)).autofocus,
        isFalse);
  });
}

final _homeSettings = SeedData.defaultSettings.copyWith(
  homeModules: const [
    HomeModuleConfig(
      id: HomeModuleConfig.heroModuleId,
      type: HomeModuleType.hero,
      title: 'Hero',
      enabled: true,
    ),
    HomeModuleConfig(
      id: 'test-module',
      type: HomeModuleType.doubanList,
      title: 'Test Module',
      enabled: true,
      doubanListUrl: 'https://example.com/list',
    ),
  ],
  homeHeroBackgroundEnabled: false,
  homeStartupAutoRefreshEnabled: false,
);

const _singleHeroSection = HomeSectionViewModel(
  id: 'hero-source',
  title: 'Hero Source',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'hero-item-1',
      title: 'Single Hero',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Single Hero',
        posterUrl: '',
        overview: '',
        sourceName: 'Test',
      ),
    ),
  ],
);

final _mediaItem = MediaItem(
  id: 'movie-1',
  title: 'Movie',
  overview: '',
  posterUrl: '',
  year: 2026,
  durationLabel: '',
  genres: const [],
  sourceId: 'source-1',
  sourceName: 'Source',
  sourceKind: MediaSourceKind.nas,
  streamUrl: 'https://example.com/movie.mkv',
  addedAt: DateTime(2026),
);
