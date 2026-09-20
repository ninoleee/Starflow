import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/application/playback_interaction_player.dart';

void main() {
  late List<String> events;
  late _FakePlatformPlayer backend;
  late PlaybackInteractionPlayer player;

  setUp(() {
    events = [];
    backend = _FakePlatformPlayer(events);
    player = PlaybackInteractionPlayer(
      platformPlayer: backend,
      onUserSeek: (position) => events.add('user:seek:${position.inSeconds}'),
      onUserPlaybackIntent: (playing) => events.add('user:playing:$playing'),
    );
    addTearDown(() => player.dispose());
  });

  test('manual intent precedes synchronous position events before await',
      () async {
    final completion = Completer<void>();
    backend.seekCompletion = completion;
    final subscription = player.stream.position.listen(
      (position) => events.add('position:${position.inSeconds}'),
    );
    addTearDown(subscription.cancel);

    // Adaptive controls retain Player, not the application-specific subtype.
    final Player controlsPlayer = player;
    final seeking = controlsPlayer.seek(const Duration(seconds: 42));
    expect(events, ['user:seek:42', 'backend:seek:42', 'position:42']);

    var finished = false;
    final observed = seeking.then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    completion.complete();
    await observed;
    expect(finished, isTrue);
  });

  test('automatic seek bypasses intent but still publishes position', () async {
    final subscription = player.stream.position.listen(
      (position) => events.add('position:${position.inSeconds}'),
    );
    addTearDown(subscription.cancel);

    await player.seekAutomatically(const Duration(seconds: 90));

    expect(events, ['backend:seek:90', 'position:90']);
  });

  test('pending automatic seek does not suppress a concurrent manual seek',
      () async {
    final completion = Completer<void>();
    backend.seekCompletion = completion;
    final automatic = player.seekAutomatically(const Duration(seconds: 90));
    final manual = player.seek(const Duration(seconds: 12));

    expect(events, ['backend:seek:90', 'user:seek:12', 'backend:seek:12']);
    completion.complete();
    await Future.wait([automatic, manual]);
  });

  test('repeated seeks notify once each without changing the target', () async {
    const target = Duration(microseconds: 1234567);
    await player.seek(target);
    await player.seek(target);

    expect(backend.state.position, target);
    expect(events, [
      'user:seek:1',
      'backend:seek:1',
      'user:seek:1',
      'backend:seek:1',
    ]);
  });

  for (final automatic in [false, true]) {
    test('${automatic ? 'automatic' : 'manual'} seek preserves backend errors',
        () async {
      final error = StateError('seek failed');
      backend.seekError = error;

      final seeking = automatic
          ? player.seekAutomatically(const Duration(seconds: 42))
          : player.seek(const Duration(seconds: 42));

      expect(events, [
        if (!automatic) 'user:seek:42',
        'backend:seek:42',
      ]);
      await expectLater(seeking, throwsA(same(error)));
    });
  }

  test('asynchronous seek failure does not retract or repeat manual intent',
      () async {
    final completion = Completer<void>();
    backend.seekCompletion = completion;
    final error = StateError('late seek failure');
    final seeking = player.seek(const Duration(seconds: 42));
    final assertion = expectLater(seeking, throwsA(same(error)));
    completion.completeError(error);
    await assertion;

    expect(events, ['user:seek:42', 'backend:seek:42']);
  });

  test(
      'throwing intent callback prevents delegation and returns a failed future',
      () async {
    final error = StateError('intent failed');
    final failingPlayer = PlaybackInteractionPlayer(
      platformPlayer: backend,
      onUserSeek: (_) => throw error,
    );

    await expectLater(
      failingPlayer.seek(const Duration(seconds: 42)),
      throwsA(same(error)),
    );
    expect(events, isEmpty);
  });

  for (final command in ['play', 'pause', 'toggleToPlay', 'toggleToPause']) {
    test('$command reports intent once before synchronous playing event',
        () async {
      final wasPlaying = command == 'pause' || command == 'toggleToPause';
      backend.state = backend.state.copyWith(playing: wasPlaying);
      final subscription = player.stream.playing.listen(
        (playing) => events.add('playing:$playing'),
      );
      addTearDown(subscription.cancel);
      final Player controlsPlayer = player;

      final Future<void> operation;
      switch (command) {
        case 'play':
          operation = controlsPlayer.play();
        case 'pause':
          operation = controlsPlayer.pause();
        default:
          operation = controlsPlayer.playOrPause();
      }

      expect(events, [
        'user:playing:${!wasPlaying}',
        'backend:${command.startsWith('toggle') ? 'toggle' : command}',
        'playing:${!wasPlaying}',
      ]);
      await operation;
    });
  }

  test('automatic playback commands bypass intent callbacks', () async {
    await player.playAutomatically();
    await player.pauseAutomatically();
    await player.playOrPauseAutomatically();

    expect(events, ['backend:play', 'backend:pause', 'backend:toggle']);
    expect(player.state.playing, isTrue);
  });

  test('EOF and backend playing events are not user commands', () async {
    final subscription = player.stream.playing.listen(
      (playing) => events.add('playing:$playing'),
    );
    addTearDown(subscription.cancel);

    backend.emitPlaying(true);
    backend.emitCompleted();
    await Future<void>.delayed(Duration.zero);

    expect(player.state.completed, isTrue);
    expect(events, ['playing:true', 'playing:false']);
  });

  test('playback intent remains recorded if the backend fails', () async {
    final error = StateError('pause failed');
    backend.playbackError = error;

    final pausing = player.pause();
    expect(events, ['user:playing:false', 'backend:pause']);
    await expectLater(pausing, throwsA(same(error)));
  });

  test('playback intent hook is optional', () async {
    final optionalPlayer = PlaybackInteractionPlayer(
      platformPlayer: backend,
      onUserSeek: (_) {},
    );

    await optionalPlayer.play();
    await optionalPlayer.pause();
    await optionalPlayer.playOrPause();

    expect(events, ['backend:play', 'backend:pause', 'backend:toggle']);
  });
}

class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer(this.events)
      : super(configuration: const PlayerConfiguration());

  final List<String> events;
  Completer<void>? seekCompletion;
  Object? seekError;
  Object? playbackError;

  // Use synchronous streams to expose ordering bugs hidden by queued events.
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);

  @override
  StreamController<Duration> get positionController => _positions;

  @override
  StreamController<bool> get playingController => _playing;

  @override
  Future<void> seek(Duration duration) {
    events.add('backend:seek:${duration.inSeconds}');
    final error = seekError;
    if (error != null) throw error;
    state = state.copyWith(position: duration);
    positionController.add(duration);
    return seekCompletion?.future ?? Future<void>.value();
  }

  @override
  Future<void> play() => _setPlaying('play', true);

  @override
  Future<void> pause() => _setPlaying('pause', false);

  @override
  Future<void> playOrPause() => _setPlaying('toggle', !state.playing);

  Future<void> _setPlaying(String command, bool playing) {
    events.add('backend:$command');
    final error = playbackError;
    if (error != null) throw error;
    emitPlaying(playing);
    return Future<void>.value();
  }

  void emitPlaying(bool playing) {
    state = state.copyWith(playing: playing);
    playingController.add(playing);
  }

  void emitCompleted() {
    state = state.copyWith(completed: true);
    completedController.add(true);
    emitPlaying(false);
  }
}
