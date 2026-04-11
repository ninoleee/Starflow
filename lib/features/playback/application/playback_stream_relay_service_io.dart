import 'dart:async';
import 'dart:io';

import 'package:starflow/core/utils/playback_trace.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const String _originHeaderName = 'origin';

PlaybackStreamRelayService createPlaybackStreamRelayService() {
  return _IoPlaybackStreamRelayService();
}

class _IoPlaybackStreamRelayService implements PlaybackStreamRelayService {
  _IoPlaybackStreamRelayService()
      : _client = HttpClient()
          ..autoUncompress = false
          ..connectionTimeout = const Duration(seconds: 15)
          ..idleTimeout = const Duration(minutes: 2)
          ..maxConnectionsPerHost = 12;

  final HttpClient _client;
  final Map<String, _RelaySession> _sessions = <String, _RelaySession>{};

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _serverSubscription;
  int _nextSessionId = 0;
  bool _closed = false;

  @override
  Future<PlaybackTarget> prepareTarget(PlaybackTarget target) async {
    if (_closed || !_shouldRelay(target)) {
      return target;
    }
    final upstreamUri = Uri.tryParse(target.streamUrl.trim());
    if (upstreamUri == null || !upstreamUri.hasScheme) {
      return target;
    }
    _traceQuarkRelay(
      'quark.relay.prepare.begin',
      target: target,
      fields: {
        'upstreamUrl': upstreamUri.toString(),
        'headers': target.headers.keys.join('|'),
      },
    );

    await _ensureServer();
    await clear(reason: 'replace-playback-relay-session');

    final sessionId = _createSessionId();
    final normalizedHeaders = _normalizedRelayHeaders(target.headers);
    final session = _RelaySession(
      originUri: upstreamUri,
      currentUri: upstreamUri,
      headers: normalizedHeaders,
      cookies:
          _parseCookieHeader(normalizedHeaders[HttpHeaders.cookieHeader] ?? ''),
      fallbackContentType: _fallbackContentTypeForTarget(target),
    );
    _sessions[sessionId] = session;

    await _warmUpSession(session);

    final relayUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: _server!.port,
      pathSegments: [
        kPlaybackRelayPathSegment,
        sessionId,
        _safeRelayPathSegment(target),
      ],
    );

