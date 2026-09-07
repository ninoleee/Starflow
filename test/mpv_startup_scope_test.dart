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
