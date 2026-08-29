import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';

void main() {
  testWidgets('settings route keeps the native iOS back gesture',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      PageRoute<void>? pushedRoute;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    SettingsMaterialPageRoute<void>(
                      builder: (context) {
                        pushedRoute = ModalRoute.of(context) as PageRoute<void>;
                        return const PopScope<void>(
                          canPop: true,
                          child: Scaffold(body: Text('设置详情')),
                        );
                      },
                    ),
                  );
                },
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();

      expect(pushedRoute, isNotNull);
      expect(pushedRoute!.transitionDuration, greaterThan(Duration.zero));
      expect(pushedRoute!.popGestureEnabled, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('non-iOS route remains animation-free', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final route = SettingsMaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
      );

      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('regular no-animation route stays animation-free on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final route = NoAnimationMaterialPageRoute<void>(
        builder: (_) => const SizedBox(),
      );

      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
