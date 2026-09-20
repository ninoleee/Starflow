import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/http_origin_policy.dart';
import 'package:starflow/core/network/network_failure.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';

import '../application/live_mpv_options.dart';
import '../domain/live_models.dart';
import 'live_playlist_parser.dart';

enum LiveProbeStatus {
  responded,
  timeout,
  httpError,
  empty,
  nonMedia,
  invalidUrl,
  redirectBlocked,
  networkError,
  cancelled,
}

class LiveProbeResult {
  const LiveProbeResult(this.status,
      {required this.checkedAt, this.latency, this.httpStatus});

  final LiveProbeStatus status;
  final DateTime checkedAt;
  final Duration? latency;
  final int? httpStatus;

  String get label => switch (status) {
        LiveProbeStatus.responded => '${latency!.inMilliseconds} ms',
        LiveProbeStatus.timeout => '超时',
        LiveProbeStatus.httpError => 'HTTP $httpStatus',
        LiveProbeStatus.empty => '空响应',
        LiveProbeStatus.nonMedia => '非媒体',
        LiveProbeStatus.invalidUrl => '无效地址',
        LiveProbeStatus.redirectBlocked => '跳转受限',
        LiveProbeStatus.networkError => '连接失败',
        LiveProbeStatus.cancelled => '未测',
      };
}

final liveChannelProbeProvider = Provider((ref) => LiveChannelProbe());

class LiveChannelProbe {
  LiveChannelProbe({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 6),
    this.cleanupWarningAfter = const Duration(seconds: 1),
    void Function(String, Map<String, Object?>)? diagnostics,
  })  : _clientFactory = clientFactory ?? createStarflowTransportClient,
        _diagnostics = diagnostics ?? _logCleanup;

  final http.Client Function() _clientFactory;
  final Duration timeout;
  final Duration cleanupWarningAfter;
  final void Function(String, Map<String, Object?>) _diagnostics;

  static void _logCleanup(String event, Map<String, Object?> fields) {
    if (event == 'complete') {
      appLogInfo('live.probe', 'Probe transport cleanup completed',
          fields: fields);
    } else {
      appLogWarning('live.probe', 'Probe transport cleanup $event',
          fields: fields);
    }
  }

  Future<LiveProbeResult> probe(LiveLine line,
      {required Future<void> cancel}) async {
    LiveProbeResult result(LiveProbeStatus status,
            {Duration? latency, int? httpStatus}) =>
        LiveProbeResult(status,
            checkedAt: DateTime.now(),
            latency: latency,
            httpStatus: httpStatus);
    if (!isLiveHttpUrl(line.url)) return result(LiveProbeStatus.invalidUrl);
    final abort = Completer<void>();
    var cancelled = false;
    unawaited(cancel.then((_) {
      cancelled = true;
      if (!abort.isCompleted) abort.complete();
    }));
    final watch = Stopwatch()..start();
    final client = _clientFactory();
    StreamIterator<List<int>>? body;

    Future<T> wait<T>(Future<T> future) => Future.any<T>([
          future,
          abort.future.then<T>((_) => throw const _ProbeCancelled()),
        ]).timeout(timeout - watch.elapsed > Duration.zero
            ? timeout - watch.elapsed
            : Duration.zero);

    try {
      var uri = Uri.parse(line.url);
      var headers = liveMediaHeaders(line.headers);
      // A Range is only a hint. Stop reading at the first data chunk even if ignored.
      headers.removeWhere((key, _) => key.toLowerCase() == 'range');
      headers['Range'] = 'bytes=0-1023';
      for (var redirects = 0;; redirects++) {
        if (cancelled) return result(LiveProbeStatus.cancelled);
        final request =
            http.AbortableRequest('GET', uri, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers.addAll(headers);
        final pending = client.send(request);
        unawaited(pending.then((response) {
          if (abort.isCompleted) {
            unawaited(response.stream.listen(null).cancel());
          }
        }, onError: (Object _, StackTrace __) {}));
        final response = await wait(pending);
        body = StreamIterator(response.stream);
        if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers['location'];
          final next = location == null ? null : uri.resolve(location);
          if (redirects >= 3 ||
              next == null ||
              !isLiveHttpUrl(next.toString()) ||
              (uri.scheme == 'https' && next.scheme != 'https')) {
            return result(LiveProbeStatus.redirectBlocked);
          }
          await wait(body.cancel());
          body = null;
          if (!isSameHttpOrigin(uri, next)) {
            // Never forward media credentials or custom headers to another origin.
            headers = {
              for (final entry in headers.entries)
                if (entry.key.toLowerCase() == 'user-agent' ||
                    entry.key.toLowerCase() == 'range')
                  entry.key: entry.value,
            };
          }
          uri = next;
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return result(LiveProbeStatus.httpError,
              httpStatus: response.statusCode);
        }
        final contentType = response.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase();
        if (const ['text/html', 'application/xhtml+xml', 'application/json']
            .contains(contentType)) {
          return result(LiveProbeStatus.nonMedia);
        }
        while (await wait(body.moveNext())) {
          if (body.current.isNotEmpty) {
            return result(LiveProbeStatus.responded, latency: watch.elapsed);
          }
        }
        return result(LiveProbeStatus.empty);
      }
    } catch (error) {
      if (cancelled || error is _ProbeCancelled) {
        return result(LiveProbeStatus.cancelled);
      }
      return result(
          classifyNetworkFailure(error).kind == NetworkFailureKind.timeout
              ? LiveProbeStatus.timeout
              : LiveProbeStatus.networkError);
    } finally {
      if (!abort.isCompleted) abort.complete();
      final cleanupWatch = Stopwatch()..start();
      var failed = false;
      final warning = Timer(cleanupWarningAfter, () {
        _diagnostics('slow', {
          'elapsedMs': cleanupWatch.elapsedMilliseconds,
          'cancelled': cancelled,
          'waitingForCleanup': true
        });
      });
      try {
        // Close even while stream cancellation is pending. Never release a
        // concurrency slot merely because a cleanup timeout has elapsed.
        Future<void>? cleanup;
        try {
          cleanup = body?.cancel();
        } finally {
          try {
            client.close();
          } finally {
            await cleanup;
          }
        }
      } catch (_) {
        failed = true;
        _diagnostics('failed', {
          'elapsedMs': cleanupWatch.elapsedMilliseconds,
          'cancelled': cancelled
        });
      } finally {
        warning.cancel();
        if (!failed) {
          _diagnostics('complete', {
            'elapsedMs': cleanupWatch.elapsedMilliseconds,
            'cancelled': cancelled,
          });
        }
        cleanupWatch.stop();
        watch.stop();
      }
    }
  }
}

class _ProbeCancelled implements Exception {
  const _ProbeCancelled();
}
