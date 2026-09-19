// Disable Riverpod's debug-only frame side effect to exercise release behavior.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/src/internals.dart'
    show debugCanModifyProviders;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/router/app_routes.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/bootstrap/application/bootstrap_controller.dart';
import 'package:starflow/features/bootstrap/presentation/bootstrap_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class _ControlledBootstrapController extends BootstrapController {
  @override
  Future<void> start() async {}

  void setProgress(double progress) {
    state = state.copyWith(progress: progress);
  }

  void complete() {
    state = state.copyWith(progress: 1, isComplete: true);
  }
}

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 720)]) {
    for (final reduceMotion in [false, true]) {
      testWidgets(
          'bootstrap stays static at $size with reduceMotion=$reduceMotion',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = _ControlledBootstrapController();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bootstrapControllerProvider.overrideWith(() => controller),
              appSettingsProvider.overrideWithValue(
                SeedData.defaultSettings.copyWith(
                  performanceReduceMotionEnabled: reduceMotion,
                ),
              ),
            ],
            child: const MaterialApp(home: BootstrapPage()),
          ),
        );

        final logo = find.byType(Image);
        final star = find.text('Star');
        final flow = find.text('flow');
        final initialLogo = _paintedRect(tester, logo);
        final initialStar = _paintedRect(tester, star);
        final initialFlow = _paintedRect(tester, flow);
        final opacity = find.descendant(
          of: find.byType(BootstrapPage),
          matching: find.byType(Opacity),
        );
        expect(initialLogo.size, const Size(108, 108));
        expect(opacity, findsNothing);
        expect(
          find.descendant(
            of: find.byType(BootstrapPage),
            matching: find.byType(TweenAnimationBuilder<double>),
          ),
          findsNothing,
        );

        for (final progress in [0.18, 0.42, 0.76, 0.94, 1.0]) {
          controller.setProgress(progress);
          await tester.pump(const Duration(milliseconds: 200));
          expect(_paintedRect(tester, logo), initialLogo);
          expect(_paintedRect(tester, star), initialStar);
          expect(_paintedRect(tester, flow), initialFlow);
          expect(opacity, findsNothing);
        }

        await tester.pumpAndSettle();
        final builders = tester.widgetList<AnimatedBuilder>(find.descendant(
          of: find.byType(BootstrapPage),
          matching: find.byType(AnimatedBuilder),
        ));
        for (final builder in builders) {
          final animation = builder.animation;
          if (animation is AnimationController) {
            expect(animation.isAnimating, isFalse);
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('idle bootstrap schedules a frame and navigates on completion',
      (tester) async {
    final controller = _ControlledBootstrapController();
    final router = GoRouter(
      initialLocation: '/bootstrap',
      routes: [
        GoRoute(
          path: '/bootstrap',
          builder: (context, state) => const BootstrapPage(),
        ),
        GoRoute(
          path: '/home',
          name: AppRoutes.home.name,
          builder: (context, state) => const Scaffold(body: Text('Home ready')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapControllerProvider.overrideWith(() => controller),
          appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    // Riverpod's debug-only mutation check schedules a frame that release lacks.
    final debugCheck = debugCanModifyProviders;
    try {
      debugCanModifyProviders = null;
      controller.complete();
    } finally {
      debugCanModifyProviders = debugCheck;
    }
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'Completion must wake the static page without user input.');
    await tester.pumpAndSettle();
    expect(find.text('Home ready'), findsOneWidget);
    expect(find.byType(BootstrapPage), findsNothing);
  });
}
