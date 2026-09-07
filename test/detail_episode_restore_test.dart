import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/details/presentation/widgets/detail_episode_browser.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

MediaItem item(String id, String type, int season, [int? episode]) => MediaItem(
      id: id,
      title: id,
      overview: '',
      posterUrl: '',
      year: 2026,
      durationLabel: '',
      genres: const [],
      sourceId: 'nas',
      sourceName: 'NAS',
      sourceKind: MediaSourceKind.nas,
      itemType: type,
      seasonNumber: season,
      episodeNumber: episode,
      streamUrl: 'https://example.com/$id',
      addedAt: DateTime(2026),
    );

const series = MediaDetailTarget(
    title: 'Series',
    posterUrl: '',
    overview: '',
    sourceId: 'nas',
    itemId: 'series',
    itemType: 'series');

void main() {
  setUp(() => activePlaybackLaunchInProgress.value = false);
  tearDown(() => activePlaybackLaunchInProgress.value = false);

  for (final tv in [false, true]) {
    testWidgets('last played marker follows matching history (TV: $tv)',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(tv ? 1280 : 390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final episode = item('e1', 'episode', 1, 1);
      for (final hasHistory in [true, false]) {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
            isTelevisionProvider.overrideWith((ref) => tv),
            playbackMemorySnapshotProvider.overrideWith(
                (ref) async => const PlaybackMemorySnapshot()),
          ],
          child: MaterialApp(home: Scaffold(body: DetailEpisodeBrowser(
            seriesTarget: series,
            groups: [DetailEpisodeGroup(
              id: 's1', title: 'Season 1', seasonNumber: 1,
              episodes: [episode],
            )],
            selectedGroupId: 's1',
            lastPlayedTarget: hasHistory
                ? PlaybackTarget.fromMediaItem(episode) : null,
            onSeasonSelected: (_) {},
          ))),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Last Played'), hasHistory ? findsOneWidget : findsNothing);
        expect(find.byIcon(Icons.history_rounded),
            hasHistory ? findsOneWidget : findsNothing);
        expect(tester.getSize(find.byType(DetailEpisodeBrowser)).height, 292);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('selected season tab expands for its checkmark', (tester) async {
    var selected = 's1';
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
        isTelevisionProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: StatefulBuilder(
        builder: (context, setState) => DetailEpisodeBrowser(
          seriesTarget: series,
          groups: const [
            DetailEpisodeGroup(
                id: 's1', title: 'Season 1', seasonNumber: 1, episodes: []),
            DetailEpisodeGroup(
                id: 's2', title: 'Season 2', seasonNumber: 2, episodes: []),
          ],
          selectedGroupId: selected,
          onSeasonSelected: (value) => setState(() => selected = value),
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    final second = find.widgetWithText(StarflowChipButton, '第 2 季');
    final before = tester.getSize(second).width;
    final bounds = tester.getRect(second);
    final labelBounds = tester.getRect(find.text('第 2 季'));
    expect(labelBounds.left - bounds.left,
        closeTo(bounds.right - labelBounds.right, 0.1));
    await tester.tap(find.text('第 2 季'));
    await tester.pumpAndSettle();
    expect(tester.getSize(second).width, greaterThan(before));
    expect(selected, 's2');
    final selectedBounds = tester.getRect(second);
    final iconBounds = tester.getRect(find.descendant(
      of: second,
      matching: find.byIcon(Icons.check_circle_rounded),
    ));
    final selectedLabelBounds = tester.getRect(find.text('第 2 季'));
    expect(iconBounds.left - selectedBounds.left,
        closeTo(selectedBounds.right - selectedLabelBounds.right, 0.1));
  });

  test('season request starts before history finishes loading', () async {
    final history = Completer<PlaybackMemorySnapshot>();
    final repository = _Repository();
    final container = ProviderContainer(overrides: [
      mediaRepositoryProvider.overrideWithValue(repository),
      playbackMemorySnapshotProvider.overrideWith((ref) => history.future),
    ]);
    addTearDown(container.dispose);
    final result = container.read(detailSeriesBrowserProvider(
      DetailSeriesBrowserRequest.fromTarget(series),
    ).future);
    await Future<void>.delayed(Duration.zero);
    expect(repository.parents, ['series']);
    history.complete(const PlaybackMemorySnapshot());
    expect((await result)!.groups, isNotEmpty);
  });

  test('preloads history season, including completed episodes', () async {
    final episode = item('e8', 'episode', 2, 8);
    final playback =
        PlaybackTarget.fromMediaItem(episode).copyWith(seriesId: 'series');
    final repository = _Repository();
    final container = ProviderContainer(overrides: [
      mediaRepositoryProvider.overrideWithValue(repository),
      playbackMemorySnapshotProvider
          .overrideWith((ref) async => PlaybackMemorySnapshot(series: {
                buildSeriesKeyForTarget(playback): PlaybackProgressEntry(
                  key: buildPlaybackItemKey(playback),
                  target: playback,
                  updatedAt: DateTime(2026),
                  completed: true,
                ),
              })),
    ]);
    addTearDown(container.dispose);
    final result = await container.read(detailSeriesBrowserProvider(
      DetailSeriesBrowserRequest.fromTarget(series),
    ).future);
    expect(result!.initialGroupId, 's2');
    expect(repository.parents, ['series', 's2']);
    expect(result.groups.first.episodesLoaded, isFalse);
    expect(result.groups.last.episodesLoaded, isTrue);
    expect(result.lastPlayedTarget?.episodeNumber, 8);
    expect(
        DetailSeriesBrowserRequest.fromTarget(series),
        DetailSeriesBrowserRequest.fromTarget(
            series.copyWith(sectionName: 'Updated', overview: 'New')));
  });

  test('episode identity wins over numbering and never crosses sources', () {
    final episodes = [item('a', 'episode', 2, 1), item('b', 'episode', 2, 2)];
    expect(
        findLastPlayedEpisodeIndex(
            episodes,
            PlaybackTarget.fromMediaItem(episodes.last)
                .copyWith(episodeNumber: 1)),
        1);
    expect(
        findLastPlayedEpisodeIndex(
            episodes,
            PlaybackTarget.fromMediaItem(episodes.last)
                .copyWith(itemId: 'old')),
        1);
    expect(
        findLastPlayedEpisodeIndex(
            episodes,
            PlaybackTarget.fromMediaItem(episodes.last)
                .copyWith(sourceId: 'other')),
        -1);
    expect(findLastPlayedEpisodeIndex(episodes, null), -1);
  });

  testWidgets('scrolls offscreen episode into view without stealing focus',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final episodes =
        List.generate(20, (index) => item('e$index', 'episode', 2, index + 1));
    final target = PlaybackTarget.fromMediaItem(episodes[18]);
    Widget app(MediaDetailTarget detail) => ProviderScope(
            overrides: [
              appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
              isTelevisionProvider.overrideWith((ref) => true),
              playbackMemorySnapshotProvider
                  .overrideWith((ref) async => const PlaybackMemorySnapshot()),
            ],
            child: MaterialApp(
                home: Scaffold(
                    body: DetailEpisodeBrowser(
              seriesTarget: detail,
              groups: [
                DetailEpisodeGroup(
                    id: 's2',
                    title: 'Season 2',
                    seasonNumber: 2,
                    episodes: episodes)
              ],
              selectedGroupId: 's2',
              lastPlayedTarget: target,
              onSeasonSelected: (_) {},
            ))));
    await tester.pumpWidget(app(series));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DetailEpisodeBrowser)).height, 292);
    final action = tester.widget<TvFocusableAction>(find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'detail:episode:e18'));
    expect(action.focusNode!.hasFocus, isFalse);
    expect(
        tester
            .getRect(find.text('e18'))
            .overlaps(const Rect.fromLTWH(0, 0, 1200, 900)),
        isTrue);
    await tester.pumpWidget(app(series.copyWith(overview: 'Updated')));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(action.focusNode!.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not steal focus after user has moved away', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final userFocus = FocusNode(debugLabel: 'user-focus');
    addTearDown(userFocus.dispose);
    final repository = _PendingSeasonRepository();
    final episode = item('e1', 'episode', 2, 1);
    final target = PlaybackTarget.fromMediaItem(episode);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
        isTelevisionProvider.overrideWith((ref) => true),
        mediaRepositoryProvider.overrideWithValue(repository),
        playbackMemorySnapshotProvider
            .overrideWith((ref) async => const PlaybackMemorySnapshot()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Focus(focusNode: userFocus, child: const SizedBox.shrink()),
              DetailEpisodeBrowser(
                seriesTarget: series,
                groups: [
                  DetailEpisodeGroup(
                    id: 's2',
                    title: 'Season 2',
                    seasonNumber: 2,
                    episodes: const [],
                    episodesLoaded: false,
                  ),
                ],
                selectedGroupId: 's2',
                lastPlayedTarget: target,
                onSeasonSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    ));
    userFocus.requestFocus();
    await tester.pump();
    repository.complete([episode]);
    await tester.pumpAndSettle();

    final lastPlayedAction = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'detail:episode:e1',
      ),
    );
    expect(lastPlayedAction.focusNode!.hasFocus, isFalse);
  });

  testWidgets('episode card shares playback launch lock', (tester) async {
    final cleanup = Completer<void>();
    var cleanups = 0;
    final token = ActivePlaybackCleanupCoordinator.register((_) {
      cleanups++;
      return cleanup.future;
    });
    addTearDown(() => ActivePlaybackCleanupCoordinator.unregister(token));
    final episode = item('e1', 'episode', 1, 1);
    var launches = 0;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: DetailEpisodeBrowser(
            seriesTarget: series,
            groups: [
              DetailEpisodeGroup(
                id: 's1',
                title: 'Season 1',
                seasonNumber: 1,
                episodes: [episode],
              ),
            ],
            selectedGroupId: 's1',
            onSeasonSelected: (_) {},
          ),
        ),
      ),
      GoRoute(
        path: '/player',
        name: 'player',
        builder: (_, __) {
          launches++;
          return const Scaffold(body: Text('Player'));
        },
      ),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
        isTelevisionProvider.overrideWith((ref) => false),
        playbackMemorySnapshotProvider
            .overrideWith((ref) async => const PlaybackMemorySnapshot()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    final action = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'detail:episode:e1',
      ),
    );
    action.onPressed!();
    action.onPressed!();
    await tester.pump();
    expect(cleanups, 1);
    cleanup.complete();
    await tester.pumpAndSettle();
    expect(launches, 1);
  });
}

class _Repository implements MediaRepository {
  final parents = <String>[];
  @override
  Future<List<MediaItem>> fetchChildren(
      {required String sourceId,
      required String parentId,
      String sectionId = '',
      String sectionName = '',
      int limit = 200}) async {
    parents.add(parentId);
    return parentId == 'series'
        ? [item('s1', 'season', 1), item('s2', 'season', 2)]
        : [item('e8', 'episode', 2, 8)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingSeasonRepository implements MediaRepository {
  final _completer = Completer<List<MediaItem>>();

  void complete(List<MediaItem> episodes) => _completer.complete(episodes);

  @override
  Future<List<MediaItem>> fetchChildren(
      {required String sourceId,
      required String parentId,
      String sectionId = '',
      String sectionName = '',
      int limit = 200}) async {
    return _completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
