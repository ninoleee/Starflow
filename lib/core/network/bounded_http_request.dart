import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'http_origin_policy.dart';

/// A deadline covers headers and body. Aborting never closes a shared client.
Future<http.Response> sendBoundedRequest(
  http.Client client,
  String method,
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Future<void>? cancel,
  bool Function(Uri)? allowUri,
  required Duration timeout,
  required int maxBytes,
}) async {
  if (maxBytes < 0 || timeout <= Duration.zero) {
    throw ArgumentError(
        'A positive deadline and nonnegative byte limit are required');
  }
  final abort = Completer<void>();
  if (cancel != null) {
    unawaited(cancel.then((_) {
      if (!abort.isCompleted) abort.complete();
    }));
  }
  final template = http.Request(method, uri);
  if (headers != null) template.headers.addAll(headers);
  if (encoding != null) template.encoding = encoding;
  if (body is String) {
    template.body = body;
  } else if (body is List<int>) {
    template.bodyBytes = body;
  } else if (body is Map) {
    template.bodyFields = body.cast<String, String>();
  } else if (body != null) {
    throw ArgumentError.value(body, 'body');
  }
  final originBound = hasOriginCredentials(template);
  final bool Function(Uri)? permitted = originBound || allowUri != null
      ? (next) =>
          (!originBound || isSameHttpOrigin(uri, next)) &&
          (allowUri?.call(next) ?? true)
      : null;
  final watch = Stopwatch()..start();
  StreamSubscription<List<int>>? subscription;
  Future<T> wait<T>(Future<T> future) {
    final raced = Future.any<T>([
      future,
      abort.future.then<T>((_) => throw http.RequestAbortedException(uri)),
    ]);
    final left = timeout - watch.elapsed;
    return raced.timeout(left > Duration.zero ? left : Duration.zero);
  }

  try {
    var current = uri;
    var currentMethod = method;
    var currentBody = template.bodyBytes;
    late http.StreamedResponse response;
    for (var redirects = 0;; redirects++) {
      if (permitted != null && !permitted(current)) {
        throw http.ClientException(
            'HTTP origin or directory rejected', current);
      }
      if (abort.isCompleted) throw http.RequestAbortedException(uri);
      final request = http.AbortableRequest(currentMethod, current,
          abortTrigger: abort.future)
        ..headers.addAll(template.headers)
        ..bodyBytes = currentBody
        ..followRedirects = permitted == null;
      final pending = client.send(request);
      // A transport that ignores abort may still deliver headers later.
      unawaited(pending.then((lateResponse) {
        if (abort.isCompleted) {
          unawaited(lateResponse.stream.listen(null).cancel());
        }
      }, onError: (Object _, StackTrace __) {}));
      response = await wait(pending);
      if (permitted == null ||
          !const [301, 302, 303, 307, 308].contains(response.statusCode) ||
          response.headers['location'] == null) {
        break;
      }
      await response.stream.listen(null).cancel();
      if (redirects >= 5) {
        throw http.ClientException('Too many redirects', uri);
      }
      current = current.resolve(response.headers['location']!);
      if (response.statusCode == 303 && currentMethod != 'HEAD') {
        currentMethod = 'GET';
        currentBody = Uint8List(0);
      }
    }
    if (currentMethod != 'HEAD' && (response.contentLength ?? 0) > maxBytes) {
      await response.stream.listen(null).cancel();
      throw http.ClientException('Response exceeds byte limit', uri);
    }
    final bytes = BytesBuilder(copy: false);
    final completed = Completer<void>();
    subscription = response.stream.listen((chunk) {
      if (completed.isCompleted) return;
      if (bytes.length + chunk.length > maxBytes) {
        completed.completeError(
            http.ClientException('Response exceeds byte limit', uri));
      } else {
        bytes.add(chunk);
      }
    }, onError: (Object error, StackTrace stackTrace) {
      if (!completed.isCompleted) completed.completeError(error, stackTrace);
    }, onDone: () {
      if (!completed.isCompleted) completed.complete();
    });
    await wait(completed.future);
    return http.Response.bytes(bytes.takeBytes(), response.statusCode,
        headers: response.headers,
        request: response.request,
        reasonPhrase: response.reasonPhrase,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection);
  } finally {
    if (!abort.isCompleted) abort.complete();
    await subscription?.cancel();
  }
}
