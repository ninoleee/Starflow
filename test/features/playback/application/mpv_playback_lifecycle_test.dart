import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:starflow/features/playback/application/mpv_playback_lifecycle.dart';
import 'package:starflow/features/playback/application/mpv_subtitle_render_binding.dart';

void main() {
  test('transport closes immediately while subscription cancellation waits',
      () async {
    final cancellation = Completer<void>();
    final events = StreamController<int>(onCancel: () => cancellation.future);
    final lifecycle = MpvPlaybackLifecycle();
    var transportCloses = 0;
    lifecycle.retain(events.stream.listen((_) {}));
    lifecycle.retainCleanup(() async {
      transportCloses++;
    });
    final closing = lifecycle.close();
    expect(transportCloses, 1);
    expect(identical(closing, lifecycle.close()), isTrue);
    cancellation.complete();
    await closing;
    expect(transportCloses, 1);
    await events.close();
  });

  test('late cleanup runs after lifecycle has closed', () async {
    final lifecycle = MpvPlaybackLifecycle();
    await lifecycle.close();
    var transportCloses = 0;
    lifecycle.retainCleanup(() async {
      transportCloses++;
    });
    expect(transportCloses, 1);
  });
  test(
      'closing an old player suppresses events without closing its replacement',
      () async {
    final events = StreamController<int>.broadcast(sync: true);
    final old = MpvPlaybackLifecycle();
    final replacement = MpvPlaybackLifecycle();
    final received = <String>[];
    old.listen(events.stream, (value) => received.add('old:$value'));
    replacement.listen(events.stream, (value) => received.add('new:$value'));
    events.add(1);
    final closing = old.close();
    expect(identical(closing, old.close()), isTrue);
    events.add(2);
    await closing;
    expect(received, ['old:1', 'new:1', 'new:2']);
    await replacement.close();
    await events.close();
  });

  test('late retained subscription is cancelled immediately', () async {
    var cancelled = 0;
    final events = StreamController<int>(onCancel: () => cancelled++);
    final lifecycle = MpvPlaybackLifecycle();
    await lifecycle.close();
    lifecycle.retain(events.stream.listen((_) {}));
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, 1);
    await events.close();
  });

  test('all subscriptions are cancelled even when one cancellation fails',
      () async {
    final failing =
        StreamController<int>(onCancel: () => throw StateError('x'));
    var cancelled = false;
    final other = StreamController<int>(onCancel: () => cancelled = true);
    final lifecycle = MpvPlaybackLifecycle();
    lifecycle.listen(failing.stream, (_) {});
    lifecycle.listen(other.stream, (_) {});
    await expectLater(lifecycle.close(), throwsStateError);
    expect(cancelled, isTrue);
    await failing.close();
    await other.close();
  });

  test('subtitle close waits for late sid registration then removes it once',
      () async {
    final registration = Completer<void>();
    var unobserved = 0;
    var writes = 0;
    void Function()? observed;
    final lifecycle = MpvPlaybackLifecycle();
    final binding = MpvSubtitleRenderBinding(
      selected: SubtitleTrack.auto,
      tracks: () => [],
      readSid: () async => '7',
      write: (_, value) async => writes++,
      onBitmapChanged: (_) => fail('closed renderer published'),
      onError: (e, _) => fail('$e'),
    );
    final bindingReady = lifecycle.subtitles.bind(
      binding: binding,
      observe: (callback) {
        observed = callback;
        return registration.future;
      },
      unobserve: () async => unobserved++,
      onObservationError: (e, _) => fail('$e'),
    );
    var finished = false;
    final closing = lifecycle.close().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    observed!();
    registration.complete();
    await bindingReady;
    await closing;
    await lifecycle.close();
    expect(unobserved, 1);
    expect(writes, 0);
  });

  test('subtitle stream refreshes are released with the owning player',
      () async {
    final events = StreamController<int>.broadcast(sync: true);
    final lifecycle = MpvPlaybackLifecycle();
    var reads = 0;
    var unobserved = 0;
    await lifecycle.subtitles.bind(
      binding: MpvSubtitleRenderBinding(
        selected: SubtitleTrack.no,
        tracks: () => [],
        readSid: () async {
          reads++;
          return 'no';
        },
        write: (_, value) async {},
        onBitmapChanged: (_) {},
        onError: (e, _) => fail('$e'),
      ),
      observe: (_) async {},
      unobserve: () async => unobserved++,
      onObservationError: (e, _) => fail('$e'),
    );
    lifecycle.subtitles.listen(events.stream);
    await Future<void>.delayed(Duration.zero);
    events.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2);
    await lifecycle.close();
    events.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2);
    expect(unobserved, 1);
    expect(events.hasListener, isFalse);
    await events.close();
  });
}
