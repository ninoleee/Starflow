import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/player_mpv_controls_sections.dart';

void main() {
  group('Player MPV controls sections contract', () {
    testWidgets('renders lean actions section in lightweight mode',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildUnderTest(leanMode: true),
          ),
        ),
      );

      expect(find.byKey(kPlayerMpvLeanActionsSectionKey), findsOneWidget);
      expect(find.byKey(kPlayerMpvFullActionsSectionKey), findsNothing);
      expect(find.byIcon(Icons.closed_caption_rounded), findsNothing);
      expect(find.byIcon(Icons.audiotrack_rounded), findsNothing);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('renders full actions section in full mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildUnderTest(leanMode: false),
          ),
        ),
      );

      expect(find.byKey(kPlayerMpvLeanActionsSectionKey), findsNothing);
      expect(find.byKey(kPlayerMpvFullActionsSectionKey), findsOneWidget);
      expect(find.byIcon(Icons.closed_caption_rounded), findsOneWidget);
      expect(find.byIcon(Icons.audiotrack_rounded), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    });
  });
}

Widget _buildUnderTest({required bool leanMode}) {
  return Center(
    child: PlayerMpvActionButtonsSection(
      data: PlayerMpvActionButtonsSectionData(
        isFullscreen: false,
        onOpenSubtitle: leanMode ? null : () {},
        onOpenAudio: leanMode ? null : () {},
        onOpenOptions: () {},
        onToggleFullscreen: () {},
        leanMode: leanMode,
        showSubtitleButton: !leanMode,
        showAudioButton: !leanMode,
        showTooltips: false,
        compact: leanMode,
        optionsIcon: leanMode ? Icons.more_horiz_rounded : Icons.tune_rounded,
        optionsTooltip: leanMode ? '更多' : '播放设置',
      ),
    ),
  );
}
