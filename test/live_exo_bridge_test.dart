import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> emit(MethodChannel channel, int generation, String state) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('state', {
          'generation': generation,
          'state': state,
        })),
        (ByteData? _) {},
      );

  test('Exo live bridge forwards scoped headers, generation and audio commands',
      () async {
    const channel = MethodChannel('starflow/live_tv/42');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'audioTracks') {
        return [
          {'id': '0:1', 'title': '中文', 'selected': true}
        ];
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final engine = ExoLiveEngine(42);
    final events = <(int, String)>[];
    await engine.open(
        const LiveLine('https://example.test/live',
            headers: {'User-Agent': 'Starflow'}),
        7,
        (g, s) => events.add((g, s)));
    expect(calls.single.arguments, {
      'url': 'https://example.test/live',
      'headers': {'User-Agent': 'Starflow'},
      'generation': 7,
      'volume': 1.0,
    });
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
                const MethodCall('state', {'generation': 7, 'state': 'frame'})),
            (ByteData? _) {});
    expect(events, [(7, 'frame')]);
    expect(await engine.audioTracks(), [('0:1', '中文')]);
    await engine.selectAudio('0:1');
    await engine.setVolume(0);
    await engine.dispose();
    expect(calls.map((c) => c.method),
        ['open', 'audioTracks', 'audio', 'volume', 'stop']);
  });

  test('Exo bridge preserves large generations and replaces callback ownership',
      () async {
    final engine = ExoLiveEngine(43);
    final channel = engine.channel;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final oldEvents = <(int, String)>[];
    final currentEvents = <(int, String)>[];
    const generation = 1 << 40;
    await engine.open(const LiveLine('https://example.test/ts'), 3,
        (g, s) => oldEvents.add((g, s)));
    await engine.open(const LiveLine('https://example.test/live'), generation,
        (g, s) => currentEvents.add((g, s)));
    for (final state in ['buffering', 'ready', 'frame', 'progress', 'error']) {
      await emit(channel, generation, state);
    }
    expect(oldEvents, isEmpty);
    expect(currentEvents, [
      (generation, 'buffering'),
      (generation, 'ready'),
      (generation, 'frame'),
      (generation, 'progress'),
      (generation, 'error'),
    ]);
    await engine.dispose();
    await emit(channel, generation, 'frame');
    expect(currentEvents, hasLength(5));
  });

  testWidgets(
      'controller rejects stale native generations after a channel change',
      (tester) async {
    final engine = ExoLiveEngine(44);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(engine.channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(engine.channel, null));
    final remembered = <String>[];
    final controller = LivePlaybackController(
      engine: engine,
      onReady: (id, _) async {
        remembered.add(id);
      },
    );
    addTearDown(controller.dispose);
    const first = LiveChannel(
      id: 'first',
      sourceId: 'source',
      name: 'First',
      lines: [LiveLine('https://example.test/first')],
    );
    const second = LiveChannel(
      id: 'second',
      sourceId: 'source',
      name: 'Second',
      lines: [LiveLine('https://example.test/second')],
    );
    controller.select(first);
    await tester.pump(const Duration(milliseconds: 180));
    final oldGeneration = controller.generation;
    controller.select(second);
    await tester.pump(const Duration(milliseconds: 180));
    for (final state in ['frame', 'progress', 'error', 'ended']) {
      await emit(engine.channel, oldGeneration, state);
    }
    expect(controller.status, 'opening');
    expect(controller.retries, 0);
    expect(remembered, isEmpty);
    await emit(engine.channel, controller.generation, 'frame');
    expect(controller.status, 'playing');
    expect(remembered, ['second']);
    await controller.close();
  });

  test('native open failure stays a PlatformException and dispose still stops',
      () async {
    final engine = ExoLiveEngine(45);
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(engine.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'open') {
        throw PlatformException(code: 'open', message: 'Live playback failed');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(engine.channel, null));
    await expectLater(
      engine.open(const LiveLine('https://example.test/live'), 9, (_, __) {}),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'open')),
    );
    await engine.dispose();
    expect(calls, ['open', 'stop']);
  });

  test('dispose tolerates an already removed native view and removes callbacks',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final platformError in [false, true]) {
      final engine = ExoLiveEngine(platformError ? 47 : 46);
      var events = 0;
      messenger.setMockMethodCallHandler(engine.channel, (_) async => null);
      await engine.open(
          const LiveLine('https://example.test/live'), 1, (_, __) => events++);
      messenger.setMockMethodCallHandler(engine.channel, (call) async {
        if (platformError) throw PlatformException(code: 'closed');
        throw MissingPluginException();
      });
      await engine.dispose();
      await emit(engine.channel, 1, 'error');
      expect(events, 0);
      messenger.setMockMethodCallHandler(engine.channel, null);
    }
  });

  test(
      'empty native audio track list remains empty and stop uses no stale args',
      () async {
    final engine = ExoLiveEngine(48);
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(engine.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(engine.channel, null));
    expect(await engine.audioTracks(), isEmpty);
    await engine.stop();
    expect(calls.last.method, 'stop');
    expect(calls.last.arguments, isNull);
    await engine.dispose();
  });
}
