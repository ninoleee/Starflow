import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/application/mpv_subtitle_render_binding.dart';
import 'package:starflow/features/playback/application/subtitle_render_policy.dart';
import 'package:starflow/features/playback/application/playback_subtitle_session_preference.dart';

void main() {
  test('bitmap aliases and codec-only preferences use one policy', () {
    for (final codec in [
      ' PGS ',
      'sup',
      'idx',
      'application/pgs',
      's_hdmv/pgs',
      'dvd_subtitle',
      'dvb_subtitle',
      'vobsub',
      'xsub'
    ]) {
      expect(isBitmapSubtitle(codec: codec), isTrue);
      final track = SubtitleTrack('1', 'English', 'en', codec: codec);
      final fingerprint = PlaybackSubtitleTrackFingerprint.fromTrack(track);
      expect(fingerprint.isImage, isTrue);
      expect(matchPlaybackSubtitleTrack([track], fingerprint, textOnly: true),
          isNull);
    }
  });

  test('auto resolves native sid against the latest metadata', () {
    final track = SubtitleTrack('7', 'PGS', 'en', codec: 'pgs');
    expect(
        resolveMpvSubtitleTrack(
            selected: SubtitleTrack.auto(), tracks: [track], sid: '7'),
        track);
    expect(
        resolveMpvSubtitleTrack(
            selected: SubtitleTrack.auto(), tracks: [track], sid: 'no'),
        isNull);
  });

  test('late metadata corrects visibility without selecting another track',
      () async {
    var tracks = <SubtitleTrack>[];
    final writes = <String>[];
    final states = <bool>[];
    final binding = MpvSubtitleRenderBinding(
      selected: () => SubtitleTrack.auto(),
      tracks: () => tracks,
      readSid: () async => '7',
      write: (name, value) async => writes.add('$name=$value'),
      onBitmapChanged: states.add,
      onError: (e, s) => fail('$e'),
    );
    binding.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(states, [true]);
    tracks = [SubtitleTrack('7', 'English', 'en', codec: 'subrip')];
    binding.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(states, [true, false]);
    tracks = [SubtitleTrack('7', 'English', 'en', codec: 'pgs')];
    binding.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(states, [true, false, true]);
    expect(writes.where((s) => s.startsWith('sid=')), isEmpty);
    await binding.close();
  });

  test('coalesces refreshes and close prevents pending native writes',
      () async {
    final sid = Completer<String>();
    var reads = 0;
    var writes = 0;
    final binding = MpvSubtitleRenderBinding(
      selected: () => SubtitleTrack.auto(),
      tracks: () => [],
      readSid: () {
        reads++;
        return sid.future;
      },
      write: (_, value) async {
        writes++;
      },
      onBitmapChanged: (_) {},
      onError: (e, s) => fail('$e'),
    );
    for (var i = 0; i < 100; i++) {
      binding.refresh();
    }
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    final closed = binding.close();
    sid.complete('7');
    await closed;
    expect(writes, 0);
  });

  test('failed write is reported and retried on next change', () async {
    var failWrite = true;
    var errors = 0;
    final states = <bool>[];
    final binding = MpvSubtitleRenderBinding(
      selected: () => SubtitleTrack.no(),
      tracks: () => [],
      readSid: () async => 'no',
      write: (_, value) async {
        if (failWrite) throw StateError('write failed');
      },
      onBitmapChanged: states.add,
      onError: (_, stack) {
        errors++;
      },
    );
    binding.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(errors, 1);
    failWrite = false;
    binding.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(states, [false]);
    await binding.close();
  });

  test('a track change during a native write corrects stale visibility',
      () async {
    var bitmap = false;
    Completer<void>? pending;
    final writes = <String>[];
    final binding = MpvSubtitleRenderBinding(
      selected: () => SubtitleTrack('1', null, null),
      tracks: () =>
          [SubtitleTrack('1', null, null, codec: bitmap ? 'pgs' : 'subrip')],
      readSid: () async => '1',
      write: (name, value) async {
        if (name == 'sub-visibility') {
          writes.add(value);
          await pending?.future;
        }
      },
      onBitmapChanged: (_) {},
      onError: (e, s) => fail('$e'),
    );
    binding.refresh();
    await Future<void>.delayed(Duration.zero);
    pending = Completer<void>();
    bitmap = true;
    binding.refresh();
    await Future<void>.delayed(Duration.zero);
    bitmap = false;
    binding.refresh();
    pending.complete();
    pending = null;
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['no', 'yes', 'no']);
    await binding.close();
  });
}
