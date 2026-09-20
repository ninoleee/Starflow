import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/router/app_navigation_shell.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/metadata/application/metadata_prefetch_concurrency_limiter.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  for (final tv in [false, true]) {
    testWidgets('custom menu order preserves branch routing (TV: $tv)',
        (tester) async {
      final router = _buildRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => tv),
          appSettingsProvider.overrideWithValue(_settings.copyWith(
            autoHideNavigationBarEnabled: false,
            navigationDestinationIds: const ['settings', 'live-tv', 'home'],
          )),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      if (tv) {
        _navigationNode(tester, 0).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        expect(tester.getCenter(find.byIcon(Icons.tune_outlined)).dx,
            lessThan(tester.getCenter(find.byIcon(Icons.live_tv_outlined)).dx));
        expect(tester.getCenter(find.byIcon(Icons.live_tv_outlined)).dx,
            lessThan(tester.getCenter(find.byIcon(Icons.space_dashboard_rounded)).dx));
        await tester.tap(find.byIcon(Icons.tune_outlined));
      }
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      if (tv) {
        _contentNode(tester, 'settings').requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(_navigationNode(tester, 0).hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/live-tv');
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final autoHide in [true, false]) {
    for (final (index, path) in const [
      'home',
      'search',
      'favorites',
      'library',
      'live-tv',
      'settings',
    ].indexed) {
      testWidgets(
        'TV idle $path left edge schedules sidebar focus '
        '(autoHide: $autoHide)',
        (tester) async {
          final router = _buildRouter(nestedPageFocusScope: true);
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                isTelevisionProvider.overrideWith((ref) => true),
                appSettingsProvider.overrideWithValue(
                  _settings.copyWith(
                    autoHideNavigationBarEnabled: autoHide,
                    navigationDestinationIds: kAllNavigationDestinationIds,
                  ),
                ),
              ],
              child: MaterialApp.router(
                theme: ThemeData.dark(),
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();
          router.go('/$path');
          await tester.pumpAndSettle();
          final content = _contentNode(tester, path);
          content.requestFocus();
          await tester.pumpAndSettle();
          expect(content.hasPrimaryFocus, isTrue);
          expect(tester.binding.hasScheduledFrame, isFalse);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.idle();
          // Do not let pumpAndSettle supply a frame the app never requested.
          expect(tester.binding.hasScheduledFrame, isTrue);
          await tester.pumpAndSettle();
          expect(_navigationNode(tester, index).hasPrimaryFocus, isTrue);
          expect(content.hasFocus, isFalse);

          final nextIndex = index == 5 ? index - 1 : index + 1;
          await tester.sendKeyEvent(
            index == 5
                ? LogicalKeyboardKey.arrowUp
                : LogicalKeyboardKey.arrowDown,
          );
          await tester.pumpAndSettle();
          expect(_navigationNode(tester, nextIndex).hasPrimaryFocus, isTrue);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(content.hasPrimaryFocus, isTrue);
        },
      );
    }

    testWidgets(
      'TV sidebar keeps vertical focus inside its bounds (autoHide: $autoHide)',
      (tester) async {
        final router = _buildRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              isTelevisionProvider.overrideWith((ref) => true),
              appSettingsProvider.overrideWithValue(
                _settings.copyWith(autoHideNavigationBarEnabled: autoHide),
              ),
            ],
            child: MaterialApp.router(
              theme: ThemeData.dark(),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (autoHide) {
          tester
              .widget<TvMenuButtonScope>(find.byType(TvMenuButtonScope))
              .onMenuButtonPressed();
          await tester.pumpAndSettle();
        }
        final navigationNodes = tester
            .widgetList<TvFocusableAction>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TvFocusableAction &&
                    (widget.focusNode?.debugLabel?.startsWith('tv-nav-') ??
                        false),
              ),
            )
            .map((action) => action.focusNode!)
            .toList(growable: false);
        expect(navigationNodes.length, greaterThanOrEqualTo(2));
        final first = navigationNodes.first;
        final last = navigationNodes.last;

        first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          first.hasPrimaryFocus,
          isTrue,
          reason: describeTvFocusNode(FocusManager.instance.primaryFocus),
        );
        expect(_contentNode(tester, 'home').hasFocus, isFalse);

        last.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(last.hasPrimaryFocus, isTrue);
        expect(_contentNode(tester, 'home').hasFocus, isFalse);
      },
    );
  }

  testWidgets(
    'TV sidebar restores focus after auto hide and remains traversable',
    (tester) async {
      final router = _buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
            appSettingsProvider.overrideWithValue(_settings),
          ],
          child: MaterialApp.router(
            theme: ThemeData.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final homeNavigationNode = _navigationNode(tester, 0);
      final liveNavigationNode = _navigationNode(tester, 1);
      final menuScope = tester.widget<TvMenuButtonScope>(
        find.byType(TvMenuButtonScope),
      );
      menuScope.onMenuButtonPressed();
      await tester.pumpAndSettle();
      expect(homeNavigationNode.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(liveNavigationNode.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_contentNode(tester, 'home').hasPrimaryFocus, isTrue);
      expect(
        tester
            .widgetList<ExcludeFocus>(find.byType(ExcludeFocus))
            .any((widget) => widget.excluding),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(homeNavigationNode.hasPrimaryFocus, isTrue);
      expect(_contentNode(tester, 'home').hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_contentNode(tester, 'home').hasPrimaryFocus, isTrue);

      // With the Stack sidebar hidden, vertical traversal must stay inside the
      // content page and must not jump back to the excluded menu items.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_contentNode(tester, 'home').hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_contentNode(tester, 'home').hasPrimaryFocus, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(homeNavigationNode.hasPrimaryFocus, isTrue);
      expect(_contentNode(tester, 'home').hasFocus, isFalse);
      expect(find.text('退出 Starflow？'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(liveNavigationNode.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_contentNode(tester, 'live-tv').hasPrimaryFocus, isTrue);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppNavigationShell)),
      );
      final limiter =
          container.read(metadataPrefetchConcurrencyLimiterProvider);
      expect(limiter.isPausedForForeground, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(liveNavigationNode.hasPrimaryFocus, isTrue);
      expect(_contentNode(tester, 'live-tv').hasFocus, isFalse);
      expect(find.text('退出 Starflow？'), findsNothing);
      expect(limiter.isPausedForForeground, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('退出 Starflow？'), findsOneWidget);
      expect(limiter.isPausedForForeground, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('退出 Starflow？'), findsNothing);
      expect(limiter.isPausedForForeground, isFalse);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('tv-nav-'),
      );
    },
  );

  testWidgets(
    'TV left edge exits a nested page focus scope to the sidebar',
    (tester) async {
      final router = _buildRouter(nestedPageFocusScope: true);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => true),
            appSettingsProvider.overrideWithValue(_settings),
          ],
          child: MaterialApp.router(
            theme: ThemeData.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final homeNavigationNode = _navigationNode(tester, 0);
      final contentNode = _contentNode(tester, 'home');
      contentNode.requestFocus();
      await tester.pump();
      expect(contentNode.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(homeNavigationNode.hasPrimaryFocus, isTrue);
      expect(contentNode.hasFocus, isFalse);
    },
  );

  testWidgets('TV permanent sidebar keeps the page offset in Row layout', (
    tester,
  ) async {
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(
            _settings.copyWith(autoHideNavigationBarEnabled: false),
          ),
        ],
        child: MaterialApp.router(
          theme: ThemeData.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final content = _contentNode(tester, 'home');
    expect(tester.getTopLeft(find.byKey(const ValueKey('page-home'))).dx, 48);

    _navigationNode(tester, 0).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(content.hasPrimaryFocus, isTrue);
    expect(
      tester
          .widgetList<ExcludeFocus>(find.byType(ExcludeFocus))
          .any((widget) => widget.excluding),
      isFalse,
    );
  });

  testWidgets('TV auto-hide starts and reselects with the sidebar hidden', (
    tester,
  ) async {
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          appSettingsProvider.overrideWithValue(_settings),
        ],
        child: MaterialApp.router(
          theme: ThemeData.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<ExcludeFocus>(find.byType(ExcludeFocus))
          .any((widget) => widget.excluding),
      isTrue,
    );
    expect(_contentNode(tester, 'home').hasPrimaryFocus, isTrue);

    final menuScope = tester.widget<TvMenuButtonScope>(
      find.byType(TvMenuButtonScope),
    );
    menuScope.onMenuButtonPressed();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(_contentNode(tester, 'live-tv').hasPrimaryFocus, isTrue);
    expect(
      tester
          .widgetList<ExcludeFocus>(find.byType(ExcludeFocus))
          .any((widget) => widget.excluding),
      isTrue,
    );
  });

  for (final autoHide in [true, false]) {
    for (final size in [const Size(960, 540), const Size(1280, 720)]) {
      testWidgets(
        'TV focus labels stay beside their buttons '
        '(autoHide: $autoHide, size: $size)',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final router = _buildRouter();
          addTearDown(router.dispose);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                isTelevisionProvider.overrideWith((ref) => true),
                appSettingsProvider.overrideWithValue(
                  _settings.copyWith(autoHideNavigationBarEnabled: autoHide),
                ),
              ],
              child: MaterialApp.router(
                theme: ThemeData.dark(),
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();
          tester
              .widget<TvMenuButtonScope>(find.byType(TvMenuButtonScope))
              .onMenuButtonPressed();
          await tester.pumpAndSettle();
          final pageRect = tester.getRect(
            find.byKey(const ValueKey('page-home')),
          );
          expect(pageRect.left, autoHide ? 0 : 48);

          final navigationActions = find.byWidgetPredicate(
            (widget) =>
                widget is TvFocusableAction &&
                (widget.focusNode?.debugLabel?.startsWith('tv-nav-') ?? false),
          );
          for (var index = 0;
              index < navigationActions.evaluate().length;
              index++) {
            final action = navigationActions.at(index);
            tester.widget<TvFocusableAction>(action).focusNode!.requestFocus();
            await tester.pumpAndSettle();

            final follower = find.byType(CompositedTransformFollower);
            expect(follower, findsOneWidget);
            final label = find.descendant(
              of: follower,
              matching: find.byType(Text),
            );
            expect(label, findsOneWidget);
            final labelRect = tester.getRect(label);
            final buttonRect = tester.getRect(action);
            expect(labelRect.width, lessThan(150));
            expect(labelRect.height, lessThan(44));
            expect(labelRect.left - buttonRect.right, closeTo(12, 0.01));
            expect(labelRect.center.dy, closeTo(buttonRect.center.dy, 0.01));
            expect(
              tester.getRect(find.byKey(const ValueKey('page-home'))),
              pageRect,
            );
          }

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(_contentNode(tester, 'home').hasPrimaryFocus, isTrue);
          expect(find.byType(CompositedTransformFollower), findsNothing);

          // Also unmount while a label is visible to check portal cleanup.
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(_navigationNode(tester, 0).hasPrimaryFocus, isTrue);
          expect(find.byType(CompositedTransformFollower), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(find.byType(CompositedTransformFollower), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

GoRouter _buildRouter({bool nestedPageFocusScope = false}) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppNavigationShell(navigationShell: navigationShell);
        },
        branches: [
          for (final path in const [
            'home',
            'search',
            'favorites',
            'library',
            'settings',
            'live-tv',
          ])
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/$path',
                  builder: (context, state) => _TestPage(
                    id: path,
                    nestedPageFocusScope: nestedPageFocusScope,
                  ),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

FocusNode _navigationNode(WidgetTester tester, int index) {
  return tester
      .widget<TvFocusableAction>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TvFocusableAction &&
              widget.focusNode?.debugLabel == 'tv-nav-$index',
        ),
      )
      .focusNode!;
}

FocusNode _contentNode(WidgetTester tester, String id) {
  return tester
      .widget<TvFocusableAction>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TvFocusableAction && widget.focusId == 'content:$id',
        ),
      )
      .focusNode!;
}

class _TestPage extends StatefulWidget {
  const _TestPage({required this.id, this.nestedPageFocusScope = false});

  final String id;
  final bool nestedPageFocusScope;

  @override
  State<_TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<_TestPage> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'content-${widget.id}',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      key: ValueKey('page-${widget.id}'),
      body: Align(
        alignment: Alignment.centerLeft,
        child: TvFocusableAction(
          focusNode: _focusNode,
          focusId: 'content:${widget.id}',
          autofocus: true,
          onPressed: () {},
          child: const SizedBox(width: 180, height: 80),
        ),
      ),
    );
    return widget.nestedPageFocusScope
        ? TvPageFocusScope(isTelevision: true, child: page)
        : page;
  }
}

const _settings = AppSettings(
  mediaSources: <MediaSourceConfig>[],
  searchProviders: <SearchProviderConfig>[],
  doubanAccount: DoubanAccountConfig(enabled: false),
  homeModules: <HomeModuleConfig>[],
  homeStartupAutoRefreshEnabled: false,
  autoHideNavigationBarEnabled: true,
  translucentEffectsEnabled: false,
);
