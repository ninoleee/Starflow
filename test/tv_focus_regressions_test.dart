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

  testWidgets('multi-item Hero skips disabled previous control on first page',
      (tester) async {
    var menuRequestCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_homeSettings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => const HomeResolvedSectionsState(
              sections: [_multiHeroSection],
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
    await tester.pumpAndSettle();

    final firstHero = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:multi-hero-1',
      ),
    );
    firstHero.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(menuRequestCount, 1);
    final previousPager = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:pager-prev',
      ),
    );
    expect(previousPager.focusNode?.hasFocus, isFalse);
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

    expect(menuRequestCount, 0);
    final editAction = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction && widget.focusId == 'home:edit',
      ),
    );
    expect(editAction.focusNode?.hasPrimaryFocus, isTrue);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

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

  testWidgets('home restores focus after a regular child route closes',
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
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final homeContext = tester.element(find.byType(HomePage));
    Navigator.of(homeContext).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const _FocusedChildRoute(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'test-home-child-focus',
    );

    Navigator.of(tester.element(find.byType(_FocusedChildRoute))).pop();
    await tester.pumpAndSettle();

    final restoredFocus = FocusManager.instance.primaryFocus;
    expect(restoredFocus, isNotNull);
    expect(restoredFocus?.debugLabel, isNot('test-home-child-focus'));
    expect(restoredFocus?.context, isNotNull);
    expect(
      ModalRoute.of(restoredFocus!.context!),
      same(ModalRoute.of(homeContext)),
    );
  });

  testWidgets('home skips an empty first module for initial TV focus',
      (tester) async {
    const emptySection = HomeSectionViewModel(
      id: 'empty-module',
      title: 'Empty',
      subtitle: '',
      emptyMessage: '无',
      layout: HomeSectionLayout.posterRail,
    );
    const contentSection = HomeSectionViewModel(
      id: 'content-module',
      title: 'Content',
      subtitle: '',
      emptyMessage: '',
      layout: HomeSectionLayout.posterRail,
      items: [
        HomeCardViewModel(
          id: 'content-item',
          title: 'Focusable Content',
          subtitle: '',
          posterUrl: '',
          detailTarget: MediaDetailTarget(
            title: 'Focusable Content',
            posterUrl: '',
            overview: '',
          ),
        ),
      ],
    );
    final settings = SeedData.defaultSettings.copyWith(
      homeModules: const [
        HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: false,
        ),
        HomeModuleConfig(
          id: 'empty-module',
          type: HomeModuleType.recentlyAdded,
          title: 'Empty',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'content-module',
          type: HomeModuleType.doubanList,
          title: 'Content',
          enabled: true,
          doubanListUrl: 'https://example.com/content',
        ),
      ],
      homeStartupAutoRefreshEnabled: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(settings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => const HomeResolvedSectionsState(
              sections: [emptySection, contentSection],
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return switch (moduleId) {
              'empty-module' => emptySection,
              'content-module' => contentSection,
              _ => null,
            };
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final contentTile = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile &&
            widget.focusId ==
                'home:section:content-module:item:Focusable Content',
      ),
    );
    expect(contentTile.autofocus, isTrue);
    expect(contentTile.focusNode?.hasPrimaryFocus, isTrue);
  });

  testWidgets('Hero is the only autofocus target when Hero is visible',
      (tester) async {
    const section = HomeSectionViewModel(
      id: 'test-module',
      title: 'Test Module',
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
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_homeSettings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => const HomeResolvedSectionsState(sections: [section]),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return moduleId == 'test-module' ? section : null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final hero = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:hero-item-1',
      ),
    );
    final regularTile = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile &&
            widget.focusId == 'home:section:test-module:item:Single Hero',
      ),
    );
    expect(hero.autofocus, isTrue);
    expect(regularTile.autofocus, isFalse);
  });

  testWidgets('late first-module content does not steal existing Home focus',
      (tester) async {
    final sectionsProvider = StateProvider<List<HomeSectionViewModel>>(
      (ref) => const [_emptyFirstSection, _secondContentSection],
    );
    final settings = SeedData.defaultSettings.copyWith(
      homeModules: const [
        HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: false,
        ),
        HomeModuleConfig(
          id: 'first-module',
          type: HomeModuleType.recentlyAdded,
          title: 'First',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'second-module',
          type: HomeModuleType.doubanList,
          title: 'Second',
          enabled: true,
          doubanListUrl: 'https://example.com/second',
        ),
      ],
      homeStartupAutoRefreshEnabled: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(settings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              sections: ref.watch(sectionsProvider),
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            for (final section in ref.watch(sectionsProvider)) {
              if (section.id == moduleId) {
                return section;
              }
            }
            return null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final secondTile = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile &&
            widget.focusId == 'home:section:second-module:item:Second Content',
      ),
    );
    secondTile.focusNode!.requestFocus();
    await tester.pump();
    expect(secondTile.focusNode?.hasPrimaryFocus, isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(sectionsProvider.notifier).state = const [
      _firstContentSection,
      _secondContentSection,
    ];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(secondTile.focusNode?.hasPrimaryFocus, isTrue);
    final firstTile = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile &&
            widget.focusId == 'home:section:first-module:item:First Content',
      ),
    );
    expect(firstTile.autofocus, isFalse);
  });

  testWidgets('Home recovers when the focused poster is removed',
      (tester) async {
    final sectionsProvider = StateProvider<List<HomeSectionViewModel>>(
      (ref) => const [_twoItemSection],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              homeModules: const [
                HomeModuleConfig(
                  id: HomeModuleConfig.heroModuleId,
                  type: HomeModuleType.hero,
                  title: 'Hero',
                  enabled: false,
                ),
                HomeModuleConfig(
                  id: 'changing-module',
                  type: HomeModuleType.doubanList,
                  title: 'Changing',
                  enabled: true,
                  doubanListUrl: 'https://example.com/changing',
                ),
              ],
              homeStartupAutoRefreshEnabled: false,
            ),
          ),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              sections: ref.watch(sectionsProvider),
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return moduleId == 'changing-module'
                ? ref.watch(sectionsProvider).single
                : null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final removedTile = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile &&
            widget.focusId == 'home:section:changing-module:item:Removed',
      ),
    );
    removedTile.focusNode!.requestFocus();
    await tester.pump();
    expect(removedTile.focusNode?.hasPrimaryFocus, isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(sectionsProvider.notifier).state = const [_oneItemSection];
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    final remainingTile = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile &&
            widget.focusId == 'home:section:changing-module:item:Remaining',
      ),
    );
    expect(remainingTile.focusNode?.hasPrimaryFocus, isTrue);
  });

  testWidgets('empty Home focuses the edit action on TV', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            SeedData.defaultSettings.copyWith(
              homeModules: const [],
              homeStartupAutoRefreshEnabled: false,
            ),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    final editAction = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction && widget.focusId == 'home:edit',
      ),
    );
    expect(editAction.focusNode?.hasPrimaryFocus, isTrue);
  });

  testWidgets(
      'Home keeps focus on the same resource through reorder and title refresh',
      (tester) async {
    final sectionProvider = StateProvider<HomeSectionViewModel>(
      (ref) => _focusIdentitySectionBefore,
    );
    final settings = SeedData.defaultSettings.copyWith(
      homeModules: const [
        HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: false,
        ),
        HomeModuleConfig(
          id: 'focus-identity-module',
          type: HomeModuleType.doubanList,
          title: 'Focus Identity',
          enabled: true,
          doubanListUrl: 'https://example.com/focus-identity',
        ),
      ],
      homeStartupAutoRefreshEnabled: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(settings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              sections: [ref.watch(sectionProvider)],
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return moduleId == 'focus-identity-module'
                ? ref.watch(sectionProvider)
                : null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final focusedBefore = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile && widget.title == 'Stable Before',
      ),
    );
    focusedBefore.focusNode!.requestFocus();
    await tester.pump();
    expect(focusedBefore.focusNode?.hasPrimaryFocus, isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(sectionProvider.notifier).state = _focusIdentitySectionAfter;
    await tester.pumpAndSettle();

    final focusedAfter = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) => widget is MediaPosterTile && widget.title == 'Stable After',
      ),
    );
    expect(focusedAfter.focusNode, same(focusedBefore.focusNode));
    expect(focusedAfter.focusNode?.hasPrimaryFocus, isTrue);
  });

  testWidgets('Hero keeps the focused resource when its list reorders',
      (tester) async {
    final sectionProvider = StateProvider<HomeSectionViewModel>(
      (ref) => _reorderingHeroSectionBefore,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_homeSettings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              sections: [ref.watch(sectionProvider)],
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return moduleId == 'test-module'
                ? ref.watch(sectionProvider)
                : null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final focusedBefore = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:reorder-hero-a',
      ),
    );
    focusedBefore.focusNode!.requestFocus();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(sectionProvider.notifier).state =
        _reorderingHeroSectionAfter;
    await tester.pumpAndSettle();

    final focusedAfter = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:reorder-hero-a',
      ),
    );
    final nextPager = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:pager-next',
      ),
    );
    expect(focusedAfter.focusNode, same(focusedBefore.focusNode));
    expect(focusedAfter.focusNode?.hasPrimaryFocus, isTrue);
    expect(nextPager.onPressed, isNull);
  });

  testWidgets('Hero leaves a pager that becomes disabled after refresh',
      (tester) async {
    final sectionProvider = StateProvider<HomeSectionViewModel>(
      (ref) => _reorderingHeroSectionBefore,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_homeSettings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              sections: [ref.watch(sectionProvider)],
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return moduleId == 'test-module'
                ? ref.watch(sectionProvider)
                : null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final nextPager = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:pager-next',
      ),
    );
    nextPager.focusNode!.requestFocus();
    await tester.pump();
    expect(nextPager.focusNode?.hasPrimaryFocus, isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(sectionProvider.notifier).state =
        _singleReorderingHeroSection;
    await tester.pumpAndSettle();

    final hero = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:reorder-hero-a',
      ),
    );
    expect(hero.focusNode?.hasPrimaryFocus, isTrue);
    expect(find.byWidget(nextPager), findsNothing);
  });

  testWidgets('Hero resets its page when the source section changes',
      (tester) async {
    final sectionProvider = StateProvider<HomeSectionViewModel>(
      (ref) => _heroScopeSectionA,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_homeSettings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              sections: [ref.watch(sectionProvider)],
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return moduleId == 'test-module'
                ? ref.watch(sectionProvider)
                : null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    TvFocusableAction pager(String focusId) => tester.widget<TvFocusableAction>(
          find.byWidgetPredicate(
            (widget) =>
                widget is TvFocusableAction && widget.focusId == focusId,
          ),
        );
    pager('home:hero:pager-next').onPressed!.call();
    await tester.pumpAndSettle();
    expect(pager('home:hero:pager-prev').onPressed, isNotNull);
    expect(pager('home:hero:pager-next').onPressed, isNull);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(sectionProvider.notifier).state = _heroScopeSectionB;
    await tester.pumpAndSettle();

    expect(pager('home:hero:pager-prev').onPressed, isNull);
    expect(pager('home:hero:pager-next').onPressed, isNotNull);
  });

  testWidgets('Home does not take focus while a child route is current',
      (tester) async {
    final sectionsProvider = StateProvider<List<HomeSectionViewModel>>(
      (ref) => const [_emptyFirstSection, _secondContentSection],
    );
    final settings = SeedData.defaultSettings.copyWith(
      homeModules: const [
        HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: false,
        ),
        HomeModuleConfig(
          id: 'first-module',
          type: HomeModuleType.recentlyAdded,
          title: 'First',
          enabled: true,
        ),
        HomeModuleConfig(
          id: 'second-module',
          type: HomeModuleType.doubanList,
          title: 'Second',
          enabled: true,
          doubanListUrl: 'https://example.com/second',
        ),
      ],
      homeStartupAutoRefreshEnabled: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(settings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              sections: ref.watch(sectionsProvider),
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            for (final section in ref.watch(sectionsProvider)) {
              if (section.id == moduleId) {
                return section;
              }
            }
            return null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final homeContext = tester.element(find.byType(HomePage));
    Navigator.of(homeContext).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const _FocusedChildRoute(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'test-home-child-focus',
    );

    final container = ProviderScope.containerOf(homeContext);
    container.read(sectionsProvider.notifier).state = const [
      _firstContentSection,
      _secondContentSection,
    ];
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'test-home-child-focus',
    );
  });

  testWidgets('Home recovers when a focused view-all action disappears',
      (tester) async {
    final sectionProvider = StateProvider<HomeSectionViewModel>(
      (ref) => _sectionWithViewAll,
    );
    final settings = SeedData.defaultSettings.copyWith(
      homeModules: const [
        HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: false,
        ),
        _viewAllModule,
      ],
      homeStartupAutoRefreshEnabled: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(settings),
          homeResolvedSectionsProvider.overrideWith(
            (ref) => HomeResolvedSectionsState(
              sections: [ref.watch(sectionProvider)],
            ),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            return moduleId == _viewAllModule.id
                ? ref.watch(sectionProvider)
                : null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final viewAll = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:section:view-all-module:view-all',
      ),
    );
    viewAll.focusNode!.requestFocus();
    await tester.pump();
    expect(viewAll.focusNode?.hasPrimaryFocus, isTrue);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    container.read(sectionProvider.notifier).state = _sectionWithoutViewAll;
    await tester.pumpAndSettle();

    final remainingTile = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile && widget.title == 'View All Resource',
      ),
    );
    expect(remainingTile.focusNode?.hasPrimaryFocus, isTrue);
  });

  testWidgets('Home reaches the first card after many empty modules',
      (tester) async {
    final emptyModules = List<HomeModuleConfig>.generate(
      12,
      (index) => HomeModuleConfig(
        id: 'distant-empty-$index',
        type: HomeModuleType.doubanList,
        title: 'Empty $index',
        enabled: true,
        doubanListUrl: 'https://example.com/empty-$index',
      ),
    );
    final sections = <HomeSectionViewModel>[
      ...List<HomeSectionViewModel>.generate(
        emptyModules.length,
        (index) => HomeSectionViewModel(
          id: 'distant-empty-$index',
          title: 'Empty $index',
          subtitle: '',
          emptyMessage: '无',
          layout: HomeSectionLayout.posterRail,
        ),
      ),
      _distantContentSection,
    ];
    final settings = SeedData.defaultSettings.copyWith(
      homeModules: [
        const HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: false,
        ),
        ...emptyModules,
        const HomeModuleConfig(
          id: 'distant-content-module',
          type: HomeModuleType.doubanList,
          title: 'Distant Content',
          enabled: true,
          doubanListUrl: 'https://example.com/distant-content',
        ),
      ],
      homeStartupAutoRefreshEnabled: false,
    );
    var menuRequestCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(settings),
          homeResolvedSectionsProvider.overrideWithValue(
            HomeResolvedSectionsState(sections: sections),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            for (final section in sections) {
              if (section.id == moduleId) {
                return section;
              }
            }
            return null;
          }),
        ],
        child: MaterialApp(
          home: TvMenuButtonScope(
            onMenuButtonPressed: () => menuRequestCount += 1,
            child: const HomePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final contentTile = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile && widget.title == 'Distant Content',
      ),
    );
    expect(contentTile.focusNode?.hasPrimaryFocus, isTrue);
    expect(menuRequestCount, 0);
  });

  testWidgets('Hero down reaches content after many empty modules',
      (tester) async {
    final emptyModules = List<HomeModuleConfig>.generate(
      12,
      (index) => HomeModuleConfig(
        id: 'hero-distant-empty-$index',
        type: HomeModuleType.doubanList,
        title: 'Empty $index',
        enabled: true,
        doubanListUrl: 'https://example.com/hero-empty-$index',
      ),
    );
    final sections = <HomeSectionViewModel>[
      ...List<HomeSectionViewModel>.generate(
        emptyModules.length,
        (index) => HomeSectionViewModel(
          id: 'hero-distant-empty-$index',
          title: 'Empty $index',
          subtitle: '',
          emptyMessage: '无',
          layout: HomeSectionLayout.posterRail,
        ),
      ),
      _distantContentSection,
    ];
    final settings = SeedData.defaultSettings.copyWith(
      homeModules: [
        const HomeModuleConfig(
          id: HomeModuleConfig.heroModuleId,
          type: HomeModuleType.hero,
          title: 'Hero',
          enabled: true,
        ),
        ...emptyModules,
        const HomeModuleConfig(
          id: 'distant-content-module',
          type: HomeModuleType.doubanList,
          title: 'Distant Content',
          enabled: true,
          doubanListUrl: 'https://example.com/distant-content',
        ),
      ],
      homeStartupAutoRefreshEnabled: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(settings),
          homeResolvedSectionsProvider.overrideWithValue(
            HomeResolvedSectionsState(sections: sections),
          ),
          homeSectionProvider.overrideWith((ref, moduleId) async {
            for (final section in sections) {
              if (section.id == moduleId) {
                return section;
              }
            }
            return null;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    final hero = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:distant-content',
      ),
    );
    hero.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final contentTile = tester.widget<MediaPosterTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaPosterTile && widget.title == 'Distant Content',
      ),
    );
    expect(contentTile.focusNode?.hasPrimaryFocus, isTrue);
  });

  testWidgets('inactive retained Home does not declare an autofocus target',
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
        ],
        child: const MaterialApp(
          home: TickerMode(
            enabled: false,
            child: HomePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hero = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'home:hero:hero-item-1',
      ),
    );
    expect(hero.autofocus, isFalse);
    expect(hero.focusNode?.hasFocus, isFalse);
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

