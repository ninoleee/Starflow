import 'dart:async';
import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/application/live_channel_probe_controller.dart';
import 'package:starflow/features/live_tv/data/live_channel_probe.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';

void main() {
  final channels = List.generate(
      5,
      (i) => LiveChannel(id: '$i', sourceId: 's', name: '$i', lines: [
            LiveLine('https://example.test/$i'),
            LiveLine('https://example.test/$i/backup'),
          ]));
  final snapshot = LiveSnapshot(
      sources: const [LiveSource(id: 's', name: 'Source')],
      channels: channels,
      preferences: const {'0': LivePreference(line: 1)});

  test('200ms admission, focus priority and immediate offscreen cancellation',
      () {
    fakeAsync((time) {
      final probe = _Probe();
      final controller = LiveChannelProbeController(probe);
      controller.start([channels[0], channels[4]], snapshot);
      controller.prioritize('4');
      time.elapse(const Duration(milliseconds: 199));
      expect(probe.urls, isEmpty);
      time.elapse(const Duration(milliseconds: 1));
      expect(probe.urls,
          ['https://example.test/4', 'https://example.test/0/backup']);
      controller.updateVisible([channels[2]], snapshot);
      time.flushMicrotasks();
      expect(probe.urls, hasLength(2));
      time.elapse(const Duration(milliseconds: 199));
      expect(probe.urls, hasLength(2));
      controller.updateVisible([channels[3]], snapshot);
      time.elapse(const Duration(milliseconds: 200));
      expect(probe.urls.last, 'https://example.test/3');
      expect(probe.urls, hasLength(3),
          reason: 'Briefly visible row never probed');
      controller.dispose();
      time.flushMicrotasks();
      expect(time.nonPeriodicTimerCount, 0);
    });
  });

  test('stop during admission prevents delayed requests', () {
    fakeAsync((time) {
      final probe = _Probe();
      final controller = LiveChannelProbeController(probe);
      controller.start(channels, snapshot);
      controller.stop();
      time.elapse(const Duration(seconds: 1));
      expect(probe.urls, isEmpty);
      expect(time.nonPeriodicTimerCount, 0);
      controller.dispose();
    });
  });

  for (final status in [LiveProbeStatus.responded, LiveProbeStatus.timeout]) {
    test('$status refreshes visible results at its TTL with one timer', () {
      fakeAsync((time) {
        final probe = _Probe()..status = status;
        final controller = LiveChannelProbeController(probe);
        controller.start([channels[0]], snapshot);
        time.elapse(const Duration(milliseconds: 200));
        probe.gates.single.complete();
        time.flushMicrotasks();
        final ttl = status == LiveProbeStatus.responded
            ? const Duration(minutes: 5)
            : const Duration(seconds: 45);
        time.elapse(ttl - const Duration(milliseconds: 1));
        expect(probe.urls, hasLength(1));
        expect(time.nonPeriodicTimerCount, 1);
        time.elapse(const Duration(milliseconds: 1));
        expect(probe.urls, hasLength(2));
        expect(controller.entry(channels[0], 1)!.result, isNotNull);
        expect(controller.entry(channels[0], 1)!.checking, isTrue);
        controller.updateVisible([], snapshot);
        time.flushMicrotasks();
        expect(controller.entry(channels[0], 1)!.checking, isFalse);
        expect(time.nonPeriodicTimerCount, 0);
        time.elapse(const Duration(minutes: 10));
        expect(probe.urls, hasLength(2));
        controller.updateVisible([channels[0]], snapshot);
        time.elapse(const Duration(milliseconds: 200));
        expect(probe.urls, hasLength(3));
        controller.dispose();
        time.flushMicrotasks();
      });
    });
  }

  test(
      'snapshot metadata preserves work, changed line and disabled source cancel',
      () {
    fakeAsync((time) {
      final probe = _Probe();
      final controller = LiveChannelProbeController(probe);
      controller.start(channels.take(2).toList(), snapshot);
      time.elapse(const Duration(milliseconds: 200));
      controller.updateSnapshot(LiveSnapshot(
          sources: snapshot.sources,
          channels: channels,
          preferences: const {
            '0': LivePreference(
                line: 1, favorite: true, name: 'Renamed', order: 3),
          }));
      time.flushMicrotasks();
      expect(probe.urls, hasLength(2));
      expect(probe.cancelled, 0);
      final changed = LiveChannel(
          id: '0',
          sourceId: 's',
          name: 'New',
          lines: const [LiveLine('https://example.test/new')]);
      controller.updateSnapshot(LiveSnapshot(
          sources: snapshot.sources, channels: [changed, channels[1]]));
      time.flushMicrotasks();
      expect(probe.cancelled, 1);
      time.elapse(const Duration(milliseconds: 200));
      expect(probe.urls.last, 'https://example.test/new');
      controller.updateSnapshot(LiveSnapshot(channels: [
        changed,
        channels[1]
      ], sources: const [
        LiveSource(id: 's', name: 'Source', enabled: false)
      ]));
      time.flushMicrotasks();
      expect(controller.total, 0);
      expect(probe.cancelled, 3);
      controller.dispose();
      time.flushMicrotasks();
    });
  });

  test('hidden groups are excluded from automatic probes', () {
    fakeAsync((time) {
      final probe = _Probe();
      final controller = LiveChannelProbeController(probe);
      final grouped = LiveSnapshot(
          sources: snapshot.sources,
          channels: channels,
          groupPreferences: const {
            'Sports': LiveGroupPreference(hidden: true),
          });
      final sports = LiveChannel(
          id: 'sports',
          sourceId: 's',
          name: 'Sports',
          group: 'Sports',
          lines: const [LiveLine('https://example.test/sports')]);
      controller.start([channels.first, sports], grouped);
      time.elapse(const Duration(milliseconds: 200));
      expect(probe.urls, ['https://example.test/0']);
      expect(controller.total, 1);
      controller.dispose();
      time.flushMicrotasks();
    });
  });

  test(
      'network invalidation clears cache, waits offline, and never restarts stopped work',
      () {
    fakeAsync((time) {
      final probe = _Probe();
      final controller = LiveChannelProbeController(probe);
      controller.start(channels.take(2).toList(), snapshot);
      time.elapse(const Duration(milliseconds: 200));
      probe.gates.first.complete();
      time.flushMicrotasks();
      controller.invalidateNetwork(available: false);
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 1));
      expect(probe.urls, hasLength(2));
      expect(controller.completed, 0);
      controller.invalidateNetwork();
      time.elapse(const Duration(milliseconds: 200));
      expect(probe.urls, hasLength(4));
      controller.stop();
      time.flushMicrotasks();
      controller.invalidateNetwork();
      time.elapse(const Duration(seconds: 1));
      expect(probe.urls, hasLength(4));
      controller.dispose();
      time.flushMicrotasks();
    });
  });

  test('manual batch uses two workers and the preferred line only', () async {
    final probe = _Probe();
    final controller =
        LiveChannelProbeController(probe, visibilityDelay: Duration.zero);
    addTearDown(controller.dispose);
    expect(probe.urls, isEmpty);
    controller.start(channels, snapshot);
    expect(probe.urls,
        ['https://example.test/0/backup', 'https://example.test/1']);
    controller.start(channels, snapshot);
    expect(probe.urls, hasLength(2));
    expect(controller.entry(channels[4], 0)!.label, '待测');
    probe.gates[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(probe.urls, hasLength(3));
    expect(controller.completed, 1);
    expect(controller.entry(channels[0], 1)!.label, '125 ms');
    await controller.stop();
    expect(controller.running, isFalse);
    expect(probe.urls, hasLength(3));
    expect(controller.entry(channels[0], 1)!.result, isNotNull);
    expect(controller.entry(channels[4], 0), isNull);
  });

  test('changed URL, headers or preferred line do not reuse stale results',
      () async {
    final probe = _Probe();
    final controller =
        LiveChannelProbeController(probe, visibilityDelay: Duration.zero);
    addTearDown(controller.dispose);
    controller.start([channels[0]], snapshot);
    probe.gates.single.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.running, isTrue, reason: 'Wait for new visible rows');
    expect(controller.entry(channels[0], 0), isNull);
    final changed = LiveChannel(id: '0', sourceId: 's', name: '0', lines: [
      channels[0].lines.first,
      LiveLine(channels[0].lines.last.url, headers: const {'Referer': 'new'}),
    ]);
    expect(controller.entry(changed, 1), isNull);
    expect(controller.entry(channels[0], 1), isNotNull);
  });

  test('dispose cancels in-flight work and does not start queued requests',
      () async {
    final probe = _Probe();
    final controller =
        LiveChannelProbeController(probe, visibilityDelay: Duration.zero);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.start(channels, snapshot);
    final before = notifications;
    controller.dispose();
    await controller.stop();
    expect(probe.urls, hasLength(2));
    expect(notifications, before);
  });

  test('visible range replaces queued work and keeps overlapping requests',
      () async {
    final probe = _Probe();
    final controller =
        LiveChannelProbeController(probe, visibilityDelay: Duration.zero);
    addTearDown(controller.dispose);
    controller.start(channels.take(3).toList(), snapshot);
    controller.updateVisible(channels.sublist(1, 4), snapshot);
    await Future<void>.delayed(Duration.zero);
    expect(probe.urls, [
      'https://example.test/0/backup',
      'https://example.test/1',
      'https://example.test/2',
    ]);
    expect(controller.entry(channels[0], 1), isNull);
    expect(controller.entry(channels[1], 0)!.checking, isTrue);
    expect(controller.total, 3);
    probe.gates[1].complete();
    await Future<void>.delayed(Duration.zero);
    expect(probe.urls.last, 'https://example.test/3');
    expect(controller.completed, 1);
    controller.updateVisible([channels[1]], snapshot);
    await Future<void>.delayed(Duration.zero);
    expect(controller.total, 1);
    expect(controller.completed, 1);
    expect(probe.urls, hasLength(4));
    await controller.stop();
  });

  test('new range and restart wait for cancelled transport cleanup', () async {
    final cleanup = Completer<void>();
    final probe = _Probe()..cleanup = cleanup;
    final controller =
        LiveChannelProbeController(probe, visibilityDelay: Duration.zero);
    addTearDown(controller.dispose);
    controller.start(channels.take(2).toList(), snapshot);
    controller.updateVisible(channels.sublist(2), snapshot);
    await Future<void>.delayed(Duration.zero);
    expect(probe.urls, hasLength(2));
    var stopped = false;
    final stopping = controller.stop().then((_) => stopped = true);
    controller.start([channels[4]], snapshot);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    expect(probe.urls, hasLength(2));
    cleanup.complete();
    await stopping;
    await Future<void>.delayed(Duration.zero);
    expect(probe.urls.last, 'https://example.test/4');
    expect(probe.urls, hasLength(3));
    expect(controller.entry(channels[0], 1), isNull);
    await controller.stop();
  });

  test('revisiting and restarting preserve fresh completed results', () async {
    final probe = _Probe();
    final controller =
        LiveChannelProbeController(probe, visibilityDelay: Duration.zero);
    addTearDown(controller.dispose);
    controller.start([channels[0]], snapshot);
    probe.gates.single.complete();
    await Future<void>.delayed(Duration.zero);
    controller.updateVisible([], snapshot);
    controller.updateVisible([channels[0]], snapshot);
    expect(probe.urls, hasLength(1));
    expect(controller.completed, 1);
    await controller.stop();
    controller.start([channels[0]], snapshot);
    expect(probe.urls, hasLength(1));
    await controller.stop();
  });

  test('failure backoff caps at five minutes and success resets failures', () {
    fakeAsync((time) {
      final probe = _Probe()..status = LiveProbeStatus.timeout;
      final controller = LiveChannelProbeController(probe);
      controller.start([channels[0]], snapshot);
      time.elapse(const Duration(milliseconds: 200));
      for (final seconds in [45, 90, 180, 300, 300]) {
        probe.gates.last.complete();
        time.flushMicrotasks();
        final count = probe.urls.length;
        time.elapse(
            Duration(seconds: seconds) - const Duration(milliseconds: 1));
        expect(probe.urls, hasLength(count));
        expect(time.nonPeriodicTimerCount, 1);
        time.elapse(const Duration(milliseconds: 1));
        expect(probe.urls, hasLength(count + 1));
      }
      probe.status = LiveProbeStatus.responded;
      probe.gates.last.complete();
      time.flushMicrotasks();
      time.elapse(const Duration(minutes: 5));
      probe.status = LiveProbeStatus.timeout;
      probe.gates.last.complete();
      time.flushMicrotasks();
      final count = probe.urls.length;
      time.elapse(const Duration(seconds: 45));
      expect(probe.urls, hasLength(count + 1));
      controller.dispose();
      time.flushMicrotasks();
      expect(time.nonPeriodicTimerCount, 0);
    });
  });

  test('paused results expire without requests and resume only visible work',
      () {
    fakeAsync((time) {
      final probe = _Probe();
      final controller = LiveChannelProbeController(probe);
      controller.start(channels.take(2).toList(), snapshot);
      time.elapse(const Duration(milliseconds: 200));
      for (final gate in probe.gates) {
        gate.complete();
      }
      time.flushMicrotasks();
      controller.stop();
      time.flushMicrotasks();
      expect(time.nonPeriodicTimerCount, 0);
      time.elapse(const Duration(minutes: 10));
      expect(probe.urls, hasLength(2));
      controller.start([channels[0]], snapshot);
      time.elapse(const Duration(milliseconds: 200));
      expect(probe.urls, hasLength(3));
      expect(probe.urls.last, channels[0].lines[1].url);
      controller.dispose();
      time.flushMicrotasks();
    });
  });
}

class _Probe extends LiveChannelProbe {
  final urls = <String>[];
  final gates = <Completer<void>>[];
  Completer<void>? cleanup;
  LiveProbeStatus status = LiveProbeStatus.responded;
  int cancelled = 0;
  @override
  Future<LiveProbeResult> probe(LiveLine line,
      {required Future<void> cancel}) async {
    urls.add(line.url);
    final gate = Completer<void>();
    gates.add(gate);
    final cancelled = await Future.any([
      gate.future.then((_) => false),
      cancel.then((_) => true),
    ]);
    if (cancelled) {
      this.cancelled++;
      await cleanup?.future;
    }
    return LiveProbeResult(status,
        checkedAt: DateTime.now(), latency: const Duration(milliseconds: 125));
  }
}
