import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/media_poster_tile.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/home/presentation/home_page.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  testWidgets('auto play does not reclaim focus moved during animation',
      (tester) async {
    await tester.pumpWidget(_heroTestApp(
      mode: HomeHeroDisplayMode.borderless,
      autoPlay: true,
    ));
    await tester.pumpAndSettle();
    final contentFocus = tester
        .widget<MediaPosterTile>(
          find.byType(MediaPosterTile).first,
        )
        .focusNode!;
    await tester.pump(const Duration(seconds: 6));
    contentFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(contentFocus.hasPrimaryFocus, isTrue);
    await tester.pump(const Duration(seconds: 12));
    expect(contentFocus.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('non-TV auto play pauses on touch and resumes after release',
      (tester) async {
    await tester.pumpWidget(_heroTestApp(
      mode: HomeHeroDisplayMode.normal,
      autoPlay: true,
      television: false,
    ));
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PageView)));
    await tester.pump(const Duration(seconds: 12));
    expect(pager.page, 0);
    await gesture.cancel();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(pager.page, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('auto play waits a full interval after manual paging',
      (tester) async {
    await tester.pumpWidget(_heroTestApp(
      mode: HomeHeroDisplayMode.normal,
      autoPlay: true,
    ));
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    await tester.pump(const Duration(seconds: 5));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(pager.page, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(pager.page, 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(pager.page, 0);
    await tester.pumpWidget(const SizedBox());
  });

  for (final simplified in [false, true]) {
    for (final mode in HomeHeroDisplayMode.values) {
      testWidgets(
          'TV auto play loops and keeps visible focus, static=$simplified mode=$mode',
          (tester) async {
        await tester.pumpWidget(_heroTestApp(
          mode: mode,
          autoPlay: true,
          simplified: simplified,
        ));
        await tester.pumpAndSettle();
        PageController pager() =>
            tester.widget<PageView>(find.byType(PageView)).controller!;
        expect(pager().page, 0);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(pager().page, 1);
        expect(FocusManager.instance.primaryFocus?.debugLabel,
            'home-hero-card:layout-b');
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(pager().page, 0);
        expect(FocusManager.instance.primaryFocus?.debugLabel,
            'home-hero-card:layout-a');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('TV auto play pauses on pager, background and lower content',
      (tester) async {
    await tester.pumpWidget(_heroTestApp(
      mode: HomeHeroDisplayMode.normal,
      autoPlay: true,
    ));
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    expect(pager.page, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 12));
    expect(pager.page, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(pager.page, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final focus = FocusManager.instance.primaryFocus;
    await tester.pump(const Duration(seconds: 12));
    expect(pager.page, 1);
    expect(FocusManager.instance.primaryFocus, focus);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('auto play stops when disabled or only one item remains',
      (tester) async {
    final state = StateProvider<HomeResolvedSectionsState>(
        (ref) => const HomeResolvedSectionsState(sections: [_heroSection]));
    await tester.pumpWidget(_heroTestApp(
      mode: HomeHeroDisplayMode.normal,
      autoPlay: true,
      state: state,
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomePage)));
    await tester.pumpWidget(_heroTestApp(
      mode: HomeHeroDisplayMode.normal,
      autoPlay: false,
      state: state,
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(pager.page, 0);
    container.read(state.notifier).state = HomeResolvedSectionsState(sections: [
      HomeSectionViewModel(
          id: _heroSection.id,
          title: 'Recent',
          subtitle: '',
          emptyMessage: '',
          layout: HomeSectionLayout.posterRail,
          items: [_heroSection.items.first]),
    ]);
    await tester.pumpWidget(_heroTestApp(
      mode: HomeHeroDisplayMode.normal,
      autoPlay: true,
      state: state,
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    expect(pager.page, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('auto play pauses when home is covered by another route',
      (tester) async {
    await tester.pumpWidget(_heroTestApp(
      mode: HomeHeroDisplayMode.normal,
      autoPlay: true,
    ));
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    final navigator = Navigator.of(tester.element(find.byType(HomePage)));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Details'))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    expect(pager.page, 0);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(pager.page, 1);
    await tester.pumpWidget(const SizedBox());
  });

  for (final mode in HomeHeroDisplayMode.values) {
    test('hero height respects space and limits in ${mode.name}', () {
      for (final height in [320.0, 360.0, 540.0, 720.0, 1080.0]) {
        final result = resolveHomeHeroHeight(
          availableHeight: height,
          displayMode: mode,
        );
        expect(result, lessThanOrEqualTo(height - 140));
        expect(result, greaterThan(0));
        expect(
            result,
            lessThanOrEqualTo(
              mode == HomeHeroDisplayMode.normal ? 440 : 500,
            ));
      }
      expect(
          resolveHomeHeroHeight(
            availableHeight: 540,
            displayMode: mode,
          ),
          closeTo(334.8, 0.01));
    });

    for (final size in [
      const Size(960, 540),
      const Size(1280, 720),
      const Size(1920, 1080),
      const Size(390, 844),
      const Size(844, 390),
    ]) {
      testWidgets('hero ${mode.name} reveals next rail at $size',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(_heroTestApp(mode: mode));
        await tester.pumpAndSettle();

        final poster = find.byType(MediaPosterTile).first;
        expect(tester.getTopLeft(poster).dy, lessThan(size.height - 60));
        expect(tester.takeException(), isNull);
        final heroHeight = tester.getSize(find.byType(PageView)).height;
        expect(heroHeight, lessThanOrEqualTo(size.height - 140));
        final overview = tester
            .widgetList<Text>(find.byType(Text))
            .where((text) => text.data == _heroOverview);
        if (overview.isNotEmpty) {
          expect(overview.first.maxLines, 2);
        }
      });
    }

    testWidgets('hero ${mode.name} uses parent height and tolerates large text',
        (tester) async {
      await tester.pumpWidget(_heroTestApp(
        mode: mode,
        height: 360,
        textScale: 2,
      ));
      await tester.pumpAndSettle();
      expect(
          tester.getSize(find.byType(PageView)).height, lessThanOrEqualTo(220));
      expect(find.text(_heroOverview), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'hero ${mode.name} loading and single/multiple items keep height',
        (tester) async {
      final state = StateProvider<HomeResolvedSectionsState>(
          (ref) => const HomeResolvedSectionsState(hasPendingSections: true));
      await tester.pumpWidget(_heroTestApp(mode: mode, state: state));
      await tester.pump();
      final slot = find.byKey(const ValueKey<String>('home:list:hero'));
      final initialHeight = tester.getSize(slot).height;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomePage)),
      );
      container.read(state.notifier).state = const HomeResolvedSectionsState(
        sections: [_heroSection],
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(slot).height, initialHeight);
      container.read(state.notifier).state = HomeResolvedSectionsState(
        sections: [
          HomeSectionViewModel(
            id: _heroSection.id,
            title: _heroSection.title,
            subtitle: '',
            emptyMessage: '',
            layout: HomeSectionLayout.posterRail,
            items: [_heroSection.items.first],
          )
        ],
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(slot).height, initialHeight);
      expect(tester.takeException(), isNull);
    });
  }

  test('hero prefetch retries on startup boundary', () {
    const decision = HomeHeroPrefetchDecision(
      shouldSchedule: true,
      forceMetadataRefresh: true,
    );
    expect(
      resolveHomeHeroPrefetchDecision(
        isPageVisible: true,
        featuredItemCount: 5,
        heroListChanged: true,
        scheduledMetadataRevision: 0,
        currentMetadataRevision: 1,
        scheduledExplicitRevision: 0,
        currentExplicitRevision: 0,
      ).shouldSchedule,
      decision.shouldSchedule,
    );
    expect(
      resolveHomeHeroPrefetchDecision(
        isPageVisible: true,
        featuredItemCount: 5,
        heroListChanged: true,
        scheduledMetadataRevision: 0,
        currentMetadataRevision: 1,
        scheduledExplicitRevision: 0,
        currentExplicitRevision: 0,
      ).forceMetadataRefresh,
      decision.forceMetadataRefresh,
    );
  });

  test('hero prefetch retries on explicit refresh boundary', () {
    final decision = resolveHomeHeroPrefetchDecision(
      isPageVisible: true,
      featuredItemCount: 5,
      heroListChanged: false,
      scheduledMetadataRevision: 1,
      currentMetadataRevision: 2,
      scheduledExplicitRevision: 0,
      currentExplicitRevision: 1,
    );
    expect(decision.shouldSchedule, isTrue);
    expect(decision.forceMetadataRefresh, isTrue);
  });

  test('hero prefetch stays idle when nothing changed', () {
    final decision = resolveHomeHeroPrefetchDecision(
      isPageVisible: true,
      featuredItemCount: 5,
      heroListChanged: false,
      scheduledMetadataRevision: 2,
      currentMetadataRevision: 2,
      scheduledExplicitRevision: 1,
      currentExplicitRevision: 1,
    );
    expect(decision.shouldSchedule, isFalse);
    expect(decision.forceMetadataRefresh, isFalse);
  });

  testWidgets('hero backdrop animation is skipped in simplified mode',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeHeroBackdrop(
          imageUrl: '',
          translucentEffectsEnabled: true,
          simplifyVisualEffects: true,
        ),
      ),
    );
    expect(find.byType(AnimatedSwitcher), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeHeroBackdrop(
          imageUrl: '',
          translucentEffectsEnabled: true,
          simplifyVisualEffects: false,
        ),
      ),
    );
    expect(find.byType(AnimatedSwitcher), findsOne);
  });

  testWidgets('media poster placeholder avoids animated icon', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MediaPosterTile(
              title: 'title',
              subtitle: 'subtitle',
              posterUrl: '',
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.movie_creation_outlined), findsNothing);
  });

  testWidgets('recent playback card shows source media library badge',
      (tester) async {
    const section = HomeSectionViewModel(
      id: 'layout-test',
      title: '最近播放',
      subtitle: '',
      emptyMessage: '暂无最近播放',
      layout: HomeSectionLayout.posterRail,
      items: [
        HomeCardViewModel(
          id: 'recent-1',
          title: '最近播放影片',
          subtitle: '27:15 / 1:42:00',
          posterUrl: '',
          detailTarget: MediaDetailTarget(
            title: '最近播放影片',
            posterUrl: '',
            overview: '',
            sourceName: '家庭影音库',
            sourceKind: MediaSourceKind.nas,
          ),
        ),
      ],
    );
    await tester.pumpWidget(_heroTestApp(
      mode: HomeHeroDisplayMode.normal,
      television: false,
      section: section,
    ));
    await tester.pumpAndSettle();

    final poster = tester.widget<MediaPosterTile>(
      find.byType(MediaPosterTile).first,
    );
    expect(poster.imageTopRightBadgeText, '家庭影音库');
  });
}

Widget _heroTestApp({
  required HomeHeroDisplayMode mode,
  double? height,
  double textScale = 1,
  bool autoPlay = false,
  bool simplified = false,
  bool television = true,
  StateProvider<HomeResolvedSectionsState>? state,
  HomeSectionViewModel section = _heroSection,
}) {
  return ProviderScope(
    overrides: [
      isTelevisionProvider.overrideWith((ref) => television),
      appSettingsProvider.overrideWithValue(SeedData.defaultSettings.copyWith(
        homeHeroDisplayMode: mode,
        homeHeroAutoPlayEnabled: autoPlay,
        performanceStaticHomeHeroEnabled: simplified,
        homeHeroBackgroundEnabled: false,
        homeHeroLogoTitleEnabled: false,
        homeStartupAutoRefreshEnabled: false,
        homeModules: const [
          HomeModuleConfig(
            id: HomeModuleConfig.heroModuleId,
            type: HomeModuleType.hero,
            title: 'Hero',
            enabled: true,
          ),
          HomeModuleConfig(
            id: 'layout-test',
            type: HomeModuleType.recentPlayback,
            title: 'Recent',
            enabled: true,
          ),
        ],
      )),
      homeResolvedSectionsProvider.overrideWith((ref) => state == null
          ? HomeResolvedSectionsState(sections: [section])
          : ref.watch(state)),
      homeSectionProvider.overrideWith((ref, id) async => section),
    ],
    child: MaterialApp(
      home: Builder(
          builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  padding: const EdgeInsets.only(top: 24, bottom: 24),
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(height: height, child: const HomePage()),
                ),
              )),
    ),
  );
}

const _heroOverview = 'A long overview that should stay within two lines even '
    'when the viewport is narrow. The next row must remain visible below the '
    'hero, and the title must remain readable on a television.';

const _heroSection = HomeSectionViewModel(
  id: 'layout-test',
  title: 'Recent',
  subtitle: '',
  emptyMessage: '',
  layout: HomeSectionLayout.posterRail,
  items: [
    HomeCardViewModel(
      id: 'layout-a',
      title: 'A long film title for responsive hero layout testing',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'A long film title for responsive hero layout testing',
        posterUrl: '',
        overview: _heroOverview,
        year: 2026,
        genres: ['Drama', 'Adventure'],
      ),
    ),
    HomeCardViewModel(
      id: 'layout-b',
      title: 'Second film',
      subtitle: '',
      posterUrl: '',
      detailTarget: MediaDetailTarget(
        title: 'Second film',
        posterUrl: '',
        overview: '',
      ),
    ),
  ],
);
