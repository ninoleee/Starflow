import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/application/mpv_startup_scope.dart';
import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';
import 'package:starflow/features/library/domain/media_models.dart';

void main() {
  test('failed remote connections retry only within attempt and time budgets',
      () {
    bool retry(Object error, int attempt, Duration remaining) =>
        shouldRetryMpvOpenFailure(
          error: error,
          remote: true,
          attempt: attempt,
          maxAttempts: 3,
          remaining: remaining,
          backoff: const Duration(milliseconds: 650),
        );
    expect(
        retry('tcp: ffurl_read returned 0xdfb9b0bb', 1,
            const Duration(seconds: 5)),
        isTrue);
    expect(retry('HTTP error 403', 1, const Duration(seconds: 5)), isFalse);
    expect(retry('connection reset', 3, const Duration(seconds: 5)), isFalse);
    expect(retry('connection reset', 1, const Duration(milliseconds: 500)),
        isFalse);
  });

  test('cancelled scope rejects subsequent native stages', () {
    final scope = MpvStartupScope()..cancel();
    expect(scope.checkActive, throwsA(isA<MpvStartupCancelled>()));
  });
  test('cancellation releases pending wait and permits late native failure',
      () async {
    final scope = MpvStartupScope();
    final native = Completer<void>();
    final result = scope.wait(native.future);
    final assertion = expectLater(result, throwsA(isA<MpvStartupCancelled>()));
    scope.cancel();
    scope.cancel();
    await assertion;
    native.completeError(StateError('late failure'));
    await Future<void>.delayed(Duration.zero);
  });

  test('all stages share the same expired deadline', () async {
    final scope = MpvStartupScope()
      ..deadline = DateTime.now().subtract(const Duration(seconds: 1));
    await expectLater(
        scope.wait(Completer<void>().future), throwsA(isA<TimeoutException>()));
  });

  test('native diagnostics never contain URLs or credentials', () {
    final summary = summarizeMpvError('ffmpeg',
        'HTTP error 403 https://host/movie.ts?token=secret Cookie: private');
    expect(summary['httpStatus'], 403);
    expect(summary.toString(), isNot(contains('secret')));
    expect(summary.toString(), isNot(contains('private')));
    expect(summary.toString(), isNot(contains('host')));
  });

  test('native diagnostics retain nested components and segment failures', () {
    final summary = summarizeMpvError('ffmpeg/demuxer',
        'HTTP/1.1 503 https://host/media-0.ts?token=secret Cookie: private');
    expect(summary, {
      'component': 'ffmpeg',
      'httpStatus': 503,
      'resource': 'segment',
      'kind': 'http-error',
    });
    expect(
      summarizeMpvError(
          'stream', 'Failed to open https://host/media-0.ts?auth_key=secret'),
      {'component': 'stream', 'resource': 'segment', 'kind': 'open-failed'},
    );
    expect(
      summarizeMpvError('unknown/secret', 'TLS handshake failed')['component'],
      'other',
    );
  });

  testWidgets('transient HLS log errors do not abort an active load',
      (tester) async {
    final failures = <String>[];
    var reads = 0;
    final gate = MpvStartupErrorGate(
      remote: true,
      readIdleActive: () async {
        reads++;
        return false;
      },
      onConfirmed: (failure) => failures.add(failure.toString()),
    );
    addTearDown(gate.dispose);
    gate.report('Failed to open https://host/media-0.ts');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(reads, 12);
    expect(failures, isEmpty);
    expect(gate.deferredErrorCount, 1);
    gate.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 12);
  });

  testWidgets('stopped load needs consecutive idle samples despite error burst',
      (tester) async {
    final failures = <String>[];
    var idle = true;
    final gate = MpvStartupErrorGate(
      remote: true,
      readIdleActive: () async => idle,
      onConfirmed: (failure) => failures.add(failure.toString()),
    );
    addTearDown(gate.dispose);
    gate.report('Failed to open stream');
    await tester.pump(const Duration(milliseconds: 250));
    expect(failures, isEmpty);
    idle = false;
    await tester.pump(const Duration(milliseconds: 250));
    idle = true;
    await tester.pump(const Duration(milliseconds: 250));
    expect(failures, isEmpty);
    gate.report('connection reset');
    await tester.pump(const Duration(milliseconds: 250));
    expect(failures, ['connection reset']);
    expect(gate.confirmation, 'idle-active');
    expect(gate.deferredErrorCount, 2);
    gate.report('another connection reset');
    await tester.pump(const Duration(seconds: 1));
    expect(failures, hasLength(1));
  });

  testWidgets('permanent error preempts pending network confirmation',
      (tester) async {
    final failures = <String>[];
    final gate = MpvStartupErrorGate(
      remote: true,
      readIdleActive: () async => false,
      onConfirmed: (failure) => failures.add(failure.toString()),
    );
    addTearDown(gate.dispose);
    gate.report('connection reset');
    gate.report('HTTP error 403');
    expect(failures, ['HTTP error 403']);
    expect(gate.confirmation, 'immediate');
    await tester.pump(const Duration(seconds: 1));
    expect(failures, hasLength(1));
  });

  test('local and Web failures do not wait for native idle state', () {
    final failures = <String>[];
    final gate = MpvStartupErrorGate(
      remote: false,
      readIdleActive: () async => throw StateError('must not read native'),
      onConfirmed: (failure) => failures.add(failure.toString()),
    );
    addTearDown(gate.dispose);
    gate.report('Failed to open file');
    expect(failures, ['Failed to open file']);
    expect(gate.confirmation, 'immediate');
  });

  testWidgets('unavailable idle property uses a bounded fallback',
      (tester) async {
    final failures = <String>[];
    final gate = MpvStartupErrorGate(
      remote: true,
      readIdleActive: () async => throw UnsupportedError('idle-active'),
      onConfirmed: (failure) => failures.add(failure.toString()),
    );
    addTearDown(gate.dispose);
    gate.report('connection reset');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(failures, isEmpty);
    await tester.pump(const Duration(milliseconds: 250));
    expect(failures, ['connection reset']);
    expect(gate.confirmation, 'idle-unavailable');
  });

  testWidgets('hung idle reads time out and cannot block failure forever',
      (tester) async {
    final failures = <String>[];
    final gate = MpvStartupErrorGate(
      remote: true,
      readIdleActive: () => Completer<bool?>().future,
      onConfirmed: (failure) => failures.add(failure.toString()),
    );
    addTearDown(gate.dispose);
    gate.report('connection reset');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(failures, ['connection reset']);
    expect(gate.confirmation, 'idle-unavailable');
  });

  testWidgets('dispose ignores an in-flight property result', (tester) async {
    final failures = <String>[];
    final pendingRead = Completer<bool?>();
    var reads = 0;
    final gate = MpvStartupErrorGate(
      remote: true,
      readIdleActive: () {
        reads++;
        return pendingRead.future;
      },
      onConfirmed: (failure) => failures.add(failure.toString()),
    );
    addTearDown(gate.dispose);
    gate.report('connection reset');
    await tester.pump(const Duration(milliseconds: 250));
    gate.dispose();
    pendingRead.complete(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(failures, isEmpty);
    expect(reads, 1);
  });

  test('recovery retains current episode and enables saved progress', () {
    const current = PlaybackTarget(
      title: 'Episode 2',
      sourceId: 'emby',
      sourceName: 'Emby',
      sourceKind: MediaSourceKind.emby,
      itemId: 'episode-2',
      streamUrl: 'https://host/old-link',
      allowResume: false,
      headers: {'Authorization': 'expired'},
    );
    final recovered = buildMpvRecoveryTarget(current);
    expect(recovered.itemId, 'episode-2');
    expect(recovered.allowResume, isTrue);
    expect(recovered.streamUrl, isEmpty);
    expect(recovered.headers, isEmpty);
  });
}
