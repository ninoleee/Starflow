import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_overlays.dart';

void main() {
  for (final showSpinner in [true, false]) {
    testWidgets('startup overlay showSpinner=$showSpinner preserves metrics',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerStartupOverlay(
            target: const PlaybackTarget(
              title: 'Episode',
              sourceId: 'nas',
              streamUrl: 'https://example.com/video.mp4',
              sourceName: 'NAS',
              sourceKind: MediaSourceKind.nas,
            ),
            speedLabel: '2 MB/s',
            bufferingProgress: 50,
            showSpinner: showSpinner,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator),
          showSpinner ? findsOneWidget : findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('2 MB/s', findRichText: true), findsOneWidget);
    });
  }
}