class _FocusedChildRoute extends StatefulWidget {
  const _FocusedChildRoute();

  @override
  State<_FocusedChildRoute> createState() => _FocusedChildRouteState();
}

class _FocusedChildRouteState extends State<_FocusedChildRoute> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'test-home-child-focus');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        focusNode: _focusNode,
        child: const SizedBox.expand(),
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

const _multiHeroSection = HomeSectionViewModel(
  id: 'multi-hero-source',
  title: 'Multi Hero Source',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'multi-hero-1',
      title: 'Multi Hero One',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Multi Hero One',
        posterUrl: '',
        overview: '',
      ),
    ),
    HomeCardViewModel(
      id: 'multi-hero-2',
      title: 'Multi Hero Two',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Multi Hero Two',
        posterUrl: '',
        overview: '',
      ),
    ),
  ],
);

const _emptyFirstSection = HomeSectionViewModel(
  id: 'first-module',
  title: 'First',
  subtitle: '',
  emptyMessage: '无',
  layout: HomeSectionLayout.posterRail,
);

const _firstContentSection = HomeSectionViewModel(
  id: 'first-module',
  title: 'First',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'first-content',
      title: 'First Content',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'First Content',
        posterUrl: '',
        overview: '',
      ),
    ),
  ],
);

const _secondContentSection = HomeSectionViewModel(
  id: 'second-module',
  title: 'Second',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'second-content',
      title: 'Second Content',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Second Content',
        posterUrl: '',
        overview: '',
      ),
    ),
  ],
);

