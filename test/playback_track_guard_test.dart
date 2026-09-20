import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/playback_track_guard.dart';

void main() {
  test('manual server download cannot overwrite a later off selection',
      () async {
    var revision = 1;
    final selectedRevision = revision;
    final download = Completer<void>();
    var subtitle = 'off';
    final pending = PlaybackTrackGuard(() => revision == selectedRevision).run([
      () async {
        await download.future;
        if (!PlaybackTrackGuard.allowsWrite) return;
        subtitle = 'server subtitle';
      },
    ]);
    revision++;
    download.complete();
    await pending;
    expect(subtitle, 'off');
  });

  test('nested selection guard retains its cancelled startup parent', () async {
    var startupCurrent = true;
    final download = Completer<void>();
    var writes = 0;
    final pending = PlaybackTrackGuard(() => startupCurrent).run([
      () => PlaybackTrackGuard(() => true).run([
            () async {
              await download.future;
              if (PlaybackTrackGuard.allowsWrite) writes++;
            },
            () async {
              writes++;
            },
          ]),
    ]);
    startupCurrent = false;
    download.complete();
    await pending;
    expect(writes, 0);
    expect(PlaybackTrackGuard.allowsWrite, isTrue);
  });

  for (final cause in ['manual selection', 'new player', 'dispose']) {
    test('$cause fences a late subtitle result and remaining steps', () async {
      var active = true;
      var writes = 0;
      var steps = 0;
      final download = Completer<void>();
      final pending = PlaybackTrackGuard(() => active).run([
        () async {
          steps++;
          await download.future;
          if (PlaybackTrackGuard.allowsWrite) writes++;
        },
        () async {
          steps++;
        },
      ]);
      expect(steps, 1);
      active = false;
      download.complete();
      await pending;
      expect(writes, 0);
      expect(steps, 1);
      expect(PlaybackTrackGuard.allowsWrite, isTrue);
    });
  }

  test('unawaited optional tracks do not block caller readiness', () async {
    final tracks = Completer<void>();
    var configured = false;
    final pending = PlaybackTrackGuard(() => true).run([
      () async {
        await tracks.future;
        configured = PlaybackTrackGuard.allowsWrite;
      },
    ]);
    expect(configured, isFalse);
    tracks.complete();
    await pending;
    expect(configured, isTrue);
  });

  test('errors propagate without running later steps or leaking guard context',
      () async {
    var later = false;
    await expectLater(
        PlaybackTrackGuard(() => true).run([
          () async {
            throw StateError('download failed');
          },
          () async {
            later = true;
          },
        ]),
        throwsStateError);
    expect(later, isFalse);
    expect(PlaybackTrackGuard.allowsWrite, isTrue);
  });
}
