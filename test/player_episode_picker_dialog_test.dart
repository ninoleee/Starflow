import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/domain/playback_episode_queue.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/widgets/player_episode_picker_dialog.dart';

void main() {
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
    final result = Completer<int?>();
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
    expect(find.text('选择剧集'), findsOneWidget);
    expect(find.text('S01E01 · 第1集'), findsOneWidget);
    expect(find.text('S01E03 · 第3集'), findsOneWidget);

    await tester.tap(find.text('S01E03 · 第3集'));
    await tester.pumpAndSettle();
    expect(await result.future, 2);
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
