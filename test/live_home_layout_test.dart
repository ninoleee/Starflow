import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/live_tv/data/live_channel_probe.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_tv_page.dart';
import 'package:starflow/features/live_tv/presentation/live_widgets.dart';

const _snapshot = LiveSnapshot(
  sources: [LiveSource(id: 'source', name: 'Source')],
  channels: [
    LiveChannel(
        id: 'news',
        sourceId: 'source',
        name: 'News channel',
        group: 'News',
        lines: [LiveLine('https://example.test/news')]),
    LiveChannel(
        id: 'sports',
        sourceId: 'source',
        name: 'Sports channel',
        group: 'Sports',
        lines: [LiveLine('https://example.test/sports')]),
    LiveChannel(
        id: 'other',
        sourceId: 'source',
        name: 'Other channel',
        group: 'Sports',
        lines: [LiveLine('https://example.test/other')]),
  ],
  preferences: {'sports': LivePreference(favorite: true)},
);

final _groups = find.byKey(const PageStorageKey('live-home-groups'));
final _channels = find.byKey(const PageStorageKey('live-home-channels'));
final _groupDropdown = find.byKey(const ValueKey('live-home-group-dropdown'));
Finder _group(String group) => find.byKey(ValueKey('live-home-group:$group'));

void main() {
  for (final tv in [false, true]) {
    for (final size in [
      const Size(390, 844),
      const Size(768, 1024),
      const Size(640, 360),
      const Size(844, 390),
      const Size(1280, 720),
    ]) {
      testWidgets('home follows orientation at $size TV=$tv', (tester) async {
        _setSize(tester, size);
        await _mount(tester, tv: tv);
        if (size.width > size.height) {
          expect(_groups, findsOneWidget);
          expect(tester.getRect(_groups).right,
              lessThan(tester.getRect(_channels).left));
          expect(tester.getRect(_groups).top, tester.getRect(_channels).top);
          expect(
              tester.getRect(_groups).bottom, tester.getRect(_channels).bottom);
          expect(_groupDropdown, findsNothing);
          await tester.tap(_group('Sports'));
          await tester.pumpAndSettle();
          expect(find.text('News channel'), findsNothing);
          expect(find.text('Sports channel'), findsOneWidget);
          expect(find.text('Other channel'), findsOneWidget);
          final selected = find.descendant(
              of: _group('Sports'), matching: find.byType(LiveSelectionLabel));
          expect(tester.widget<LiveSelectionLabel>(selected).selected, isTrue);
          expect(
              tester
                  .widget<ColoredBox>(find.descendant(
                      of: _group('Sports'), matching: find.byType(ColoredBox)))
                  .color,
              AppAccent.coral.primary.withValues(alpha: .09));
          await tester.tap(_group(''));
          await tester.pumpAndSettle();
          expect(find.text('News channel'), findsOneWidget);
        } else {
          expect(_groups, findsNothing);
          expect(_groupDropdown, findsOneWidget);
          expect(tester.getRect(_groupDropdown).bottom,
              lessThanOrEqualTo(tester.getRect(_channels).top));
          await tester.tap(_groupDropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Sports').last);
          await tester.pumpAndSettle();
          expect(find.text('News channel'), findsNothing);
          expect(find.text('Sports channel'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('rotation retains group, search, favorites and organize state',
      (tester) async {
    _setSize(tester, const Size(390, 844));
    await _mount(tester);
    await tester.tap(_groupDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sports').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'channel');
    await tester.tap(find.byType(FilterChip));
    await tester.tap(find
        .byWidgetPredicate((w) => w is LiveIconButton && w.label == '整理频道'));
    await tester.pumpAndSettle();
    for (final size in [const Size(844, 390), const Size(390, 844)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'channel');
      expect(
          tester.widget<FilterChip>(find.byType(FilterChip)).selected, isTrue);
      expect(find.text('Sports channel'), findsOneWidget);
      expect(find.text('News channel'), findsNothing);
      expect(find.text('Other channel'), findsNothing);
      expect(
          find.byWidgetPredicate(
              (w) => w is LiveIconButton && w.label == '隐藏频道'),
          findsOneWidget);
      if (size.width > size.height) {
        expect(
            tester
                .widget<LiveSelectionLabel>(find.descendant(
                    of: _group('Sports'),
                    matching: find.byType(LiveSelectionLabel)))
                .selected,
            isTrue);
      } else {
        expect(
            tester
                .widget<DropdownButton<String>>(
                    _groupDropdown)
                .value,
            'Sports');
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('landscape columns scroll independently and fit long groups',
      (tester) async {
    _setSize(tester, const Size(640, 360));
    final snapshot = LiveSnapshot(sources: _snapshot.sources, channels: [
      for (var i = 0; i < 40; i++)
        LiveChannel(
            id: '$i',
            sourceId: 'source',
            name: 'Channel $i',
            group:
                'Group ${i.toString().padLeft(2, '0')} with a very long name',
            lines: [LiveLine('https://example.test/$i')]),
    ]);
    await _mount(tester, snapshot: snapshot, textScale: 1.5);
    ScrollPosition position(Finder list) => tester
        .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)))
        .position;
    await tester.drag(_groups, const Offset(0, -400));
    await tester.pumpAndSettle();
    final groupOffset = position(_groups).pixels;
    expect(groupOffset, greaterThan(0));
    expect(position(_channels).pixels, 0);
    await tester.drag(_channels, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(position(_channels).pixels, greaterThan(0));
    expect(position(_groups).pixels, groupOffset);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TV can select groups and navigate between the columns',
      (tester) async {
    _setSize(tester, const Size(1280, 720));
    await _mount(tester, tv: true);
    final detector = tester.widget<FocusableActionDetector>(find.descendant(
        of: _group('News'), matching: find.byType(FocusableActionDetector)));
    detector.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'tv-focus:live-home-group:Sports');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('News channel'), findsNothing);
    expect(find.text('Sports channel'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus!;
    expect(focused.debugLabel, startsWith('tv-focus:live:'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('tv-focus:live-home-group:'));
    expect(find.byType(LiveTvPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removed group falls back to all, including an empty snapshot',
      (tester) async {
    _setSize(tester, const Size(844, 390));
    final snapshots = StreamController<LiveSnapshot>();
    addTearDown(snapshots.close);
    await _mount(tester, snapshots: snapshots.stream);
    snapshots.add(_snapshot);
    await tester.pumpAndSettle();
    await tester.tap(_group('Sports'));
    await tester.pumpAndSettle();
    snapshots.add(LiveSnapshot(
        sources: _snapshot.sources, channels: [_snapshot.channels.first]));
    await tester.pumpAndSettle();
    expect(_group('Sports'), findsNothing);
    expect(find.text('News channel'), findsOneWidget);
    expect(
        tester
            .widget<LiveSelectionLabel>(find.descendant(
                of: _group(''), matching: find.byType(LiveSelectionLabel)))
            .selected,
        isTrue);
    snapshots.add(const LiveSnapshot());
    await tester.pumpAndSettle();
    expect(_group(''), findsOneWidget);
    expect(find.text('尚未添加直播订阅'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> _mount(WidgetTester tester,
    {bool tv = false,
    double textScale = 1,
    LiveSnapshot snapshot = _snapshot,
    Stream<LiveSnapshot>? snapshots}) async {
  final repository = LiveRepository(
      openDatabase: () => databaseFactoryMemory.openDatabase('home-layout'),
      client: MockClient((_) async => http.Response('', 404)));
  addTearDown(repository.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        liveRepositoryProvider.overrideWithValue(repository),
        liveSnapshotProvider
            .overrideWith((_) => snapshots ?? Stream.value(snapshot)),
        liveNowNextProvider.overrideWith((_) async => {}),
        liveChannelProbeProvider.overrideWithValue(_Probe()),
        isTelevisionProvider.overrideWith((_) => tv),
      ],
      child: MaterialApp(
          theme: AppTheme.dark(accent: AppAccent.coral),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: const LiveTvPage())));
  if (snapshots == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _Probe extends LiveChannelProbe {
  @override
  Future<LiveProbeResult> probe(LiveLine line,
          {required Future<void> cancel}) async =>
      LiveProbeResult(LiveProbeStatus.responded,
          checkedAt: DateTime.now(),
          latency: const Duration(milliseconds: 100));
}
