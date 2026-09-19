import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/playback_system_session.dart';
import 'package:starflow/features/playback/application/playback_platform_session_owner.dart';

PlaybackSessionProgress progress(int seconds) => (
      position: Duration(seconds: seconds),
      duration: const Duration(minutes: 10),
      playing: true,
      buffering: false,
      speed: 1.0,
      hasEpisodeQueue: false,
      hasPrevious: false,
      hasNext: false,
    );

const state = PlaybackSystemSessionState(
  title: 'test',
  position: Duration.zero,
  duration: Duration(minutes: 10),
  playing: true,
);

void main() {
  test('detach fences in-flight activation and queued updates', () async {
    final activated = Completer<void>();
    final calls = <String>[];
    final owner = PlaybackPlatformSessionOwner(
      supported: true,
      attach: (_) async {},
      detach: () async => calls.add('detach'),
      setActive: (active) async {
        calls.add('active:$active');
        if (active) await activated.future;
      },
      update: (_) async => calls.add('update'),
    );
    final first = owner.publish(
        progress: progress(0),
        isForeground: true,
        force: true,
        buildState: () => state);
    await Future<void>.delayed(Duration.zero);
    final queued = owner.publish(
        progress: progress(1),
        isForeground: true,
        force: true,
        buildState: () => state);
    final detached = owner.detach();
    activated.complete();
    await Future.wait([first, queued, detached]);
    expect(calls, ['active:true', 'active:false', 'detach']);
  });

  test('late attach cannot deliver commands after detach, rebind can',
      () async {
    final attachment = Completer<void>();
    final listeners = <PlaybackRemoteCommandListener>[];
    var commands = 0;
    var detached = 0;
    final owner = PlaybackPlatformSessionOwner(
      supported: true,
      attach: (listener) async {
        listeners.add(listener);
        await attachment.future;
      },
      detach: () async => detached++,
      setActive: (_) async {},
      update: (_) async {},
    );
    final binding = owner.bind((_) async => commands++);
    await Future<void>.delayed(Duration.zero);
    final closing = owner.detach();
    attachment.complete();
    await binding;
    await closing;
    await listeners
        .single(const PlaybackRemoteCommand(PlaybackRemoteCommandType.play));
    expect(commands, 0);
    expect(detached, 1);
    await owner.bind((_) async => commands++);
    await owner.bind((_) async => commands++);
    expect(listeners.length, 2);
    await listeners
        .first(const PlaybackRemoteCommand(PlaybackRemoteCommandType.play));
    await listeners
        .last(const PlaybackRemoteCommand(PlaybackRemoteCommandType.play));
    expect(commands, 1);
    await owner.detach();
  });

  test('keeps background throttle and lazy metadata, reset on detach',
      () async {
    var now = DateTime(2026, 9, 20);
    var built = 0;
    var updates = 0;
    final owner = PlaybackPlatformSessionOwner(
      supported: true,
      attach: (_) async {},
      detach: () async {},
      setActive: (_) async {},
      update: (_) async => updates++,
      clock: () => now,
    );
    Future<void> publish(int second, {bool force = false}) => owner.publish(
          progress: progress(second),
          isForeground: false,
          force: force,
          buildState: () {
            built++;
            return state;
          },
        );
    await publish(0);
    now = now.add(const Duration(seconds: 1));
    await publish(1);
    expect(built, 1);
    now = now.add(const Duration(seconds: 9));
    await publish(10);
    await publish(10, force: true);
    expect(updates, 3);
    await owner.detach();
    await publish(10);
    expect(updates, 4);
    expect(built, 4);
  });

  test('unsupported platforms never construct metadata or call the bridge',
      () async {
    final owner = PlaybackPlatformSessionOwner(
      supported: false,
      attach: (_) async => fail('attach'),
      detach: () async => fail('detach'),
      setActive: (_) async => fail('active'),
      update: (_) async => fail('update'),
    );
    await owner.bind((_) async {});
    await owner.publish(
        progress: progress(1),
        isForeground: true,
        force: true,
        buildState: () => throw StateError('metadata'));
    await owner.deactivate();
    await owner.detach();
  });
}
