import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:starflow/features/playback/presentation/widgets/player_controls_layout.dart';

const _topBarKey = Key('adaptive-top-bar');
const _bottomBarKey = Key('adaptive-bottom-bar');
const _primaryBarKey = Key('adaptive-primary-bar');
const _captureKey = Key('adaptive-controls-capture');

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets('$platform updates control insets after rotation',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      _setMetrics(
        tester,
        const Size(390, 844),
        const FakeViewPadding(top: 59, bottom: 34),
      );
      addTearDown(tester.view.reset);

      final player = Player(platformPlayer: _FakePlatformPlayer());
      final controller = _FakeVideoController(player);
      addTearDown(player.dispose);
      addTearDown(controller.notifier.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Video(
          controller: controller,
          wakelock: false,
          subtitleViewConfiguration:
              const SubtitleViewConfiguration(visible: false),
          controls: _buildControls,
        ),
      ));
      await tester.pump();

      _expectControlEdges(tester, const Rect.fromLTRB(12, 65, 378, 804));
      _expectBackdropBounds(tester, platform, const Size(390, 844));
      final topBar = tester.element(find.byKey(_topBarKey));
      final videoState = tester.state<VideoState>(find.byType(Video));

      _setMetrics(
        tester,
        const Size(844, 390),
        const FakeViewPadding(left: 59, right: 59, bottom: 21),
      );
      await tester.pump();
      await tester.pump();

      _expectControlEdges(tester, const Rect.fromLTRB(71, 6, 773, 363));
      _expectBackdropBounds(tester, platform, const Size(844, 390));
      expect(tester.element(find.byKey(_topBarKey)), same(topBar));
      expect(tester.state<VideoState>(find.byType(Video)), same(videoState));

      _setMetrics(
        tester,
        const Size(844, 390),
        const FakeViewPadding(left: 59, bottom: 21),
      );
      await tester.pump();
      _expectControlEdges(tester, const Rect.fromLTRB(71, 6, 832, 363));
      _expectBackdropBounds(tester, platform, const Size(844, 390));

      _setMetrics(
        tester,
        const Size(844, 390),
        const FakeViewPadding(top: 24, bottom: 21),
      );
      await tester.pump();
      _expectControlEdges(tester, const Rect.fromLTRB(12, 30, 832, 363));
      _expectBackdropBounds(tester, platform, const Size(844, 390));

      _setMetrics(tester, const Size(844, 390), const FakeViewPadding());
      await tester.pump();
      _expectControlEdges(tester, const Rect.fromLTRB(12, 6, 832, 384));
      _expectBackdropBounds(tester, platform, const Size(844, 390));

      _setMetrics(
        tester,
        const Size(390, 844),
        const FakeViewPadding(top: 59, bottom: 34),
      );
      await tester.pump();
      _expectControlEdges(tester, const Rect.fromLTRB(12, 65, 378, 804));
      _expectBackdropBounds(tester, platform, const Size(390, 844));
      expect(tester.element(find.byKey(_topBarKey)), same(topBar));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('$platform uses current insets on fullscreen entry and exit',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      _setMetrics(
        tester,
        const Size(844, 390),
        const FakeViewPadding(top: 24, bottom: 21),
      );
      addTearDown(tester.view.reset);

      final player = Player(platformPlayer: _FakePlatformPlayer());
      final controller = _FakeVideoController(player);
      addTearDown(player.dispose);
      addTearDown(controller.notifier.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Video(
          controller: controller,
          wakelock: false,
          onEnterFullscreen: () async {},
          onExitFullscreen: () async {},
          subtitleViewConfiguration:
              const SubtitleViewConfiguration(visible: false),
          controls: _buildControls,
        ),
      ));
      await tester.pump();

      _expectControlEdges(tester, const Rect.fromLTRB(12, 30, 832, 363));
      _expectBackdropBounds(tester, platform, const Size(844, 390));
      final videoState = tester.state<VideoState>(find.byType(Video));
      await videoState.enterFullscreen();
      await tester.pump();
      _setMetrics(tester, const Size(844, 390), const FakeViewPadding());
      await tester.pump();

      expect(videoState.isFullscreen(), isTrue);
      _expectControlEdges(tester, const Rect.fromLTRB(12, 6, 832, 384));
      _expectBackdropBounds(tester, platform, const Size(844, 390));

      await videoState.exitFullscreen();
      await tester.pump();
      _setMetrics(
        tester,
        const Size(844, 390),
        const FakeViewPadding(top: 24, bottom: 21),
      );
      await tester.pump();
      await tester.pump();

      expect(videoState.isFullscreen(), isFalse);
      _expectControlEdges(tester, const Rect.fromLTRB(12, 30, 832, 363));
      _expectBackdropBounds(tester, platform, const Size(844, 390));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('$platform keeps controls hidden when insets change',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      _setMetrics(
        tester,
        const Size(390, 844),
        const FakeViewPadding(top: 59, bottom: 34),
      );
      addTearDown(tester.view.reset);

      final player = Player(platformPlayer: _FakePlatformPlayer());
      final controller = _FakeVideoController(player);
      addTearDown(player.dispose);
      addTearDown(controller.notifier.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Video(
          controller: controller,
          wakelock: false,
          subtitleViewConfiguration:
              const SubtitleViewConfiguration(visible: false),
          controls: _buildControls,
        ),
      ));
      await tester.pump();
      expect(find.byKey(_topBarKey), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byKey(_topBarKey), findsNothing);

      _setMetrics(
        tester,
        const Size(844, 390),
        const FakeViewPadding(left: 59, right: 59, bottom: 21),
      );
      await tester.pump();
      expect(find.byKey(_topBarKey), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$platform paints the backdrop to all edges and hides it',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      _setMetrics(
        tester,
        const Size(844, 390),
        const FakeViewPadding(left: 59, right: 59, bottom: 21),
      );
      addTearDown(tester.view.reset);
      final player = Player(platformPlayer: _FakePlatformPlayer());
      final controller = _FakeVideoController(player);
      addTearDown(player.dispose);
      addTearDown(controller.notifier.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Video(
          controller: controller,
          wakelock: false,
          subtitleViewConfiguration:
              const SubtitleViewConfiguration(visible: false),
          controls: (state) => RepaintBoundary(
            key: _captureKey,
            child: ColoredBox(
              color: Colors.white,
              child: _buildControls(state),
            ),
          ),
        ),
      ));
      await tester.pump();

      final mobile = platform != TargetPlatform.windows;
      await _expectEdgePixels(tester, mobile ? 204 : 158);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await _expectEdgePixels(tester, 255);
      expect(find.byKey(_topBarKey), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform keeps edge gestures and hidden seek bar insets',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      _setMetrics(
        tester,
        const Size(844, 390),
        const FakeViewPadding(left: 59, right: 59, bottom: 21),
      );
      addTearDown(tester.view.reset);
      final backend = _FakePlatformPlayer();
      backend.state = backend.state.copyWith(
        duration: const Duration(minutes: 10),
        position: const Duration(minutes: 2),
      );
      final player = Player(platformPlayer: backend);
      final controller = _FakeVideoController(player);
      addTearDown(player.dispose);
      addTearDown(controller.notifier.dispose);
      final brightnessValues = <double>[];
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Video(
          controller: controller,
          wakelock: false,
          subtitleViewConfiguration:
              const SubtitleViewConfiguration(visible: false),
          controls: (state) => _buildControls(
            state,
            onBrightnessChanged: brightnessValues.add,
          ),
        ),
      ));
      await tester.pump();

      // The upstream 16px system-gesture exclusion remains intact.
      await tester.dragFrom(const Offset(8, 190), const Offset(0, -60));
      expect(brightnessValues, isEmpty);
      // x=30 lies outside the inset buttons but inside the gesture surface.
      await tester.dragFrom(const Offset(30, 190), const Offset(0, -60));
      expect(brightnessValues, isNotEmpty);
      expect(brightnessValues.last, greaterThan(0.5));

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byKey(_topBarKey), findsNothing);
      await tester.tapAt(const Offset(420, 190));
      await tester.pump(const Duration(milliseconds: 400));
      // media_kit toggles visibility on pointer-down, before drag recognition.
      final gesture = await tester.startGesture(const Offset(30, 190));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      _expectSeekBarEdges(tester, const Rect.fromLTRB(71, 6, 773, 363));
      expect(find.byKey(_topBarKey), findsNothing);
      await gesture.up();
      expect(backend.seeks, isNotEmpty);
      expect(backend.seeks.last, greaterThan(const Duration(minutes: 2)));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });
  }
}

