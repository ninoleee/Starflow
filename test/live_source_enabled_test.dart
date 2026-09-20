import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_sources_page.dart';
import 'package:starflow/features/live_tv/presentation/live_widgets.dart';

const _source = LiveSource(
    id: 's',
    name: 'A long subscription name that wraps on narrow screens',
    url: 'https://example.test/list',
    epgUrl: 'https://example.test/epg',
    refreshHours: 48);

class _ToggleRepository extends LiveRepository {
  _ToggleRepository()
      : super(
            openDatabase: () => databaseFactoryMemory.openDatabase('unused'),
            client: MockClient((_) async => http.Response('', 404)));
  final snapshots = StreamController<LiveSnapshot>.broadcast();
  LiveSource source = _source;
  Completer<void>? pending;
  int calls = 0;

  @override
  Stream<LiveSnapshot> watch() async* {
    yield LiveSnapshot(sources: [source]);
    yield* snapshots.stream;
  }

  @override
  Future<void> setSourceEnabled(String id, bool enabled) async {
    calls++;
    if (pending != null) await pending!.future;
    source = LiveSource.fromJson({...source.toJson(), 'enabled': enabled});
    snapshots.add(LiveSnapshot(sources: [source]));
  }

  @override
  void dispose() {
    snapshots.close();
    super.dispose();
  }
}

void main() {
  for (final tv in [false, true]) {
    testWidgets('list toggles persist with touch and remote (TV: $tv)',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      final repository = _ToggleRepository();
      addTearDown(repository.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        isTelevisionProvider.overrideWith((_) => tv),
        liveRepositoryProvider.overrideWithValue(repository),
      ], child: MaterialApp(home: const LiveSourcesPage())));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('source-enabled-s'));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      if (tv) {
        final focus = find.descendant(
            of: toggle,
            matching: find
                .byWidgetPredicate((w) => w is Focus && w.focusNode != null));
        tester.widget<Focus>(focus.first).focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(toggle);
      }
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.textContaining('已停用'), findsOneWidget);
      final refresh = find.byWidgetPredicate(
          (w) => w is LiveIconButton && w.label == '更新频道与节目单');
      expect(tester.widget<LiveIconButton>(refresh).onPressed, isNull);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(repository.source.enabled, isTrue);
      expect(tester.widget<LiveIconButton>(refresh).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending toggle blocks repeats and failed save retains state',
      (tester) async {
    final repository = _ToggleRepository()..pending = Completer<void>();
    addTearDown(repository.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      isTelevisionProvider.overrideWith((_) => false),
      liveRepositoryProvider.overrideWithValue(repository),
    ], child: const MaterialApp(home: LiveSourcesPage())));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('source-enabled-s'));
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<TvFocusableAction>(toggle).onPressed, isNull);
    await tester.tap(toggle);
    expect(repository.calls, 1);
    repository.pending!.completeError(StateError('write failed'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('订阅状态保存失败，请重试'), findsOneWidget);
    expect(tester.widget<TvFocusableAction>(toggle).onPressed, isNotNull);
  });

  test('toggle preserves cached data and does not recreate deleted sources',
      () async {
    var requests = 0;
    final repository = LiveRepository(
        openDatabase: () => databaseFactoryMemory.openDatabase('toggle-data'),
        client: MockClient((_) async {
          requests++;
          return http.Response('News,https://example.test/live', 200);
        }));
    addTearDown(repository.dispose);
    await repository.saveSource(const LiveSource(
        id: 's', name: 'Source', url: 'https://example.test/list'));
    await repository.refresh('s');
    final channel = (await repository.load()).channels.single;
    await repository.preference(channel.id, {'favorite': true});
    final before = await repository.load();
    final requestsBefore = requests;
    await repository.setSourceEnabled('s', false);
    final disabled = await repository.load();
    expect(disabled.sources.single.toJson(),
        {...before.sources.single.toJson(), 'enabled': false});
    expect(disabled.channels.single.toJson(), channel.toJson());
    expect(disabled.preferences[channel.id]!.toJson(),
        before.preferences[channel.id]!.toJson());
    await repository.refresh('s');
    expect(requests, requestsBefore);
    await repository.setSourceEnabled('s', true);
    expect((await repository.load()).sources.single.toJson(),
        before.sources.single.toJson());
    expect(requests, requestsBefore);
    await repository.removeSource('s');
    await repository.setSourceEnabled('s', true);
    expect((await repository.load()).sources, isEmpty);
  });
}