const _twoItemSection = HomeSectionViewModel(
  id: 'changing-module',
  title: 'Changing',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'removed',
      title: 'Removed',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Removed',
        posterUrl: '',
        overview: '',
      ),
    ),
    HomeCardViewModel(
      id: 'remaining',
      title: 'Remaining',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Remaining',
        posterUrl: '',
        overview: '',
      ),
    ),
  ],
);

const _oneItemSection = HomeSectionViewModel(
  id: 'changing-module',
  title: 'Changing',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'remaining',
      title: 'Remaining',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Remaining',
        posterUrl: '',
        overview: '',
      ),
    ),
  ],
);

const _focusIdentitySectionBefore = HomeSectionViewModel(
  id: 'focus-identity-module',
  title: 'Focus Identity',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'other-resource',
      title: 'Other',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Other',
        posterUrl: '',
        overview: '',
        itemId: 'other-resource',
      ),
    ),
    HomeCardViewModel(
      id: 'stable-resource',
      title: 'Stable Before',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Stable Before',
        posterUrl: '',
        overview: '',
        itemId: 'stable-resource',
      ),
    ),
  ],
);

const _focusIdentitySectionAfter = HomeSectionViewModel(
  id: 'focus-identity-module',
  title: 'Focus Identity',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'stable-resource',
      title: 'Stable After',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Stable After',
        posterUrl: '',
        overview: '',
        itemId: 'stable-resource',
      ),
    ),
    HomeCardViewModel(
      id: 'other-resource',
      title: 'Other',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Other',
        posterUrl: '',
        overview: '',
        itemId: 'other-resource',
      ),
    ),
  ],
);

