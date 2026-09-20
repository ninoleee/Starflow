import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/live_tv/data/live_logo_provider.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_channel_picker.dart';
import 'package:starflow/features/live_tv/presentation/live_logo.dart';

void main() {
  for (final width in [320.0, 390.0, 560.0]) {
    testWidgets('channel rows fit without loading logos at $width',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 480);
      addTearDown(tester.view.reset);
      const current = LiveChannel(
          id: 'current',
          sourceId: 's',
          name: 'Current channel with a long name',
          logo: 'https://example.test/original.png',
          lines: [LiveLine('https://example.test/current')]);
      const other = LiveChannel(
          id: 'other',
          sourceId: 's',
          name: 'Other channel with a long name',
          logo: 'https://example.test/other.png',
          lines: [LiveLine('https://example.test/other')]);
      const missing = LiveChannel(
          id: 'missing',
          sourceId: 's',
          name: 'No logo',
          lines: [LiveLine('https://example.test/missing')]);
      const snapshot = LiveSnapshot(
          sources: [LiveSource(id: 's', name: 'Source')],
          channels: [current, other, missing],
          preferences: {
            'current': LivePreference(logo: 'https://example.test/override.png')
          });
      final requests = <String>[];
      final selections = <String>[];
      await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((_) => false),
            liveLogoProvider.overrideWith((_, url) async {
              requests.add(url);
              throw StateError('Player must not load logos');
            }),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: LiveChannelPicker(
                      snapshot: snapshot,
                      currentChannel: current,
                      onSelected: (c) => selections.add(c.id))))));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(find.byType(LiveLogo), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.live_tv), findsNWidgets(3));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      for (final channel in snapshot.channels) {
        final tile = find.ancestor(
            of: find.text(channel.name), matching: find.byType(ListTile));
        final icon = find.descendant(
            of: tile, matching: find.byIcon(Icons.live_tv));
        final title = find.text(channel.name);
        final trailing = find.byWidget(tester.widget<ListTile>(tile).trailing!);
        expect(tester.getSize(icon), const Size(20, 20));
        expect(tester.getTopLeft(title).dx,
            greaterThanOrEqualTo(tester.getTopRight(icon).dx + 8));
        expect(tester.getTopRight(title).dx,
            lessThanOrEqualTo(tester.getTopLeft(trailing).dx));
      }
      final otherIcon = find.descendant(
          of: find.ancestor(
              of: find.text(other.name), matching: find.byType(ListTile)),
          matching: find.byIcon(Icons.live_tv));
      await tester.tap(otherIcon);
      expect(selections, ['other']);
      expect(requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('touch group filtering and long labels fit a 320px viewport',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(tester.view.reset);
    final close = FocusNode();
    addTearDown(close.dispose);
    const first = LiveChannel(
        id: 'a',
        sourceId: 's',
        name: '综合新闻频道特别长的频道名称',
        group: '综合新闻特别长的频道分组名称',
        lines: [LiveLine('https://example.test/a')]);
    const second = LiveChannel(
        id: 'b',
        sourceId: 's',
        name: '体育频道',
        group: '体育',
        lines: [LiveLine('https://example.test/b')]);
    const snapshot = LiveSnapshot(
        sources: [LiveSource(id: 's', name: 'Source')],
        channels: [first, second]);
    final selections = <String>[];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((_) => false),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: LiveChannelPicker(
          snapshot: snapshot,
          currentChannel: first,
          closeFocus: close,
          onSelected: (c) => selections.add(c.id),
        )))));
    await tester.pumpAndSettle();
    expect(find.text(first.name).hitTestable(), findsOneWidget);
    await tester.tap(find.text('体育'));
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    await tester.tap(find.text('体育频道'));
    expect(selections, ['b']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 390.0, 560.0]) {
    testWidgets(
        'current channel is visible and focused in two columns at $width',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 480);
      addTearDown(tester.view.reset);
      final close = FocusNode();
      addTearDown(close.dispose);
      final key = GlobalKey<LiveChannelPickerState>();
      final channels = List.generate(
          100,
          (i) => LiveChannel(
              id: '$i',
              sourceId: 's',
              name: 'Channel $i',
              group: i < 80 ? 'News' : 'Sports',
              logo: 'https://example.test/logo-$i.png',
              lines: [LiveLine('https://example.test/$i')]));
      final snapshot = LiveSnapshot(
          sources: const [LiveSource(id: 's', name: 'Source')],
          channels: channels);
      final selections = <String>[];
      final logoRequests = <String>[];
      Widget picker() => ProviderScope(
              overrides: [
                isTelevisionProvider.overrideWith((_) => true),
                liveLogoProvider.overrideWith((_, url) async {
                  logoRequests.add(url);
                  throw StateError('Player must not load logos');
                }),
              ],
              child: MaterialApp(
                  theme: ThemeData.dark(),
                  home: Scaffold(
                    body: Column(children: [
                      IconButton(
                          focusNode: close,
                          onPressed: () {},
                          icon: const Icon(Icons.close)),
                      Expanded(
                          child: LiveChannelPicker(
                              key: key,
                              snapshot: snapshot,
                              currentChannel: channels[65],
                              closeFocus: close,
                              onSelected: (c) => selections.add(c.id))),
                    ]),
                  )));
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(picker());
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:65');
      expect(find.text('Channel 65').hitTestable(), findsOneWidget);
      expect(logoRequests, isEmpty);
      expect(find.byType(LiveLogo), findsNothing);
      expect(tester.getTopLeft(find.text('News')).dx,
          lessThan(tester.getTopLeft(find.text('Channel 65')).dx));
      expect(
          tester
              .widgetList<ListTile>(find.byType(ListTile))
              .where((tile) => tile.selected),
          hasLength(1));

      for (var i = 0; i < 10; i++) {
        await press(LogicalKeyboardKey.arrowDown);
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:75');
      expect(find.text('Channel 75').hitTestable(), findsOneWidget);
      await press(LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-group:News');
      await press(LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:75');
      await press(LogicalKeyboardKey.arrowLeft);
      await press(LogicalKeyboardKey.arrowDown);
      expect(
          FocusManager.instance.primaryFocus?.debugLabel, 'live-group:Sports');
      expect(find.text('Channel 80').hitTestable(), findsOneWidget);
      await press(LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:80');
      expect(selections, isEmpty, reason: 'Browsing never tunes a channel');
      await press(LogicalKeyboardKey.enter);
      expect(selections, ['80']);
      await press(LogicalKeyboardKey.arrowUp);
      expect(close.hasFocus, isTrue);

      // Reopening resets browsing state to the actual playback selection.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(picker());
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:65');
      expect(logoRequests, isEmpty,
          reason: 'Scrolling, group changes and reopening must not load logos');
      expect(find.byType(LiveLogo), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'late group, missing current channel, and empty snapshot stay usable',
      (tester) async {
    final close = FocusNode();
    addTearDown(close.dispose);
    final channels = List.generate(
        80,
        (i) => LiveChannel(
            id: '$i',
            sourceId: 's',
            name: 'Channel $i',
            group: 'Group $i',
            lines: [LiveLine('https://example.test/$i')]));
    var snapshot = LiveSnapshot(
        sources: const [LiveSource(id: 's', name: 'Source')],
        channels: channels);
    final key = GlobalKey<LiveChannelPickerState>();
    Widget page() => ProviderScope(
            overrides: [
              isTelevisionProvider.overrideWith((_) => true),
            ],
            child: MaterialApp(
                home: Scaffold(
                    body: SizedBox(
                        width: 560,
                        child: LiveChannelPicker(
                            key: key,
                            snapshot: snapshot,
                            currentChannel: channels[70],
                            closeFocus: close,
                            onSelected: (_) {})))));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'live-group:Group 70');
    expect(find.text('Group 70').hitTestable(), findsOneWidget);
    snapshot =
        LiveSnapshot(sources: snapshot.sources, channels: [channels.first]);
    await tester.pumpWidget(page());
    key.currentState!.focusChannels();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-overlay:0');
    snapshot = const LiveSnapshot();
    await tester.pumpWidget(page());
    key.currentState!.focusChannels();
    await tester.pumpAndSettle();
    expect(find.text('暂无频道'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'live-group:');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
