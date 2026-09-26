import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_overlays.dart';
import 'package:starflow/features/playback/presentation/widgets/player_playback_formatters.dart';

void main() {
  for (final showSpinner in [true, false]) {
    testWidgets('MPV overlay has no metrics or bar ($showSpinner)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PlayerStartupOverlay(
          target: const PlaybackTarget(
            title: 'Episode',
            sourceId: 'nas',
            streamUrl: 'https://example.com/video.mp4',
            sourceName: 'NAS',
            sourceKind: MediaSourceKind.nas,
          ),
          showMetrics: false,
          showSpinner: showSpinner,
        ),
      ));
      expect(find.byType(Text), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator),
          showSpinner ? findsOneWidget : findsNothing);
    });
  }

  for (final showSpinner in [true, false]) {
    testWidgets(
        'MPV overlay hides metrics and preserves progress ($showSpinner)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PlayerStartupOverlay(
          target: const PlaybackTarget(
            title: 'Episode',
            sourceId: 'nas',
            streamUrl: 'https://example.com/video.mp4',
            sourceName: 'NAS',
            sourceKind: MediaSourceKind.nas,
          ),
          networkSpeed: const Text('1.0 KB/s'),
          showMetrics: false,
          bufferingProgress: 50,
          showSpinner: showSpinner,
        ),
      ));
      expect(find.byType(Text), findsNothing);
      expect(find.byType(CircularProgressIndicator),
          showSpinner ? findsOneWidget : findsNothing);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          0.5);
    });
  }

  test('startup format omits source container and bitrate', () {
    expect(
        buildPlaybackStartupFormatValue(const PlaybackTarget(
          title: 'Video',
          sourceId: 'nas',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
          streamUrl: 'https://example.com/v.mkv',
          container: 'mkv',
          videoCodec: 'hevc',
          audioCodec: 'aac',
          width: 1920,
          height: 1080,
          bitrate: 8000000,
        )),
        '1920x1080 · HEVC · AAC');
  });
  testWidgets('startup without a player shows unknown instead of cached speed',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PlayerStartupOverlay(
        target: PlaybackTarget(
          title: 'Episode',
          sourceId: 'nas',
          streamUrl: 'https://example.com/video.mp4',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
        ),
        showSpinner: false,
      ),
    ));
    expect(find.textContaining('--', findRichText: true), findsOneWidget);
  });

  testWidgets('startup accepts the current session speed widget',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PlayerStartupOverlay(
        target: PlaybackTarget(
          title: 'Episode',
          sourceId: 'nas',
          streamUrl: 'https://example.com/video.mp4',
          sourceName: 'NAS',
          sourceKind: MediaSourceKind.nas,
        ),
        speedLabel: 'historical value',
        networkSpeed: Text('1.0 KB/s'),
        showSpinner: false,
      ),
    ));
    expect(find.text('1.0 KB/s'), findsOneWidget);
    expect(find.textContaining('格式', findRichText: true), findsNothing);
    expect(find.textContaining('historical value', findRichText: true),
        findsNothing);
  });

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
