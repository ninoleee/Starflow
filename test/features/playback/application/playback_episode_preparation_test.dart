import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_auto_skip_policy.dart';
import 'package:starflow/features/playback/application/playback_episode_preparation.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const _target = PlaybackTarget(
  title: 'Episode 2',
  sourceId: 'source',
  streamUrl: 'https://example.test/resolved-2?token=prepared',
  headers: {'Authorization': 'Bearer prepared'},
  sourceName: 'Emby',
  sourceKind: MediaSourceKind.emby,
);

void main() {
  late PlaybackEpisodePreparation preparation;

  void initialize(WidgetTester tester) {
    preparation = PlaybackEpisodePreparation(clock: tester.binding.clock.now);
    addTearDown(preparation.reset);
  }

  test('late callback is expired even before its timer gets to run', () async {
    var now = DateTime(2026, 9, 20);
    final cache = PlaybackEpisodePreparation(clock: () => now);
    addTearDown(cache.reset);
    final pending = Completer<PlaybackTarget>();
    final result = expectLater(
      cache.resolve(key: 'session', resolver: () => pending.future),
      throwsA(isA<TimeoutException>()),
    );
    now = now.add(kPlaybackEpisodeResolveTimeout);
    pending.complete(_target);
    await result;
  });

  test('an expired background deadline cannot be promoted before timer runs', () async {
    var now = DateTime(2026, 9, 20);
    final cache = PlaybackEpisodePreparation(clock: () => now);
    addTearDown(cache.reset);
    final pending = Completer<PlaybackTarget>();
    var calls = 0;
    final background = cache.prepare(key: 'session', resolver: () {
      calls++;
      return pending.future;
    });
    now = now.add(kPlaybackEpisodeResolveTimeout);
    final result = await cache.resolve(key: 'session', resolver: () async {
      calls++;
      return _target;
    });
    await background;
    expect(calls, 2);
    expect(result.wasPrepared, isFalse);
    pending.complete(_target);
  });

  testWidgets('completed preparation preserves target and provenance',
      (tester) async {
    initialize(tester);
    var calls = 0;
    Future<PlaybackTarget> resolver() async {
      calls++;
      return _target;
    }

    await preparation.prepare(key: 'session', resolver: resolver);
    await preparation.prepare(key: 'session', resolver: resolver);
    final result =
        await preparation.resolve(key: 'session', resolver: resolver);
    expect(result.target, same(_target));
    expect(result.target.headers, {'Authorization': 'Bearer prepared'});
    expect(result.wasPrepared, isTrue);
    expect(calls, 1);
  });

  testWidgets('only an explicit manual retry repeats a failed foreground',
      (tester) async {
    initialize(tester);
    var calls = 0;
    Future<PlaybackTarget> resolver() async {
      calls++;
      if (calls == 1) throw StateError('unavailable');
      return _target;
    }

    await expectLater(
      preparation.resolve(key: 'session', resolver: resolver),
      throwsStateError,
    );
    await expectLater(
      preparation.resolve(key: 'session', resolver: resolver),
      throwsStateError,
    );
    expect(calls, 1);
    final result = await preparation.resolve(
      key: 'session',
      resolver: resolver,
      retryFailed: true,
    );
    expect(result.target, same(_target));
    expect(calls, 2);
  });

  testWidgets('foreground promotes in-flight background without duplication',
      (tester) async {
    initialize(tester);
    final pending = Completer<PlaybackTarget>();
    var calls = 0;
    Future<PlaybackTarget> resolver() {
      calls++;
      return pending.future;
    }

    final background = preparation.prepare(key: 'session', resolver: resolver);
    await tester.pump(const Duration(seconds: 29));
    final foreground = preparation.resolve(key: 'session', resolver: resolver);
    await tester.pump(const Duration(seconds: 2));
    pending.complete(_target);
    await tester.pump();
    await background;
    expect((await foreground).wasPrepared, isTrue);
    expect(calls, 1);
  });

  testWidgets('promotion extends deadline once even with repeated callers',
      (tester) async {
    initialize(tester);
    final pending = Completer<PlaybackTarget>();
    var calls = 0;
    Future<PlaybackTarget> resolver() {
      calls++;
      return pending.future;
    }

    final background = preparation.prepare(key: 'session', resolver: resolver);
    await tester.pump(const Duration(seconds: 20));
    final first = expectLater(
      preparation.resolve(key: 'session', resolver: resolver),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 20));
    var secondSettled = false;
    final second = expectLater(
      preparation.resolve(key: 'session', resolver: resolver),
      throwsA(isA<TimeoutException>()),
    ).then((_) => secondSettled = true);
    await tester.pump(const Duration(seconds: 9));
    expect(secondSettled, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await first;
    await second;
    await background;
    expect(secondSettled, isTrue);
    pending.completeError(StateError('late failure after promotion'));
    await tester.pump();
    await expectLater(
      preparation.resolve(key: 'session', resolver: resolver),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 1);
  });

  testWidgets('TTL starts at completion and expires exactly at 60 seconds',
      (tester) async {
    initialize(tester);
    final pending = Completer<PlaybackTarget>();
    final background = preparation.prepare(
      key: 'session',
      resolver: () => pending.future,
    );
    await tester.pump(const Duration(seconds: 20));
    pending.complete(_target);
    await tester.pump();
    await background;
    var calls = 0;
    final fresh = _target.copyWith(streamUrl: 'https://example.test/fresh');
    Future<PlaybackTarget> resolver() async {
      calls++;
      return fresh;
    }

    await tester.pump(const Duration(seconds: 59));
    final cached =
        await preparation.resolve(key: 'session', resolver: resolver);
    expect(cached.wasPrepared, isTrue);
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 1));
    await preparation.prepare(key: 'session', resolver: resolver);
    expect(calls, 0);
    final refreshed = await preparation.resolve(
      key: 'session',
      resolver: resolver,
    );
    expect(refreshed.target, same(fresh));
    expect(refreshed.wasPrepared, isFalse);
    expect(calls, 1);
  });

  testWidgets('background sync failure is absorbed and foreground retries once',
      (tester) async {
    initialize(tester);
    var calls = 0;
    Future<PlaybackTarget> resolver() {
      calls++;
      throw StateError('offline');
    }

    unawaited(preparation.prepare(key: 'session', resolver: resolver));
    await tester.pump();
    await preparation.prepare(key: 'session', resolver: resolver);
    expect(calls, 1);
    for (var i = 0; i < 2; i++) {
      await expectLater(
        preparation.resolve(key: 'session', resolver: resolver),
        throwsStateError,
      );
    }
    expect(calls, 2);
  });

  testWidgets('promoted failure does not start a second foreground request',
      (tester) async {
    initialize(tester);
    final pending = Completer<PlaybackTarget>();
    var calls = 0;
    Future<PlaybackTarget> resolver() {
      calls++;
      return pending.future;
    }

    final background = preparation.prepare(key: 'session', resolver: resolver);
    final foreground = expectLater(
      preparation.resolve(key: 'session', resolver: resolver),
      throwsStateError,
    );
    pending.completeError(StateError('promoted request failed'));
    await tester.pump();
    await background;
    await foreground;
    await expectLater(
      preparation.resolve(key: 'session', resolver: resolver),
      throwsStateError,
    );
    expect(calls, 1);
  });

  testWidgets('expired foreground result cannot restart a resolution loop',
      (tester) async {
    initialize(tester);
    var calls = 0;
    Future<PlaybackTarget> resolver() async {
      calls++;
      return _target;
    }

    await preparation.resolve(key: 'session', resolver: resolver);
    await tester.pump(kPlaybackPreparedEpisodeTtl);
    await preparation.prepare(key: 'session', resolver: resolver);
    await expectLater(
      preparation.resolve(key: 'session', resolver: resolver),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 1);
  });

  testWidgets('late background completion cannot settle the fallback request',
      (tester) async {
    initialize(tester);
    final oldPending = Completer<PlaybackTarget>();
    final background = preparation.prepare(
      key: 'session',
      resolver: () => oldPending.future,
    );
    await tester.pump(kPlaybackEpisodeResolveTimeout);
    await background;
    final freshPending = Completer<PlaybackTarget>();
    var settled = false;
    final foreground = preparation
        .resolve(key: 'session', resolver: () => freshPending.future)
        .then((result) {
      settled = true;
      return result;
    });
    oldPending.complete(_target);
    await tester.pump();
    expect(settled, isFalse);
    final fresh = _target.copyWith(streamUrl: 'https://example.test/fresh');
    freshPending.complete(fresh);
    await tester.pump();
    expect((await foreground).target, same(fresh));
  });

  for (final lateFailure in [false, true]) {
    testWidgets('timed out background cannot overwrite fallback: $lateFailure',
        (tester) async {
      initialize(tester);
      final pending = Completer<PlaybackTarget>();
      final background = preparation.prepare(
        key: 'session',
        resolver: () => pending.future,
      );
      await tester.pump(kPlaybackEpisodeResolveTimeout);
      await background;
      final fresh = _target.copyWith(streamUrl: 'https://example.test/fresh');
      var calls = 0;
      Future<PlaybackTarget> resolver() async {
        calls++;
        return fresh;
      }

      final result = await preparation.resolve(
        key: 'session',
        resolver: resolver,
      );
      expect(result.wasPrepared, isFalse);
      if (lateFailure) {
        pending.completeError(StateError('late failure'));
      } else {
        pending.complete(_target);
      }
      await tester.pump();
      expect(
        (await preparation.resolve(key: 'session', resolver: resolver)).target,
        same(fresh),
      );
      expect(calls, 1);
    });

    testWidgets('reset isolates same-key generation: $lateFailure',
        (tester) async {
      initialize(tester);
      final oldPending = Completer<PlaybackTarget>();
      final oldBackground = preparation.prepare(
        key: 'session',
        resolver: () => oldPending.future,
      );
      preparation.reset();
      await oldBackground;
      final fresh = _target.copyWith(streamUrl: 'https://example.test/new');
      await preparation.prepare(key: 'session', resolver: () async => fresh);
      if (lateFailure) {
        oldPending.completeError(StateError('stale failure'));
      } else {
        oldPending.complete(_target);
      }
      await tester.pump();
      final result = await preparation.resolve(
        key: 'session',
        resolver: () => throw StateError('must use new cache'),
      );
      expect(result.target, same(fresh));
      expect(result.wasPrepared, isTrue);
    });
  }

  testWidgets('reset settles foreground waiters without waiting for resolver',
      (tester) async {
    initialize(tester);
    final pending = Completer<PlaybackTarget>();
    final expectation = expectLater(
      preparation.resolve(key: 'session', resolver: () => pending.future),
      throwsStateError,
    );
    preparation.reset();
    await tester.pump();
    await expectation;
    pending.completeError(StateError('failure after reset'));
    await tester.pump();
  });

  testWidgets('caller intent cancellation prevents commit but retains cache',
      (tester) async {
    initialize(tester);
    final pending = Completer<PlaybackTarget>();
    var intent = 1;
    var commits = 0;
    final background = preparation.prepare(
      key: 'session',
      resolver: () => pending.future,
    );
    final token = intent;
    final foreground = preparation
        .resolve(key: 'session', resolver: () => pending.future)
        .then((_) {
      if (intent == token) commits++;
    });
    intent++;
    pending.complete(_target);
    await tester.pump();
    await background;
    await foreground;
    expect(commits, 0);
    final result = await preparation.resolve(
      key: 'session',
      resolver: () => throw StateError('must use cache'),
    );
    expect(result.target, same(_target));
    expect(result.wasPrepared, isTrue);
  });

  testWidgets('foreground-only calls share one request and retain provenance',
      (tester) async {
    initialize(tester);
    final pending = Completer<PlaybackTarget>();
    var calls = 0;
    Future<PlaybackTarget> resolver() {
      calls++;
      return pending.future;
    }

    final first = preparation.resolve(key: 'session', resolver: resolver);
    final second = preparation.resolve(key: 'session', resolver: resolver);
    await preparation.prepare(key: 'session', resolver: resolver);
    pending.complete(_target);
    await tester.pump();
    expect((await first).wasPrepared, isFalse);
    expect((await second).wasPrepared, isFalse);
    expect(
      (await preparation.resolve(key: 'session', resolver: resolver))
          .wasPrepared,
      isFalse,
    );
    expect(calls, 1);
  });

  testWidgets('foreground-only deadline is not extended by repeated calls',
      (tester) async {
    initialize(tester);
    final pending = Completer<PlaybackTarget>();
    final first = expectLater(
      preparation.resolve(key: 'session', resolver: () => pending.future),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 20));
    final second = expectLater(
      preparation.resolve(key: 'session', resolver: () => pending.future),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 10));
    await first;
    await second;
    pending.completeError(StateError('late foreground failure'));
    await tester.pump();
  });

  testWidgets('keys isolate sessions and prepare at most once per key',
      (tester) async {
    initialize(tester);
    var calls = 0;
    Future<PlaybackTarget> resolver() async {
      calls++;
      return _target.copyWith(streamUrl: 'https://example.test/$calls');
    }

    await preparation.prepare(key: ('queue', 1), resolver: resolver);
    await preparation.prepare(key: ('queue', 2), resolver: resolver);
    await preparation.prepare(key: ('queue', 1), resolver: resolver);
    final first = await preparation.resolve(
      key: ('queue', 1),
      resolver: resolver,
    );
    final second = await preparation.resolve(
      key: ('queue', 2),
      resolver: resolver,
    );
    expect(first.target.streamUrl, 'https://example.test/1');
    expect(second.target.streamUrl, 'https://example.test/2');
    expect(calls, 2);
  });
}
