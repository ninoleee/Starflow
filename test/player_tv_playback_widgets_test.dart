import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/presentation/widgets/player_tv_playback_widgets.dart';

void main() {
  testWidgets('TV chrome exposes episode controls with boundary states',
      (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final focusNodes = _focusNodes();
    addTearDown(() {
      for (final node in focusNodes) {
        node.dispose();
      }
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [isTelevisionProvider.overrideWith((ref) => true)],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: PlayerTvPlaybackChrome(
              title: 'Series',
              position: const Duration(minutes: 10),
              duration: const Duration(minutes: 45),
              playing: true,
              bufferingPercentage: 80,
              backFocusNode: focusNodes[0],
              previousEpisodeFocusNode: focusNodes[1],
              playPauseFocusNode: focusNodes[2],
              nextEpisodeFocusNode: focusNodes[3],
              episodePickerFocusNode: focusNodes[4],
              subtitleFocusNode: focusNodes[5],
              audioFocusNode: focusNodes[6],
              moreFocusNode: focusNodes[7],
              onBack: () {},
              showEpisodeControls: true,
              onPreviousEpisode: null,
              onTogglePlayback: () {},
              onNextEpisode: () {},
              onOpenEpisodePicker: () {},
              onOpenSubtitle: () {},
              onOpenAudio: () {},
              onOpenOptions: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final previous = tester.widget<StarflowIconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is StarflowIconButton &&
            widget.icon == Icons.skip_previous_rounded,
      ),
    );
    final next = tester.widget<StarflowIconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is StarflowIconButton &&
            widget.icon == Icons.skip_next_rounded,
      ),
    );
    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNotNull);
    expect(find.byIcon(Icons.playlist_play_rounded), findsOneWidget);
  });

  testWidgets('TV chrome hides episode controls for non-episode content',
      (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final focusNodes = _focusNodes();
    addTearDown(() {
      for (final node in focusNodes) {
        node.dispose();
      }
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [isTelevisionProvider.overrideWith((ref) => true)],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: PlayerTvPlaybackChrome(
              title: 'Movie',
              position: Duration.zero,
              duration: const Duration(hours: 2),
              playing: false,
              bufferingPercentage: 0,
              backFocusNode: focusNodes[0],
              previousEpisodeFocusNode: focusNodes[1],
              playPauseFocusNode: focusNodes[2],
              nextEpisodeFocusNode: focusNodes[3],
              episodePickerFocusNode: focusNodes[4],
              subtitleFocusNode: focusNodes[5],
              audioFocusNode: focusNodes[6],
              moreFocusNode: focusNodes[7],
              onBack: () {},
              showEpisodeControls: false,
              onPreviousEpisode: null,
              onTogglePlayback: () {},
              onNextEpisode: null,
              onOpenEpisodePicker: () {},
              onOpenSubtitle: () {},
              onOpenAudio: () {},
              onOpenOptions: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.skip_previous_rounded), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    expect(find.byIcon(Icons.playlist_play_rounded), findsNothing);
  });
}

List<FocusNode> _focusNodes() {
  return List<FocusNode>.generate(
    8,
    (index) => FocusNode(debugLabel: 'player-tv-test-$index'),
  );
}