const _reorderingHeroSectionBefore = HomeSectionViewModel(
  id: 'test-module',
  title: 'Reordering Hero',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'reorder-hero-a',
      title: 'Hero A',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Hero A',
        posterUrl: '',
        overview: '',
      ),
    ),
    HomeCardViewModel(
      id: 'reorder-hero-b',
      title: 'Hero B',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Hero B',
        posterUrl: '',
        overview: '',
      ),
    ),
  ],
);

const _reorderingHeroSectionAfter = HomeSectionViewModel(
  id: 'test-module',
  title: 'Reordering Hero',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'reorder-hero-b',
      title: 'Hero B',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Hero B',
        posterUrl: '',
        overview: '',
      ),
    ),
    HomeCardViewModel(
      id: 'reorder-hero-a',
      title: 'Hero A',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Hero A',
        posterUrl: '',
        overview: '',
      ),
    ),
  ],
);

const _singleReorderingHeroSection = HomeSectionViewModel(
  id: 'test-module',
  title: 'Reordering Hero',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'reorder-hero-a',
      title: 'Hero A',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Hero A',
        posterUrl: '',
        overview: '',
      ),
    ),
  ],
);

const _heroScopeSectionA = HomeSectionViewModel(
  id: 'hero-scope-a',
  title: 'Hero Scope A',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [_heroScopeFirst, _heroScopeSecond],
);

