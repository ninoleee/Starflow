import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A deadline covers headers and body. Aborting never closes a shared client.
Future<http.Response> sendBoundedRequest(
  http.Client client,
  String method,
  Uri uri, {
  Map<String, String>? headers,
  String? body,
  Future<void>? cancel,
  required Duration timeout,
  required int maxBytes,
}) async {
  final abort = Completer<void>();
  if (cancel != null) {
    unawaited(cancel.then((_) {
      if (!abort.isCompleted) abort.complete();
    }));
  }
  final request =
      http.AbortableRequest(method, uri, abortTrigger: abort.future);
  if (headers != null) request.headers.addAll(headers);
  if (body != null) request.body = body;
  final watch = Stopwatch()..start();
  Duration remaining() {
    final value = timeout - watch.elapsed;
    if (value <= Duration.zero) throw TimeoutException('HTTP body deadline');
    return value;
  }

  StreamIterator<List<int>>? iterator;
  try {
    final response = await client.send(request).timeout(remaining());
    if ((response.contentLength ?? 0) > maxBytes) {
      throw http.ClientException('Response exceeds byte limit', uri);
    }
    iterator = StreamIterator(response.stream);
    final bytes = BytesBuilder(copy: false);
    while (await iterator.moveNext().timeout(remaining())) {
      if (bytes.length + iterator.current.length > maxBytes) {
        throw http.ClientException('Response exceeds byte limit', uri);
      }
      bytes.add(iterator.current);
    }
    return http.Response.bytes(bytes.takeBytes(), response.statusCode,
        headers: response.headers,
        request: response.request,
        reasonPhrase: response.reasonPhrase,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection);
  } finally {
    if (!abort.isCompleted) abort.complete();
    await iterator?.cancel();
  }
}
