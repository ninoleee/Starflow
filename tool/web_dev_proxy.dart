import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:starflow/core/network/http_origin_policy.dart';

Future<void> main(List<String> args) async {
  final host = InternetAddress.loopbackIPv4;
  final port = _resolvePort(args, fallback: 8787);
  final server = await HttpServer.bind(host, port);

  stdout.writeln(
    'Starflow web dev proxy listening on http://${host.address}:$port',
  );

  await for (final request in server) {
    unawaited(handleWebDevProxyRequest(request));
  }
}

int _resolvePort(List<String> args, {required int fallback}) {
  for (final arg in args) {
    if (arg.startsWith('--port=')) {
      return int.tryParse(arg.substring('--port='.length)) ?? fallback;
    }
  }
  final fromEnv = Platform.environment['STARFLOW_WEB_PROXY_PORT'];
  return int.tryParse(fromEnv ?? '') ?? fallback;
}

Future<void> handleWebDevProxyRequest(HttpRequest request) async {
  try {
    _addCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.uri.path == '/health') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok'}));
      await request.response.close();
      return;
    }

    final manualRedirects = request.uri.path == '/proxy-v1';
    if (request.uri.path != '/proxy' && !manualRedirects) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not Found');
      await request.response.close();
      return;
    }

    final targetRaw = request.uri.queryParameters['url']?.trim() ?? '';
    if (targetRaw.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Missing url query parameter');
      await request.response.close();
      return;
    }

    final targetUri = Uri.tryParse(targetRaw);
    if (targetUri == null || !isHttpUri(targetUri)) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Invalid target url');
      await request.response.close();
      return;
    }

    final headerOverrides = _readHeaderOverrides(request);
    final client = HttpClient()..autoUncompress = false;
    try {
      final outbound = await client.openUrl(request.method, targetUri);
      _copyRequestHeaders(
        request,
        outbound,
        headerOverrides: headerOverrides,
      );
      final credentialProbe = http.Request(request.method, targetUri);
      outbound.headers.forEach((name, values) {
        credentialProbe.headers[name] = values.join(',');
      });
      outbound.followRedirects =
          !manualRedirects && !hasOriginCredentials(credentialProbe);
      await request.cast<List<int>>().pipe(outbound);

      final inbound = await outbound.close();
      // Browsers must never see an actual 3xx for the manual contract. They
      // would follow it outside this proxy before Dart can validate the origin.
      request.response.statusCode = manualRedirects ? 200 : inbound.statusCode;
      if (!manualRedirects && inbound.isRedirect && !outbound.followRedirects) {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('Authenticated redirects require /proxy-v1');
        await request.response.close();
        return;
      }

      inbound.headers.forEach((name, values) {
        if (_isHopByHopHeader(name) ||
            name.startsWith('x-starflow-') ||
            (manualRedirects && name == 'location')) {
          return;
        }
        for (final value in values) {
          request.response.headers.add(name, value);
        }
      });
      if (manualRedirects) {
        request.response.headers.set('x-starflow-proxy-status', '${inbound.statusCode}');
        final location = inbound.headers.value('location');
        if (location != null) {
          request.response.headers.set('x-starflow-proxy-location', location);
        }
      }
      _addCorsHeaders(request.response);

      await inbound.pipe(request.response);
    } finally {
      client.close(force: true);
    }
  } catch (_) {
    stderr.writeln('Proxy request failed');
    try {
      _addCorsHeaders(request.response);
      request.response.statusCode = HttpStatus.badGateway;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'Proxy request failed'}));
    } catch (_) {
      // Ignore if the response has already started streaming.
    }
    try {
      await request.response.close();
    } catch (_) {
      // The browser may have aborted the request.
    }
  }
}

Map<String, String> _readHeaderOverrides(HttpRequest request) {
  final encoded = request.uri.queryParameters['headers']?.trim() ?? '';
  if (encoded.isEmpty) {
    return const <String, String>{};
  }

  try {
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    final json = jsonDecode(decoded);
    if (json is! Map) {
      return const <String, String>{};
    }
    return json.map(
      (key, value) => MapEntry('$key'.trim(), '$value'.trim()),
    )..removeWhere((key, value) => key.isEmpty || value.isEmpty);
  } catch (_) {
    return const <String, String>{};
  }
}

void _copyRequestHeaders(
  HttpRequest source,
  HttpClientRequest target, {
  Map<String, String> headerOverrides = const <String, String>{},
}) {
  source.headers.forEach((name, values) {
    final lowerName = name.toLowerCase();
    if (_isHopByHopHeader(lowerName) ||
        lowerName == 'cookie' ||
        lowerName == 'referer' ||
        lowerName == 'origin' ||
        lowerName.startsWith('x-starflow-')) {
      return;
    }
    for (final value in values) {
      target.headers.add(name, value);
    }
  });

  final cookie = source.headers.value('x-starflow-cookie');
  if (cookie != null && cookie.trim().isNotEmpty) {
    target.headers.set(HttpHeaders.cookieHeader, cookie);
  }

  final referer = source.headers.value('x-starflow-referer');
  if (referer != null && referer.trim().isNotEmpty) {
    target.headers.set(HttpHeaders.refererHeader, referer);
  }

  final targetOrigin = source.headers.value('x-starflow-target-origin');
  if (targetOrigin != null && targetOrigin.trim().isNotEmpty) {
    target.headers.set('origin', targetOrigin);
  }

  for (final entry in headerOverrides.entries) {
    final lowerName = entry.key.toLowerCase();
    if (_isHopByHopHeader(lowerName) || lowerName.startsWith('x-starflow-')) {
      continue;
    }
    target.headers.set(entry.key, entry.value);
  }
}

bool _isHopByHopHeader(String name) {
  switch (name.toLowerCase()) {
    case 'connection':
    case 'content-length':
    case 'host':
    case 'keep-alive':
    case 'proxy-authenticate':
    case 'proxy-authorization':
    case 'te':
    case 'trailer':
    case 'transfer-encoding':
    case 'upgrade':
      return true;
    default:
      return false;
  }
}

void _addCorsHeaders(HttpResponse response) {
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set(
      'Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, Authorization, Depth, '
          'Cache-Control, If-Match, If-None-Match, Authx, Trim-MC-token, Range, '
          'x-emby-token, x-emby-authorization, x-starflow-cookie, '
          'x-starflow-referer, x-starflow-target-origin',
    )
    ..set(
      'Access-Control-Allow-Methods',
      'GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, PROPFIND, MKCOL',
    )
    ..set('Access-Control-Expose-Headers', '*');
}
