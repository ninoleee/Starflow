import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/data/live_channel_probe.dart';
import 'package:starflow/features/live_tv/data/live_probe_network.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_tv_page.dart';
import 'package:starflow/features/live_tv/presentation/live_logo.dart';
import 'package:starflow/features/live_tv/presentation/live_sources_page.dart';
import 'package:starflow/features/live_tv/presentation/live_widgets.dart';
import 'package:starflow/features/live_tv/presentation/live_player_page.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/presentation/live_network_speed_label.dart';

void main() {
  for (final topInset in [0.0, 24.0, 59.0]) {
    for (final showBackButton in [false, true]) {
      testWidgets(
          'channel header applies top safe area once '
          '(inset: $topInset, back: $showBackButton)', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.viewPadding = FakeViewPadding(top: topInset);
        tester.view.padding = FakeViewPadding(top: topInset);
        addTearDown(tester.view.reset);
        final repository = LiveRepository(
            openDatabase: () => databaseFactoryMemory
                .openDatabase('header-$topInset-$showBackButton'),
            client: MockClient((_) async => http.Response('', 404)));
        await tester.pumpWidget(ProviderScope(
            overrides: [
              liveRepositoryProvider.overrideWithValue(repository),
              liveSnapshotProvider
                  .overrideWith((_) => Stream.value(const LiveSnapshot())),
              liveNowNextProvider.overrideWith((_) async => {}),
              isTelevisionProvider.overrideWith((_) => topInset == 0),
            ],
            child:
                MaterialApp(home: LiveTvPage(showBackButton: showBackButton))));
        await tester.pumpAndSettle();
        final header = find
            .ancestor(of: find.text('直播'), matching: find.byType(Row))
            .first;
        expect(tester.getTopLeft(header).dy, topInset);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        repository.dispose();
      });
    }
  }
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
          epgId: 'one',
          lines: [LiveLine('https://example.test/a')]);
      const second = LiveChannel(
          id: 'b',
          sourceId: 's',
          name: '频道二',
          epgId: 'two',
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
            liveNowNextProvider.overrideWith((_) async => {
                  's|one': [
                    LiveProgramme(
                        channel: 'one',
                        title: '正在直播的新闻节目',
                        start: now.subtract(const Duration(hours: 1)),
                        end: now.add(const Duration(hours: 1))),
                  ],
                  's|two': [
                    LiveProgramme(
                        channel: 'two',
                        title: '体育赛事现场直播',
                        start: now.subtract(const Duration(hours: 1)),
                        end: now.add(const Duration(hours: 1))),
                  ],
                }),
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
      expect(_icon('上一频道'), findsNothing);
      expect(_icon('下一频道'), findsNothing);
      expect(_icon('音轨'), findsNothing);
      expect(_icon('播放设置'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(find.text('切换频道'), findsNothing);
      expect(_icon('上一频道'), findsNothing);
      expect(_icon('下一频道'), findsNothing);
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(_icon('音轨'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'live-settings-close');
      await _capture(tester, capture, 'settings-${size.width.toInt()}');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(engine.urls, ['https://example.test/a']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_icon('关闭设置'), findsNothing);
      expect(_icon('播放设置'), findsNothing);
      expect(find.byType(LiveNetworkSpeedLabel), findsOneWidget);
      await tester.pump();
      expect(find.text('2.0 KB/s · 32.0 MB · 18s'), findsOneWidget);
      expect(find.text('1920x1080 · HEVC · AAC'), findsOneWidget);
      expect(tester.getTopRight(find.byType(LiveNetworkSpeedLabel)).dx,
          closeTo(size.width - 12, 1));
      await _capture(tester, capture, 'player-${size.width.toInt()}');
      await tester.pump(const Duration(seconds: 4));
      engine.emit('progress');
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(LiveNetworkSpeedLabel), findsNothing);
      engine.emit('buffering');
      await tester.pump();
      expect(find.byType(LiveNetworkSpeedLabel), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await _capture(tester, capture, 'buffering-${size.width.toInt()}');
      engine.emit('progress');
      await tester.pump();
      expect(find.byType(LiveNetworkSpeedLabel), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.urls.last, 'https://example.test/b');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:b');
      expect(find.text('全部分组'), findsOneWidget);
      expect(find.text('正在直播的新闻节目'), findsOneWidget);
      expect(find.text('体育赛事现场直播'), findsOneWidget);
      expect(_icon('关闭'), findsNothing);
      expect(find.text('频道'), findsNothing);
      expect(tester.getTopLeft(find.text('全部分组')).dy, lessThan(48));
      final channelPanel =
          find.byKey(const ValueKey('live-channels-background'));
      expect(tester.getTopLeft(channelPanel).dx, 0);
      expect(tester.getSize(channelPanel).width,
          size.width < 720 ? size.width : 560);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:a');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-group:');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
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
      final guidePanel = find.byKey(const ValueKey('live-guide-background'));
      expect(tester.getTopRight(guidePanel).dx, size.width);
      expect(tester.getSize(guidePanel).width,
          size.width < 480 ? size.width : 440);
      expect(find.byType(LiveNetworkSpeedLabel), findsOneWidget);
      expect(
          find.descendant(
              of: guidePanel, matching: find.byType(LiveNetworkSpeedLabel)),
          findsOneWidget);
      expect(tester.getTopRight(find.text('节目单')).dx,
          lessThan(tester.getTopLeft(find.byType(LiveNetworkSpeedLabel)).dx));
      expect(tester.getBottomRight(find.byType(LiveNetworkSpeedLabel)).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(ListView)).dy));
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
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'live-settings-close');
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
    await _accentStates(tester);
    await _overlayBackNavigation(tester);
  });
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(640, 360),
    const Size(844, 390),
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
          epgId: 'news',
          group: '新闻与综合节目特别长的频道分组名称测试窄屏显示',
          lines: [LiveLine('https://example.test/live')]);
      const snapshot = LiveSnapshot(
          sources: [LiveSource(id: 's', name: 'Demo')],
          channels: [channel],
          preferences: {'one': LivePreference(favorite: true)},
          lastChannel: 'one');
      final capture = GlobalKey();
      final now = DateTime.now();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            liveChannelProbeProvider.overrideWithValue(_LayoutProbe()),
            liveProbeNetworkProvider.overrideWithValue(const Stream.empty()),
            liveRepositoryProvider.overrideWithValue(repository),
            liveSnapshotProvider.overrideWith((_) => Stream.value(snapshot)),
            liveNowNextProvider.overrideWith((_) async => {
                  's|news': [
                    LiveProgramme(
                        channel: 'news',
                        title: '新闻直播间特别报道',
                        start: now.subtract(const Duration(hours: 1)),
                        end: now.add(const Duration(hours: 1))),
                  ],
                }),
            isTelevisionProvider.overrideWith((_) => false),
          ],
          child: MaterialApp(
              theme: _reviewTheme,
              builder: (_, child) =>
                  RepaintBoundary(key: capture, child: child),
              home: const LiveTvPage())));
      await tester.pumpAndSettle();
      expect(find.text('综合新闻频道'), findsNWidgets(2));
      expect(find.text('正在播出 新闻直播间特别报道'), findsOneWidget);
      final logo = find.byType(LiveLogo);
      final channelTitle = find.descendant(
          of: find.byType(ListView), matching: find.text('综合新闻频道'));
      expect(tester.getSize(logo), const Size(64, 40));
      expect(
          tester.getTopLeft(channelTitle).dx, tester.getTopRight(logo).dx + 12);
      expect(tester.getTopRight(channelTitle).dx,
          lessThanOrEqualTo(tester.getTopLeft(_icon('取消收藏')).dx));
      expect(tester.takeException(), isNull);
      final favoriteIcon =
          find.descendant(of: _icon('取消收藏'), matching: find.byType(Icon));
      expect(tester.widget<Icon>(favoriteIcon).color, AppAccent.coral.primary);
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
            theme: _reviewTheme,
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
    expect(find.byType(SwitchListTile), findsNothing);
    await _capture(tester, capture, 'source-editor-320');
    await _press(tester, '保存');
    expect(find.byType(TextField), findsNothing);
    expect(repository.refreshes, 1,
        reason: 'New subscriptions are enabled by default');
    final toggle = find.ancestor(
        of: find.byType(Switch), matching: find.byType(TvFocusableAction));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.textContaining('已停用'), findsOneWidget);
    await tester.tap(_icon('编辑订阅'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    await _press(tester, '保存');
    expect(repository.refreshes, 1);
    expect(find.textContaining('已停用'), findsOneWidget,
        reason: 'Editing preserves disabled state');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
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
            theme: _reviewTheme,
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
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      await tester.pump();
      expect(find.byType(Switch), findsNothing);
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
      expect(replacement.openVolumes, [1]);
      final exitGate = Completer<void>();
      replacement.disposeGate = exitGate;
      tester.widget<LiveIconButton>(_icon('切换播放内核')).onPressed!();
      await tester.pump();
      await tester.binding.handlePopRoute();
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

Future<void> _accentStates(WidgetTester tester) async {
  const first = LiveChannel(id: 'a', sourceId: 's', name: 'First', lines: [
    LiveLine('https://example.test/a'),
    LiveLine('https://example.test/backup'),
  ]);
  const second = LiveChannel(id: 'b', sourceId: 's', name: 'Second', lines: [
    LiveLine('https://example.test/b'),
  ]);
  const snapshot = LiveSnapshot(
      sources: [LiveSource(id: 's', name: 'Source')],
      channels: [first, second]);
  for (final accent in AppAccent.values) {
    for (final tv in [false, true]) {
      final repository = LiveRepository(
          openDatabase: () =>
              databaseFactoryMemory.openDatabase('accent-$accent-$tv'),
          client: MockClient((_) async => http.Response('', 404)));
      final engine = _PageEngine();
      final now = DateTime.now();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            liveRepositoryProvider.overrideWithValue(repository),
            liveSnapshotProvider.overrideWith((_) => Stream.value(snapshot)),
            isTelevisionProvider.overrideWith((_) => tv),
            liveGuideProvider.overrideWith((_, __) async => [
                  LiveProgramme(
                      channel: 'a',
                      title: 'Current',
                      start: now.subtract(const Duration(minutes: 30)),
                      end: now.add(const Duration(minutes: 30))),
                  LiveProgramme(
                      channel: 'a',
                      title: 'Next',
                      start: now.add(const Duration(minutes: 30)),
                      end: now.add(const Duration(minutes: 60))),
                ]),
          ],
          child: MaterialApp(
              theme: AppTheme.dark(accent: accent)
                  .copyWith(splashFactory: NoSplash.splashFactory),
              home: LivePlayerPage(
                  initialChannel: first,
                  snapshot: snapshot,
                  engineFactory: () => engine))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(_icon('上一频道'), findsNothing);
      expect(_icon('下一频道'), findsNothing);
      expect(_icon('静音'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(find.byType(Switch), findsNothing);
      expect(find.text('静音'), findsNothing);
      expect(find.text('切换频道'), findsNothing);
      expect(_icon('上一频道'), findsNothing);
      expect(_icon('下一频道'), findsNothing);

      Future<void> expectLine(int index) async {
        final dropdown = find.byType(DropdownButton<int>);
        expect(tester.widget<DropdownButton<int>>(dropdown).value, index);
        expect(
            tester
                .widget<Text>(find.text('线路 ${index + 1}').hitTestable())
                .style!
                .color,
            accent.primary);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        expect(
            tester
                .widgetList<Icon>(find.byIcon(Icons.check))
                .every((icon) => icon.color == accent.primary),
            isTrue);
        await tester.tap(find.text('线路 ${2 - index}').last);
        await tester.pumpAndSettle();
      }

      await expectLine(0);
      expect(engine.urls.last, 'https://example.test/backup');
      await expectLine(1);
      expect(engine.urls.last, 'https://example.test/a');
      await tester.tap(_icon('关闭设置'));
      await tester.pump();
      for (final label in ['频道列表', '节目单']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        await tester.pump();
        await tester.tap(_icon(label));
        await tester.pump();
        final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
        expect(tiles.where((tile) => tile.selected), hasLength(1));
        final selected = tiles.singleWhere((tile) => tile.selected);
        expect(selected.selectedColor, accent.primary);
        expect(
            selected.selectedTileColor, accent.primary.withValues(alpha: .09));
        expect(tiles.where((tile) => !tile.selected), hasLength(1));
        if (tv && label == '频道列表') {
          expect(_icon('关闭'), findsNothing);
          expect(find.text('频道'), findsNothing);
          await tester.binding.handlePopRoute();
        } else {
          expect(_icon('关闭'), findsOneWidget);
          await tester.tap(_icon('关闭'));
        }
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump();
      repository.dispose();
    }
  }
}

Future<void> _overlayBackNavigation(WidgetTester tester) async {
  for (final tv in [false, true]) {
    for (final size in [const Size(320, 640), const Size(1280, 720)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      const rightInset = 24.0;
      tester.view.viewPadding = const FakeViewPadding(right: rightInset);
      tester.view.padding = const FakeViewPadding(right: rightInset);
      const channel = LiveChannel(
          id: 'back',
          sourceId: 's',
          name: '很长的直播频道名称测试固定高度',
          lines: [
            LiveLine('https://example.test/one'),
            LiveLine('https://example.test/two')
          ]);
      const snapshot = LiveSnapshot(
          sources: [LiveSource(id: 's', name: 'Source')], channels: [channel]);
      final repository = LiveRepository(
          openDatabase: () =>
              databaseFactoryMemory.openDatabase('back-$tv-$size'),
          client: MockClient((_) async => http.Response('', 404)));
      final engine = _PageEngine();
      final guide = Completer<List<LiveProgramme>>();
      final navigator = GlobalKey<NavigatorState>();
      final router = GoRouter(navigatorKey: navigator, routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('Outside player'))),
      ]);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            liveRepositoryProvider.overrideWithValue(repository),
            liveSnapshotProvider.overrideWith((_) => Stream.value(snapshot)),
            liveGuideProvider.overrideWith((_, __) => guide.future),
            isTelevisionProvider.overrideWith((_) => tv),
          ],
          child: MaterialApp.router(
              routerConfig: router,
              theme: _reviewTheme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!))));
      navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => LivePlayerPage(
              initialChannel: channel,
              snapshot: snapshot,
              engineFactory: () => engine)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 250));
      final header = find.byKey(const ValueKey('live-player-top-bar'));
      expect(tester.getSize(header).height, 112);
      expect(_icon('退出直播'), tv ? findsNothing : findsOneWidget);
      expect(_icon('播放设置'), tv ? findsNothing : findsOneWidget);
      expect(
          tester
              .getTopRight(
                  tv ? find.byType(LiveNetworkSpeedLabel) : _icon('播放设置'))
              .dx,
          tester.getTopRight(header).dx - 12);
      if (!tv) {
        expect(tester.getTopRight(find.byType(LiveNetworkSpeedLabel)).dx,
            lessThan(tester.getTopLeft(_icon('播放设置')).dx));
      }
      expect(tester.getTopLeft(find.text(channel.name)).dx,
          tester.getTopLeft(header).dx + (tv ? 12 : 60));
      final background =
          find.byKey(const ValueKey('live-player-top-bar-background'));
      expect(tester.widget<ColoredBox>(background).color,
          Colors.black.withValues(alpha: .2));
      final now = DateTime.now();
      guide.complete([
        LiveProgramme(
            channel: 'back',
            title: '当前节目名称很长也不能撑高控制栏',
            start: now.subtract(const Duration(hours: 1)),
            end: now.add(const Duration(hours: 1))),
        LiveProgramme(
            channel: 'back',
            title: '接下来节目名称同样很长',
            start: now.add(const Duration(hours: 1)),
            end: now.add(const Duration(hours: 2))),
      ]);
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(header).height, 112);
      for (final label in ['频道列表', '节目单', '上一频道', '下一频道', '音轨']) {
        expect(_icon(label), findsNothing);
      }
      final stops = engine.stops;
      final opens = engine.urls.length;
      for (final target in ['频道列表', '节目单', '播放设置']) {
        for (final back in ['system', 'escape', 'goBack', 'pop']) {
          if (tv) {
            await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
          } else {
            await tester.tap(_icon('播放设置'));
          }
          await tester.pump();
          expect(header, findsNothing);
          expect(find.byType(LiveNetworkSpeedLabel), findsNothing);
          _expectMenuBackground(tester, 'live-settings-background');
          if (target != '播放设置') {
            await tester.tap(_icon(target));
            await tester.pump();
            await tester.pump();
            _expectMenuBackground(
                tester,
                target == '频道列表'
                    ? 'live-channels-background'
                    : 'live-guide-background');
            if (target == '频道列表') {
              expect(find.byType(LiveLogo), findsNothing);
              expect(find.byType(Image), findsNothing);
              expect(find.byIcon(Icons.live_tv), findsOneWidget);
              expect(
                  tester
                      .getTopLeft(find
                          .byKey(const ValueKey('live-channels-background')))
                      .dx,
                  0);
            } else {
              final panel = find.byKey(const ValueKey('live-guide-background'));
              expect(tester.getTopRight(panel).dx, size.width - rightInset);
              expect(tester.getSize(panel).width,
                  size.width < 480 ? size.width - rightInset : 440);
              expect(find.byType(LiveNetworkSpeedLabel), findsOneWidget);
              expect(
                  find.descendant(
                      of: panel, matching: find.byType(LiveNetworkSpeedLabel)),
                  findsOneWidget);
            }
          }
          switch (back) {
            case 'system':
              await tester.binding.handlePopRoute();
            case 'pop':
              navigator.currentState!.pop();
            default:
              final key = back == 'escape'
                  ? LogicalKeyboardKey.escape
                  : LogicalKeyboardKey.goBack;
              const physical = PhysicalKeyboardKey.escape;
              expect(await tester.sendKeyDownEvent(key, physicalKey: physical),
                  isTrue);
              await tester.pump();
              expect(
                  await tester.sendKeyRepeatEvent(key, physicalKey: physical),
                  isTrue);
              final handled =
                  await tester.sendKeyUpEvent(key, physicalKey: physical);
              expect(handled, isTrue,
                  reason: 'Back release must not reach Android system back');
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(LivePlayerPage), findsOneWidget,
              reason: '$tv/$size/$target/$back must return to the player');
          expect(_icon('关闭设置'), findsNothing);
          expect(find.text('全部分组'), findsNothing);
          expect(_icon('关闭'), findsNothing);
          expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-player');
          expect(tester.getSize(header).height, 112);
          expect(_icon('退出直播'), tv ? findsNothing : findsOneWidget);
          expect(_icon('播放设置'), tv ? findsNothing : findsOneWidget);
          expect(engine.disposals, 0);
          expect(engine.stops, stops);
          expect(engine.urls.length, opens);
          engine.emit('progress');
        }
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      await tester.ensureVisible(find.byType(DropdownButton<int>));
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_icon('关闭设置'), findsOneWidget);
      await tester.ensureVisible(_icon('音轨'));
      await tester.tap(_icon('音轨'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_icon('关闭设置'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-player');
      if (tv) {
        await tester.sendKeyEvent(LogicalKeyboardKey.goBack,
            physicalKey: PhysicalKeyboardKey.escape);
      } else if (size.width == 320) {
        await tester.tap(_icon('退出直播'));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.text('Outside player'), findsOneWidget);
      expect(find.byType(LivePlayerPage), findsNothing);
      expect(engine.disposals, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      router.dispose();
      repository.dispose();
    }
  }
}

void _expectMenuBackground(WidgetTester tester, String key) {
  final background = find.byKey(ValueKey(key));
  expect(tester.widget<Material>(background).color,
      const Color(0xFF202020).withValues(alpha: .7));
  final nestedMaterials = tester.widgetList<Material>(
      find.descendant(of: background, matching: find.byType(Material)));
  expect(
      nestedMaterials.every((material) =>
          material.type == MaterialType.transparency || material.color?.a == 0),
      isTrue,
      reason: 'Menu content must not add another opaque surface');
  expect(find.descendant(of: background, matching: find.byType(Opacity)),
      findsNothing,
      reason: 'Only the background, not menu content, is faded');
}

const _review = bool.fromEnvironment('LIVE_TV_REVIEW');
ThemeData get _reviewTheme => AppTheme.dark(accent: AppAccent.coral).copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: AppTheme.dark(accent: AppAccent.coral)
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

class _LayoutProbe extends LiveChannelProbe {
  @override
  Future<LiveProbeResult> probe(LiveLine line,
          {required Future<void> cancel}) async =>
      LiveProbeResult(LiveProbeStatus.responded,
          checkedAt: DateTime.now(),
          latency: const Duration(milliseconds: 100));
}

class _PageEngine
    implements CancellableLiveEngine, LiveNetworkSpeedSource, LiveCacheSizeSource, LiveVideoFormatSource {
  void Function(String)? _onState;
  void emit(String state) => _onState?.call(state);
  @override
  Future<int?> readNetworkSpeed(int generation) async => 2048;
  @override
  Future<int?> readCacheBytes(int generation) async => 32 * 1024 * 1024;
  @override
  Future<int?> readBufferDurationMs(int generation) async => 18000;
  @override
  Future<String?> readVideoFormat(int generation) async => '1920x1080 · HEVC · AAC';
  final urls = <String>[];
  final openVolumes = <double>[];
  double volume = 1;
  int disposals = 0;
  int stops = 0;
  Completer<void>? disposeGate;
  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) async {
    urls.add(line.url);
    openVolumes.add(volume);
    _onState = (state) => onState(generation, state);
    onState(generation, 'progress');
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> cancelOpen() async {}
  @override
  Future<void> dispose() async {
    disposals++;
    await disposeGate?.future;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<List<(String, String)>> audioTracks() async => [];
  @override
  Future<void> selectAudio(String id) async {}
}
