import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_channel_picker.dart';
import 'package:starflow/features/live_tv/presentation/live_player_page.dart';
import 'package:starflow/features/live_tv/presentation/live_tv_page.dart';

const _first = LiveChannel(
    id: 'a',
    sourceId: 's1',
    epgId: 'original',
    name: 'Channel A',
    lines: [LiveLine('https://example.test/a')]);
const _second = LiveChannel(
    id: 'b',
    sourceId: 's2',
    epgId: 'mapped',
    name: 'Channel B',
    lines: [LiveLine('https://example.test/b')]);
const _gap = LiveChannel(
    id: 'gap',
    sourceId: 's1',
    epgId: 'gap',
    name: 'Channel without current programme',
    lines: [LiveLine('https://example.test/gap')]);
const _snapshot = LiveSnapshot(sources: [
  LiveSource(id: 's1', name: 'Source 1'),
  LiveSource(id: 's2', name: 'Source 2'),
], channels: [
  _first,
  _second,
  _gap
], preferences: {
  'a': LivePreference(epgId: 'mapped')
});

Map<String, List<LiveProgramme>> _schedule([String title = 'Current news']) {
  final now = DateTime.now();
  LiveProgramme current(String title) => LiveProgramme(
      channel: 'mapped',
      title: title,
      start: now.subtract(const Duration(hours: 1)),
      end: now.add(const Duration(hours: 1)));
  final future = LiveProgramme(
      channel: 'gap',
      title: 'Future programme',
      start: now.add(const Duration(hours: 1)),
      end: now.add(const Duration(hours: 2)));
  return {
    's1|original': [current('Wrong mapping')],
    's1|mapped': [current(title)],
    's2|mapped': [current('Other source programme')],
    's1|gap': [
      LiveProgramme(
          channel: 'gap',
          title: 'Ended programme',
          start: now.subtract(const Duration(hours: 2)),
          end: now.subtract(const Duration(minutes: 1))),
      future,
    ],
  };
}

LiveRepository _repository(String name) => LiveRepository(
    openDatabase: () => databaseFactoryMemory.openDatabase(name),
    client: MockClient((_) async => http.Response('', 404)));

