// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/media_detail_page.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

import 'package:starflow/app/app.dart';

void main() {
  testWidgets('renders Starflow shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StarflowApp()));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('正在唤醒你的片库'), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('renders media detail content', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: 'The Last of Us',
              posterUrl: '',
              overview: 'After a global pandemic, survivors keep moving.',
              year: 2023,
              durationLabel: '1h 20m',
              ratingLabels: ['IMDb 8.7'],
              genres: ['Drama'],
              directors: ['Craig Mazin'],
              actors: ['Pedro Pascal'],
              availabilityLabel: '资源已就绪：Emby · Home Emby',
              searchQuery: 'The Last of Us',
              playbackTarget: PlaybackTarget(
                title: 'The Last of Us',
                sourceId: 'emby-main',
                streamUrl: 'https://example.com/video.mp4',
                sourceName: 'Home Emby',
                sourceKind: MediaSourceKind.emby,
              ),
              itemId: 'series-1',
              sourceId: 'emby-main',
              itemType: 'Movie',
              sourceKind: MediaSourceKind.emby,
              sourceName: 'Home Emby',
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('The Last of Us'), findsAtLeastNWidgets(1));
    expect(
      find.text('After a global pandemic, survivors keep moving.'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('IMDb 8.7'), findsOneWidget);
    expect(find.text('立即播放'), findsOneWidget);
  });

  testWidgets('episode detail overview heading prefers episode title',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaDetailPage(
            target: const MediaDetailTarget(
              title: '第1集 风暴前夜',
              posterUrl: '',
              overview: '这一集讲述主角行动前夜的准备与冲突。',
              year: 2026,
              durationLabel: '48m',
              availabilityLabel: '资源已就绪：WebDAV · NAS',
              searchQuery: '测试剧',
              playbackTarget: PlaybackTarget(
                title: '第1集 风暴前夜',
                sourceId: 'nas-main',
                streamUrl: 'https://example.com/show-s01e01.mp4',
                sourceName: 'NAS',
                sourceKind: MediaSourceKind.nas,
                itemType: 'episode',
                seriesTitle: '测试剧',
                seasonNumber: 1,
                episodeNumber: 1,
              ),
              itemId: 'episode-1',
              sourceId: 'nas-main',
              itemType: 'episode',
              seasonNumber: 1,
              episodeNumber: 1,
              sourceKind: MediaSourceKind.nas,
              sourceName: 'NAS',
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('测试剧'), findsNothing);
    expect(find.text('第1集 风暴前夜'), findsAtLeastNWidgets(2));
    expect(find.text('这一集讲述主角行动前夜的准备与冲突。'), findsOneWidget);
  });
}
