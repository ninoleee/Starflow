import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_completion_state.dart';
import 'package:starflow/features/playback/application/playback_episode_advance_guard.dart';
import 'package:starflow/features/playback/application/playback_episode_preparation.dart';
import 'package:starflow/features/playback/application/playback_interaction_player.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_controls_layout.dart';

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows
  ]) {
    testWidgets('$platform Adaptive seek cancels advance before backend events',
        (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final guard = PlaybackEpisodeAdvanceGuard();
      final request = guard.begin(key: 'next', automatic: true)!;
      final completion = PlaybackCompletionState()..startMedia('episode');
      completion.markCompletedByAutoSkip();
      final backend = _Backend(() {
        expect(guard.isCurrent(request), isFalse);
        expect(completion.completedByAutoSkip, isFalse);
      });
      final player = PlaybackInteractionPlayer(
        platformPlayer: backend,
        onUserSeek: (_) {
          guard.invalidateAutomaticPending();
          completion.clearForManualSeek();
        },
      );
      final controller = _Controller(player);
      addTearDown(player.dispose);
      addTearDown(controller.notifier.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Video(
          controller: controller,
          wakelock: false,
          subtitleViewConfiguration:
              const SubtitleViewConfiguration(visible: false),
          controls: (state) => PlayerAdaptiveControlsLayout(
            state: state,
            materialThemeBuilder: (_) => const MaterialVideoControlsThemeData(
              visibleOnMount: true,
              primaryButtonBar: [],
              topButtonBar: [],
              bottomButtonBar: [SizedBox(width: 1)],
            ),
            desktopThemeBuilder: (_) =>
                const MaterialDesktopVideoControlsThemeData(
              visibleOnMount: true,
              primaryButtonBar: [],
              topButtonBar: [],
              bottomButtonBar: [SizedBox(width: 1)],
            ),
          ),
        ),
      ));
      await tester.pump();
      final bar = platform == TargetPlatform.windows
          ? find.byType(MaterialDesktopSeekBar)
          : find.byType(MaterialSeekBar);
      final bounds = tester.getRect(bar);
      final point = Offset(bounds.left + bounds.width * .95, bounds.center.dy);
      if (platform == TargetPlatform.windows) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: point);
        await mouse.moveTo(point);
        await tester.pump();
        await mouse.down(point);
        await mouse.up();
        await mouse.removePointer();
      } else {
        await tester.tapAt(point);
      }
      await tester.pump();
      expect(backend.seeks, isNotEmpty);
      expect(backend.seeks.last, greaterThan(const Duration(seconds: 90)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });
  }

  testWidgets(
      'cancelled auto resolver is cached and manual successor owns commit',
      (tester) async {
    final guard = PlaybackEpisodeAdvanceGuard();
    final preparation =
        PlaybackEpisodePreparation(clock: tester.binding.clock.now);
    addTearDown(preparation.reset);
    final pending = Completer<PlaybackTarget>();
    var calls = 0;
    Future<PlaybackTarget> resolve() {
      calls++;
      return pending.future;
    }

    const key = (null, 'session-next');
    final background = preparation.prepare(key: key, resolver: resolve);
    final auto = guard.begin(key: 'next', automatic: true)!;
    final autoResult = preparation.resolve(key: key, resolver: resolve);
    guard.invalidateAutomaticPending();
    final manual = guard.begin(key: 'next', automatic: false)!;
    final manualResult =
        preparation.resolve(key: key, resolver: resolve, retryFailed: true);
    pending.complete(const PlaybackTarget(
        title: 'Next',
        sourceId: 'test',
        sourceName: 'test',
        sourceKind: MediaSourceKind.nas,
        streamUrl: 'https://example.test/next'));
    await background;
    await autoResult;
    expect(guard.commit(auto), isFalse);
    expect(guard.finish(auto), isFalse);
    expect((await manualResult).wasPrepared, isTrue);
    expect(guard.commit(manual), isTrue);
    expect(guard.finish(manual), isTrue);
    expect(calls, 1);
  });
}

class _Backend extends PlatformPlayer {
  _Backend(this.onSeek) : super(configuration: const PlayerConfiguration()) {
    state = state.copyWith(
        duration: const Duration(seconds: 100),
        position: const Duration(seconds: 60));
  }
  final VoidCallback onSeek;
  final seeks = <Duration>[];
  @override
  Future<void> seek(Duration position) async {
    onSeek();
    seeks.add(position);
    state = state.copyWith(position: position);
  }
}

class _Controller extends Fake implements VideoController {
  _Controller(this.player);
  @override
  final Player player;
  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);
}
