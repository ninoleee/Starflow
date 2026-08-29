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
  testWidgets(
    'TV sidebar restores focus after auto hide and remains traversable',
    (tester) async {
      final router = GoRouter(
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
              ])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/$path',
                      builder: (context, state) => _TestPage(id: path),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
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
      final searchNavigationNode = _navigationNode(tester, 1);
      homeNavigationNode.requestFocus();
      await tester.pump();
      expect(homeNavigationNode.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(searchNavigationNode.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_contentNode(tester, 'home').hasPrimaryFocus, isTrue);
      expect(
        tester
            .widgetList<ExcludeFocus>(find.byType(ExcludeFocus))
            .any((widget) => widget.excluding),
        isTrue,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(homeNavigationNode.hasPrimaryFocus, isTrue);
      expect(_contentNode(tester, 'home').hasFocus, isFalse);
      expect(find.text('退出 Starflow？'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(searchNavigationNode.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_contentNode(tester, 'search').hasPrimaryFocus, isTrue);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppNavigationShell)),
      );
      final limiter =
          container.read(metadataPrefetchConcurrencyLimiterProvider);
      expect(limiter.isPausedForForeground, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(searchNavigationNode.hasPrimaryFocus, isTrue);
      expect(_contentNode(tester, 'search').hasFocus, isFalse);
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
  const _TestPage({required this.id});

  final String id;

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
    return Scaffold(
      body: Align(
        alignment: Alignment.centerLeft,
        child: TvFocusableAction(
          focusNode: _focusNode,
          focusId: 'content:${widget.id}',
          onPressed: () {},
          child: const SizedBox(width: 180, height: 80),
        ),
      ),
    );
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
