import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/network_failure.dart';

final starflowHttpClientProvider = Provider<http.Client>((ref) {
  final client = StarflowHttpClient(http.Client());
  ref.onDispose(client.close);
  return client;
});

class StarflowHttpClient extends http.BaseClient {
  StarflowHttpClient(
    this._inner, {
    this.requestTimeout = const Duration(seconds: 20),
  });

  final http.Client _inner;
  final Duration requestTimeout;

  static const String _proxyBase = String.fromEnvironment(
    'STARFLOW_WEB_PROXY_BASE',
  );

  static String get _effectiveProxyBase {
    return resolveStarflowWebProxyBase(
      isWeb: kIsWeb,
      configuredProxyBase: _proxyBase,
    );
  }

  static bool get _proxyEnabled => kIsWeb && _effectiveProxyBase.isNotEmpty;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final originalUrl = request.url;
    try {
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
  ) {
    final proxiedUrl = buildStarflowWebProxyUri(
      originalUrl.toString(),
      headers: request.headers,
    );
    final proxied = http.StreamedRequest(
      request.method,
      proxiedUrl ?? originalUrl,
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
    };
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
    'url': trimmedUrl,
  };
  if (normalizedHeaders.isNotEmpty) {
    queryParameters['headers'] = base64Url.encode(
      utf8.encode(jsonEncode(normalizedHeaders)),
    );
  }

  return Uri.parse('$trimmedProxyBase/proxy').replace(
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
