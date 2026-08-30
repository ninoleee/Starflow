import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_options_dialog.dart';

void main() {
  testWidgets('MPV playback settings omit the live playback information card',
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
    expect(find.text('播放信息'), findsNothing);
    expect(find.text('缓冲进度'), findsNothing);
    expect(find.text('画面'), findsNothing);
    expect(find.text('状态'), findsNothing);
  });
}

class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());
}