void _setMetrics(WidgetTester tester, Size size, FakeViewPadding insets) {
  tester.view.physicalSize = size;
  tester.view.viewPadding = insets;
  tester.view.padding = insets;
}

void _expectControlEdges(WidgetTester tester, Rect bounds) {
  final topBar = tester.getRect(find.byKey(_topBarKey));
  final bottomBar = tester.getRect(find.byKey(_bottomBarKey));
  expect(topBar.topLeft, bounds.topLeft);
  expect(topBar.topRight, bounds.topRight);
  expect(bottomBar.bottomLeft, bounds.bottomLeft);
  expect(bottomBar.bottomRight, bounds.bottomRight);
  expect(topBar.height, playbackButtonBarHeight);
  expect(bottomBar.height, playbackButtonBarHeight);
  final primary = find.byKey(_primaryBarKey);
  if (primary.evaluate().isNotEmpty) {
    expect(tester.getCenter(primary), bounds.center);
  }
  _expectSeekBarEdges(tester, bounds);
}

void _expectSeekBarEdges(WidgetTester tester, Rect bounds) {
  final mobile = find.byType(MaterialSeekBar).evaluate().isNotEmpty;
  final seekBar = mobile
      ? find.byType(MaterialSeekBar)
      : find.byType(MaterialDesktopSeekBar);
  final track = find.descendant(
    of: seekBar,
    matching: find.byType(LayoutBuilder),
  );
  expect(track, findsOneWidget);
  final rect = tester.getRect(track);
  expect(rect.left, bounds.left);
  expect(rect.right, bounds.right);
  expect(
    rect.bottom,
    mobile
        ? bounds.bottom - playbackSeekBarMargin.bottom
        : bounds.bottom -
            playbackButtonBarHeight +
            16 -
            playbackSeekBarMargin.bottom,
  );
}

