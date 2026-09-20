import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starflow/features/library/data/media_repository.dart';
import 'package:starflow/features/library/data/media_server_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/fntv_session_owner.dart';
import 'package:starflow/features/playback/application/mpv_startup_scope.dart';
import 'package:starflow/features/playback/application/playback_engine_router.dart';
import 'package:starflow/features/playback/application/playback_startup_coordinator.dart';
import 'package:starflow/features/playback/application/playback_startup_routing.dart';
import 'package:starflow/features/playback/application/playback_target_resolver.dart';
import 'package:starflow/features/playback/data/playback_memory_repository.dart';
import 'package:starflow/features/playback/domain/playback_memory_models.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/playback/presentation/player_page.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _session = PlaybackTarget(
  title: 'Episode',
  sourceId: 'fntv-test',
  sourceName: 'FNTV',
  sourceKind: MediaSourceKind.fntv,
  itemId: 'episode-1',
  streamUrl: 'https://example.test/session/index.m3u8',
  fntvSessionLink: 'session-1',
);

void main() {
  testWidgets(
      'player page releases sessions after resume and skip read failures',
      (tester) async {
    // The page's static cleanup queue must stay in one fakeAsync zone.
    for (final failure in ['resume', 'skip']) {
      SharedPreferences.setMockInitialValues({});
      final server = _SessionServer();
      final memory = _FaultMemory(
        failure: failure,
        fault: StateError('$failure storage unavailable'),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(_NoopMediaRepository()),
          mediaServerClientProvider(MediaSourceKind.fntv)
              .overrideWithValue(server),
          playbackMemoryRepositoryProvider.overrideWithValue(memory),
          appSettingsProvider.overrideWithValue(
            AppSettings.fromJson(const {}).copyWith(
              playbackEngine: PlaybackEngine.embeddedMpv,
              mediaSources: const [
                MediaSourceConfig(
                  id: 'fntv-test',
                  name: 'FNTV',
                  kind: MediaSourceKind.fntv,
                  endpoint: 'https://example.test',
                  enabled: true,
                  accessToken: 'synthetic-token',
                  userId: 'test-user',
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(home: PlayerPage(target: _session)),
      ));
      await tester.pumpAndSettle();
      expect(server.resolutions, 1);
      expect(
          memory.reads, failure == 'resume' ? ['resume'] : ['resume', 'skip']);
      expect(server.released, ['session-1']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(server.released, ['session-1']);
      expect(tester.takeException(), isNull);
    }
  });

  for (final alreadyResolved in [false, true]) {
    for (final failure in ['resume', 'skip']) {
      test('$failure read failure releases session (resolved=$alreadyResolved)',
          () async {
        final fault = StateError('$failure storage unavailable');
        final memory = _FaultMemory(failure: failure, fault: fault);
        final harness = _Harness(memory: memory);
        addTearDown(harness.dispose);

        await expectLater(
          harness.start(alreadyResolved: alreadyResolved),
          throwsA(same(fault)),
        );
        expect(harness.released, ['session-1']);
        expect(memory.reads,
            failure == 'resume' ? ['resume'] : ['resume', 'skip']);
        await harness.owner.release(_session);
        await harness.owner.close();
        expect(harness.released, ['session-1']);
      });
    }
  }

  test('failure cleanup also owns a session before native handoff', () async {
    final fault = StateError('resume unavailable');
    final harness = _Harness(
      memory: _FaultMemory(failure: 'resume', fault: fault),
      engine: PlaybackEngine.nativeContainer,
    );
    addTearDown(harness.dispose);
    await expectLater(harness.start(), throwsA(same(fault)));
    expect(harness.routes, [PlaybackStartupRouteAction.launchNativeContainer]);
    expect(harness.released, ['session-1']);
    await harness.owner.close();
    expect(harness.released, ['session-1']);
  });

  test('embedded session is owned while the first storage read is pending',
      () async {
    final pending = Completer<void>();
    final memory = _FaultMemory(pendingResume: pending.future);
    final harness = _Harness(memory: memory);
    addTearDown(harness.dispose);
    final startup = harness.start();
    final cancelled = expectLater(startup, throwsA(isA<MpvStartupCancelled>()));
    await memory.enteredResume.future;
    harness.active = false;
    await harness.owner.close();
    expect(harness.released, ['session-1']);
    pending.complete();
    await cancelled;
    expect(harness.released, ['session-1']);
  });

  test('closing during a storage read and its late failure releases once',
      () async {
    final pending = Completer<void>();
    final fault = StateError('late storage failure');
    final memory = _FaultMemory(
      pendingResume: pending.future,
      failure: 'resume',
      fault: fault,
    );
    final harness = _Harness(memory: memory);
    addTearDown(harness.dispose);
    final startup = harness.start();
    final failed = expectLater(startup, throwsA(same(fault)));
    await memory.enteredResume.future;
    harness.active = false;
    await harness.owner.close();
    expect(harness.released, ['session-1']);
    pending.complete();
    await failed;
    await harness.owner.release(_session);
    expect(harness.released, ['session-1']);
  });

  for (final engine in [
    PlaybackEngine.embeddedMpv,
    PlaybackEngine.nativeContainer,
  ]) {
    for (final closeOwner in [false, true]) {
      test('late resolution is released: $engine, closed=$closeOwner',
          () async {
        final resolved = Completer<PlaybackTarget>();
        final memory = _FaultMemory();
        final harness = _Harness(
          memory: memory,
          engine: engine,
          resolve: () => resolved.future,
        );
        addTearDown(harness.dispose);
        final startup = harness.start();
        final cancelled =
            expectLater(startup, throwsA(isA<MpvStartupCancelled>()));
        harness.active = false;
        if (closeOwner) await harness.owner.close();
        resolved.complete(_session);
        await cancelled;
        expect(memory.reads, isEmpty);
        expect(harness.released, ['session-1']);
        await harness.owner.close();
        expect(harness.released, ['session-1']);
      });
    }
  }

  test('successful embedded startup retains session until owner closes',
      () async {
    final harness = _Harness(memory: _FaultMemory());
    addTearDown(harness.dispose);
    final outcome = await harness.start();
    expect(outcome.resolvedTarget, same(_session));
    expect(outcome.routeAction, PlaybackStartupRouteAction.openEmbeddedMpv);
    expect(harness.released, isEmpty);
    await harness.owner.close();
    expect(harness.released, ['session-1']);
  });

  test('successful native startup leaves session for the native owner',
      () async {
    final harness = _Harness(
      memory: _FaultMemory(),
      engine: PlaybackEngine.nativeContainer,
    );
    addTearDown(harness.dispose);
    final outcome = await harness.start();
    expect(
        outcome.routeAction, PlaybackStartupRouteAction.launchNativeContainer);
    await harness.owner.close();
    expect(harness.released, isEmpty);
  });

  test('non-transcoding storage failure does not invoke session cleanup',
      () async {
    final fault = StateError('storage failure');
    final harness = _Harness(
      memory: _FaultMemory(failure: 'resume', fault: fault),
      resolve: () async => _session.copyWith(fntvSessionLink: ''),
    );
    addTearDown(harness.dispose);
    await expectLater(harness.start(), throwsA(same(fault)));
    expect(harness.cleanupCalls, 0);
    expect(harness.released, isEmpty);
  });

  test('resolution failure has no resolved session to release', () async {
    final fault = StateError('resolve failed');
    final memory = _FaultMemory();
    final harness = _Harness(memory: memory, resolve: () async => throw fault);
    addTearDown(harness.dispose);
    await expectLater(harness.start(), throwsA(same(fault)));
    expect(memory.reads, isEmpty);
    expect(harness.cleanupCalls, 0);
  });

  test('cleanup error cannot replace the original storage error', () async {
    final fault = StateError('storage failure');
    final harness =
        _Harness(memory: _FaultMemory(failure: 'skip', fault: fault));
    addTearDown(harness.dispose);
    final coordinator = harness.coordinator(
      release: (_) async => throw StateError('release failed'),
    );
    await expectLater(
      coordinator.start(
          initialTarget: _session, isTelevision: true, isWeb: false),
      throwsA(same(fault)),
    );
  });
}

class _Harness {
  _Harness({
    required _FaultMemory memory,
    PlaybackEngine engine = PlaybackEngine.embeddedMpv,
    Future<PlaybackTarget> Function()? resolve,
  }) : resolve = resolve ?? (() async => _session) {
    container = ProviderContainer(overrides: [
      mediaRepositoryProvider.overrideWithValue(_NoopMediaRepository()),
      playbackMemoryRepositoryProvider.overrideWithValue(memory),
      appSettingsProvider.overrideWithValue(
        AppSettings.fromJson(const {}).copyWith(playbackEngine: engine),
      ),
    ]);
    owner = FntvSessionOwner(
        (target) async => released.add(target.fntvSessionLink));
  }

  late final ProviderContainer container;
  late final FntvSessionOwner owner;
  final Future<PlaybackTarget> Function() resolve;
  final released = <String>[];
  final routes = <PlaybackStartupRouteAction>[];
  var cleanupCalls = 0;
  var active = true;

  PlaybackStartupCoordinator coordinator({
    Future<void> Function(PlaybackTarget)? release,
  }) =>
      PlaybackStartupCoordinator(
        read: container.read,
        targetResolver: _Resolver(container, resolve),
        engineRouter: const PlaybackEngineRouter(),
        releaseSession: release ??
            (target) async {
              cleanupCalls++;
              await owner.retain(target);
              await owner.release(target);
            },
      );

  Future<PlaybackStartupOutcome> start({bool alreadyResolved = false}) =>
      coordinator().start(
        initialTarget: _session,
        isTelevision: true,
        isWeb: false,
        targetAlreadyResolved: alreadyResolved,
        onTargetResolved: (target, route) async {
          routes.add(route);
          if (route == PlaybackStartupRouteAction.openEmbeddedMpv || !active) {
            await owner.retain(target);
          }
        },
        checkActive: () {
          if (!active) throw const MpvStartupCancelled();
        },
      );

  Future<void> dispose() async {
    await owner.close();
    container.dispose();
  }
}

class _Resolver extends PlaybackTargetResolver {
  _Resolver(ProviderContainer container, this.resolveTarget)
      : super(read: container.read);
  final Future<PlaybackTarget> Function() resolveTarget;

  @override
  Future<PlaybackTarget> resolve(PlaybackTarget target) => resolveTarget();
}

class _FaultMemory extends PlaybackMemoryRepository {
  _FaultMemory({this.failure, this.fault, this.pendingResume});
  final String? failure;
  final Object? fault;
  final Future<void>? pendingResume;
  final enteredResume = Completer<void>();
  final reads = <String>[];

  @override
  Future<PlaybackProgressEntry?> loadEntryForTarget(
      PlaybackTarget target) async {
    reads.add('resume');
    enteredResume.complete();
    await pendingResume;
    if (failure == 'resume') throw fault!;
    return null;
  }

  @override
  Future<SeriesSkipPreference?> loadSkipPreference(
      PlaybackTarget target) async {
    reads.add('skip');
    if (failure == 'skip') throw fault!;
    return null;
  }
}

class _NoopMediaRepository implements MediaRepository {
  @override
  Future<void> cancelActiveWebDavRefreshes(
      {bool includeForceFull = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SessionServer implements MediaServerClient, MediaServerSessionClient {
  int resolutions = 0;
  final released = <String>[];

  @override
  Future<PlaybackTarget> resolvePlaybackTarget({
    required MediaSourceConfig source,
    required PlaybackTarget target,
  }) async {
    resolutions++;
    return _session;
  }

  @override
  Future<void> releasePlaybackSession({
    required MediaSourceConfig source,
    required PlaybackTarget target,
  }) async {
    released.add(target.fntvSessionLink);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
