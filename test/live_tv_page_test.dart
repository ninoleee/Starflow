import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_tv_page.dart';
import 'package:starflow/features/live_tv/presentation/live_sources_page.dart';
import 'package:starflow/features/live_tv/presentation/live_widgets.dart';
import 'package:starflow/features/live_tv/presentation/live_player_page.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';

void main() {
  testWidgets('live remote controls fit mobile and TV across repeated sessions',
      (tester) async {
    await _loadReviewFont(tester);
    for (final size in [const Size(390, 844), const Size(1280, 720)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = LiveRepository(
          openDatabase: () =>
              databaseFactoryMemory.openDatabase('player-$size'),
          client: MockClient((_) async => http.Response('', 404)));
      const first = LiveChannel(
          id: 'a',
          sourceId: 's',
          name: '频道一',
          lines: [LiveLine('https://example.test/a')]);
      const second = LiveChannel(
          id: 'b',
          sourceId: 's',
          name: '频道二',
          lines: [LiveLine('https://example.test/b')]);
      const snapshot = LiveSnapshot(
          sources: [LiveSource(id: 's', name: 'Source')],
          channels: [first, second]);
      final engine = _PageEngine();
      final capture = GlobalKey();
      final now = DateTime.now();
      final programmes = List.generate(
          30,
          (i) => LiveProgramme(
              channel: 'epg',
              title: '节目 $i',
              start: now.add(Duration(hours: i - 1)),
              end: now.add(Duration(hours: i)),
              description: '节目简介与多日节目详情'));
      await tester.pumpWidget(ProviderScope(
          overrides: [
            liveRepositoryProvider.overrideWithValue(repository),
            liveSnapshotProvider.overrideWith((_) => Stream.value(snapshot)),
            liveGuideProvider.overrideWith((_, __) async => programmes),
            isTelevisionProvider.overrideWith((_) => true),
          ],
          child: MaterialApp(
              theme: _reviewTheme,
              builder: (_, child) =>
                  RepaintBoundary(key: capture, child: child),
              home: LivePlayerPage(
                  initialChannel: first,
                  snapshot: snapshot,
                  engineFactory: () => engine))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.urls, ['https://example.test/a']);
      await _capture(tester, capture, 'player-${size.width.toInt()}');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.urls.last, 'https://example.test/b');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('全部分组'), findsOneWidget);
      final beforeBrowse = engine.urls.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.channelDown);
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.urls.length, beforeBrowse,
          reason: 'Browsing or channel keys inside an overlay must not tune');
      await _capture(tester, capture, 'channels-${size.width.toInt()}');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('全部分组'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump();
      expect(
          FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay-close');
      expect(find.text('节目单'), findsOneWidget);
      await _capture(tester, capture, 'guide-${size.width.toInt()}');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          isNot('live-overlay-close'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('节目单'), findsOneWidget);
      expect(engine.urls.length, beforeBrowse);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-tools');
      await tester.pump(const Duration(seconds: 6));
      expect(_icon('频道列表'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-player');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.urls.last, 'https://example.test/a');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final beforeResume = engine.urls.length;
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.urls.length, beforeResume);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.urls.length, beforeResume + 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump();
      repository.dispose();
    }
    // Playback scenarios share FakeAsync because cleanup owns a global queue.
    await _attachmentRaces(tester);
  });
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1280, 720)
  ]) {
    testWidgets('channel search, favorites, organize and layout at $size',
        (tester) async {
      await _loadReviewFont(tester);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = LiveRepository(
          openDatabase: () => databaseFactoryMemory.openDatabase('ui-$size'),
          client: MockClient((_) async => http.Response('', 404)));
      const channel = LiveChannel(
          id: 'one',
          sourceId: 's',
          name: '综合新闻频道',
          group: '新闻与综合节目特别长的频道分组名称测试窄屏显示',
          lines: [LiveLine('https://example.test/live')]);
      const snapshot = LiveSnapshot(
          sources: [LiveSource(id: 's', name: 'Demo')],
          channels: [channel],
          lastChannel: 'one');
      final capture = GlobalKey();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            liveRepositoryProvider.overrideWithValue(repository),
            liveSnapshotProvider.overrideWith((_) => Stream.value(snapshot)),
            liveNowNextProvider.overrideWith((_) async => {}),
            isTelevisionProvider.overrideWith((_) => false),
          ],
          child: MaterialApp(
              theme: _reviewTheme,
              builder: (_, child) =>
                  RepaintBoundary(key: capture, child: child),
              home: const LiveTvPage())));
      await tester.pumpAndSettle();
      expect(find.text('综合新闻频道'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await _capture(tester, capture, 'library-${size.width.toInt()}');
      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pumpAndSettle();
      expect(find.text('没有符合条件的频道'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      final organize = tester.widget<LiveIconButton>(find
          .byWidgetPredicate((w) => w is LiveIconButton && w.label == '整理频道'));
      organize.onPressed!();
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate(
              (w) => w is LiveIconButton && w.label == '隐藏频道'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, capture, 'organize-${size.width.toInt()}');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      repository.dispose();
    });
  }
  testWidgets('TV empty state retains a usable subscription action',
      (tester) async {
    final repository = LiveRepository(
        openDatabase: () => databaseFactoryMemory.openDatabase('empty-ui'),
        client: MockClient((_) async => http.Response('', 404)));
    await tester.pumpWidget(ProviderScope(overrides: [
      liveRepositoryProvider.overrideWithValue(repository),
      liveSnapshotProvider
          .overrideWith((_) => Stream.value(const LiveSnapshot())),
      liveNowNextProvider.overrideWith((_) async => {}),
      isTelevisionProvider.overrideWith((_) => true),
    ], child: MaterialApp(theme: ThemeData.dark(), home: const LiveTvPage())));
    await tester.pumpAndSettle();
    expect(find.text('尚未添加直播订阅'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(LiveSourcesPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    repository.dispose();
  });
  testWidgets('explicit settings entry has a visible back action',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final repository = LiveRepository(
        openDatabase: () => databaseFactoryMemory.openDatabase('back-ui'),
        client: MockClient((_) async => http.Response('', 404)));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          liveRepositoryProvider.overrideWithValue(repository),
          liveSnapshotProvider
              .overrideWith((_) => Stream.value(const LiveSnapshot())),
          liveNowNextProvider.overrideWith((_) async => {}),
          isTelevisionProvider.overrideWith((_) => false),
        ],
        child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Settings')))));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const LiveTvPage(showBackButton: true)));
    await tester.pumpAndSettle();
    await tester.tap(_icon('返回'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(LiveTvPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    repository.dispose();
  });
  testWidgets(
      'subscription validation, edit, disable, refresh and delete at 320px',
      (tester) async {
    await _loadReviewFont(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _UiRepository();
    final capture = GlobalKey();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          liveRepositoryProvider.overrideWithValue(repository),
          isTelevisionProvider.overrideWith((_) => false),
        ],
        child: MaterialApp(
            theme: _reviewTheme,
            builder: (_, child) => RepaintBoundary(key: capture, child: child),
            home: const LiveSourcesPage())));
    await tester.pumpAndSettle();
    await tester.tap(_icon('添加订阅'));
    await tester.pumpAndSettle();
    await _press(tester, '保存');
    expect(find.text('请填写名称，并填写订阅地址或选择文件'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '测试直播订阅');
    await tester.enterText(find.byType(TextField).at(1), 'file:///invalid.m3u');
    await _press(tester, '保存');
    expect(find.text('请检查名称与 HTTP/HTTPS 地址'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).at(1), 'https://example.test/live.m3u');
    await tester.enterText(
        find.byType(TextField).at(2), 'https://example.test/epg.xml.gz');
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await _capture(tester, capture, 'source-editor-320');
    await _press(tester, '保存');
    expect(find.byType(TextField), findsNothing);
    expect(repository.refreshes, 0,
        reason: 'Disabled source must not auto-refresh');
    expect(find.textContaining('已停用'), findsOneWidget);
    await tester.tap(_icon('编辑订阅'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await _press(tester, '保存');
    expect(repository.refreshes, 1);
    await tester.tap(_icon('更新频道与节目单'));
    await tester.pumpAndSettle();
    expect(repository.refreshes, 2);
    await _capture(tester, capture, 'sources-320');
    await tester.tap(_icon('删除订阅'));
    await tester.pumpAndSettle();
    await _press(tester, '取消');
    expect(find.text('测试直播订阅'), findsOneWidget);
    await tester.tap(_icon('删除订阅'));
    await tester.pumpAndSettle();
    await _press(tester, '删除');
    expect(find.text('测试直播订阅'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    repository.dispose();
  });
}

class _UiRepository extends LiveRepository {
  _UiRepository()
      : super(
            openDatabase: () => databaseFactoryMemory.openDatabase('source-ui'),
            client: MockClient((_) async => http.Response('', 404)));
  int refreshes = 0;
  @override
  Future<void> refresh(String id) async {
    refreshes++;
  }
}

Future<void> _press(WidgetTester tester, String label) async {
  final finder =
      find.byWidgetPredicate((w) => w is StarflowButton && w.label == label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _icon(String label) =>
    find.byWidgetPredicate((w) => w is LiveIconButton && w.label == label);

Future<void> _attachmentRaces(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  const channel = LiveChannel(
      id: 'a',
      sourceId: 's',
      name: 'Race channel',
      lines: [LiveLine('https://example.test/a')]);
  const snapshot = LiveSnapshot(
      sources: [LiveSource(id: 's', name: 'Source')], channels: [channel]);
  for (final exitWhilePending in [false, true]) {
    final repository = LiveRepository(
        openDatabase: () =>
            databaseFactoryMemory.openDatabase('race-$exitWhilePending'),
        client: MockClient((_) async => http.Response('', 404)));
    final gate = Completer<void>();
    final cleanupToken =
        ActivePlaybackCleanupCoordinator.register((_) => gate.future);
    final engine = _PageEngine();
    final replacement = _PageEngine();
    var creations = 0;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          liveRepositoryProvider.overrideWithValue(repository),
          liveSnapshotProvider.overrideWith((_) => Stream.value(snapshot)),
          liveGuideProvider.overrideWith((_, __) async => []),
          isTelevisionProvider.overrideWith((_) => true),
        ],
        child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Outside player')))));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => LivePlayerPage(
            initialChannel: channel,
            snapshot: snapshot,
            engineFactory: () => creations++ == 0 ? engine : replacement)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(engine.urls, isEmpty);
    if (exitWhilePending) {
      navigator.currentState!.pop();
      // Resolve cleanup during the reverse route animation, before dispose.
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(engine.urls, isEmpty);
      expect(engine.disposals, 1);
    } else {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.urls, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.urls, hasLength(1));
      tester.widget<LiveIconButton>(_icon('静音')).onPressed!();
      await tester.pump();
      final closeGate = Completer<void>();
      engine.disposeGate = closeGate;
      final switchAction =
          tester.widget<LiveIconButton>(_icon('切换播放内核')).onPressed!;
      switchAction();
      switchAction();
      await tester.pump();
      expect(creations, 1);
      closeGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.disposals, 1);
      expect(creations, 2, reason: 'Repeated switch action must be coalesced');
      expect(replacement.urls, hasLength(1));
      expect(replacement.openVolumes, [0]);
      final exitGate = Completer<void>();
      replacement.disposeGate = exitGate;
      tester.widget<LiveIconButton>(_icon('切换播放内核')).onPressed!();
      await tester.pump();
      navigator.currentState!.pop();
      exitGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(creations, 2,
          reason: 'Switch completion after pop must not attach');
      expect(replacement.disposals, 1);
    }
    ActivePlaybackCleanupCoordinator.unregister(cleanupToken);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
    repository.dispose();
    expect(tester.takeException(), isNull);
  }
  debugDefaultTargetPlatformOverride = null;
}

const _review = bool.fromEnvironment('LIVE_TV_REVIEW');
ThemeData get _reviewTheme => ThemeData.dark().copyWith(
    textTheme: ThemeData.dark()
        .textTheme
        .apply(fontFamily: _review ? 'LiveReview' : null));

Future<void> _loadReviewFont(WidgetTester tester) async {
  if (!_review) return;
  await tester.runAsync(() async {
    final loader = FontLoader('LiveReview');
    loader.addFont(File('/System/Library/Fonts/STHeiti Light.ttc')
        .readAsBytes()
        .then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!_review) return;
  await tester.pump();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/live-tv-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _PageEngine implements CancellableLiveEngine {
  final urls = <String>[];
  final openVolumes = <double>[];
  double volume = 1;
  int disposals = 0;
  Completer<void>? disposeGate;
  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) async {
    urls.add(line.url);
    openVolumes.add(volume);
    onState(generation, 'progress');
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> cancelOpen() async {}
  @override
  Future<void> dispose() async {
    disposals++;
    await disposeGate?.future;
  }

  @override
  Future<void> setVolume(double volume) async { this.volume = volume; }
  @override
  Future<List<(String, String)>> audioTracks() async => [];
  @override
  Future<void> selectAudio(String id) async {}
}