void _expectBackdropBounds(
  WidgetTester tester,
  TargetPlatform platform,
  Size size,
) {
  final mobile =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  final backdrop = find.byWidgetPredicate((widget) {
    if (widget is! Container) return false;
    if (mobile) return widget.color == const Color(0x33000000);
    final decoration = widget.decoration;
    return decoration is BoxDecoration && decoration.gradient != null;
  });
  expect(backdrop, mobile ? findsOneWidget : findsNWidgets(2));
  for (final element in backdrop.evaluate()) {
    expect(tester.getRect(find.byWidget(element.widget)), Offset.zero & size);
  }
}

Future<void> _expectEdgePixels(WidgetTester tester, int expected) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (final point in [
        const Offset(0, 0),
        Offset(image.width - 1, 0),
        Offset(0, image.height - 1),
        Offset(image.width - 1, image.height - 1),
      ]) {
        final offset = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
        for (var channel = 0; channel < 3; channel++) {
          expect(pixels.getUint8(offset + channel), closeTo(expected, 1));
        }
        expect(pixels.getUint8(offset + 3), 255);
      }
    } finally {
      image.dispose();
    }
  });
}

Widget _buildControls(
  VideoState state, {
  ValueChanged<double>? onBrightnessChanged,
}) {
  return PlayerAdaptiveControlsLayout(
    state: state,
    materialThemeBuilder: (padding) => MaterialVideoControlsThemeData(
      backdropColor: const Color(0x33000000),
      padding: EdgeInsets.zero,
      visibleOnMount: true,
      volumeGesture: false,
      brightnessGesture: onBrightnessChanged != null,
      onBrightnessChanged: onBrightnessChanged,
      initialBrightness: 0.5,
      seekGesture: true,
      gesturesEnabledWhileControlsVisible: true,
      buttonBarHeight: playbackButtonBarHeight,
      topButtonBarMargin: padding.copyWith(bottom: 0),
      bottomButtonBarMargin: padding.copyWith(top: 0),
      seekBarMargin: padding.copyWith(top: 0) + playbackSeekBarMargin,
      primaryButtonBar: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: padding.left, right: padding.right),
            child: const Row(children: [
              Spacer(),
              SizedBox(key: _primaryBarKey, width: 48, height: 48),
              Spacer(),
            ]),
          ),
        ),
      ],
      topButtonBar: const [
        Expanded(child: SizedBox(key: _topBarKey, height: 56))
      ],
      bottomButtonBar: const [
        Expanded(child: SizedBox(key: _bottomBarKey, height: 56)),
      ],
    ),
    desktopThemeBuilder: (padding) => MaterialDesktopVideoControlsThemeData(
      padding: EdgeInsets.zero,
      visibleOnMount: true,
      buttonBarHeight: playbackButtonBarHeight,
      topButtonBarMargin: padding.copyWith(bottom: 0),
      bottomButtonBarMargin: padding.copyWith(top: 0),
      seekBarMargin: EdgeInsets.only(left: padding.left, right: padding.right) +
          playbackSeekBarMargin,
      primaryButtonBar: const [],
      topButtonBar: const [
        Expanded(child: SizedBox(key: _topBarKey, height: 56))
      ],
      bottomButtonBar: const [
        Expanded(child: SizedBox(key: _bottomBarKey, height: 56)),
      ],
    ),
  );
}

class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());

  final seeks = <Duration>[];

  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
  }
}

class _FakeVideoController extends Fake implements VideoController {
  _FakeVideoController(this.player);

  @override
  final Player player;

  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
}
