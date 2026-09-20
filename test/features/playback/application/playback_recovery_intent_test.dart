import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/application/playback_interaction_player.dart';
import 'package:starflow/features/playback/application/playback_recovery_intent.dart';
import 'package:starflow/features/playback/application/fntv_session_owner.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

void main() {
  for (final command in [
    'pause',
    'seek',
    'background',
    'exit',
    'replacement'
  ]) {
    for (final duringPlay in [false, true]) {
      test(
          '$command cancels recovery ${duringPlay ? 'during play' : 'during confirmation'}',
          () async {
        final intent = PlaybackRecoveryIntent();
        final backend = _Backend();
        final player = PlaybackInteractionPlayer(
          platformPlayer: backend,
          onUserSeek: (_) => intent.invalidate(),
          onUserPlaybackIntent: intent.playback,
        );
        var current = true;
        final revision = intent.revision;
        final confirmation = Completer<void>();
        final playing = Completer<void>();
        var plays = 0;
        var seeks = 0;
        Future<void> recover() async {
          await confirmation.future;
          await intent.playAndSeek(
            revision: revision,
            isCurrent: () => current,
            play: () {
              plays++;
              return playing.future;
            },
            seek: () async {
              seeks++;
            },
          );
        }

        final recovery = recover();
        if (duringPlay) {
          confirmation.complete();
          await Future<void>.delayed(Duration.zero);
          expect(plays, 1);
        }
        switch (command) {
          case 'pause':
            await player.pause();
          case 'seek':
            await player.seek(const Duration(seconds: 90));
          case 'background':
            intent.foreground(false);
            intent.foreground(true);
          case 'exit':
            intent.invalidate();
            current = false;
          case 'replacement':
            current = false;
        }
        if (!confirmation.isCompleted) confirmation.complete();
        playing.complete();
        await recovery;
        expect(plays, duringPlay ? 1 : 0);
        expect(seeks, 0);
      });
    }
  }

  test('current recovery plays then seeks', () async {
    final intent = PlaybackRecoveryIntent();
    final calls = <String>[];
    await intent.playAndSeek(
        revision: intent.revision,
        isCurrent: () => true,
        play: () async => calls.add('play'),
        seek: () async => calls.add('seek'));
    expect(calls, ['play', 'seek']);
  });

  test('hard recovery releases old session once without closing page owner',
      () async {
    final released = <String>[];
    final releaseOld = Completer<void>();
    final owner = FntvSessionOwner((target) async {
      released.add(target.fntvSessionLink);
      if (target.fntvSessionLink == 'old') await releaseOld.future;
    });
    PlaybackTarget target(String link) => PlaybackTarget(
          title: 'Episode',
          sourceId: 'fntv',
          sourceName: 'FNTV',
          sourceKind: MediaSourceKind.fntv,
          streamUrl: 'https://example.test/stream',
          fntvSessionLink: link,
        );
    final pendingResolution = Completer<PlaybackTarget>();
    await owner.retain(target('old'));
    final teardown = owner.release(target('old'));
    final resolving = pendingResolution.future.then(owner.retain);
    pendingResolution.complete(target('new'));
    await resolving;
    await owner.release(target('old'));
    expect(released, ['old']);
    releaseOld.complete();
    await teardown;
    expect(released, ['old']);
    await owner.close();
    await owner.retain(target('new'));
    await owner.retain(target('late'));
    await owner.close();
    expect(released, ['old', 'new', 'late']);
  });
}

class _Backend extends PlatformPlayer {
  _Backend() : super(configuration: const PlayerConfiguration());
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
}
