import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/playback/application/active_playback_cleanup.dart';

LiveChannel _channel(String id) => LiveChannel(
      id: id,
      sourceId: 'source',
      name: id,
      lines: [
        LiveLine('https://example.test/$id'),
        LiveLine('https://example.test/$id/backup'),
      ],
    );

Future<void> _debounce(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 180));
}

final _cleanups = <Future<void> Function()>[];

void _test(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      final cleanups = _cleanups.reversed.toList();
      _cleanups.clear();
      for (final cleanup in cleanups) {
        await cleanup();
      }
    }
  });
}

LivePlaybackController _controller(
  _Engine engine, {
  Future<void> Function(String, int)? onReady,
}) {
  final controller = LivePlaybackController(
    engine: engine,
    onReady: onReady ?? (_, __) async {},
  );
  _cleanups.add(() async {
    engine.release();
    await controller.close();
    controller.dispose();
    expect(engine.maxConcurrentOperations, lessThanOrEqualTo(1));
    expect(engine.concurrentOperations, 0);
    expect(engine.activePlayers, 0);
  });
  return controller;
}

void main() {
  _test('switch releases the old player before opening the latest target',
      (tester) async {
    final engine = _Engine();
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    final stop = engine.block('stop');
    c.select(_channel('b'));
    await _debounce(tester);
    c.select(_channel('c'), preferredLine: 1);
    await _debounce(tester);
    expect(engine.opens, hasLength(1));
    stop.complete();
    await tester.pump();
    expect(engine.urls, [
      'https://example.test/a',
      'https://example.test/c/backup',
    ]);
    expect(engine.calls, ['open', 'volume:1.0', 'stop', 'open', 'volume:1.0']);
    expect(engine.maxActivePlayers, 1);
  });

  _test('open timeout retains ownership and fences late events and volume',
      (tester) async {
    final engine = _Engine();
    final opening = engine.block('open');
    final remembered = <String>[];
    final c = _controller(engine, onReady: (id, _) async => remembered.add(id));
    c.select(_channel('a'));
    await _debounce(tester);
    final old = engine.opens.single;
    await tester.pump(const Duration(seconds: 15));
    expect(c.status, 'retrying');
    expect(c.retries, 1);
    expect(c.failure, LivePlaybackFailure.openTimeout);
    old.emit('frame');
    expect(remembered, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    await _debounce(tester);
    expect(engine.calls, ['open']);
    expect(engine.opens, hasLength(1));
    opening.complete();
    await tester.pump();
    expect(engine.calls, ['open', 'stop', 'open', 'volume:1.0']);
    expect(engine.urls.last, 'https://example.test/a/backup');
    old.emit('error');
    old.emit('progress');
    expect(c.retries, 1);
    expect(remembered, isEmpty);
    expect(engine.maxActivePlayers, 1);
  });

  _test('late rejected open cannot fail a newer channel', (tester) async {
    final engine = _Engine();
    final opening = engine.block('open');
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    c.select(_channel('b'));
    await _debounce(tester);
    opening.completeError(StateError('late open failure'));
    await tester.pump();
    expect(c.retries, 0);
    expect(c.status, 'opening');
    expect(engine.urls.last, 'https://example.test/b');
    expect(engine.calls, ['open', 'stop', 'open', 'volume:1.0']);
  });

  _test('old callbacks cannot claim the new generation during debounce',
      (tester) async {
    final engine = _Engine();
    final remembered = <(String, int)>[];
    final c = _controller(engine,
        onReady: (id, line) async => remembered.add((id, line)));
    c.select(_channel('a'));
    await _debounce(tester);
    final old = engine.opens.single;
    c.select(_channel('b'), preferredLine: 1);
    old.emit('progress');
    old.callback(c.generation, 'frame');
    expect(remembered, isEmpty);
    expect(c.status, 'opening');
    await _debounce(tester);
    old.callback(c.generation, 'error');
    engine.opens.last.emit('frame');
    engine.opens.last.emit('progress');
    expect(remembered, [('b', 1)]);
    expect(c.retries, 0);
    expect(c.status, 'playing');
  });

  _test('short successful playback does not replenish retry budget',
      (tester) async {
    final engine = _Engine();
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    for (var attempt = 0; attempt < 4; attempt++) {
      final current = engine.opens.last;
      current.emit('progress');
      expect(c.status, 'playing');
      current.emit('error');
      current.emit('ended');
      current.emit('frame');
      expect(c.retries, (attempt + 1).clamp(0, 3));
      await tester.pump();
      expect(engine.activePlayers, 0);
      if (attempt == 3) break;
      expect(c.status, 'retrying');
      await tester.pump(Duration(seconds: (attempt + 1) * 2 - 1));
      expect(engine.opens, hasLength(attempt + 1));
      await tester.pump(const Duration(seconds: 1));
      await _debounce(tester);
      expect(engine.opens, hasLength(attempt + 2));
    }
    expect(c.status, 'failed');
    expect(c.failure, LivePlaybackFailure.engineError);
    await tester.pump(const Duration(minutes: 5));
    expect(engine.urls, [
      'https://example.test/a',
      'https://example.test/a/backup',
      'https://example.test/a',
      'https://example.test/a/backup',
    ]);
    c.select(_channel('a'));
    await _debounce(tester);
    expect(c.retries, 0);
    expect(engine.opens, hasLength(5));
    expect(c.failure, isNull);
  });

  _test('ready and buffering chatter cannot extend the progress watchdog',
      (tester) async {
    final engine = _Engine();
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    for (var second = 0; second < 17; second++) {
      engine.opens.single.emit('ready');
      engine.opens.single.emit('buffering');
      await tester.pump(const Duration(seconds: 1));
    }
    expect(c.retries, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(c.status, 'retrying');
    expect(c.failure, LivePlaybackFailure.progressTimeout);
    expect(c.retries, 1);
    expect(engine.activePlayers, 0);
  });

  _test('progress and frame refresh the watchdog but ready does not',
      (tester) async {
    final engine = _Engine();
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    await tester.pump(const Duration(seconds: 17));
    engine.opens.single.emit('progress');
    await tester.pump(const Duration(seconds: 17));
    engine.opens.single.emit('frame');
    await tester.pump(const Duration(seconds: 17));
    engine.opens.single.emit('ready');
    expect(c.retries, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(c.retries, 1);
  });

  _test('suspend cancels retries and waits for an in-flight open to stop',
      (tester) async {
    final engine = _Engine();
    final opening = engine.block('open');
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    c.suspend();
    engine.opens.single.emit('frame');
    await tester.pump(const Duration(minutes: 1));
    expect(c.status, 'suspended');
    expect(c.retries, 0);
    expect(engine.calls, ['open']);
    opening.complete();
    await tester.pump();
    expect(engine.calls, ['open', 'stop']);
    expect(engine.activePlayers, 0);
    c.select(_channel('a'));
    await _debounce(tester);
    engine.opens.last.emit('error');
    c.suspend();
    await tester.pump(const Duration(minutes: 1));
    expect(engine.opens, hasLength(2));
    expect(c.status, 'suspended');
  });

  _test('close is idempotent and drains late open before disposal',
      (tester) async {
    final engine = _Engine();
    final opening = engine.block('open');
    final c = _controller(engine);
    var notifications = 0;
    c.addListener(() => notifications++);
    c.select(_channel('a'));
    await _debounce(tester);
    final closing = c.close();
    expect(identical(closing, c.close()), isTrue);
    var closed = false;
    unawaited(closing.then((_) => closed = true));
    final before = notifications;
    c.select(_channel('b'));
    c.suspend();
    await c.toggleMute();
    engine.opens.single.emit('frame');
    await tester.pump(const Duration(minutes: 1));
    expect(closed, isFalse);
    expect(engine.calls, ['open']);
    opening.complete();
    await tester.pump();
    await closing;
    expect(closed, isTrue);
    expect(engine.calls, ['open', 'dispose']);
    expect(notifications, before);
  });

  _test('global cleanup drains and unregisters the old session',
      (tester) async {
    final engine = _Engine();
    final opening = engine.block('open');
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    var cleaned = false;
    final cleanup = ActivePlaybackCleanupCoordinator.cleanupAll(reason: 'test');
    unawaited(cleanup.then((_) => cleaned = true));
    await tester.pump();
    c.select(_channel('b'));
    await tester.pump(const Duration(minutes: 1));
    expect(cleaned, isFalse);
    opening.complete();
    await tester.pump();
    await cleanup;
    expect(engine.calls, ['open', 'dispose']);
    c.select(_channel('c'));
    c.suspend();
    await c.toggleMute();
    await _debounce(tester);
    await ActivePlaybackCleanupCoordinator.cleanupAll(reason: 'test-again');
    expect(engine.calls, ['open', 'dispose']);

    // Keep coordinator checks in one fake-clock zone: its queue is static.
    final failingEngine = _Engine()..failDispose = true;
    final failing = LivePlaybackController(
        engine: failingEngine, onReady: (_, __) async {});
    try {
      failing.select(_channel('a'));
      await _debounce(tester);
      await ActivePlaybackCleanupCoordinator.cleanupAll(reason: 'test-failure');
      await expectLater(failing.close(), throwsStateError);
      await ActivePlaybackCleanupCoordinator.cleanupAll(reason: 'test-again');
      failing.select(_channel('b'));
      await _debounce(tester);
      expect(failingEngine.calls, ['open', 'volume:1.0', 'dispose']);
      expect(failingEngine.maxConcurrentOperations, 1);
      expect(failingEngine.activePlayers, 0);
    } finally {
      failing.dispose();
      await tester.pump();
    }
  });

  _test('mute is serialized and invalidated queued mute cannot touch next open',
      (tester) async {
    final engine = _Engine();
    final opening = engine.block('open');
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    final mute = c.toggleMute();
    c.select(_channel('b'));
    await _debounce(tester);
    expect(engine.calls, ['open']);
    opening.complete();
    await tester.pump();
    await mute;
    expect(engine.calls, ['open', 'stop', 'open', 'volume:0.0']);
  });

  _test('close waits for volume and suppresses its late notification',
      (tester) async {
    final engine = _Engine();
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    final volume = engine.block('volume:0.0');
    final mute = c.toggleMute();
    await tester.pump();
    var notifications = 0;
    c.addListener(() => notifications++);
    final closing = c.close();
    await tester.pump();
    expect(engine.calls.last, 'volume:0.0');
    volume.complete();
    await tester.pump();
    await mute;
    await closing;
    expect(engine.calls.last, 'dispose');
    expect(notifications, 0);
  });

  _test('stop failure cannot authorize overlapping players or poison close',
      (tester) async {
    final engine = _Engine();
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    engine.failStop = true;
    c.select(_channel('b'));
    await _debounce(tester);
    expect(engine.opens, hasLength(1));
    expect(c.status, 'retrying');
    await c.close();
    expect(engine.calls.last, 'dispose');
  });

  _test('synchronous remember errors do not escape engine callbacks',
      (tester) async {
    final engine = _Engine();
    final c = _controller(engine,
        onReady: (_, __) => throw StateError('storage unavailable'));
    c.select(_channel('a'));
    await _debounce(tester);
    expect(() => engine.opens.single.emit('frame'), returnsNormally);
    await tester.pump();
    expect(c.status, 'playing');
    expect(c.retries, 0);
  });

  _test('reentrant selection from remember cannot publish old playing state',
      (tester) async {
    final engine = _Engine();
    late LivePlaybackController c;
    c = _controller(engine, onReady: (_, __) async {
      c.select(_channel('b'));
    });
    c.select(_channel('a'));
    await _debounce(tester);
    engine.opens.single.emit('frame');
    expect(c.channel!.id, 'b');
    expect(c.status, 'opening');
    await _debounce(tester);
    expect(engine.urls.last, 'https://example.test/b');
  });

  _test('reentrant suspend from opening notification cancels debounce',
      (tester) async {
    final engine = _Engine();
    final c = _controller(engine);
    c.addListener(() {
      if (c.status == 'opening') c.suspend();
    });
    c.select(_channel('a'));
    await tester.pump(const Duration(minutes: 1));
    expect(engine.opens, isEmpty);
    expect(c.status, 'suspended');
  });

  _test('reentrant close from retry notification cancels all recovery work',
      (tester) async {
    final engine = _Engine();
    final c = _controller(engine);
    c.addListener(() {
      if (c.status == 'retrying') unawaited(c.close());
    });
    c.select(_channel('a'));
    await _debounce(tester);
    engine.opens.single.emit('error');
    await tester.pump(const Duration(minutes: 1));
    expect(engine.calls, ['open', 'volume:1.0', 'stop', 'dispose']);
    expect(engine.opens, hasLength(1));
  });

  _test('late open rejection after timeout releases ownership before retry',
      (tester) async {
    final engine = _Engine();
    final opening = engine.block('open');
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    await tester.pump(const Duration(seconds: 15));
    opening.completeError(StateError('late timeout rejection'));
    await tester.pump();
    expect(c.retries, 1);
    expect(c.status, 'retrying');
    expect(engine.calls, ['open', 'stop']);
    await tester.pump(const Duration(seconds: 2));
    await _debounce(tester);
    expect(engine.urls.last, 'https://example.test/a/backup');
    expect(c.retries, 1);
  });

  _test('newest queued target does not time out while waiting for ownership',
      (tester) async {
    final engine = _Engine();
    final opening = engine.block('open');
    final c = _controller(engine);
    c.select(_channel('a'));
    await _debounce(tester);
    c.select(_channel('b'));
    await _debounce(tester);
    await tester.pump(const Duration(minutes: 1));
    expect(c.retries, 0);
    expect(engine.opens, hasLength(1));
    opening.complete();
    await tester.pump();
    expect(engine.urls.last, 'https://example.test/b');
    expect(c.status, 'opening');
    expect(c.retries, 0);
  });
}

class _Open {
  _Open(this.line, this.generation, this.callback);
  final LiveLine line;
  final int generation;
  final void Function(int, String) callback;

  void emit(String state) => callback(generation, state);
}

class _Engine implements LiveEngine {
  final calls = <String>[];
  final opens = <_Open>[];
  final _gates = <String, List<Completer<void>>>{};
  final _allGates = <Completer<void>>[];
  int concurrentOperations = 0, maxConcurrentOperations = 0;
  int activePlayers = 0, maxActivePlayers = 0;
  bool failStop = false, failDispose = false;

  List<String> get urls => opens.map((open) => open.line.url).toList();

  Completer<void> block(String operation) {
    final gate = Completer<void>();
    (_gates[operation] ??= []).add(gate);
    _allGates.add(gate);
    return gate;
  }

  void release() {
    for (final gate in _allGates) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  Future<void> _operation(String name, void Function() finish) async {
    calls.add(name);
    concurrentOperations++;
    if (concurrentOperations > maxConcurrentOperations) {
      maxConcurrentOperations = concurrentOperations;
    }
    try {
      final gates = _gates[name];
      if (gates != null && gates.isNotEmpty) await gates.removeAt(0).future;
      finish();
    } finally {
      concurrentOperations--;
    }
  }

  @override
  Future<void> open(
      LiveLine line, int generation, void Function(int, String) onState) {
    opens.add(_Open(line, generation, onState));
    return _operation('open', () {
      activePlayers++;
      if (activePlayers > maxActivePlayers) maxActivePlayers = activePlayers;
    });
  }

  @override
  Future<void> stop() => _operation('stop', () {
        if (failStop) throw StateError('stop failed');
        activePlayers = 0;
      });

  @override
  Future<void> dispose() => _operation('dispose', () {
        activePlayers = 0;
        if (failDispose) throw StateError('dispose failed');
      });

  @override
  Future<void> setVolume(double volume) => _operation('volume:$volume', () {});

  @override
  Future<List<(String, String)>> audioTracks() async => [];

  @override
  Future<void> selectAudio(String id) async {}
}