void main() {
  for (final width in [320.0, 390.0, 560.0]) {
    testWidgets('picker programme labels fit at $width with large text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 640);
      addTearDown(tester.view.reset);
      var schedule = _schedule('Current news with a very long programme title');
      final selections = <String>[];
      Widget page() => ProviderScope(
          overrides: [isTelevisionProvider.overrideWith((_) => true)],
          child: MaterialApp(
              theme: ThemeData.dark(),
              home: MediaQuery(
                  data: MediaQueryData(
                      size: Size(width, 640),
                      textScaler: const TextScaler.linear(2)),
                  child: Scaffold(
                      body: LiveChannelPicker(
                          snapshot: _snapshot,
                          currentChannel: _first,
                          nowNext: schedule,
                          onSelected: (c) => selections.add(c.id))))));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('Current news with a very long programme title'),
          findsOneWidget);
      expect(find.text('Other source programme'), findsOneWidget);
      expect(find.text('暂无节目信息'), findsOneWidget);
      expect(find.text('Wrong mapping'), findsNothing);
      expect(find.text('Ended programme'), findsNothing);
      expect(find.text('Future programme'), findsNothing);
      final positions = <Offset>[];
      for (final tile in find.byType(ListTile).evaluate()) {
        final finder = find.byWidget(tile.widget);
        positions.add(tester.getTopLeft(finder));
        expect(tester.getSize(finder).height, 64);
        final row = tile.widget as ListTile;
        final title = find.byWidget(row.title!);
        final subtitle = find.descendant(
            of: find.byWidget(row.subtitle!), matching: find.byType(Text));
        expect(tester.getBottomLeft(title).dy,
            lessThanOrEqualTo(tester.getTopLeft(subtitle).dy));
        expect(tester.getBottomRight(subtitle).dy,
            lessThanOrEqualTo(tester.getBottomRight(finder).dy));
        expect(
            tester.getTopRight(subtitle).dx,
            lessThanOrEqualTo(
                tester.getTopLeft(find.byWidget(row.trailing!)).dx));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:b');
      schedule = _schedule('Updated news');
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('Updated news'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:b');
      expect(
          find
              .byType(ListTile)
              .evaluate()
              .map((e) => tester.getTopLeft(find.byWidget(e.widget))),
          positions);
      expect(selections, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selections, ['b']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('channel home refreshes local programmes and resumes immediately',
      (tester) async {
    final repository = _repository('programme-home');
    var reads = 0;
    var active = true;
    Widget page() => ProviderScope(
            overrides: [
              liveRepositoryProvider.overrideWithValue(repository),
              liveSnapshotProvider.overrideWith((_) => Stream.value(_snapshot)),
              liveNowNextProvider.overrideWith((_) async {
                reads++;
                return _schedule('News $reads');
              }),
              isTelevisionProvider.overrideWith((_) => false),
            ],
            child: MaterialApp(
                home: TickerMode(enabled: active, child: const LiveTvPage())));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('正在播出 News $reads'), findsOneWidget);
    expect(find.text('正在播出 Other source programme'), findsOneWidget);
    expect(find.text('暂无节目信息'), findsOneWidget);
    expect(find.textContaining('Wrong mapping'), findsNothing);
    expect(find.textContaining('Ended programme'), findsNothing);
    expect(find.textContaining('接下来'), findsOneWidget);
    final initialReads = reads;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(reads, initialReads + 1);
    expect(find.text('正在播出 News $reads'), findsOneWidget);
    active = false;
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final inactiveReads = reads;
    await tester.pump(const Duration(minutes: 2));
    expect(reads, inactiveReads);
    active = true;
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(reads, inactiveReads + 1);
    expect(find.text('正在播出 News $reads'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    repository.dispose();
  });

  testWidgets('player reads programmes only for open picker and keeps playback',
      (tester) async {
    final repository = _repository('programme-player');
    final engine = _ProgrammeEngine();
    var reads = 0;
    var guideReads = 0;
    final pending = Completer<Map<String, List<LiveProgramme>>>();
    final container = ProviderContainer(overrides: [
      liveRepositoryProvider.overrideWithValue(repository),
      liveSnapshotProvider.overrideWith((_) => Stream.value(_snapshot)),
      liveNowNextProvider.overrideWith((_) async {
        reads++;
        if (reads == 1) return pending.future;
        if (reads == 3) throw StateError('Local EPG unavailable');
        return _schedule('News $reads');
      }),
      liveGuideProvider.overrideWith((_, __) async {
        guideReads++;
        return [];
      }),
      isTelevisionProvider.overrideWith((_) => true),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: LivePlayerPage(
                initialChannel: _first,
                snapshot: _snapshot,
                engineFactory: () => engine))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(reads, 0);
    expect(engine.opens, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('暂无节目信息'), findsNWidgets(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    pending.complete(_schedule('News 1'));
    await tester.pumpAndSettle();
    expect(find.text('News 1'), findsOneWidget);
    expect(find.text('Other source programme'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:b');
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('News 2'), findsOneWidget);
    expect(engine.opens, 1);
    expect(guideReads, 1, reason: 'No guide query for each channel row');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:b');

    // A retained home page can keep the old query alive behind the player.
    final subscription = container.listen(liveNowNextProvider, (_, __) {});
    addTearDown(subscription.close);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    expect(reads, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(reads, 3);
    expect(find.text('News 2'), findsOneWidget,
        reason: 'A read failure preserves still-current cached programmes');
    expect(find.text('暂无节目信息'), findsOneWidget);
    expect(engine.opens, 1);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(reads, 4);
    expect(find.text('News 4'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    expect(reads, 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(reads, 5);
    expect(find.text('News 5'), findsOneWidget);
    expect(engine.opens, 2, reason: 'Only lifecycle resume reopens playback');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    repository.dispose();
  });
}

class _ProgrammeEngine implements CancellableLiveEngine {
  Timer? _progress;
  int opens = 0;

  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) async {
    opens++;
    onState(generation, 'progress');
    _progress = Timer.periodic(
        const Duration(seconds: 1), (_) => onState(generation, 'progress'));
  }

  @override
  Future<void> stop() async => _progress?.cancel();
  @override
  Future<void> cancelOpen() => stop();
  @override
  Future<void> dispose() => stop();
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<List<(String, String)>> audioTracks() async => [];
  @override
  Future<void> selectAudio(String id) async {}
}
