import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_hero_section.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

void main() {
  testWidgets('resume action precedes start action and owns primary focus',
      (tester) async {
    final playFocusNode = FocusNode(debugLabel: 'detail-primary-play');
    addTearDown(playFocusNode.dispose);
    const startTarget = PlaybackTarget(
      title: '测试剧',
      sourceId: 'nas-main',
      streamUrl: 'https://media.example.com/start.mkv',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
    );
    const resumeTarget = PlaybackTarget(
      title: '测试剧 第 4 集',
      sourceId: 'nas-main',
      streamUrl: 'https://media.example.com/resume.mkv',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      episodeNumber: 4,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailHeroContent(
            target: const MediaDetailTarget(
              title: '测试剧',
              posterUrl: '',
              overview: '',
              year: 2026,
            ),
            metadata: const [],
            peopleLine: '',
            simplifyVisualEffects: true,
            isTelevision: true,
            startPlaybackTarget: startTarget,
            resumePlaybackTarget: resumeTarget,
            playFocusNode: playFocusNode,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('继续播放')).dx,
      lessThan(tester.getTopLeft(find.text('从头播放')).dx),
    );
    final resumeButton = tester.widget<StarflowButton>(
      find.ancestor(
        of: find.text('继续播放'),
        matching: find.byType(StarflowButton),
      ),
    );
    final startButton = tester.widget<StarflowButton>(
      find.ancestor(
        of: find.text('从头播放'),
        matching: find.byType(StarflowButton),
      ),
    );
    expect(resumeButton.focusNode, same(playFocusNode));
    expect(resumeButton.autofocus, isTrue);
    expect(resumeButton.variant, StarflowButtonVariant.primary);
    expect(startButton.focusNode, isNull);
    expect(startButton.autofocus, isFalse);
    expect(startButton.variant, StarflowButtonVariant.secondary);
  });
}
