import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/router/home_navigation_tap_coordinator.dart';

void main() {
  testWidgets('distinguishes a single tap from a double tap', (tester) async {
    final coordinator = HomeNavigationTapCoordinator();
    addTearDown(coordinator.dispose);
    var singleTapCount = 0;
    var doubleTapCount = 0;

    void registerTap() {
      coordinator.registerTap(
        onSingleTap: () => singleTapCount += 1,
        onDoubleTap: () => doubleTapCount += 1,
      );
    }

    registerTap();
    await tester.pump(const Duration(milliseconds: 100));
    registerTap();
    await tester.pump(const Duration(milliseconds: 300));

    expect(singleTapCount, 0);
    expect(doubleTapCount, 1);

    registerTap();
    await tester.pump(const Duration(milliseconds: 300));

    expect(singleTapCount, 1);
    expect(doubleTapCount, 1);
  });
}