const _heroScopeSectionB = HomeSectionViewModel(
  id: 'hero-scope-b',
  title: 'Hero Scope B',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [_heroScopeFirst, _heroScopeSecond],
);

const _heroScopeFirst = HomeCardViewModel(
  id: 'hero-scope-first',
  title: 'Hero Scope First',
  subtitle: '',
  posterUrl: '',
  detailTarget: MediaDetailTarget(
    title: 'Hero Scope First',
    posterUrl: '',
    overview: '',
  ),
);

const _heroScopeSecond = HomeCardViewModel(
  id: 'hero-scope-second',
  title: 'Hero Scope Second',
  subtitle: '',
  posterUrl: '',
  detailTarget: MediaDetailTarget(
    title: 'Hero Scope Second',
    posterUrl: '',
    overview: '',
  ),
);

const _viewAllModule = HomeModuleConfig(
  id: 'view-all-module',
  type: HomeModuleType.doubanList,
  title: 'View All',
  enabled: true,
  doubanListUrl: 'https://example.com/view-all',
);

const _sectionWithViewAll = HomeSectionViewModel(
  id: 'view-all-module',
  title: 'View All',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [_viewAllResource],
  viewAllTarget: HomeSectionViewAllTarget.module(_viewAllModule),
);

const _sectionWithoutViewAll = HomeSectionViewModel(
  id: 'view-all-module',
  title: 'View All',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [_viewAllResource],
);

const _viewAllResource = HomeCardViewModel(
  id: 'view-all-resource',
  title: 'View All Resource',
  subtitle: '',
  posterUrl: '',
  detailTarget: MediaDetailTarget(
    title: 'View All Resource',
    posterUrl: '',
    overview: '',
  ),
);

const _distantContentSection = HomeSectionViewModel(
  id: 'distant-content-module',
  title: 'Distant Content',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'distant-content',
      title: 'Distant Content',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Distant Content',
        posterUrl: '',
        overview: '',
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
