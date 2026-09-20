import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/app/router/app_navigation_shell.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_player_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _channel = LiveChannel(
  id: 'last',
  sourceId: 'source',
  name: 'Last channel',
  lines: [LiveLine('https://example.test/live')],
);
const _snapshot = LiveSnapshot(
  sources: [LiveSource(id: 'source', name: 'Source')],
  channels: [_channel],
  preferences: {'last': LivePreference(line: 0)},
  lastChannel: 'last',
  engine: 'exo',
);

void main() {
  testWidgets(
      'TV menu playback consumes back release before returning to shell',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'] as int;
        final channel = MethodChannel('starflow/live_tv/$id');
        messenger.setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        return id;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views, null));
    final repository = _Repository(() async => _snapshot);
    final observer = _PlayerObserver(keepOpen: true);
    await _mount(tester, repository, observer);
    await _selectLive(tester);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(LivePlayerPage), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-player');

    const key = LogicalKeyboardKey.goBack;
    const physical = PhysicalKeyboardKey.escape;
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(find.text('播放设置'), findsOneWidget);
    await tester.sendKeyDownEvent(key, physicalKey: physical);
    await tester.pump(const Duration(milliseconds: 500));
    expect(await tester.sendKeyRepeatEvent(key, physicalKey: physical), isTrue);
    expect(await tester.sendKeyUpEvent(key, physicalKey: physical), isTrue);
    await tester.pump();
    expect(find.text('播放设置'), findsNothing);
    expect(find.byType(LivePlayerPage), findsOneWidget);
    expect(find.text('退出 Starflow？'), findsNothing);

    expect(await tester.sendKeyDownEvent(key, physicalKey: physical), isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LivePlayerPage), findsOneWidget);
    expect(await tester.sendKeyRepeatEvent(key, physicalKey: physical), isTrue);
    final releaseHandled =
        await tester.sendKeyUpEvent(key, physicalKey: physical);
    // Android can turn an unhandled BACK release into a system popRoute.
    if (!releaseHandled) await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('退出 Starflow？'), findsNothing);
    expect(releaseHandled, isTrue);
    expect(find.byType(LivePlayerPage), findsNothing);
    expect(find.text('live-tv'), findsOneWidget);
    expect(observer.players, hasLength(1));
    await _selectLive(tester);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(LivePlayerPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(LivePlayerPage), findsNothing);
    expect(find.text('退出 Starflow？'), findsNothing);
    expect(observer.players, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final tv in [false, true]) {
    testWidgets('menu resumes history only on TV (TV: $tv)', (tester) async {
      final repository = _Repository(() async => _snapshot);
      final observer = _PlayerObserver();
      final router = await _mount(tester, repository, observer, tv: tv);
      await _selectLive(tester, tv: tv);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/live-tv');
      expect(observer.players, hasLength(tv ? 1 : 0));
      expect(repository.reads, tv ? 1 : 0);
      if (tv) {
        expect(observer.players.single.initialChannel.id, 'last');
        expect(observer.players.single.snapshot.engine, 'exo');
        expect(observer.players.single.snapshot.preference(_channel).line, 0);
      }
      // The observer returns from playback immediately; ordinary rebuilds and
      // lifecycle transitions must not start another playback session.
      await tester.pump(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(observer.players, hasLength(tv ? 1 : 0));
      await _selectLive(tester, tv: tv);
      await tester.pumpAndSettle();
      expect(observer.players, hasLength(tv ? 2 : 0));
      router.go('/home');
      await tester.pumpAndSettle();
      await _selectLive(tester, tv: tv);
      await tester.pumpAndSettle();
      expect(observer.players, hasLength(tv ? 3 : 0));
      expect(repository.reads, tv ? 3 : 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  for (final tv in [false, true]) {
    testWidgets('disabled menu autoplay keeps channel list (TV: $tv)',
        (tester) async {
      final repository = _Repository(() async => _snapshot);
      final observer = _PlayerObserver();
      final router =
          await _mount(tester, repository, observer, tv: tv, autoPlay: false);
      for (var tap = 0; tap < 3; tap++) {
        if (tap == 2) {
          router.go('/home');
          await tester.pumpAndSettle();
        }
        await _selectLive(tester, tv: tv);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/live-tv');
        expect(observer.players, isEmpty);
        expect(repository.reads, 0);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  final unavailable = <String, LiveSnapshot>{
    'no history': const LiveSnapshot(
      sources: [LiveSource(id: 'source', name: 'Source')],
      channels: [_channel],
    ),
    'deleted channel': const LiveSnapshot(lastChannel: 'last'),
    'disabled source': const LiveSnapshot(
      sources: [LiveSource(id: 'source', name: 'Source', enabled: false)],
      channels: [_channel],
      lastChannel: 'last',
    ),
    'hidden channel': const LiveSnapshot(
      sources: [LiveSource(id: 'source', name: 'Source')],
      channels: [_channel],
      preferences: {'last': LivePreference(hidden: true)},
      lastChannel: 'last',
    ),
    'no playable lines': const LiveSnapshot(
      sources: [LiveSource(id: 'source', name: 'Source')],
      channels: [
        LiveChannel(id: 'last', sourceId: 'source', name: 'Empty', lines: [])
      ],
      lastChannel: 'last',
    ),
  };
  for (final entry in unavailable.entries) {
    testWidgets('${entry.key} leaves the channel branch open', (tester) async {
      final repository = _Repository(() async => entry.value);
      final observer = _PlayerObserver();
      final router = await _mount(tester, repository, observer);
      await _selectLive(tester);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/live-tv');
      expect(observer.players, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('history read failure keeps navigation usable', (tester) async {
    final repository = _Repository(() async => throw StateError('read failed'));
    final observer = _PlayerObserver();
    final router = await _mount(tester, repository, observer);
    await _selectLive(tester);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/live-tv');
    expect(observer.players, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final cancel in ['menu', 'background', 'dispose']) {
    testWidgets('$cancel cancels pending history playback', (tester) async {
      final gate = Completer<LiveSnapshot>();
      final repository = _Repository(() => gate.future);
      final observer = _PlayerObserver();
      await _mount(tester, repository, observer);
      await _selectLive(tester);
      await tester.pumpAndSettle();
      switch (cancel) {
        case 'menu':
          await tester.tap(find.byIcon(Icons.tune_outlined));
        case 'background':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      gate.complete(_snapshot);
      await tester.pumpAndSettle();
      expect(observer.players, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('rapid taps ignore older reads and use the latest history',
      (tester) async {
    final gates = <Completer<LiveSnapshot>>[];
    final repository = _Repository(() {
      final gate = Completer<LiveSnapshot>();
      gates.add(gate);
      return gate.future;
    });
    final observer = _PlayerObserver();
    await _mount(tester, repository, observer);
    await _selectLive(tester);
    await tester.pumpAndSettle();
    await _selectLive(tester);
    await tester.pumpAndSettle();
    expect(gates, hasLength(2));
    gates.last.complete(_snapshot);
    await tester.pumpAndSettle();
    expect(observer.players, hasLength(1));
    gates.first.complete(_snapshot);
    await tester.pumpAndSettle();
    expect(observer.players, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
}

Future<GoRouter> _mount(
    WidgetTester tester, _Repository repository, _PlayerObserver observer,
    {bool tv = true, bool autoPlay = true}) async {
  final router = GoRouter(
    initialLocation: '/home',
    observers: [observer],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppNavigationShell(navigationShell: shell),
        branches: [
          for (final path in [
            'home',
            'search',
            'favorites',
            'library',
            'settings',
            'live-tv'
          ])
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/$path',
                  builder: (_, __) => Scaffold(body: Text(path))),
            ]),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(repository.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    liveRepositoryProvider.overrideWithValue(repository),
    liveSnapshotProvider.overrideWith((_) => Stream.value(_snapshot)),
    liveGuideProvider.overrideWith((_, __) async => []),
    isTelevisionProvider.overrideWith((_) => tv),
    appSettingsProvider.overrideWithValue(AppSettings(
      liveNavigationAutoPlayEnabled: autoPlay,
      mediaSources: [],
      searchProviders: [],
      doubanAccount: const DoubanAccountConfig(enabled: false),
      homeModules: [],
      homeStartupAutoRefreshEnabled: false,
      autoHideNavigationBarEnabled: false,
      navigationDestinationIds: ['home', 'live-tv', 'settings'],
    )),
  ], child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _selectLive(WidgetTester tester, {bool tv = true}) async {
  if (tv) {
    final action = tester.widget<TvFocusableAction>(find.byWidgetPredicate(
      (w) => w is TvFocusableAction && w.focusNode?.debugLabel == 'tv-nav-1',
    ));
    action.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await tester.tap(find.byIcon(Icons.live_tv_outlined).evaluate().isNotEmpty
        ? find.byIcon(Icons.live_tv_outlined)
        : find.byIcon(Icons.live_tv));
  }
}

class _Repository extends LiveRepository {
  _Repository(this.readSnapshot)
      : super(
          openDatabase: () => databaseFactoryMemory.openDatabase('navigation'),
          client: MockClient((_) async => http.Response('', 404)),
        );
  final Future<LiveSnapshot> Function() readSnapshot;
  int reads = 0;
  @override
  Future<LiveSnapshot> load() {
    reads++;
    return readSnapshot();
  }
}

class _PlayerObserver extends NavigatorObserver {
  _PlayerObserver({this.keepOpen = false});
  final bool keepOpen;
  final players = <LivePlayerPage>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! MaterialPageRoute<void>) return;
    final page = route.builder(navigator!.context);
    if (page is! LivePlayerPage) return;
    players.add(page);
    // Inspect the real playback destination without starting native decoders.
    if (!keepOpen) scheduleMicrotask(() => navigator!.pop());
  }
}
