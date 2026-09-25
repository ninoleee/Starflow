import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';

void main() {
  test('duration and format discard responses from a stopped session', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final engine = ExoLiveEngine(901);
    final format = Completer<String?>();
    num? duration = 18000;
    messenger.setMockMethodCallHandler(engine.channel, (call) async {
      if (call.method == 'videoFormat') return format.future;
      if (call.method == 'cacheDurationMs') return duration;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(engine.channel, null));
    expect(await engine.readVideoFormat(1), isNull);
    await engine.open(const LiveLine('https://example.test/live'), 1, (_, __) {});
    expect(await engine.readBufferDurationMs(1), 18000);
    for (final invalid in [null, -1, double.nan, double.infinity]) {
      duration = invalid;
      expect(await engine.readBufferDurationMs(1), isNull);
    }
    final pending = engine.readVideoFormat(1);
    await Future<void>.delayed(Duration.zero);
    await engine.stop();
    format.complete('1920x1080 · HEVC · AAC');
    expect(await pending, isNull);
    await engine.open(const LiveLine('https://example.test/live'), 2, (_, __) {});
    expect(await engine.readVideoFormat(2), '1920x1080 · HEVC · AAC');
    expect(await engine.readVideoFormat(1), isNull);
    await engine.dispose();
    expect(await engine.readBufferDurationMs(2), isNull);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('Exo cache is generation scoped and rejects invalid or late results',
      () async {
    final engine = ExoLiveEngine(60);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final pending = Completer<num>();
    final calls = <MethodCall>[];
    num? bytes;
    var delayed = true;
    messenger.setMockMethodCallHandler(engine.channel, (call) async {
      calls.add(call);
      if (call.method == 'cacheBytes') {
        return delayed ? pending.future : bytes;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(engine.channel, null));
    expect(await engine.readCacheBytes(1), isNull);
    await engine.open(const LiveLine('https://example.test/live'), 1, (_, __) {});
    final reading = engine.readCacheBytes(1);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.arguments, {'generation': 1});
    await engine.stop();
    pending.complete(4096);
    expect(await reading, isNull);
    delayed = false;
    await engine.open(const LiveLine('https://example.test/live'), 2, (_, __) {});
    for (final invalid in [null, -1, double.nan, double.infinity]) {
      bytes = invalid;
      expect(await engine.readCacheBytes(2), isNull);
    }
    bytes = 0;
    expect(await engine.readCacheBytes(2), 0);
    bytes = 33554432;
    expect(await engine.readCacheBytes(2), 33554432);
    await engine.dispose();
    expect(await engine.readCacheBytes(2), isNull);
  });

  test('Exo speed reads use the current generation and discard late responses',
      () async {
    final engine = ExoLiveEngine(50);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final pending = Completer<num>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(engine.channel, (call) async {
      calls.add(call);
      return call.method == 'networkSpeed' ? pending.future : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(engine.channel, null));
    expect(await engine.readNetworkSpeed(1), isNull);
    await engine.open(
        const LiveLine('https://example.test/live'), 1, (_, __) {});
    final reading = engine.readNetworkSpeed(1);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.arguments, {'generation': 1});
    await engine.stop();
    pending.complete(4096);
    expect(await reading, isNull);
    expect(await engine.readNetworkSpeed(1), isNull);
    await engine.open(
        const LiveLine('https://example.test/live'), 2, (_, __) {});
    expect(await engine.readNetworkSpeed(2), 4096);
    await engine.dispose();
  });

  Future<void> emit(MethodChannel channel, int generation, String state,
          {Object? error}) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('state', {
          'generation': generation,
          'state': state,
          if (error != null) 'error': error,
        })),
        (ByteData? _) {},
      );

  testWidgets('native errors reach the controller and survive engine cleanup',
      (tester) async {
    final engine = ExoLiveEngine(51);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(engine.channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(engine.channel, null));
    final controller =
        LivePlaybackController(engine: engine, onReady: (_, __) async {});
    addTearDown(controller.dispose);
    const channel = LiveChannel(
        id: 'first',
        sourceId: 'source',
        name: 'First',
        lines: [LiveLine('https://example.test/live')]);
    controller.select(channel);
    await tester.pump(const Duration(milliseconds: 180));
    final old = controller.generation;
    await emit(engine.channel, old, 'error', error: {
      'errorCategory': 'http',
      'nativeErrorCode': 2000,
      'httpStatus': 403,
      'message': 'https://private.test/password',
    });
    await tester.pump();
    expect(controller.status, 'retrying');
    expect(controller.errorDetails?.httpStatus, 403);
    expect(controller.failureLabel, contains('HTTP 403'));
    expect(engine.errorFor(old), isNull);
    controller.select(channel);
    expect(controller.errorDetails, isNull);
    await tester.pump(const Duration(milliseconds: 180));
    await emit(engine.channel, old, 'error', error: {'httpStatus': 401});
    expect(controller.status, 'opening');
    expect(controller.errorDetails, isNull);
    expect(engine.errorFor(controller.generation), isNull);
    await emit(engine.channel, controller.generation, 'frame');
    expect(controller.status, 'playing');
    await controller.close();
  });

  test('native open exceptions retain safe details but stop clears ownership',
      () async {
    final engine = ExoLiveEngine(52);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(engine.channel, (call) async {
      if (call.method == 'open') {
        throw PlatformException(
            code: 'open',
            message: 'https://private.test/password',
            details: {'errorCategory': 'decoder', 'nativeErrorCode': 4001});
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(engine.channel, null));
    await expectLater(
        engine.open(const LiveLine('https://example.test/live'), 1, (_, __) {}),
        throwsA(isA<PlatformException>()));
    expect(engine.errorFor(1)?.fields,
        {'errorCategory': 'decoder', 'nativeErrorCode': 4001});
    await engine.dispose();
    expect(engine.errorFor(1), isNull);
  });

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

  test(
      'Exo cancellation waits for native acknowledgement and preserves initial mute',
      () async {
    final engine = ExoLiveEngine(49);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final pendingOpen = Completer<void>();
    final pendingCancel = Completer<void>();
    final started = Completer<void>();
    final cancelling = Completer<void>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(engine.channel, (call) async {
      calls.add(call);
      if (call.method == 'open') {
        started.complete();
        await pendingOpen.future;
      }
      if (call.method == 'cancelOpen') {
        cancelling.complete();
        await pendingCancel.future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(engine.channel, null));
    await engine.setVolume(0);
    var settled = false;
    final opening = engine.open(
        const LiveLine('https://example.test/live'), 77, (_, __) {});
    final rejected = expectLater(opening.whenComplete(() => settled = true),
        throwsA(isA<LiveOpenCancelled>()));
    await started.future;
    var acknowledged = false;
    final cancellation = engine.cancelOpen().then((_) => acknowledged = true);
    await cancelling.future;
    expect(acknowledged, isFalse);
    expect(settled, isFalse);
    expect(calls.firstWhere((c) => c.method == 'open').arguments['volume'], 0);
    expect(calls.last.arguments, {'generation': 77});
    pendingCancel.complete();
    await cancellation;
    await rejected;
    expect(acknowledged, isTrue);
    expect(settled, isTrue);
    expect(pendingOpen.isCompleted, isFalse);
    pendingOpen.completeError(PlatformException(code: 'late-open'));
    await engine.dispose();
    expect(
        calls.map((c) => c.method), ['volume', 'open', 'cancelOpen', 'stop']);
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
