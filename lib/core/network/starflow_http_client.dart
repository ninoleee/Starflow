import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/network_failure.dart';
import 'package:starflow/core/network/network_proxy_runtime.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/network/http_origin_policy.dart';

final starflowHttpClientProvider = Provider<http.Client>((ref) {
  final client = StarflowHttpClient(createStarflowTransportClient());
  ref.onDispose(client.close);
  return client;
});

class StarflowHttpClient extends http.BaseClient {
  StarflowHttpClient(
    this._inner, {
    this.requestTimeout = const Duration(seconds: 20),
    this.maxResponseBytes = 32 * 1024 * 1024,
  }) : _webProxyBase = _effectiveProxyBase;

  @visibleForTesting
  StarflowHttpClient.withWebProxyForTesting(
    this._inner, {
    required String proxyBase,
    this.requestTimeout = const Duration(seconds: 20),
    this.maxResponseBytes = 32 * 1024 * 1024,
  }) : _webProxyBase = proxyBase;

  final http.Client _inner;
  final String _webProxyBase;
  final Duration requestTimeout;
  final int maxResponseBytes;

  // Buffered convenience APIs are finite; send() remains a streaming API.
  Future<http.Response> _buffered(String method, Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      sendBoundedRequest(this, method, url,
          headers: headers,
          body: body,
          encoding: encoding,
          timeout: requestTimeout > Duration.zero
              ? requestTimeout
              : const Duration(seconds: 20),
          maxBytes: maxResponseBytes);

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _buffered('GET', url, headers: headers);
  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
      _buffered('HEAD', url, headers: headers);
  @override
  Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _buffered('POST', url, headers: headers, body: body, encoding: encoding);
  @override
  Future<http.Response> put(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _buffered('PUT', url, headers: headers, body: body, encoding: encoding);
  @override
  Future<http.Response> patch(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _buffered('PATCH', url, headers: headers, body: body, encoding: encoding);
  @override
  Future<http.Response> delete(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _buffered('DELETE', url,
          headers: headers, body: body, encoding: encoding);

  static const String _proxyBase = String.fromEnvironment(
    'STARFLOW_WEB_PROXY_BASE',
  );

  static String get _effectiveProxyBase {
    return resolveStarflowWebProxyBase(
      isWeb: kIsWeb,
      configuredProxyBase: _proxyBase,
    );
  }

  bool get _proxyEnabled => _webProxyBase.isNotEmpty;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final originalUrl = request.url;
    try {
      // Custom auth headers are not stripped by dart:io redirects. Buffered
      // requests follow validated hops themselves; raw streams fail closed.
      if (hasOriginCredentials(request)) request.followRedirects = false;
      final Future<http.StreamedResponse> responseFuture = _proxyEnabled
          ? _sendProxied(request, originalUrl)
          : _inner.send(request);
      final http.StreamedResponse response = requestTimeout > Duration.zero
          ? await responseFuture.timeout(requestTimeout)
          : await responseFuture;
      if (response.statusCode >= 400) {
        final failure = classifyNetworkFailure(
          http.ClientException('HTTP error response'),
          statusCode: response.statusCode,
        );
        appLogWarning(
          'network.http',
          'HTTP request returned an error response',
          fields: <String, Object?>{
            ..._requestLogFields(
              request,
              originalUrl,
              statusCode: response.statusCode,
            ),
            'failureKind': failure.kind.name,
            'transient': failure.isTransient,
          },
        );
      }
      return response;
    } catch (error, stackTrace) {
      final failure = classifyNetworkFailure(error);
      appLogError(
        'network.http',
        'HTTP request failed',
        fields: <String, Object?>{
          ..._requestLogFields(request, originalUrl),
          'failureKind': failure.kind.name,
          'transient': failure.isTransient,
          'timeoutMs': requestTimeout.inMilliseconds,
          'proxyEnabled': _usesProxyFor(originalUrl),
        },
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<http.StreamedResponse> _sendProxied(
    http.BaseRequest request,
    Uri originalUrl,
  ) async {
    final manualRedirects = !request.followRedirects;
    // A distinct endpoint fails closed with older proxies. A query flag on
    // /proxy would let an old proxy follow redirects before we could reject it.
    final proxiedUrl = _buildWebProxyUri(
      originalUrl.toString(),
      proxyBase: _webProxyBase,
      manualRedirects: manualRedirects,
    );
    final proxied = http.AbortableStreamedRequest(
      request.method,
      proxiedUrl,
      abortTrigger: request is http.Abortable ? request.abortTrigger : null,
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

    unawaited(request.finalize().pipe(proxied.sink).catchError((Object _) {
      // The transport reports request/abort errors to the caller.
    }));
    final response = await _inner.send(proxied);
    if (!manualRedirects) return response;
    final status = int.tryParse(response.headers['x-starflow-proxy-status'] ?? '');
    if (response.statusCode != 200 || status == null || status < 200 || status > 599) {
      await response.stream.listen(null).cancel();
      throw http.ClientException('Web proxy redirect contract unavailable', originalUrl);
    }
    final headers = Map<String, String>.of(response.headers);
    headers.remove('x-starflow-proxy-status');
    headers.remove('location');
    final location = headers.remove('x-starflow-proxy-location');
    if (location != null) headers['location'] = location;
    return http.StreamedResponse(response.stream, status,
        headers: headers,
        request: request,
        contentLength: response.contentLength,
        isRedirect: const [301, 302, 303, 307, 308].contains(status),
        persistentConnection: response.persistentConnection);
  }

  Map<String, Object?> _requestLogFields(
    http.BaseRequest request,
    Uri originalUrl, {
    int? statusCode,
  }) {
    return <String, Object?>{
      'method': request.method,
      'scheme': originalUrl.scheme,
      'host': originalUrl.host,
      'port': originalUrl.hasPort ? originalUrl.port : null,
      'path': originalUrl.path,
      if (statusCode != null) 'statusCode': statusCode,
      'proxyEnabled': _usesProxyFor(originalUrl),
    };
  }

  bool _usesProxyFor(Uri uri) {
    return _proxyEnabled ||
        (!kIsWeb && networkProxyRuntime.config.shouldProxy(uri));
  }

  @override
  void close() {
    _inner.close();
  }
}

Uri? buildStarflowWebProxyUri(
  String url, {
  Map<String, String> headers = const <String, String>{},
}) {
  if (!kIsWeb) {
    return null;
  }

  final trimmedUrl = url.trim();
  final trimmedProxyBase = StarflowHttpClient._effectiveProxyBase;
  if (trimmedUrl.isEmpty || trimmedProxyBase.isEmpty) {
    return null;
  }

  return _buildWebProxyUri(trimmedUrl,
      proxyBase: trimmedProxyBase, headers: headers);
}

Uri _buildWebProxyUri(
  String url, {
  required String proxyBase,
  Map<String, String> headers = const {},
  bool manualRedirects = false,
}) {
  final normalizedHeaders = <String, String>{};
  for (final entry in headers.entries) {
    final key = entry.key.trim();
    final value = entry.value.trim();
    if (key.isEmpty || value.isEmpty) {
      continue;
    }
    normalizedHeaders[key] = value;
  }

  final queryParameters = <String, String>{
    'url': url,
  };
  if (normalizedHeaders.isNotEmpty) {
    queryParameters['headers'] = base64Url.encode(
      utf8.encode(jsonEncode(normalizedHeaders)),
    );
  }

  return Uri.parse('$proxyBase/${manualRedirects ? 'proxy-v1' : 'proxy'}').replace(
    queryParameters: queryParameters,
  );
}

String buildStarflowWebProxyUrl(
  String url, {
  Map<String, String> headers = const <String, String>{},
}) {
  return buildStarflowWebProxyUri(url, headers: headers)?.toString() ??
      url.trim();
}

@visibleForTesting
String resolveStarflowWebProxyBase({
  required bool isWeb,
  required String configuredProxyBase,
}) {
  if (!isWeb) {
    return '';
  }
  return configuredProxyBase.trim();
}