    final relayTarget = target.copyWith(
      streamUrl: relayUri.toString(),
      actualAddress: upstreamUri.toString(),
      headers: const <String, String>{},
    );
    _traceQuarkRelay(
      'quark.relay.prepare.ready',
      target: relayTarget,
      fields: {
        'relayUrl': relayUri.toString(),
        'fallbackContentType': session.fallbackContentType,
      },
    );
    return relayTarget;
  }

  @override
  Future<void> clear({String reason = ''}) async {
    _sessions.clear();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _sessions.clear();
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }

  Future<void> _ensureServer() async {
    if (_server != null) {
      return;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _serverSubscription = server.listen(
      (request) {
        unawaited(_handleRequest(request));
      },
      cancelOnError: false,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.bufferOutput = false;
    try {
      final segments = request.uri.pathSegments
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (segments.length < 2 || segments.first != kPlaybackRelayPathSegment) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      final session = _sessions[segments[1]];
      if (session == null) {
        request.response.statusCode = HttpStatus.gone;
        await request.response.close();
        return;
      }

      final upstream = await _openUpstreamResponse(
        session,
        method: request.method,
        forwardedHeaders: _collectForwardedHeaders(request.headers),
      );
      request.response.statusCode = upstream.statusCode;
      _copyUpstreamHeaders(upstream.headers, request.response.headers);
      _applyFallbackResponseHeaders(session, request.response.headers);
      _traceQuarkRelay(
        'quark.relay.request.ready',
        fields: {
          'method': request.method,
          'path': request.uri.path,
          'statusCode': upstream.statusCode,
          'contentType':
              request.response.headers.value(HttpHeaders.contentTypeHeader) ??
                  '',
          'upstreamUrl': session.currentUri.toString(),
        },
      );

      if (request.method == 'HEAD') {
        await upstream.drain<void>();
        await request.response.close();
        return;
      }

      await upstream.pipe(request.response);
    } catch (error, stackTrace) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('Playback relay failed');
      } catch (_) {}
      _traceQuarkRelay(
        'quark.relay.request.failed',
        fields: {
          'method': request.method,
          'path': request.uri.path,
          'upstreamUrl':
              _sessionUrlForTrace(segments: request.uri.pathSegments),
        },
        error: error,
        stackTrace: stackTrace,
      );
      await request.response.close();
    }
  }

  Future<void> _warmUpSession(_RelaySession session) async {
    try {
      final response = await _openUpstreamResponse(
        session,
        method: 'GET',
        forwardedHeaders: const <String, List<String>>{
          HttpHeaders.rangeHeader: <String>['bytes=0-0'],
          HttpHeaders.acceptHeader: <String>['*/*'],
        },
      );
      _traceQuarkRelay(
        'quark.relay.warmup.ready',
        fields: {
          'statusCode': response.statusCode,
          'upstreamUrl': session.currentUri.toString(),
          'contentType':
              response.headers.value(HttpHeaders.contentTypeHeader) ?? '',
        },
      );
      await response.drain<void>();
    } catch (error, stackTrace) {
      _traceQuarkRelay(
        'quark.relay.warmup.failed',
        fields: {'upstreamUrl': session.currentUri.toString()},
        error: error,
        stackTrace: stackTrace,
      );
      // Warm-up is best-effort. Playback must still proceed even if the
      // upstream refuses the initial probe or DNS is temporarily unavailable.
    }
  }

  Future<HttpClientResponse> _openUpstreamResponse(
    _RelaySession session, {
    required String method,
    required Map<String, List<String>> forwardedHeaders,
  }) async {
    var candidateUri = session.currentUri;
    var retriedOriginal = false;

    while (true) {
      final response = await _issueUpstreamRequest(
        session,
        uri: candidateUri,
        method: method,
        forwardedHeaders: forwardedHeaders,
      );
      _captureResponseCookies(session, response);

      if (_isRedirectStatus(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location != null && location.trim().isNotEmpty) {
          final redirectedUri = candidateUri.resolve(location.trim());
          await response.drain<void>();
          candidateUri = redirectedUri;
          session.currentUri = redirectedUri;
          continue;
        }
      }

      if (!retriedOriginal &&
          candidateUri != session.originUri &&
          (response.statusCode == HttpStatus.unauthorized ||
              response.statusCode == HttpStatus.forbidden)) {
        retriedOriginal = true;
        await response.drain<void>();
        candidateUri = session.originUri;
        session.currentUri = session.originUri;
        continue;
      }

      session.currentUri = candidateUri;
      return response;
    }
  }

  Future<HttpClientResponse> _issueUpstreamRequest(
    _RelaySession session, {
    required Uri uri,
    required String method,
    required Map<String, List<String>> forwardedHeaders,
  }) async {
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.persistentConnection = true;

    for (final entry in forwardedHeaders.entries) {
      for (final value in entry.value) {
        request.headers.add(entry.key, value);
      }
    }

    for (final entry in session.headers.entries) {
      if (entry.key.toLowerCase() == HttpHeaders.cookieHeader) {
        continue;
      }
      request.headers.set(entry.key, entry.value);
    }

    final referer = session.headers[HttpHeaders.refererHeader];
    final hasOriginHeader = session.headers.keys.any(
      (item) => item.toLowerCase() == _originHeaderName,
    );
    if (!hasOriginHeader && referer != null && referer.trim().isNotEmpty) {
      final origin = _originFromReferer(referer);
      if (origin.isNotEmpty) {
        request.headers.set(_originHeaderName, origin);
      }
    }

    for (final entry in session.cookies.entries) {
      request.cookies.add(Cookie(entry.key, entry.value));
    }

    return request.close();
  }

  Map<String, List<String>> _collectForwardedHeaders(HttpHeaders headers) {
    final forwarded = <String, List<String>>{};
    headers.forEach((name, values) {
      final lowerName = name.toLowerCase();
      if (!_shouldForwardHeader(lowerName)) {
        return;
      }
      final sanitizedValues = values
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (sanitizedValues.isEmpty) {
        return;
      }
      forwarded[name] = sanitizedValues;
    });
    return forwarded;
  }

  bool _shouldForwardHeader(String headerName) {
    return switch (headerName) {
      HttpHeaders.rangeHeader ||
      HttpHeaders.acceptHeader ||
      HttpHeaders.acceptEncodingHeader ||
      HttpHeaders.cacheControlHeader ||
      HttpHeaders.ifModifiedSinceHeader ||
      HttpHeaders.ifRangeHeader ||
      HttpHeaders.pragmaHeader =>
        true,
      _ => false,
    };
  }

  void _copyUpstreamHeaders(HttpHeaders source, HttpHeaders target) {
    source.forEach((name, values) {
      final lowerName = name.toLowerCase();
      if (_isHopByHopHeader(lowerName) ||
          lowerName == HttpHeaders.setCookieHeader) {
        return;
      }
      for (final value in values) {
        target.add(name, value);
      }
    });
  }

  void _captureResponseCookies(
      _RelaySession session, HttpClientResponse response) {
    for (final cookie in response.cookies) {
      final name = cookie.name.trim();
      if (name.isEmpty) {
        continue;
      }
      session.cookies[name] = cookie.value;
    }

    final setCookieHeaders =
        response.headers[HttpHeaders.setCookieHeader] ?? const <String>[];
    for (final header in setCookieHeaders) {
      final cookieMap = _parseCookieHeader(header.split(';').first);
      session.cookies.addAll(cookieMap);
    }
  }

  bool _shouldRelay(PlaybackTarget target) {
    if (target.sourceKind != MediaSourceKind.quark) {
      return false;
    }
    final uri = Uri.tryParse(target.streamUrl.trim());
    if (uri == null) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && target.headers.isNotEmpty;
  }

  Map<String, String> _normalizedRelayHeaders(Map<String, String> headers) {
    final normalized = <String, String>{};
    for (final entry in headers.entries) {
      final key = entry.key.trim().toLowerCase();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      normalized[key] = value;
    }
    return normalized;
  }

  Map<String, String> _parseCookieHeader(String raw) {
    final cookies = <String, String>{};
    for (final fragment in raw.split(';')) {
      final separatorIndex = fragment.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }
      final name = fragment.substring(0, separatorIndex).trim();
      final value = fragment.substring(separatorIndex + 1).trim();
      if (name.isEmpty || value.isEmpty) {
        continue;
      }
      cookies[name] = value;
    }
    return cookies;
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  bool _isHopByHopHeader(String name) {
    return switch (name.toLowerCase()) {
      'connection' ||
      'keep-alive' ||
      'proxy-authenticate' ||
      'proxy-authorization' ||
      'te' ||
      'trailer' ||
      'transfer-encoding' ||
      'upgrade' =>
        true,
      _ => false,
    };
  }

  String _originFromReferer(String referer) {
    final uri = Uri.tryParse(referer.trim());
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return '';
    }
    return '${uri.scheme}://${uri.authority}';
  }

  String _createSessionId() {
    _nextSessionId += 1;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_nextSessionId.toRadixString(36)}';
  }

  String _safeRelayPathSegment(PlaybackTarget target) {
    final sanitizedBaseName = target.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fileExtension = _preferredRelayFileExtension(target);
    final baseName = sanitizedBaseName.isEmpty ? 'stream' : sanitizedBaseName;
    if (fileExtension.isEmpty ||
        baseName.toLowerCase().endsWith('.$fileExtension')) {
      return baseName;
    }
    return '$baseName.$fileExtension';
  }

  void _applyFallbackResponseHeaders(
    _RelaySession session,
    HttpHeaders headers,
  ) {
    if (session.fallbackContentType.isEmpty) {
      return;
    }
    final existingContentType =
        headers.value(HttpHeaders.contentTypeHeader)?.trim().toLowerCase() ??
            '';
    if (existingContentType.isEmpty ||
        existingContentType == 'application/octet-stream') {
      headers.set(HttpHeaders.contentTypeHeader, session.fallbackContentType);
    }
  }

  String _fallbackContentTypeForTarget(PlaybackTarget target) {
    final fileExtension = _preferredRelayFileExtension(target);
    return switch (fileExtension) {
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'mkv' => 'video/x-matroska',
      'avi' => 'video/x-msvideo',
      'ts' || 'm2ts' => 'video/mp2t',
      'webm' => 'video/webm',
      'flv' => 'video/x-flv',
      'wmv' => 'video/x-ms-wmv',
      'mpg' || 'mpeg' => 'video/mpeg',
      _ => '',
    };
  }

  String _preferredRelayFileExtension(PlaybackTarget target) {
    for (final candidate in [
      target.container,
      _fileExtensionFromUrl(target.actualAddress),
      _fileExtensionFromUrl(target.streamUrl),
    ]) {
      final normalized = candidate.trim().toLowerCase();
      if (_isUsableRelayFileExtension(normalized)) {
        return normalized;
      }
    }
    return '';
  }

  String _fileExtensionFromUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    final path = (uri?.path ?? trimmed).trim();
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= path.length - 1) {
      return '';
    }
    return path.substring(dotIndex + 1).trim().toLowerCase();
  }

  bool _isUsableRelayFileExtension(String value) {
    if (value.isEmpty || value.length > 8) {
      return false;
    }
    return RegExp(r'^[a-z0-9]+$').hasMatch(value);
  }

  String _sessionUrlForTrace({required List<String> segments}) {
    if (segments.length < 2) {
      return '';
    }
    final session = _sessions[segments[1].trim()];
    return session?.currentUri.toString() ?? '';
  }
}

class _RelaySession {
  _RelaySession({
    required this.originUri,
    required this.currentUri,
    required this.headers,
    required this.cookies,
    required this.fallbackContentType,
  });

  final Uri originUri;
  Uri currentUri;
  final Map<String, String> headers;
  final Map<String, String> cookies;
  final String fallbackContentType;
}

void _traceQuarkRelay(
  String stage, {
  PlaybackTarget? target,
  Map<String, Object?> fields = const <String, Object?>{},
  Object? error,
  StackTrace? stackTrace,
}) {
  playbackTrace(
    stage,
    fields: <String, Object?>{
      if (target != null)
        'title': target.title.trim().isEmpty ? 'Starflow' : target.title.trim(),
      if (target != null) 'sourceKind': target.sourceKind.name,
      if (target != null) 'container': target.container,
      ...fields,
    },
    error: error,
    stackTrace: stackTrace,
  );
}
