import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final host = InternetAddress.loopbackIPv4;
  final port = _resolvePort(args, fallback: 8787);
  final server = await HttpServer.bind(host, port);

  stdout.writeln(
    'Starflow web dev proxy listening on http://${host.address}:$port',
  );

  await for (final request in server) {
    unawaited(_handleRequest(request));
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

Future<void> _handleRequest(HttpRequest request) async {
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

    if (request.uri.path != '/proxy') {
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
    if (targetUri == null || !targetUri.hasScheme) {
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
      await request.cast<List<int>>().pipe(outbound);

      final inbound = await outbound.close();
      request.response.statusCode = inbound.statusCode;

      inbound.headers.forEach((name, values) {
        if (_isHopByHopHeader(name)) {
          return;
        }
        for (final value in values) {
          request.response.headers.add(name, value);
        }
      });
      _addCorsHeaders(request.response);

      await inbound.pipe(request.response);
    } finally {
      client.close(force: true);
    }
  } catch (error, stackTrace) {
    stderr
      ..writeln('Proxy request failed: $error')
      ..writeln(stackTrace);
    try {
      _addCorsHeaders(request.response);
      request.response.statusCode = HttpStatus.badGateway;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': '$error'}));
    } catch (_) {
      // Ignore if the response has already started streaming.
    }
    await request.response.close();
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
        lowerName == 'x-starflow-cookie' ||
        lowerName == 'x-starflow-referer' ||
        lowerName == 'x-starflow-target-origin') {
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
    if (_isHopByHopHeader(lowerName) || lowerName == 'content-length') {
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
          'x-emby-token, x-emby-authorization, x-starflow-cookie, '
          'x-starflow-referer, x-starflow-target-origin',
    )
    ..set(
      'Access-Control-Allow-Methods',
      'GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, PROPFIND',
    )
    ..set('Access-Control-Expose-Headers', '*');
}
