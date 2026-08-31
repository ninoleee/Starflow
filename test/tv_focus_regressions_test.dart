import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';
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

  testWidgets('home content completion recovers only a missing TV focus',
      (tester) async {
    final pendingProvider = StateProvider<bool>((ref) => true);
    var menuRequestCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            _homeSettings,
          ),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              hasPendingSections: ref.watch(pendingProvider),
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
    await tester.pump();
    menuRequestCount = 0;
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(pendingProvider.notifier).state = false;
    await tester.pump();
    await tester.pump();

    expect(menuRequestCount, 1);
  });

  testWidgets('home content completion keeps an existing actionable focus',
      (tester) async {
    final pendingProvider = StateProvider<bool>((ref) => true);
    final existingFocusNode = FocusNode(debugLabel: 'existing-action');
    addTearDown(existingFocusNode.dispose);
    var menuRequestCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_homeSettings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              hasPendingSections: ref.watch(pendingProvider),
            ),
          ),
        ],
        child: MaterialApp(
          home: TvMenuButtonScope(
            onMenuButtonPressed: () => menuRequestCount += 1,
            child: Column(
              children: [
                Focus(
                  focusNode: existingFocusNode,
                  child: const SizedBox(width: 1, height: 1),
                ),
                const Expanded(child: HomePage()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    existingFocusNode.requestFocus();
    await tester.pump();
    menuRequestCount = 0;

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(pendingProvider.notifier).state = false;
    await tester.pump();
    await tester.pump();

    expect(existingFocusNode.hasPrimaryFocus, isTrue);
    expect(menuRequestCount, 0);
  });

  testWidgets('home restores first content focus after editor route closes',
      (tester) async {
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
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return moduleId == 'test-module' ? _singleHeroSection : null;
          }),
        ],
        child: const MaterialApp(
          home: TvMenuButtonScope(
            onMenuButtonPressed: _noop,
            child: HomePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final homeContext = tester.element(find.byType(HomePage));
    Navigator.of(homeContext).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const _FocusedEditorRoute(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'test-home-editor-focus',
    );

    Navigator.of(tester.element(find.byType(_FocusedEditorRoute))).pop();
    await tester.pumpAndSettle();

    final restoredFocus = FocusManager.instance.primaryFocus;
    expect(restoredFocus, isNotNull);
    expect(restoredFocus?.debugLabel, isNot('test-home-editor-focus'));
    expect(restoredFocus?.context, isNotNull);
    expect(
      ModalRoute.of(restoredFocus!.context!),
      same(ModalRoute.of(homeContext)),
    );
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

void _noop() {}

class _FocusedEditorRoute extends ConsumerStatefulWidget {
  const _FocusedEditorRoute();

  @override
  ConsumerState<_FocusedEditorRoute> createState() =>
      _FocusedEditorRouteState();
}

class _FocusedEditorRouteState extends ConsumerState<_FocusedEditorRoute> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'test-home-editor-focus');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(homeNavigationResetRevisionProvider.notifier).state += 1;
        }
      },
      child: Scaffold(
        body: Center(
          child: Focus(
            autofocus: true,
            focusNode: _focusNode,
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      ),
    );
  }
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
