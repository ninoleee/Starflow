import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/player_controls_layout.dart';

void main() {
  for (final viewport in [const Size(844, 390), const Size(390, 844)]) {
    testWidgets('ordinary surface fills $viewport for all video ratios',
        (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final ratio in [4 / 3, 16 / 9, 2.35]) {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: PlayerEmbeddedSurface(
            isTelevision: false,
            aspectRatio: ratio,
            child: const SizedBox(key: ValueKey('video')),
          ),
        ));
        expect(tester.getSize(find.byKey(const ValueKey('video'))), viewport);
        expect(tester.getTopLeft(find.byKey(const ValueKey('video'))),
            Offset.zero);
      }
    });
  }

  testWidgets('TV retains centered video ratio container', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: PlayerEmbeddedSurface(
        isTelevision: true,
        aspectRatio: 2,
        child: SizedBox(key: ValueKey('video')),
      ),
    ));
    expect(tester.getSize(find.byKey(const ValueKey('video'))),
        const Size(800, 400));
    expect(tester.getTopLeft(find.byKey(const ValueKey('video'))),
        const Offset(0, 100));
  });

  test('seek bar adds spacing only below the track', () {
    expect(playbackSeekBarMargin, const EdgeInsets.only(bottom: 6));
  });
  const safeArea = EdgeInsets.fromLTRB(24, 44, 12, 21);

  test('portrait adds 12 horizontal and 6 vertical pixels inside the safe area',
      () {
    expect(
      playbackControlsPadding(
          viewport: const Size(390, 844), safeArea: safeArea),
      const EdgeInsets.fromLTRB(36, 50, 24, 27),
    );
  });

  test(
      'landscape adds 12 horizontal and 6 vertical pixels inside the safe area',
      () {
    expect(
      playbackControlsPadding(
          viewport: const Size(844, 390), safeArea: safeArea),
      const EdgeInsets.fromLTRB(36, 50, 24, 27),
    );
  });

  test(
      'fullscreen without system insets keeps horizontal and vertical clearance',
      () {
    expect(
      playbackControlsPadding(
          viewport: const Size(1920, 1080), safeArea: EdgeInsets.zero),
      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
    expect(
      playbackControlsPadding(
          viewport: const Size(390, 844), safeArea: EdgeInsets.zero),
      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  });

  test('square viewport uses the landscape rule', () {
    expect(
      playbackControlsPadding(
          viewport: const Size(600, 600), safeArea: EdgeInsets.zero),
      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  });
}
