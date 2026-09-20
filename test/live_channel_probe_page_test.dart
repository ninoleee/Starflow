import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/network/network_proxy_config.dart';
import 'package:starflow/core/network/network_proxy_runtime.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/features/live_tv/data/live_channel_probe.dart';
import 'package:starflow/features/live_tv/data/live_probe_network.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_probe_label.dart';
import 'package:starflow/features/live_tv/presentation/live_probe_viewport.dart';
import 'package:starflow/features/live_tv/presentation/live_player_page.dart';
import 'package:starflow/features/live_tv/presentation/live_tv_page.dart';
import 'package:starflow/features/live_tv/presentation/live_widgets.dart';

const _snapshot = LiveSnapshot(
  sources: [LiveSource(id: 's', name: 'Source')],
  channels: [
    LiveChannel(
        id: 'a',
        sourceId: 's',
        name: 'First channel long title',
        lines: [
          LiveLine('https://example.test/first'),
          LiveLine('https://example.test/preferred'),
        ]),
    LiveChannel(id: 'b', sourceId: 's', name: 'Second channel', lines: [
      LiveLine('https://example.test/second'),
    ]),
  ],
  preferences: {'a': LivePreference(line: 1)},
);

void main() {
  testWidgets('metadata snapshot preserves active probes and result labels',
      (tester) async {
    final probe = _Probe();
    final snapshots = StreamController<LiveSnapshot>();
    addTearDown(snapshots.close);
    await _mount(tester, probe, snapshots: snapshots.stream);
    snapshots.add(_snapshot);
    await _settle(tester);
    probe.gates.first.complete(LiveProbeResult(LiveProbeStatus.responded,
        checkedAt: DateTime.now(), latency: const Duration(milliseconds: 230)));
    await _settle(tester);
    final before = probe.cancellations;
    snapshots.add(LiveSnapshot(
        sources: _snapshot.sources,
        channels: _snapshot.channels,
        preferences: const {
          'a':
              LivePreference(line: 1, favorite: true, name: 'Renamed', order: 1)
        }));
    await _settle(tester);
    expect(probe.urls, hasLength(2));
    expect(probe.cancellations, before);
    expect(find.text('230 ms'), findsOneWidget);
    expect(find.text('Renamed'), findsOneWidget);
    expect(_button('停止检测 1/2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'network and proxy changes invalidate without restarting stopped detection',
      (tester) async {
    final network = StreamController<bool>.broadcast();
    addTearDown(network.close);
    final saved = networkProxyRuntime.config;
    addTearDown(() => networkProxyRuntime.configure(saved));
    final probe = _Probe();
    final navigator = GlobalKey<NavigatorState>();
    await _mount(tester, probe, network: network.stream, navigator: navigator);
    expect(network.hasListener, isTrue);
    network.add(false);
    await _settle(tester);
    expect(probe.cancellations, 2);
    expect(probe.urls, hasLength(2));
    network.add(true);
    await _settle(tester);
    expect(probe.urls, hasLength(4));
    networkProxyRuntime
        .configure(const NetworkProxyConfig(enabled: true, host: 'proxy.test'));
    await _settle(tester);
    expect(probe.urls, hasLength(6));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')))));
    await _settle(tester);
    expect(network.hasListener, isTrue);
    network.add(false);
    networkProxyRuntime.configure(saved);
    await _settle(tester);
    expect(probe.urls, hasLength(6));
    network.add(true);
    await _settle(tester);
    expect(probe.urls, hasLength(6));
    navigator.currentState!.pop();
    await _settle(tester);
    expect(probe.urls, hasLength(8));
    expect(network.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(network.hasListener, isFalse);
  });

  testWidgets('TV focused visible row is admitted first after 200ms',
      (tester) async {
    final probe = _Probe();
    final refresh = Completer<void>();
    await _mount(tester, probe, tv: true, refresh: refresh.future);
    final detector = tester.widget<FocusableActionDetector>(
        find.byWidgetPredicate((w) =>
            w is FocusableActionDetector &&
            w.focusNode?.debugLabel == 'tv-focus:live:b'));
    detector.focusNode!.requestFocus();
    await tester.pump();
    refresh.complete();
    await tester.pump();
    await tester.pump();
    expect(probe.urls, isEmpty);
    await tester.pump(const Duration(milliseconds: 199));
    expect(probe.urls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(probe.urls.first, 'https://example.test/second');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fresh cache survives route return; expired visible rows refresh',
      (tester) async {
    final probe = _Probe();
    final navigator = GlobalKey<NavigatorState>();
    await _mount(tester, probe, navigator: navigator);
    await _completeAvailable(tester, probe);
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')))));
    await _settle(tester);
    navigator.currentState!.pop();
    await _settle(tester);
    expect(probe.urls, hasLength(2));
    await tester.pump(const Duration(minutes: 5));
    await _settle(tester);
    expect(probe.urls, hasLength(4));
    expect(find.text('125 ms'), findsNWidgets(2));
    expect(find.byIcon(Icons.refresh), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual pause survives search, expiry and network until reentry',
      (tester) async {
    final probe = _Probe();
    final network = StreamController<bool>.broadcast();
    addTearDown(network.close);
    final navigator = GlobalKey<NavigatorState>();
    await _mount(tester, probe, navigator: navigator, network: network.stream);
    await _completeAvailable(tester, probe);
    await tester.tap(_button('停止检测 2/2'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'First');
    await _settle(tester);
    network.add(true);
    await tester.pump(const Duration(minutes: 10));
    await _settle(tester);
    expect(probe.urls, hasLength(2));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')))));
    await _settle(tester);
    navigator.currentState!.pop();
    await _settle(tester);
    expect(probe.urls, hasLength(3));
    expect(probe.urls.last, 'https://example.test/preferred');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'background while another route is open invalidates cache on return',
      (tester) async {
    final probe = _Probe();
    final navigator = GlobalKey<NavigatorState>();
    await _mount(tester, probe, navigator: navigator);
    await _completeAvailable(tester, probe);
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')))));
    await _settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(probe.urls, hasLength(2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(probe.urls, hasLength(2));
    navigator.currentState!.pop();
    await _settle(tester);
    expect(probe.urls, hasLength(4));
    await tester.pumpWidget(const SizedBox());
  });

  for (final tv in [false, true]) {
    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets('initial probe labels fit next to titles at $width TV=$tv',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 720);
        addTearDown(tester.view.reset);
        final probe = _Probe();
        await _mount(tester, probe, tv: tv);
        expect(probe.urls,
            ['https://example.test/preferred', 'https://example.test/second']);
        expect(find.text('检测中'), findsNWidgets(2));
        probe.gates[0].complete(LiveProbeResult(LiveProbeStatus.responded,
            checkedAt: DateTime.now(),
            latency: const Duration(milliseconds: 230)));
        probe.gates[1].complete(LiveProbeResult(LiveProbeStatus.httpError,
            checkedAt: DateTime.now(), httpStatus: 403));
        await _settle(tester);
        expect(find.text('230 ms'), findsOneWidget);
        expect(find.text('HTTP 403'), findsOneWidget);
        expect(_button('停止检测 2/2'), findsOneWidget);
        for (final channel in _snapshot.channels) {
          final title = find.text(channel.name);
          final label = find.byKey(ValueKey('live-probe:${channel.id}'));
          expect(tester.getTopRight(title).dx,
              lessThanOrEqualTo(tester.getTopLeft(label).dx - 6));
          expect(
              (tester.getCenter(title).dy - tester.getCenter(label).dy).abs(),
              lessThan(1));
        }
        expect(tester.takeException(), isNull);
        await _capture(tester, 'probe-${width.toInt()}-$tv');
        await tester.pump(const Duration(seconds: 1));
        await _settle(tester);
        expect(probe.urls, hasLength(2));
        await tester.tap(_button('停止检测 2/2'));
        await _settle(tester);
        if (tv) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(_button('检测可见频道'));
        }
        await _settle(tester);
        expect(probe.urls, [
          'https://example.test/preferred',
          'https://example.test/second',
        ]);
        await tester.pump(const Duration(minutes: 5));
        await _settle(tester);
        expect(probe.urls, hasLength(4));
        expect(find.text('230 ms'), findsOneWidget);
        expect(find.text('HTTP 403'), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await _capture(tester, 'probe-refresh-${width.toInt()}-$tv');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('empty and unavailable lists defer the first automatic probe',
      (tester) async {
    final probe = _Probe();
    final snapshots = StreamController<LiveSnapshot>();
    addTearDown(snapshots.close);
    await _mount(tester, probe, snapshots: snapshots.stream);
    expect(probe.urls, isEmpty);
    snapshots.add(const LiveSnapshot());
    await _settle(tester);
    expect(probe.urls, isEmpty);
    const unavailable = LiveSnapshot(sources: [
      LiveSource(id: 's', name: 'Source'),
      LiveSource(id: 'disabled', name: 'Disabled', enabled: false),
    ], channels: [
      LiveChannel(id: 'hidden', sourceId: 's', name: 'Hidden', lines: [
        LiveLine('https://example.test/hidden'),
      ]),
      LiveChannel(
          id: 'disabled',
          sourceId: 'disabled',
          name: 'Disabled',
          lines: [
            LiveLine('https://example.test/disabled'),
          ]),
      LiveChannel(id: 'empty', sourceId: 's', name: 'Empty', lines: []),
    ], preferences: {
      'hidden': LivePreference(hidden: true),
    });
    snapshots.add(unavailable);
    await _settle(tester);
    await tester.tap(_button('整理频道'));
    await _settle(tester);
    expect(find.text('Hidden'), findsOneWidget);
    expect(probe.urls, isEmpty);
    snapshots.add(LiveSnapshot(
      sources: unavailable.sources,
      channels: [...unavailable.channels, ..._snapshot.channels],
      preferences: {...unavailable.preferences, ..._snapshot.preferences},
    ));
    await _settle(tester);
    expect(probe.urls,
        ['https://example.test/preferred', 'https://example.test/second']);
    await tester.pumpWidget(const SizedBox());
  });

  for (final failed in [false, true]) {
    testWidgets('initial probe waits for source refresh, failure=$failed',
        (tester) async {
      final probe = _Probe();
      final refresh = Completer<void>();
      final snapshots = StreamController<LiveSnapshot>();
      addTearDown(snapshots.close);
      await _mount(tester, probe,
          snapshots: snapshots.stream, refresh: refresh.future);
      snapshots.add(_snapshot);
      await _settle(tester);
      expect(probe.urls, isEmpty);
      expect(find.text('未测'), findsNWidgets(2));
      if (failed) {
        refresh.completeError(StateError('Refresh failed'));
      } else {
        snapshots.add(const LiveSnapshot(sources: [
          LiveSource(id: 's', name: 'Source')
        ], channels: [
          LiveChannel(id: 'new', sourceId: 's', name: 'New channel', lines: [
            LiveLine('https://example.test/new'),
          ])
        ]));
        await _settle(tester);
        expect(probe.urls, isEmpty);
        refresh.complete();
      }
      await _settle(tester);
      expect(
          probe.urls,
          failed
              ? [
                  'https://example.test/preferred',
                  'https://example.test/second'
                ]
              : ['https://example.test/new']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('manual detection during refresh consumes the initial batch',
      (tester) async {
    final probe = _Probe();
    final refresh = Completer<void>();
    await _mount(tester, probe, refresh: refresh.future);
    expect(probe.urls, isEmpty);
    await tester.tap(_button('检测可见频道'));
    await _settle(tester);
    expect(probe.urls, hasLength(2));
    await tester.tap(_button('停止检测 0/2'));
    await _settle(tester);
    refresh.complete();
    await _settle(tester);
    expect(probe.urls, hasLength(2));
    expect(probe.cancellations, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an inactive tab waits until its first visible entry',
      (tester) async {
    final probe = _Probe();
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    await _mount(tester, probe, active: active);
    expect(probe.urls, isEmpty);
    active.value = true;
    await _settle(tester);
    expect(probe.urls, hasLength(2));
    active.value = false;
    await _settle(tester);
    expect(probe.cancellations, 2);
    active.value = true;
    await _settle(tester);
    expect(probe.urls, hasLength(4));
    await tester.pumpWidget(const SizedBox());
  });

  for (final reason in ['background', 'route', 'dispose']) {
    testWidgets('pending initial probe does not start after $reason',
        (tester) async {
      final probe = _Probe();
      final refresh = Completer<void>();
      final navigator = GlobalKey<NavigatorState>();
      await _mount(tester, probe,
          navigator: navigator, refresh: refresh.future);
      expect(probe.urls, isEmpty);
      switch (reason) {
        case 'background':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
        case 'route':
          unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Other page')))));
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      await _settle(tester);
      refresh.complete();
      await _settle(tester);
      expect(probe.urls, isEmpty);
      if (reason == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else if (reason == 'route') {
        navigator.currentState!.pop();
      }
      await _settle(tester);
      expect(probe.urls, hasLength(reason == 'dispose' ? 0 : 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('search cancels the old range and probes the new visible range',
      (tester) async {
    final probe = _Probe();
    await _mount(tester, probe);
    await tester.enterText(find.byType(TextField), 'First');
    await _settle(tester);
    expect(probe.cancellations, 2);
    expect(probe.urls, [
      'https://example.test/preferred',
      'https://example.test/second',
      'https://example.test/preferred',
    ]);
    await tester.enterText(find.byType(TextField), 'Second');
    await _settle(tester);
    expect(probe.cancellations, 3);
    expect(find.text('检测中'), findsOneWidget);
    expect(probe.urls, hasLength(4));
    expect(probe.urls.last, 'https://example.test/second');
    await tester.pumpWidget(const SizedBox());
  });

  for (final tv in [false, true]) {
    testWidgets('only viewport rows are probed while scrolling TV=$tv',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 720);
      addTearDown(tester.view.reset);
      final channels = List.generate(
          80,
          (i) => LiveChannel(
                id: '$i',
                sourceId: 's',
                name: 'Channel $i',
                lines: [LiveLine('https://example.test/$i')],
              ));
      final probe = _Probe();
      await _mount(tester, probe,
          tv: tv,
          snapshot: LiveSnapshot(
            sources: _snapshot.sources,
            channels: channels,
          ));
      final viewport = tester.getRect(find.byType(ListView));
      Set<String> visibleUrls() => {
            for (final element in find
                .byType(LiveProbeViewportItem, skipOffstage: false)
                .evaluate())
              if (tester
                  .getRect(find.byWidget(element.widget, skipOffstage: false))
                  .overlaps(viewport))
                (element.widget as LiveProbeViewportItem)
                    .channel
                    .lines
                    .first
                    .url,
          };
      final initial = visibleUrls();
      expect(initial.length, lessThan(channels.length));
      expect(
          find
              .byType(LiveProbeViewportItem, skipOffstage: false)
              .evaluate()
              .length,
          greaterThan(initial.length),
          reason: 'Offscreen cache rows exist');
      await _completeAvailable(tester, probe);
      expect(probe.urls.toSet(), initial);
      final count = probe.urls.length;
      await tester.drag(find.byType(ListView), const Offset(0, -950));
      await _settle(tester);
      final afterScroll = visibleUrls();
      expect(afterScroll.difference(initial), isNotEmpty);
      await _completeAvailable(tester, probe);
      expect(probe.urls.toSet().containsAll(afterScroll), isTrue);
      expect(probe.urls.length, greaterThan(count));
      expect(probe.urls.length, lessThan(channels.length));
      final beforeReturn = probe.urls.length;
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .jumpTo(0);
      await _settle(tester);
      expect(probe.urls.length, beforeReturn,
          reason: 'Completed rows are reused');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('scroll cancels offscreen requests before reusing their slots',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 720);
    addTearDown(tester.view.reset);
    final cleanup = Completer<void>();
    final probe = _Probe()..cleanup = cleanup;
    await _mount(tester, probe,
        snapshot: LiveSnapshot(
          sources: _snapshot.sources,
          channels: List.generate(
              80,
              (i) => LiveChannel(
                  id: '$i',
                  sourceId: 's',
                  name: 'Channel $i',
                  lines: [LiveLine('https://example.test/$i')])),
        ));
    expect(probe.urls, hasLength(2));
    tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .jumpTo(1500);
    await _settle(tester);
    expect(probe.cancellations, 2);
    expect(probe.urls, hasLength(2),
        reason: 'Transport cleanup still owns both slots');
    cleanup.complete();
    await _settle(tester);
    expect(probe.urls, hasLength(4));
    final viewport = tester.getRect(find.byType(ListView));
    final visible = {
      for (final element
          in find.byType(LiveProbeViewportItem, skipOffstage: false).evaluate())
        if (tester
            .getRect(find.byWidget(element.widget, skipOffstage: false))
            .overlaps(viewport))
          (element.widget as LiveProbeViewportItem).channel.lines.first.url,
    };
    expect(visible.containsAll(probe.urls.skip(2)), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(probe.cancellations, 4);
  });

  testWidgets(
      'group chooser pauses requests and continues in the selected group',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final probe = _Probe();
    final channels = [
      for (final group in ['A', 'B'])
        LiveChannel(
            id: group,
            sourceId: 's',
            name: 'Channel $group',
            group: group,
            lines: [LiveLine('https://example.test/$group')]),
    ];
    await _mount(tester, probe,
        snapshot: LiveSnapshot(sources: _snapshot.sources, channels: channels));
    expect(probe.urls, hasLength(2));
    await tester.tap(find.byType(DropdownButton<String>).first);
    await _settle(tester);
    expect(probe.cancellations, 2);
    expect(probe.urls, hasLength(2));
    await tester.tap(find.text('B').last);
    await _settle(tester);
    expect(probe.urls, [
      'https://example.test/A',
      'https://example.test/B',
      'https://example.test/B'
    ]);
    probe.gates.last.complete(LiveProbeResult(LiveProbeStatus.responded,
        checkedAt: DateTime.now(), latency: const Duration(milliseconds: 125)));
    await _settle(tester);
    await tester.tap(find.byType(DropdownButton<String>).first);
    await _settle(tester);
    await tester.tap(find.text('A').last);
    await _settle(tester);
    expect(probe.urls.last, 'https://example.test/A');
    expect(probe.urls, hasLength(4));
    await tester.tap(find.byType(DropdownButton<String>).first);
    await _settle(tester);
    await tester.tap(find.text('B').last);
    await _settle(tester);
    expect(probe.urls, hasLength(4));
    expect(find.text('125 ms'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final reason in ['stop', 'background', 'route', 'dispose']) {
    testWidgets('$reason cancels probes and only visible reentry resumes',
        (tester) async {
      final probe = _Probe();
      final navigator = GlobalKey<NavigatorState>();
      await _mount(tester, probe, navigator: navigator);
      expect(probe.urls, hasLength(2));
      switch (reason) {
        case 'stop':
          await tester.tap(_button('停止检测 0/2'));
        case 'background':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
        case 'route':
          unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Other page')))));
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      await _settle(tester);
      expect(probe.cancellations, 2);
      if (reason == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else if (reason == 'route') {
        navigator.currentState!.pop();
      }
      await _settle(tester);
      expect(probe.urls,
          hasLength(reason == 'background' || reason == 'route' ? 4 : 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('known offline state gates probes across background resume',
      (tester) async {
    final probe = _Probe();
    final network = StreamController<bool>.broadcast();
    addTearDown(network.close);
    await _mount(tester, probe, network: network.stream);
    network.add(false);
    await _settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(probe.urls, hasLength(2));
    network.add(true);
    await _settle(tester);
    expect(probe.urls, hasLength(4));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('result label exposes line and timestamp without media URL',
      (tester) async {
    final probe = _Probe();
    await _mount(tester, probe);
    probe.gates[0].complete(LiveProbeResult(LiveProbeStatus.timeout,
        checkedAt: DateTime(2026, 9, 20, 12, 34)));
    await _settle(tester);
    final tooltip = tester.widget<Tooltip>(find.descendant(
        of: find.byType(LiveProbeLabel).first, matching: find.byType(Tooltip)));
    expect(tooltip.message, contains('线路 2'));
    expect(tooltip.message, contains('12:34'));
    expect(tooltip.message, isNot(contains('https://')));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'snapshot replacement cancels queued work and invalidates changed lines',
      (tester) async {
    final probe = _Probe();
    final snapshots = StreamController<LiveSnapshot>();
    addTearDown(snapshots.close);
    await _mount(tester, probe, snapshots: snapshots.stream);
    snapshots.add(_snapshot);
    await _settle(tester);
    probe.gates[0].complete(LiveProbeResult(LiveProbeStatus.responded,
        checkedAt: DateTime.now(), latency: const Duration(milliseconds: 230)));
    await _settle(tester);
    expect(find.text('230 ms'), findsOneWidget);
    snapshots.add(const LiveSnapshot(sources: [
      LiveSource(id: 's', name: 'Source')
    ], channels: [
      LiveChannel(
          id: 'a',
          sourceId: 's',
          name: 'Changed',
          lines: [LiveLine('https://example.test/new')])
    ]));
    await _settle(tester);
    expect(find.text('230 ms'), findsNothing);
    expect(find.text('检测中'), findsOneWidget);
    expect(probe.urls, hasLength(3));
    expect(probe.urls.last, 'https://example.test/new');
    expect(_button('停止检测 0/1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'play waits for probe cleanup and coalesces repeated channel taps',
      (tester) async {
    final cleanup = Completer<void>();
    final probe = _Probe()..cleanup = cleanup;
    final observer = _PlayerObserver(() => expect(cleanup.isCompleted, isTrue));
    await _mount(tester, probe, observer: observer);
    await tester.tap(find.text(_snapshot.channels.first.name));
    await tester.tap(find.text(_snapshot.channels.first.name));
    await tester.pump();
    expect(observer.players, 0);
    expect(probe.cancellations, 2);
    cleanup.complete();
    await _settle(tester);
    expect(observer.players, 1);
    expect(probe.urls, hasLength(4), reason: 'Returning from player resumes');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Finder _button(String label) => find.byWidgetPredicate(
    (widget) => widget is LiveIconButton && widget.label == label);

Future<void> _mount(WidgetTester tester, _Probe probe,
    {bool tv = false,
    GlobalKey<NavigatorState>? navigator,
    NavigatorObserver? observer,
    Stream<LiveSnapshot>? snapshots,
    LiveSnapshot snapshot = _snapshot,
    Future<void>? refresh,
    Stream<bool> network = const Stream.empty(),
    ValueNotifier<bool>? active}) async {
  if (const bool.fromEnvironment('LIVE_TV_REVIEW')) {
    await tester.runAsync(() async {
      final font = FontLoader('ProbeReview');
      font.addFont(File('/System/Library/Fonts/STHeiti Light.ttc')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)));
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
  }
  final repository = _Repository(refresh: refresh);
  addTearDown(repository.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      liveRepositoryProvider.overrideWithValue(repository),
      liveSnapshotProvider
          .overrideWith((_) => snapshots ?? Stream.value(snapshot)),
      liveNowNextProvider.overrideWith((_) async => {}),
      liveChannelProbeProvider.overrideWithValue(probe),
      liveProbeNetworkProvider.overrideWithValue(network),
      isTelevisionProvider.overrideWith((_) => tv),
    ],
    child: MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [if (observer != null) observer],
        theme: AppTheme.dark().copyWith(
            textTheme: AppTheme.dark().textTheme.apply(
                fontFamily: const bool.fromEnvironment('LIVE_TV_REVIEW')
                    ? 'ProbeReview'
                    : null)),
        home: active == null
            ? const RepaintBoundary(
                key: ValueKey('probe-capture'), child: LiveTvPage())
            : ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (_, enabled, child) =>
                    TickerMode(enabled: enabled, child: child!),
                child: const LiveTvPage())),
  ));
  if (snapshots == null) {
    await _settle(tester);
  } else {
    await tester.pump();
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 210));
  await tester.pumpAndSettle();
}

Future<void> _completeAvailable(WidgetTester tester, _Probe probe) async {
  for (var i = 0; i < 100; i++) {
    final pending = probe.gates.where((gate) => !gate.isCompleted).toList();
    if (pending.isEmpty) return;
    for (final gate in pending) {
      gate.complete(LiveProbeResult(LiveProbeStatus.responded,
          checkedAt: DateTime.now(),
          latency: const Duration(milliseconds: 125)));
    }
    await _settle(tester);
  }
  fail('Probe queue did not settle');
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('LIVE_TV_REVIEW')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('probe-capture')));
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

class _Probe extends LiveChannelProbe {
  final urls = <String>[];
  final gates = <Completer<LiveProbeResult>>[];
  int cancellations = 0;
  Completer<void>? cleanup;
  @override
  Future<LiveProbeResult> probe(LiveLine line,
      {required Future<void> cancel}) async {
    urls.add(line.url);
    final gate = Completer<LiveProbeResult>();
    gates.add(gate);
    final result = await Future.any([
      gate.future,
      cancel.then((_) {
        cancellations++;
        return LiveProbeResult(LiveProbeStatus.cancelled,
            checkedAt: DateTime.now());
      }),
    ]);
    if (result.status == LiveProbeStatus.cancelled) await cleanup?.future;
    return result;
  }
}

class _Repository extends LiveRepository {
  _Repository({Future<void>? refresh})
      : _refresh = refresh,
        super(
            openDatabase: () =>
                databaseFactoryMemory.openDatabase('probe-page'),
            client: MockClient((_) async => http.Response('', 404)));
  final Future<void>? _refresh;
  @override
  Future<void> refreshDue({bool Function()? canContinue}) async {
    await _refresh;
  }
}

class _PlayerObserver extends NavigatorObserver {
  _PlayerObserver(this.onPlayer);
  final VoidCallback onPlayer;
  int players = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! MaterialPageRoute<void>) return;
    if (route.builder(navigator!.context) is! LivePlayerPage) return;
    players++;
    onPlayer();
    scheduleMicrotask(() => navigator!.pop());
  }
}
