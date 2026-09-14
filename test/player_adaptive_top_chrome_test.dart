import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/player_adaptive_top_chrome.dart';

void main() {
  group('PlayerAdaptiveTopChrome', () {
    for (final insets in [
      EdgeInsets.zero,
      const EdgeInsets.fromLTRB(24, 44, 12, 21)
    ]) {
      testWidgets(
          'top bar adds 12 side and 6 top pixels inside view insets $insets',
          (tester) async {
        final controller =
            PlayerAdaptiveTopChromeController(autoHideEnabled: false);
        addTearDown(controller.dispose);
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data:
                MediaQueryData(size: const Size(800, 600), viewPadding: insets),
            child: Material(
              child: PlayerAdaptiveTopChrome(
                controller: controller,
                onBack: () {},
                onMore: () {},
              ),
            ),
          ),
        ));
        final row = find.descendant(
          of: find.byType(PlayerAdaptiveTopChrome),
          matching: find.byType(Row),
        );
        expect(
            tester.getTopLeft(row), Offset(insets.left + 12, insets.top + 6));
        expect(tester.getSize(row), Size(800 - insets.horizontal - 24, 56));
        expect(
            tester
                .getCenter(find.byKey(kPlayerAdaptiveTopChromeBackButtonKey))
                .dy,
            insets.top + 34);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders back and more buttons', (tester) async {
      final controller = PlayerAdaptiveTopChromeController(
        autoHideEnabled: false,
      );
      await tester.pumpWidget(
        _buildUnderTest(
          controller: controller,
          onBack: () {},
          onMore: () {},
        ),
      );

      expect(find.byKey(kPlayerAdaptiveTopChromeBackButtonKey), findsOneWidget);
      expect(find.byKey(kPlayerAdaptiveTopChromeMoreButtonKey), findsOneWidget);
      expect(_overlayOpacity(tester), 1);
    });

    testWidgets('auto hides after delay', (tester) async {
      final controller = PlayerAdaptiveTopChromeController(
        autoHideEnabled: true,
        autoHideDelay: const Duration(milliseconds: 120),
      );
      await tester.pumpWidget(
        _buildUnderTest(
          controller: controller,
          onBack: () {},
          onMore: () {},
        ),
      );

      expect(_overlayOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.visible, isFalse);
      expect(_overlayOpacity(tester), 0);
    });

    testWidgets('activity ping wakes chrome and restarts auto hide', (
      tester,
    ) async {
      final controller = PlayerAdaptiveTopChromeController(
        autoHideEnabled: true,
        autoHideDelay: const Duration(milliseconds: 120),
      );
      await tester.pumpWidget(
        _buildUnderTest(
          controller: controller,
          onBack: () {},
          onMore: () {},
        ),
      );

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_overlayOpacity(tester), 0);

      controller.pingActivity();
      await tester.pump();
      expect(controller.visible, isTrue);
      expect(_overlayOpacity(tester), 1);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_overlayOpacity(tester), 0);
    });

    testWidgets('forwards back and more callbacks', (tester) async {
      final controller = PlayerAdaptiveTopChromeController(
        autoHideEnabled: false,
      );
      var backTapped = 0;
      var moreTapped = 0;
      await tester.pumpWidget(
        _buildUnderTest(
          controller: controller,
          onBack: () => backTapped += 1,
          onMore: () => moreTapped += 1,
        ),
      );

      await tester.tap(find.byKey(kPlayerAdaptiveTopChromeBackButtonKey));
      await tester.pump();
      await tester.tap(find.byKey(kPlayerAdaptiveTopChromeMoreButtonKey));
      await tester.pump();

      expect(backTapped, 1);
      expect(moreTapped, 1);
    });
  });
}

Widget _buildUnderTest({
  required PlayerAdaptiveTopChromeController controller,
  required VoidCallback onBack,
  VoidCallback? onMore,
}) {
  return MaterialApp(
    home: Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const SizedBox.expand(),
          PlayerAdaptiveTopChrome(
            controller: controller,
            onBack: onBack,
            onMore: onMore,
          ),
        ],
      ),
    ),
  );
}

double _overlayOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(
        find.byKey(kPlayerAdaptiveTopChromeRootKey),
      )
      .opacity;
}
