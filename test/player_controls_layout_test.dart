import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/player_controls_layout.dart';

void main() {
  for (final width in [320.0, 844.0]) {
    for (final metricsWidth in [0.0, 60.0, 1000.0]) {
      testWidgets('top actions stay at edges: $width / $metricsWidth',
          (tester) async {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: width,
              height: 56,
              child: PlayerMpvTopBarRow(
                backButton: const SizedBox(key: ValueKey('back'), width: 48),
                title: const Text('A long playback title that can be truncated',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                metrics: SizedBox(
                    key: const ValueKey('metrics'),
                    width: metricsWidth,
                    height: 20),
                format: const SizedBox(key: ValueKey('format'), height: 20),
                actions: const [
                  SizedBox(width: 48),
                  SizedBox(key: ValueKey('more'), width: 48),
                ],
              ),
            ),
          ),
        ));
        final rowRect = tester.getRect(find.byType(PlayerMpvTopBarRow));
        expect(tester.getTopLeft(find.byKey(const ValueKey('back'))).dx,
            rowRect.left);
        expect(tester.getTopRight(find.byKey(const ValueKey('more'))).dx,
            rowRect.right);
        final metrics = tester.getRect(find.byKey(const ValueKey('metrics')));
        final format = tester.getRect(find.byKey(const ValueKey('format')));
        expect(metrics.top, rowRect.top + playbackTopMetricsOffset);
        expect(metrics.top, rowRect.top + 40);
        expect(tester.getRect(find.byType(Text)).bottom,
            lessThanOrEqualTo(metrics.top));
        expect(metrics.right, rowRect.right - 12);
        expect(format.left, rowRect.left + 56);
        expect(format.left, tester.getTopLeft(find.byType(Text)).dx);
        expect(format.right, lessThan(metrics.left));
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('top bar keeps safe area with four pixels of extra side clearance', () {
    expect(
      playbackTopBarPadding(playbackControlsPadding(
        viewport: const Size(844, 390),
        safeArea: const EdgeInsets.fromLTRB(44, 0, 24, 21),
      )),
      const EdgeInsets.fromLTRB(48, 6, 28, 0),
    );
  });

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
