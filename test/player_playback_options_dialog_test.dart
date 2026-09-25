import 'package:flutter/material.dart';
import 'package:starflow/features/playback/presentation/widgets/player_menu_style.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_options_dialog.dart';

void main() {
  testWidgets('TV playback dialogs use remote-focusable close buttons',
      (tester) async {
    final player = Player(platformPlayer: _FakePlatformPlayer());
    var versionSelections = 0;
    addTearDown(player.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWithValue(const AsyncData(true))
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(builder: (context) {
          return TextButton(
            child: const Text('Open'),
            onPressed: () => showPlaybackMenuDialog<void>(
              context: context,
              builder: (context) => PlaybackOptionsDialog(
                player: player,
                target: const PlaybackTarget(
                  title: 'Episode',
                  sourceId: 'nas',
                  streamUrl: '',
                  sourceName: 'NAS',
                  sourceKind: MediaSourceKind.nas,
                ),
                isTelevision: true,
                subtitleDelayLabel: '0s',
                seriesSkipLabel: 'Off',
                onSelectSubtitle: (tracks, current) async {},
                onSelectAudio: (tracks, current) async {},
                onAdjustSubtitleDelay: () async {},
                onLoadExternalSubtitle: () async {},
                onSearchSubtitlesOnline: () async {},
                onConfigureSeriesSkip: () async {},
                onSelectVersion: () async {
                  versionSelections++;
                },
                runtimeSettings: const PlaybackMpvRuntimeSettings(
                  backgroundPlaybackEnabled: true,
                  doubleTapToSeekEnabled: true,
                  swipeToSeekEnabled: true,
                  longPressSpeedBoostEnabled: true,
                  stallAutoRecoveryEnabled: true,
                  aggressiveTuningEnabled: false,
                  subtitleScale: 32,
                  primarySubtitlePosition: 80,
                  secondarySubtitlePosition: 90,
                  secondarySubtitleScale: 50,
                ),
                onApplyRuntimeSettings: (settings) async {},
              ),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    Future<void> select(Finder button) async {
      tester
          .widget<FocusableActionDetector>(find.descendant(
            of: button,
            matching: find.byType(FocusableActionDetector),
          ))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }

    Future<void> closeDialog() async {
      final theme = Theme.of(tester.element(find.byType(AlertDialog).last));
      expect(theme.dialogTheme.backgroundColor, playbackMenuBackground);
      expect(theme.dialogTheme.elevation, 0);
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
      final close = find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.widgetWithText(StarflowButton, '关闭'),
      );
      expect(close, findsOneWidget);
      expect(tester.widget<StarflowButton>(close).variant,
          StarflowButtonVariant.ghost);
      await select(close);
    }

    await select(find.widgetWithText(StarflowSelectionTile, '播放版本'));
    expect(versionSelections, 1);
    for (final title in ['字幕', '更多']) {
      await select(find.widgetWithText(StarflowSelectionTile, title));
      await closeDialog();
      expect(find.text('播放设置'), findsOneWidget);
    }
    await closeDialog();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in ['other', 'empty', 'grouped']) {
    final fntv = mode != 'other';
    testWidgets(
        'MPV playback settings keep subtitle layout and MPV options under More ($mode)',
        (tester) async {
      final player = Player(platformPlayer: _FakePlatformPlayer());
      addTearDown(player.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: PlaybackOptionsDialog(
              player: player,
              target: PlaybackTarget(
                title: 'Episode',
                sourceId: 'nas-main',
                streamUrl: 'https://media.example.com/episode.mp4',
                sourceName: 'NAS',
                sourceKind: fntv ? MediaSourceKind.fntv : MediaSourceKind.nas,
                itemType: 'episode',
                preferredPlaybackQualityIndex: 0,
                playbackQualities: mode != 'grouped'
                    ? const []
                    : const [
                        FntvPlaybackQuality(index: 0, resolution: '原画'),
                        FntvPlaybackQuality(
                            index: -1,
                            resolution: '1080',
                            bitrate: 8000000,
                            serverTranscode: true),
                        FntvPlaybackQuality(
                            index: -2,
                            resolution: '1080P',
                            bitrate: 4000000,
                            serverTranscode: true),
                      ],
              ),
              isTelevision: false,
              subtitleDelayLabel: '0s',
              seriesSkipLabel: '未设置',
              onSelectSubtitle: (tracks, current) async {},
              onSelectAudio: (tracks, current) async {},
              onSelectQuality: (quality) async {},
              onAdjustSubtitleDelay: () async {},
              onLoadExternalSubtitle: () async {},
              onSearchSubtitlesOnline: () async {},
              onConfigureSeriesSkip: () async {},
              runtimeSettings: const PlaybackMpvRuntimeSettings(
                backgroundPlaybackEnabled: true,
                doubleTapToSeekEnabled: true,
                swipeToSeekEnabled: true,
                longPressSpeedBoostEnabled: true,
                stallAutoRecoveryEnabled: true,
                aggressiveTuningEnabled: false,
                subtitleScale: 32,
                primarySubtitlePosition: 80,
                secondarySubtitlePosition: 90,
                secondarySubtitleScale: 50,
              ),
              onApplyRuntimeSettings: (settings) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('速度'), findsOneWidget);
      expect(find.text('循环播放'), findsOneWidget);
      expect(find.text('字幕'), findsOneWidget);
      expect(find.text('音轨'), findsOneWidget);
      if (fntv) {
        await tester.scrollUntilVisible(find.text('画质'), 150,
            scrollable: find.byType(Scrollable).first);
        if (mode == 'empty') expect(find.text('未返回可切换画质'), findsOneWidget);
        await tester.tap(find.text('画质'));
        await tester.pumpAndSettle();
        if (mode == 'empty') {
          expect(find.text('飞牛未返回可切换画质'), findsOneWidget);
          await tester.tap(find.text('关闭').last);
        } else {
          expect(find.text('1080P'), findsOneWidget);
          expect(find.textContaining('Mbps'), findsNothing);
          await tester.tap(find.text('自定义'));
          await tester.pumpAndSettle();
          expect(find.text('自定义画质'), findsOneWidget);
          expect(find.text('1080P · 8.0 Mbps'), findsOneWidget);
          expect(find.text('1080P · 4.0 Mbps'), findsOneWidget);
          Navigator.of(tester.element(find.text('自定义画质'))).pop();
        }
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(
        find.text('本剧跳过片头片尾'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('本剧跳过片头片尾'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('更多'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('更多'), findsOneWidget);
      expect(find.text('字幕布局'), findsNothing);
      expect(find.text('主字幕大小'), findsNothing);
      expect(find.text('后台播放'), findsNothing);
      expect(find.text('双击快进/快退'), findsNothing);
      expect(find.text('播放信息'), findsNothing);
      expect(find.text('缓冲进度'), findsNothing);
      expect(find.text('画面'), findsNothing);
      expect(find.text('状态'), findsNothing);

      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();

      expect(find.text('字幕布局'), findsOneWidget);
      expect(find.text('主字幕大小'), findsOneWidget);
      expect(find.text('主字幕位置'), findsOneWidget);
      expect(find.text('副字幕位置'), findsOneWidget);
      expect(find.text('副字幕大小'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('MPV'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('MPV'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('后台播放'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('后台播放'), findsOneWidget);
      expect(find.text('双击快进/快退'), findsOneWidget);
    });
  }
}

class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());
}
