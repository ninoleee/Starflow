import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final starflowHttpClientProvider = Provider<http.Client>((ref) {
  final client = StarflowHttpClient(http.Client());
  ref.onDispose(client.close);
  return client;
});

class StarflowHttpClient extends http.BaseClient {
  StarflowHttpClient(this._inner);

  final http.Client _inner;

  static const String _proxyBase = String.fromEnvironment(
    'STARFLOW_WEB_PROXY_BASE',
  );

  static bool get _proxyEnabled => kIsWeb && _proxyBase.trim().isNotEmpty;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!_proxyEnabled) {
      return _inner.send(request);
    }

    final originalUrl = request.url;
    final proxied = http.StreamedRequest(
      request.method,
      Uri.parse(
        '${_proxyBase.trim()}/proxy?url=${Uri.encodeQueryComponent(originalUrl.toString())}',
      ),
    )
      ..contentLength = request.contentLength
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;

    proxied.headers.addAll(request.headers);

    final cookie = proxied.headers.remove('Cookie');
    if (cookie != null && cookie.trim().isNotEmpty) {
      proxied.headers['x-starflow-cookie'] = cookie;
    }

    final referer = proxied.headers.remove('Referer');
    if (referer != null && referer.trim().isNotEmpty) {
      proxied.headers['x-starflow-referer'] = referer;
    }

    proxied.headers['x-starflow-target-origin'] =
        '${originalUrl.scheme}://${originalUrl.authority}';

    unawaited(request.finalize().pipe(proxied.sink));
    return _inner.send(proxied);
  }

  @override
  void close() {
    _inner.close();
  }
}
