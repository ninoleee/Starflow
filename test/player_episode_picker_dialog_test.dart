import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:starflow/features/playback/presentation/widgets/player_menu_style.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  setUpAll(() async {
    final icons = Platform.environment['EPISODE_PREVIEW_ICONS'];
    if (icons != null) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(File(icons)
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
      await loader.load();
    }
    final path = Platform.environment['EPISODE_PREVIEW_FONT'];
    if (path != null) {
      final loader = FontLoader('EpisodePreview');
      loader.addFont(File(path)
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Finder episode(int index) => find.byWidgetPredicate((w) =>
      w is TvFocusableAction && w.focusId == 'player:episode-picker:$index');

  for (final width in [320.0, 1280.0]) {
    testWidgets(
        'styled panel at width $width keeps titles and status in bounds',
        (tester) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = _queue(currentIndex: 15, count: 65);
      final entries = [...original.entries];
      entries[15] = _entry(season: 1, episode: 16, title: '穿过漫长的夜晚，在海边等待黎明');
      final queue = PlaybackEpisodeQueue(entries: entries, currentIndex: 15);
      await _openPicker(tester, queue, television: width > 600);
      expect(find.byTooltip('关闭'),
          width > 600 ? findsNothing : findsOneWidget);
      expect(
          Theme.of(tester.element(find.byType(Dialog)))
              .dialogTheme
              .backgroundColor,
          playbackMenuBackground);
      expect(find.text('第 1 季 · 共 65 集'), findsOneWidget);
      expect(tester.getCenter(find.byTooltip('列表')).dy,
          closeTo(tester.getCenter(find.text('Series')).dy, 1));
      for (final mode in ['列表', '网格']) {
        await tester.tap(find.byTooltip(mode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final info =
            find.byKey(const ValueKey('player:episode-picker:information'));
        if (mode == '列表') {
          expect(info, findsNothing);
        } else {
          expect(tester.getSize(info).height, 28);
        }
        expect(
            tester.getTopLeft(episode(16)).dy -
                tester.getTopLeft(episode(12)).dy,
            mode == '列表' ? 288 : 72);
        final output = Platform.environment['EPISODE_PREVIEW_OUTPUT'];
        if (output != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('picker-preview')));
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
                    '$output/picker-${width.toInt()}-${mode == '列表' ? 'list' : 'grid'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    });
  }

  testWidgets('episode boundaries enter tools and return to the same episode',
      (tester) async {
    await _openPicker(tester, _queue(currentIndex: 0, count: 1));
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(tester.widget<TvFocusableAction>(episode(0)).focusNode!.hasFocus,
          isFalse);
      await tester.sendKeyEvent(key == LogicalKeyboardKey.arrowUp
          ? LogicalKeyboardKey.arrowDown
          : LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(tester.widget<TvFocusableAction>(episode(0)).focusNode!.hasFocus,
          isTrue);
    }
  });

  for (final grid in [false, true]) {
    for (final index in grid ? [0, 1, 2, 3] : [0]) {
      testWidgets('top episode $index enters season before tools grid=$grid',
          (tester) async {
        SharedPreferences.setMockInitialValues(
            {'episode_picker_layout': grid ? 'grid' : 'list'});
        final queue = _queue(currentIndex: index, count: 65);
        await _openPicker(tester, queue,
            browser: PlaybackEpisodeBrowser(
                resolver: _PickerResolver(), target: queue.currentEntry!.target));

        bool toolHasFocus(String label) => Focus.of(tester.element(
            find.descendant(of: find.byTooltip(label), matching: find.byType(Icon))
                .first)).hasFocus;

        Future<void> press(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        await press(LogicalKeyboardKey.arrowUp);
        expect(toolHasFocus('选择季'), isTrue);
        await press(LogicalKeyboardKey.arrowDown);
        expect(tester.widget<TvFocusableAction>(episode(index)).focusNode!.hasFocus,
            isTrue);
        await press(LogicalKeyboardKey.arrowUp);
        await press(LogicalKeyboardKey.enter);
        expect(find.text('第一季'), findsOneWidget);
        await press(LogicalKeyboardKey.escape);
        expect(toolHasFocus('选择季'), isTrue);
        await press(LogicalKeyboardKey.arrowUp);
        expect(toolHasFocus('列表'), isTrue);
        await press(LogicalKeyboardKey.arrowDown);
        expect(toolHasFocus('选择季'), isTrue);
        await press(LogicalKeyboardKey.arrowUp);
        await press(LogicalKeyboardKey.arrowRight);
        expect(toolHasFocus('网格'), isTrue);
        await press(LogicalKeyboardKey.arrowDown);
        expect(toolHasFocus('选择季'), isTrue);
        await press(LogicalKeyboardKey.arrowDown);
        expect(tester.widget<TvFocusableAction>(episode(index)).focusNode!.hasFocus,
            isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final grid in [false, true]) {
    testWidgets('single season skips the disabled selector grid=$grid',
        (tester) async {
      SharedPreferences.setMockInitialValues(
          {'episode_picker_layout': grid ? 'grid' : 'list'});
      final queue = _queue(currentIndex: 0);
      final resolver = _PickerResolver()..singleSeason = true;
      await _openPicker(tester, queue,
          browser: PlaybackEpisodeBrowser(
              resolver: resolver, target: queue.currentEntry!.target));
      final selector = tester.widget<TvFocusableAction>(find.descendant(
          of: find.byTooltip('选择季'), matching: find.byType(TvFocusableAction)));
      expect(selector.onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final list = tester.widget<TvFocusableAction>(find.descendant(
          of: find.byTooltip('列表'), matching: find.byType(TvFocusableAction)));
      expect(list.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final gridTool = tester.widget<TvFocusableAction>(find.descendant(
          of: find.byTooltip('网格'), matching: find.byType(TvFocusableAction)));
      expect(gridTool.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(tester.widget<TvFocusableAction>(episode(0)).focusNode!.hasFocus,
          isTrue);
      expect(selector.focusNode!.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(320, 720),
    const Size(844, 390),
    const Size(1280, 720),
  ]) {
    for (final grid in [false, true]) {
      testWidgets('automatic positioning keeps whole rows at $size grid=$grid',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues(
            {'episode_picker_layout': grid ? 'grid' : 'list'});
        final television = size.width > 1000;

        void expectAligned(int current, {required bool grid}) {
          final viewportFinder = find.byType(SingleChildScrollView);
          final viewport = tester.getRect(viewportFinder);
          final scroll = tester
              .widget<SingleChildScrollView>(viewportFinder)
              .controller!;
          expect(scroll.offset % 72, closeTo(0, .01));
          final first = current ~/ 30 * 30 +
              (scroll.offset / 72).round() * (grid ? 4 : 1);
          expect(tester.getRect(episode(first)).top,
              closeTo(viewport.top + 4, .01));
          final currentRect = tester.getRect(episode(current));
          expect(currentRect.top, greaterThanOrEqualTo(viewport.top));
          expect(currentRect.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(tester.takeException(), isNull);
        }

        await _openPicker(tester, _queue(currentIndex: 15, count: 65),
            television: television, settle: false);
        expectAligned(15, grid: grid);
        final firstRect = tester.getRect(episode(15));
        await tester.pumpAndSettle();
        expect(tester.getRect(episode(15)), firstRect);
        expectAligned(15, grid: grid);
        if (television) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expectAligned(grid ? 19 : 16, grid: grid);
        }
        await tester.tap(find.byTooltip('下一段'));
        await tester.pumpAndSettle();
        expectAligned(30, grid: grid);
        await tester.tap(find.byTooltip('下一段'));
        await tester.pumpAndSettle();
        expectAligned(60, grid: grid);
        await tester.tap(find.byTooltip('定位当前集'));
        await tester.pump();
        expectAligned(15, grid: grid);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(grid ? '列表' : '网格'));
        await tester.pump();
        expectAligned(15, grid: !grid);
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
        SharedPreferences.setMockInitialValues(
            {'episode_picker_layout': grid ? 'grid' : 'list'});
        await _openPicker(tester, _queue(currentIndex: 29, count: 30),
            television: television, settle: false);
        expectAligned(29, grid: grid);
        await tester.pumpAndSettle();
        expectAligned(29, grid: grid);
      });
    }
  }

  testWidgets('mobile drag remains free between row boundaries',
      (tester) async {
    await _openPicker(tester, _queue(currentIndex: 15, count: 65),
        television: false);
    final viewport = find.byType(SingleChildScrollView);
    final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
    final initial = scroll.offset;
    final gesture = await tester.startGesture(tester.getCenter(viewport));
    await gesture.moveBy(const Offset(0, -53));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(initial));
    expect(scroll.offset % 72, isNot(closeTo(0, .01)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout changes and locate are positioned before painting',
      (tester) async {
    await _openPicker(tester, _queue(currentIndex: 25, count: 65));
    for (final mode in ['网格', '列表']) {
      await tester.tap(find.byTooltip(mode));
      await tester.pump();
      final rect = tester.getRect(episode(25));
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
      await tester.pumpAndSettle();
      expect(tester.getRect(episode(25)), rect);
    }
    await tester.tap(find.byTooltip('下一段'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('定位当前集'));
    await tester.pump();
    final rect = tester.getRect(episode(25));
    await tester.pumpAndSettle();
    expect(tester.getRect(episode(25)), rect);
  });

  testWidgets('grid does not wrap horizontally and crosses ranges in column',
      (tester) async {
    await _openPicker(tester, _queue(currentIndex: 27, count: 65));
    await tester.tap(find.byTooltip('网格'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<TvFocusableAction>(episode(27)).focusNode!.hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.widget<TvFocusableAction>(episode(33)).focusNode!.hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(tester.widget<TvFocusableAction>(episode(29)).focusNode!.hasFocus,
        isTrue);
  });

  testWidgets('same range movement retains the panel tiles', (tester) async {
    await _openPicker(tester, _queue(currentIndex: 10, count: 30));
    final tile = tester.widget<TvFocusableAction>(episode(15));
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(
        identical(tester.widget<TvFocusableAction>(episode(15)), tile), isTrue);
    expect(tester.widget<TvFocusableAction>(episode(13)).focusNode!.hasFocus,
        isTrue);
  });

  testWidgets(
      'layout preference survives closing while position follows playback',
      (tester) async {
    await _openPicker(tester, _queue(currentIndex: 7, count: 24));
    await tester.tap(find.byTooltip('网格'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    expect(tester.widget<TvFocusableAction>(episode(7)).focusNode!.hasFocus,
        isTrue);
    expect(
        (await SharedPreferences.getInstance())
            .getString('episode_picker_layout'),
        'grid');
  });

  testWidgets(
      'loading keeps the old season and ignores late results after locate',
      (tester) async {
    final queue = _queue(currentIndex: 1);
    final pending = Completer<PlaybackEpisodeQueue>();
    final resolver = _PickerResolver()..pending = pending;
    await _openPicker(tester, queue,
        television: false,
        browser: PlaybackEpisodeBrowser(
            resolver: resolver, target: queue.currentEntry!.target));
    await tester.tap(find.byTooltip('选择季'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二季'));
    await tester.pumpAndSettle();
    expect(find.text('正在加载剧集'), findsOneWidget);
    expect(find.text('正在加载剧集'), findsOneWidget);
    expect(find.text('正在播放'), findsOneWidget);
    expect(tester.widget<TvFocusableAction>(episode(1)).onPressed, isNull);
    await tester.tap(find.byTooltip('定位当前集'));
    await tester.pumpAndSettle();
    pending.complete(PlaybackEpisodeQueue(currentIndex: -1, entries: [
      _entry(season: 2, episode: 1, title: '迟到结果'),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('迟到结果'), findsNothing);
    expect(find.text('第 1 季 · 共 3 集'), findsOneWidget);
  });
  for (final index in [0, 15, 29, 58, 64]) {
    testWidgets('episode $index is positioned in the first painted frame',
        (tester) async {
      await _openPicker(tester, _queue(currentIndex: index, count: 65),
          settle: false);
      final tile = find.byWidgetPredicate((widget) =>
          widget is TvFocusableAction &&
          widget.focusId == 'player:episode-picker:$index');
      final viewport = find.byType(SingleChildScrollView);
      final firstRect = tester.getRect(tile);
      final viewportRect = tester.getRect(viewport);
      expect(firstRect.top, greaterThanOrEqualTo(viewportRect.top));
      expect(firstRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
      final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
      expect(scroll.offset, scroll.initialScrollOffset);
      await tester.pumpAndSettle();
      expect(tester.getRect(tile), firstRect);
      expect(
          tester.widget<TvFocusableAction>(tile).focusNode!.hasFocus, isTrue);
    });
  }
  testWidgets('episode panel has no entrance or exit transition',
      (tester) async {
    await _openPicker(tester, _queue(currentIndex: 0));
    final context = tester.element(find.byType(Dialog));
    final route = ModalRoute.of(context)!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
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
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final current = tester.widget<TvFocusableAction>(find.byWidgetPredicate(
        (w) =>
            w is TvFocusableAction && w.focusId == 'player:episode-picker:11'));
    expect(current.focusNode!.hasFocus, isTrue);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('正在播放'), findsNothing);
    expect(find.text('第 12 集'), findsOneWidget);
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

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    for (final grid in [false, true]) {
      testWidgets(
          'mobile bottom-left close cancels at $size with grid=$grid',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues(
            {'episode_picker_layout': grid ? 'grid' : 'list'});
        final result = Completer<PlaybackEpisodeSelection?>();
        final queue = _queue(currentIndex: 15, count: 65);
        await _openPicker(tester, queue,
            television: false, onResult: result.complete);

        final close = find.byTooltip('关闭');
        final panel = tester.getRect(
            find.byKey(const ValueKey('player:episode-picker:panel')));
        final closeRect = tester.getRect(close);
        final previousRect = tester.getRect(find.byTooltip('上一段'));
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
        expect(closeRect.size, const Size(44, 44));
        expect(closeRect.left, closeTo(panel.left + 20, .1));
        expect(panel.bottom - closeRect.bottom, inInclusiveRange(8, 24));
        expect(closeRect.right, lessThanOrEqualTo(previousRect.left));
        expect(closeRect.center.dy, closeTo(previousRect.center.dy, .1));
        expect(tester.takeException(), isNull);

        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('打开'), findsOneWidget);
        expect(result.isCompleted, isTrue);
        expect(await result.future, isNull);
        expect(queue.currentIndex, 15);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final fails in [false, true]) {
    testWidgets('mobile close ignores late season result with fails=$fails',
        (tester) async {
      final queue = _queue(currentIndex: 1);
      final pending = Completer<PlaybackEpisodeQueue>();
      final resolver = _PickerResolver()..pending = pending;
      final result = Completer<PlaybackEpisodeSelection?>();
      await _openPicker(tester, queue,
          television: false,
          onResult: result.complete,
          browser: PlaybackEpisodeBrowser(
              resolver: resolver, target: queue.currentEntry!.target));
      await tester.tap(find.byTooltip('选择季'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第二季'));
      await tester.pumpAndSettle();
      expect(find.text('正在加载剧集'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(result.isCompleted, isTrue);
      expect(await result.future, isNull);

      if (fails) {
        pending.completeError(StateError('offline'));
      } else {
        pending.complete(PlaybackEpisodeQueue(currentIndex: -1, entries: [
          _entry(season: 2, episode: 1, title: '迟到结果'),
        ]));
      }
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(queue.currentIndex, 1);
      expect(tester.takeException(), isNull);
    });
  }

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
    expect(find.text('正在播放'), findsOneWidget);
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
  bool singleSeason = false;
  Completer<PlaybackEpisodeQueue>? pending;
  @override
  Future<List<PlaybackEpisodeSeason>> loadSeasons(
          PlaybackTarget target) async =>
      [
        const PlaybackEpisodeSeason(id: '1', number: 1, title: '第一季'),
        if (!singleSeason)
          const PlaybackEpisodeSeason(id: '2', number: 2, title: '第二季'),
      ];
  @override
  Future<PlaybackEpisodeQueue> loadSeason(
      PlaybackTarget target, PlaybackEpisodeSeason season) async {
    if (fail) throw StateError('offline');
    if (pending != null) return pending!.future;
    return PlaybackEpisodeQueue(currentIndex: -1, entries: [
      _entry(season: 2, episode: 1, title: '第二季开篇')
          .copyWith(playbackItemKey: 's2-e1'),
    ]);
  }
}

Future<void> _openPicker(WidgetTester tester, PlaybackEpisodeQueue queue,
    {bool television = true,
    bool settle = true,
    PlaybackEpisodeBrowser? browser,
    ValueChanged<PlaybackEpisodeSelection?>? onResult,
    Future<PlaybackMemorySnapshot> Function()? loadHistory}) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => television)],
      child: RepaintBoundary(
          key: const ValueKey('picker-preview'),
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark().copyWith(
                  textTheme: ThemeData.dark().textTheme.apply(
                      fontFamily:
                          Platform.environment['EPISODE_PREVIEW_FONT'] == null
                              ? null
                              : 'EpisodePreview')),
              home: Scaffold(
                  body: Builder(
                      builder: (context) => ElevatedButton(
                            onPressed: () async {
                              final result =
                                  await showPlaybackEpisodePickerDialog(
                                      context: context,
                                      queue: queue,
                                      browser: browser,
                                      loadHistory: loadHistory,
                                      isTelevision: television);
                              onResult?.call(result);
                            },
                            child: const Text('打开'),
                          )))))));
  await tester.tap(find.text('打开'));
  await tester.pump();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
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
