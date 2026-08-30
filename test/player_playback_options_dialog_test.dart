import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_options_dialog.dart';

void main() {
  testWidgets(
      'MPV playback settings keep subtitle layout and MPV options under More',
      (tester) async {
    final player = Player(platformPlayer: _FakePlatformPlayer());
    addTearDown(player.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: PlaybackOptionsDialog(
            player: player,
            target: const PlaybackTarget(
              title: 'Episode',
              sourceId: 'nas-main',
              streamUrl: 'https://media.example.com/episode.mp4',
              sourceName: 'NAS',
              sourceKind: MediaSourceKind.nas,
              itemType: 'episode',
            ),
            isTelevision: false,
            subtitleDelayLabel: '0s',
            seriesSkipLabel: '未设置',
            onSelectSubtitle: (tracks, current) async {},
            onSelectAudio: (tracks, current) async {},
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
              secondarySubtitleScale: 75,
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

class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());
}
