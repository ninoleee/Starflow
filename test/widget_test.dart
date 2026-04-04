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

    expect(find.text('Starflow'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
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

    expect(find.text('The Last of Us'), findsOneWidget);
    expect(
      find.text('After a global pandemic, survivors keep moving.'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('立即播放'), findsOneWidget);
  });
}
