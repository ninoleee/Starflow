import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/mpv_buffer_progress.dart';
import 'package:starflow/features/playback/application/mpv_startup_scope.dart';
import 'package:starflow/features/playback/application/mpv_tuning_policy.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const _target = PlaybackTarget(
  title: 'Test',
  sourceId: 'nas',
  sourceName: 'NAS',
  sourceKind: MediaSourceKind.nas,
  streamUrl: 'https://example.com/test.mp4',
);

void main() {
  test('HTTP recovery is bounded and does not loop EOF or nonseekable bodies',
      () {
    final options = resolveMpvHttpReconnectOptions(_target)!;
    expect(options, contains('reconnect_on_network_error=1'));
    expect(options, contains('reconnect_on_http_error=%15%408,425,429,5xx'));
    expect(options, contains('reconnect_delay_max=7'));
    expect(options, contains('reconnect_at_eof=0'));
    expect(options, contains('reconnect_streamed=0'));
    expect(options, isNot(contains('reconnect_max_retries')));
    expect(
        resolveMpvHttpReconnectOptions(
            _target.copyWith(streamUrl: 'http://example.com/test.m3u8')),
        options);
    for (final url in [
      'file:///test.mp4',
      'rtsp://example.com/live',
      'rtmp://example.com/live',
      'ftp://example.com/file',
      '/video.mp4'
    ]) {
      expect(resolveMpvHttpReconnectOptions(_target.copyWith(streamUrl: url)),
          isNull);
    }
  });

  test('HTTP classification matches Exo and takes precedence over generic text',
      () {
    for (final status in [408, 425, 429, 500, 503, 599]) {
      expect(
          classifyMpvOpenFailure(
              MpvOpenFailure('Failed to open', httpStatus: status)),
          MpvOpenFailureKind.transientNetwork);
    }
    for (final status in [400, 401, 403, 404, 405, 410, 416]) {
      final error = MpvOpenFailure('connection failed', httpStatus: status);
      expect(classifyMpvOpenFailure(error), MpvOpenFailureKind.permanent);
      expect(
          shouldRetryMpvOpenFailure(
              error: error,
              remote: true,
              attempt: 1,
              maxAttempts: 3,
              remaining: const Duration(seconds: 30),
              backoff: const Duration(milliseconds: 650)),
          isFalse);
    }
    expect(mpvHttpErrorStatus('http: HTTP error 403 Forbidden'), 403);
    expect(mpvHttpErrorStatus('HTTP/1.1 503 Service Unavailable'), 503);
    expect(mpvHttpErrorStatus('HTTP/2 429'), 429);
    expect(mpvHttpErrorStatus('status code=404'), 404);
    expect(mpvHttpErrorStatus('HTTP/1.1 200 OK'), isNull);
    expect(mpvHttpErrorStatus('Failed to open https://host/HTTP/403/movie.ts'),
        isNull);
  });

  test('prepared address refresh is limited to Exo expired-address statuses',
      () {
    for (final status in [401, 403, 404, 410]) {
      expect(
          isMpvPreparedAddressRefreshable(
              MpvOpenFailure('Failed to open', httpStatus: status)),
          isTrue);
      expect(isMpvPreparedAddressRefreshable('HTTP error $status'), isTrue);
    }
    for (final error in [
      'unsupported codec',
      'HTTP error 400',
      'HTTP error 503',
      'Failed to open stream'
    ]) {
      expect(isMpvPreparedAddressRefreshable(error), isFalse);
    }
  });

  test('HTTP evidence is scoped to resource, time and current load', () {
    var now = DateTime(2026, 9, 7);
    final evidence = MpvHttpFailureEvidence(clock: () => now);
    evidence.record('ffmpeg/demuxer',
        'HTTP error 403 https://host/segment.ts?token=secret');
    expect(evidence.statusFor('Failed to open https://host/other.ts'), isNull);
    expect(
        evidence
            .statusFor('Failed to open https://host/segment.ts?token=secret'),
        403);
    expect(evidence.statusFor('decoder initialization failed'), isNull);
    now = now.add(const Duration(seconds: 2));
    expect(evidence.statusFor('Failed to open stream'), isNull);
    evidence.record('ffmpeg', 'HTTP error 503');
    expect(evidence.statusFor('Failed to open stream'), 503);
    evidence.clear();
    expect(evidence.statusFor('Failed to open stream'), isNull);
    evidence.record('vd', 'HTTP error 403');
    expect(evidence.statusFor('Failed to open stream'), isNull);
  });

  test('buffer progress accumulates small increments but rejects oscillation',
      () {
    final progress = MpvBufferProgress();
    expect(
        progress.observe(
            buffer: const Duration(milliseconds: 400), percentage: 0),
        isFalse);
    expect(
        progress.observe(
            buffer: const Duration(milliseconds: 800), percentage: 0),
        isFalse);
    expect(
        progress.observe(
            buffer: const Duration(milliseconds: 1100), percentage: 0),
        isTrue);
    expect(progress.observe(buffer: Duration.zero, percentage: 50), isTrue);
    expect(progress.observe(buffer: Duration.zero, percentage: 49), isFalse);
    expect(progress.observe(buffer: Duration.zero, percentage: 50), isFalse);
    expect(progress.observe(buffer: Duration.zero, percentage: 50.5), isFalse);
    expect(progress.observe(buffer: Duration.zero, percentage: 51), isTrue);
    expect(progress.observe(buffer: Duration.zero, percentage: double.nan),
        isFalse);
    expect(progress.observe(buffer: Duration.zero, percentage: double.infinity),
        isFalse);
    progress.reset();
    expect(progress.observe(buffer: const Duration(seconds: 1), percentage: 0),
        isTrue);
  });

  testWidgets('generic stream error uses native permanent status immediately',
      (tester) async {
    final failures = <MpvOpenFailure>[];
    final gate = MpvStartupErrorGate(
        remote: true,
        readIdleActive: () async => false,
        onConfirmed: failures.add);
    addTearDown(gate.dispose);
    gate.report('Failed to open', httpStatus: 403);
    expect(failures.single.httpStatus, 403);
    expect(gate.confirmation, 'immediate');
  });

  testWidgets('transient errors plus no progress stop after the grace window',
      (tester) async {
    var now = DateTime(2026, 9, 7);
    final failures = <MpvOpenFailure>[];
    final gate = MpvStartupErrorGate(
        remote: true,
        clock: () => now,
        readIdleActive: () async => false,
        consumeProgress: () => false,
        onConfirmed: failures.add);
    addTearDown(gate.dispose);
    gate.report('Failed to open', httpStatus: 503);
    now = now.add(const Duration(seconds: 14));
    await tester.pump(const Duration(milliseconds: 250));
    expect(failures, isEmpty);
    gate.report('connection reset', httpStatus: 503);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(failures.single.httpStatus, 503);
    expect(gate.confirmation, 'load-stalled');
  });

  testWidgets(
      'real buffer progress keeps loading without extending scope deadline',
      (tester) async {
    var now = DateTime(2026, 9, 7);
    var advanced = false;
    final failures = <MpvOpenFailure>[];
    final gate = MpvStartupErrorGate(
        remote: true,
        clock: () => now,
        readIdleActive: () async => false,
        consumeProgress: () => advanced,
        onConfirmed: failures.add);
    addTearDown(gate.dispose);
    gate.report('connection reset');
    for (var i = 0; i < 4; i++) {
      now = now.add(const Duration(seconds: 10));
      advanced = true;
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(failures, isEmpty);
    final scope = MpvStartupScope()
      ..deadline = DateTime.now().subtract(const Duration(seconds: 1));
    expect(scope.checkActive, throwsA(isA<TimeoutException>()));
    gate.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(failures, isEmpty);
  });
}
