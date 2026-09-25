import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_episode_browser.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

Widget _app(String overview,
    {bool isTelevision = false, double textScale = 1}) {
  final episode = MediaItem(
    id: 'episode',
    title: 'Test episode',
    overview: overview,
    posterUrl: '',
    year: 2026,
    durationLabel: '45m',
    genres: const [],
    sourceId: 'test',
    sourceName: 'Test',
    sourceKind: MediaSourceKind.emby,
    streamUrl: 'https://example.com/episode.mp4',
    seasonNumber: 1,
    episodeNumber: 2,
    itemType: 'episode',
    addedAt: DateTime(2026),
  );
  return ProviderScope(
    overrides: [
      isTelevisionProvider.overrideWith((ref) => isTelevision),
      appSettingsProvider.overrideWithValue(const AppSettings(
        mediaSources: [],
        searchProviders: [],
        homeModules: [],
        doubanAccount: DoubanAccountConfig(enabled: false),
      )),
      playbackEntryForMediaItemProvider(episode).overrideWith((ref) => null),
    ],
    child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
        home: Scaffold(
            body: DetailEpisodeBrowser(
          seriesTarget: const MediaDetailTarget(
              title: 'Series', posterUrl: '', overview: '', itemType: 'series'),
          groups: [
            DetailEpisodeGroup(
                id: 'season',
                title: 'Season',
                seasonNumber: 1,
                episodes: [episode])
          ],
          selectedGroupId: 'season',
          onSeasonSelected: (_) {},
        ))),
  );
}

void main() {
  for (final isTelevision in [false, true]) {
    for (final textScale in [1.0, 1.5, 2.0]) {
      testWidgets(
          'three-line summary keeps compact top and normal bottom padding '
          '(TV: $isTelevision, scale: $textScale)', (tester) async {
        const summary = 'First line\nSecond line\nThird line';
        await tester.pumpWidget(_app(
          summary,
          isTelevision: isTelevision,
          textScale: textScale,
        ));
        await tester.pumpAndSettle();

        final summaryFinder = find.text(summary);
        final cardFinder = find.ancestor(
          of: summaryFinder,
          matching: find.byType(TvFocusableAction),
        );
        final summaryRect = tester.getRect(summaryFinder);
        final cardRect = tester.getRect(cardFinder);
        expect(
          cardRect.top - tester.getRect(find.byType(DetailEpisodeBrowser)).top,
          closeTo(14, 0.1),
        );
        final artwork = find.descendant(
          of: cardFinder,
          matching: find.byType(AspectRatio),
        ).first;
        expect(summaryRect.top - tester.getRect(artwork).bottom, closeTo(8, 0.1));
        expect(cardRect.bottom - summaryRect.bottom, closeTo(14, 2));
        expect(summaryRect.height,
            greaterThanOrEqualTo(13 * 1.45 * 3 * textScale - 1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('card caps clean overview at three lines', (tester) async {
    await tester
        .pumpWidget(_app('来源：<a href="https://example.com">编号</a><br/>正文'));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('正文'));
    expect(text.maxLines, 3);
    expect(find.textContaining('编号'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('link-only episode summary falls back to episode details',
      (tester) async {
    await tester
        .pumpWidget(_app('来源：<a href="https://example.com">编号</a><br/>'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 季 第 2 集 · 45m'), findsOneWidget);
    expect(find.textContaining('编号'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
