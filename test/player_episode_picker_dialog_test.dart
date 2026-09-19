import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/application/playback_episode_browser.dart';
import 'package:starflow/features/playback/application/playback_episode_queue_resolver.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_episode_picker_dialog.dart';

void main() {
  testWidgets('episode panel has no entrance or exit transition',
      (tester) async {
    await _openPicker(tester, _queue(currentIndex: 0));
    final context = tester.element(find.byType(Dialog));
    final route = ModalRoute.of(context)!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
  });
  test('formats season and episode numbers for the picker', () {
    expect(
      formatPlaybackEpisodePickerLabel(
        _entry(season: 2, episode: 3, title: '第三集'),
        2,
      ),
      'S02E03 · 第三集',
    );
  });

  testWidgets('returns the selected episode index on mobile', (tester) async {
    final result = Completer<PlaybackEpisodeSelection?>();
    final queue = _queue(currentIndex: 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isTelevisionProvider.overrideWith((ref) => false)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result.complete(
                    await showPlaybackEpisodePickerDialog(
                      context: context,
                      queue: queue,
                      isTelevision: false,
                    ),
                  );
                },
                child: const Text('打开选集'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开选集'));
    await tester.pumpAndSettle();
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('第 1 集'), findsOneWidget);
    expect(find.text('第 3 集'), findsOneWidget);

    await tester.tap(find.text('第 3 集'));
    await tester.pumpAndSettle();
    expect((await result.future)?.index, 2);
  });

  testWidgets('TV picker initially focuses the current episode',
      (tester) async {
    final queue = _queue(currentIndex: 25, count: 30);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isTelevisionProvider.overrideWith((ref) => true)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  unawaited(
                    showPlaybackEpisodePickerDialog(
                      context: context,
                      queue: queue,
                      isTelevision: true,
                    ),
                  );
                },
                child: const Text('打开选集'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开选集'));
    await tester.pumpAndSettle();

    final current = tester.widget<TvFocusableAction>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TvFocusableAction &&
            widget.focusId == 'player:episode-picker:25',
      ),
    );
    expect(current.autofocus, isTrue);
    expect(current.focusNode?.hasFocus, isTrue);
  });

  testWidgets('TV navigation crosses a 30 episode range without wrapping',
      (tester) async {
    await _openPicker(tester, _queue(currentIndex: 29, count: 65));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final current = tester.widget<TvFocusableAction>(find.byWidgetPredicate(
        (w) =>
            w is TvFocusableAction && w.focusId == 'player:episode-picker:30'));
    expect(current.focusNode!.hasFocus, isTrue);
    expect(find.text('31–60 集'), findsOneWidget);
    expect(find.text('正在播放'), findsNothing);
    await tester.tap(find.byTooltip('定位当前集'));
    await tester.pumpAndSettle();
    expect(find.text('正在播放'), findsOneWidget);
  });

  testWidgets('grid keeps the playing state and current focus', (tester) async {
    await _openPicker(tester, _queue(currentIndex: 7, count: 24));
    await tester.tap(find.byTooltip('网格'));
    await tester.pumpAndSettle();
    expect(find.text('正在播放'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final current = tester.widget<TvFocusableAction>(find.byWidgetPredicate(
        (w) =>
            w is TvFocusableAction && w.focusId == 'player:episode-picker:11'));
    expect(current.focusNode!.hasFocus, isTrue);
    expect(find.text('正在播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow mobile layout has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openPicker(tester, _queue(currentIndex: 1), television: false);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('网格'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV panel uses about 30 percent of a wide screen',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openPicker(tester, _queue(currentIndex: 0));
    final width = tester
        .getSize(
          find.byKey(
            const ValueKey<String>('player:episode-picker:panel'),
          ),
        )
        .width;
    expect(width, closeTo(384, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'season failure retries without marking another season as playing',
      (tester) async {
    final queue = _queue(currentIndex: 1);
    final resolver = _PickerResolver()..fail = true;
    final browser = PlaybackEpisodeBrowser(
        resolver: resolver, target: queue.currentEntry!.target);
    await _openPicker(tester, queue, television: false, browser: browser);
    await tester.tap(find.byTooltip('选择季'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二季'));
    await tester.pumpAndSettle();
    expect(find.text('本季加载失败，请重试'), findsOneWidget);
    resolver.fail = false;
    await tester.tap(find.byTooltip('重试'));
    await tester.pumpAndSettle();
    expect(find.text('第二季开篇'), findsOneWidget);
    expect(find.text('正在播放'), findsNothing);
    expect(queue.currentIndex, 1);
    await tester.tap(find.byTooltip('定位当前集'));
    await tester.pumpAndSettle();
    expect(find.text('正在播放'), findsOneWidget);
  });

  testWidgets('history only marks episodes with stored records',
      (tester) async {
    final queue = _queue(currentIndex: 1);
    await _openPicker(tester, queue,
        television: false,
        loadHistory: () async => PlaybackMemorySnapshot(items: {
              'episode-1': PlaybackProgressEntry(
                  key: 'episode-1',
                  target: queue.entries.first.target,
                  updatedAt: DateTime(2026),
                  completed: true),
            }));
    expect(find.text('已看完'), findsOneWidget);
    expect(find.text('未看'), findsNothing);
  });

  testWidgets('Escape closes the panel and restores the opener focus',
      (tester) async {
    await _openPicker(tester, _queue(currentIndex: 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
  });

  test('numeric episode titles normalize without changing meaningful titles',
      () {
    expect(
        playbackEpisodeTitle(_entry(season: 0, episode: 3, title: '第03集'), 0),
        '第 3 集');
    expect(
        playbackEpisodeTitle(_entry(season: 1, episode: 3, title: '风从海上来'), 0),
        '风从海上来');
  });
}

class _PickerResolver extends PlaybackEpisodeQueueResolver {
  _PickerResolver() : super(read: <T>(provider) => throw UnimplementedError());
  bool fail = false;
  @override
  Future<List<PlaybackEpisodeSeason>> loadSeasons(
          PlaybackTarget target) async =>
      const [
        PlaybackEpisodeSeason(id: '1', number: 1, title: '第一季'),
        PlaybackEpisodeSeason(id: '2', number: 2, title: '第二季'),
      ];
  @override
  Future<PlaybackEpisodeQueue> loadSeason(
      PlaybackTarget target, PlaybackEpisodeSeason season) async {
    if (fail) throw StateError('offline');
    return PlaybackEpisodeQueue(currentIndex: -1, entries: [
      _entry(season: 2, episode: 1, title: '第二季开篇')
          .copyWith(playbackItemKey: 's2-e1'),
    ]);
  }
}

Future<void> _openPicker(WidgetTester tester, PlaybackEpisodeQueue queue,
    {bool television = true,
    PlaybackEpisodeBrowser? browser,
    Future<PlaybackMemorySnapshot> Function()? loadHistory}) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => television)],
      child: MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => ElevatedButton(
                        onPressed: () => showPlaybackEpisodePickerDialog(
                            context: context,
                            queue: queue,
                            browser: browser,
                            loadHistory: loadHistory,
                            isTelevision: television),
                        child: const Text('打开'),
                      ))))));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

PlaybackEpisodeQueue _queue({required int currentIndex, int count = 3}) {
  return PlaybackEpisodeQueue(
    currentIndex: currentIndex,
    entries: List<PlaybackEpisodeQueueEntry>.generate(
      count,
      (index) => _entry(
        season: 1,
        episode: index + 1,
        title: '第${index + 1}集',
      ),
    ),
  );
}

PlaybackEpisodeQueueEntry _entry({
  required int season,
  required int episode,
  required String title,
}) {
  final target = PlaybackTarget(
    title: title,
    sourceId: 'nas-main',
    streamUrl: 'https://media.example.com/s$season-e$episode.mp4',
    sourceName: 'NAS',
    sourceKind: MediaSourceKind.nas,
    itemType: 'episode',
    seriesId: 'series-main',
    seriesTitle: 'Series',
    seasonNumber: season,
    episodeNumber: episode,
  );
  return PlaybackEpisodeQueueEntry(
    target: target,
    playbackItemKey: 'episode-$episode',
    seriesKey: 'series-main',
  );
}
