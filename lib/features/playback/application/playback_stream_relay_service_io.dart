import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:starflow/core/network/http_origin_policy.dart';
import 'package:starflow/core/network/network_proxy_runtime.dart';
import 'package:starflow/features/playback/application/playback_hls_rewriter.dart';
import 'package:starflow/features/playback/application/playback_relay_disk_cache.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_contract.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const _maxRedirects = 5;
const _sampleSize = 512;
const _requestTimeout = Duration(seconds: 15);
const _maxManifestBytes = 1024 * 1024;
const _maxResources = 20000;
const _resourceGrace = Duration(minutes: 2);
final _diskCaches = <PlaybackRelayDiskCache>{};
PlaybackRelayDiskCache? _sharedDiskCache;
final _cacheOwners = <PlaybackRelayDiskCache, int>{};

PlaybackRelayDiskCache? _acquireDiskCache(int capacityMiB) {
  if (!const [256, 512, 1024].contains(capacityMiB)) return null;
  final bytes = capacityMiB * 1024 * 1024;
  final previous = _sharedDiskCache;
  if (previous == null ||
      previous.disabled ||
      previous.capacityBytes != bytes) {
    if (previous != null) unawaited(previous.clear());
    _sharedDiskCache = PlaybackRelayDiskCache(capacityBytes: bytes);
  }
  return _sharedDiskCache;
}

Future<void> clearPlaybackDiskCache() async {
  await Future.wait(_diskCaches.toList().map((cache) => cache.clear()));
  await PlaybackRelayDiskCache.clearInactiveFiles();
}

PlaybackStreamRelayService createPlaybackStreamRelayService({
  Duration requestTimeout = _requestTimeout,
  DateTime Function()? clock,
  int diskCacheMiB = 0,
  PlaybackRelayDiskCache? diskCache,
}) =>
    _IoPlaybackStreamRelayService(requestTimeout, clock ?? DateTime.now,
        diskCache ?? _acquireDiskCache(diskCacheMiB));

class _IoPlaybackStreamRelayService implements PlaybackStreamRelayService {
  _IoPlaybackStreamRelayService(
      this.requestTimeout, this.clock, this.diskCache) {
    if (diskCache != null) {
      _diskCaches.add(diskCache!);
      _cacheOwners.update(diskCache!, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  final PlaybackRelayDiskCache? diskCache;
  final Duration requestTimeout;
  final DateTime Function() clock;
  final _sessions = <String, _RelaySession>{};
  final _preparing = <_RelaySession>{};
  final _random = Random.secure();
  HttpServer? _server;
  Future<void>? _starting;
  bool _closed = false;
  bool _cacheReleased = false;

  @override
  Future<PlaybackTarget> prepareTarget(PlaybackTarget target) async {
    final needsSecurityRelay = requiresPlaybackStreamRelay(target);
    final candidate = Uri.tryParse(target.streamUrl.trim());
    if (candidate != null &&
        const {'file', 'content'}.contains(candidate.scheme)) {
      return target;
    }
    if (!needsSecurityRelay &&
        (diskCache == null || candidate == null || !isHttpUri(candidate))) {
      return target;
    }
    if (_closed) throw const PlaybackRelayException();
    final uri = Uri.tryParse(target.streamUrl.trim());
    if (uri == null || !isHttpUri(uri)) throw const PlaybackRelayException();
    if (target.isIsoLike ||
        (_manifestPath(uri) && !_hlsPath(uri)) ||
        const {'m3u', 'mpd', 'dash'}.contains(target.container.toLowerCase())) {
      throw unsupportedRelayMedia;
    }
    final session = _RelaySession(uri, _normalizeHeaders(target.headers));
    _preparing.add(session);
    try {
      final id = base64Url
          .encode(List.generate(32, (_) => _random.nextInt(256)))
          .replaceAll('=', '');
      session.path = '/$kPlaybackRelayPathSegment/$id/media';
      await (_starting ??= _start());
      final isHls = _hlsPath(uri) ||
          const {'hls', 'm3u8'}.contains(target.container.toLowerCase());
      // Validate a bounded prefix before exposing a transport to any engine.
      // Never drain a probe: servers are allowed to ignore Range.
      var opened = await _open(
          session,
          'GET',
          {
            if (!isHls) 'range': ['bytes=0-511']
          },
          allowHls: true);
      try {
        if (opened.response.statusCode != 200 &&
            opened.response.statusCode != 206) {
          throw const PlaybackRelayException();
        }
        final chunks = await _prefix(opened.body, opened.budget);
        final prefix =
            chunks.expand((chunk) => chunk).take(_sampleSize).toList();
        if (isHls ||
            _hlsPath(opened.uri) ||
            _hlsPrefix(prefix) ||
            (opened.response.headers.contentType?.mimeType
                    .contains('mpegurl') ??
                false)) {
          // A range probe is not a complete manifest. Re-fetch without Range.
          if (!isHls) {
            await opened.close();
            opened = await _open(session, 'GET', {}, allowHls: true);
          }
          session.hls = true;
          await _manifest(session, opened, isHls ? chunks : const <List<int>>[],
              depth: 0);
        } else {
          if (!_progressivePrefix(prefix)) throw unsupportedRelayMedia;
          session.validatedPrefix = prefix;
        }
      } finally {
        await opened.close();
      }
      if (_closed || session.closed) throw const PlaybackRelayException();
      if (session.hls) {
        session.path = '/$kPlaybackRelayPathSegment/$id/media.m3u8';
      }
      _sessions[id] = session;
      return target.copyWith(
        container: session.hls ? 'hls' : target.container,
        streamUrl: Uri(
                scheme: 'http',
                host: '127.0.0.1',
                port: _server!.port,
                path: session.path)
            .toString(),
        actualAddress: target.actualAddress.isEmpty
            ? target.streamUrl
            : target.actualAddress,
        headers: const {},
      );
    } on PlaybackRelayException {
      if (!needsSecurityRelay && !_closed) return target;
      rethrow;
    } catch (_) {
      if (!needsSecurityRelay && !_closed) return target;
      // Network exceptions can contain signed URLs or Basic credentials.
      throw const PlaybackRelayException();
    } finally {
      _preparing.remove(session);
      if (!_sessions.containsValue(session)) session.close();
    }
  }

  Future<void> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      throw const PlaybackRelayException();
    }
    _server = server;
    server.listen((request) => unawaited(_serve(request)));
  }

  @override
  Future<void> clear({String reason = ''}) async {
    for (final session in {..._sessions.values, ..._preparing}) {
      session.close();
      await diskCache?.removePrefix(
          session.path.substring(0, session.path.lastIndexOf('/') + 1));
    }
    _sessions.clear();
    _preparing.clear();
  }

  @override
  Future<void> close() async {
    _closed = true;
    await clear();
    await _server?.close(force: true);
    _server = null;
    if (!_cacheReleased && diskCache != null) {
      _cacheReleased = true;
      final count = (_cacheOwners[diskCache] ?? 1) - 1;
      if (count == 0) {
        _cacheOwners.remove(diskCache);
        _diskCaches.remove(diskCache);
        await diskCache!.close();
      } else {
        _cacheOwners[diskCache!] = count;
      }
    }
  }

  Future<void> _serve(HttpRequest request) async {
    _Opened? opened;
    PlaybackCachedResponse? cached;
    try {
      final parts = request.uri.pathSegments;
      final session =
          parts.length == 3 && parts.first == kPlaybackRelayPathSegment
              ? _sessions[parts[1]]
              : null;
      final resource = session?.resources[request.uri.path];
      if (session == null ||
          (request.uri.path != session.path && resource == null) ||
          request.uri.hasQuery ||
          request.headers.value(HttpHeaders.hostHeader) !=
              '127.0.0.1:${_server?.port}') {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final forwarded = <String, List<String>>{};
      for (final name in [
        'range',
        'if-range',
        'if-modified-since',
        'if-none-match',
        'accept'
      ]) {
        final values = request.headers[name];
        if (values != null) forwarded[name] = values;
      }
      final playlist = resource?.kind == HlsResourceKind.playlist ||
          (resource == null && session.hls);
      if (playlist || resource?.kind == HlsResourceKind.key) forwarded.clear();
      final cacheable = request.method == 'GET' &&
          !playlist &&
          resource?.kind != HlsResourceKind.key &&
          !forwarded.keys.any((key) => key.startsWith('if-'));
      // Dynamic playlist resources can reuse URLs for changing content. Only VOD is reusable.
      final reusable = resource == null || resource.reusable;
      if (cacheable && reusable && diskCache != null) {
        cached = await diskCache!
            .read(request.uri.path, request.headers.value('range'));
        if (cached != null) {
          try {
            await cached.send(request.response);
            return;
          } on FileSystemException {
            await diskCache!.clear();
            opened = await _open(
                session,
                'GET',
                {
                  'range': [
                    'bytes=${cached.start + cached.delivered}-${cached.end}'
                  ]
                },
                resource: resource);
            final expectedStart = cached.start + cached.delivered;
            if (opened.response.statusCode != 206 ||
                opened.response.headers.value('content-range') !=
                    'bytes $expectedStart-${cached.end}/${cached.total}') {
              throw const PlaybackRelayException();
            }
            while (await session
                .wait(opened.body.moveNext())
                .timeout(requestTimeout)) {
              request.response.add(opened.body.current);
              await request.response.flush();
            }
            return;
          }
        }
      }
      opened = await _open(
          session, playlist ? 'GET' : request.method, forwarded,
          resource: resource, allowHls: playlist);
      final response = opened.response;
      if (playlist) {
        final bytes = await _manifest(session, opened, const [],
            depth: resource?.depth ?? 0);
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        request.response.headers.set('cache-control', 'no-store');
        request.response.contentLength = bytes.length;
        if (request.method != 'HEAD') request.response.add(bytes);
        return;
      }
      final chunks = request.method == 'HEAD'
          ? <List<int>>[]
          : await _prefix(opened.body, opened.budget);
      final prefix = chunks.expand((chunk) => chunk).take(_sampleSize).toList();
      if (request.method != 'HEAD' &&
          resource?.kind == HlsResourceKind.key &&
          (response.statusCode != 200 || prefix.length != 16)) {
        throw unsupportedRelayMedia;
      }
      final startsAtZero = response.statusCode == 200 ||
          (response.statusCode == 206 &&
              RegExp(r'^bytes 0-')
                  .hasMatch(response.headers.value('content-range') ?? ''));
      // A short range need not contain a whole container signature. Only
      // accept it when its bytes match the previously validated media prefix.
      final matchesShortPrefix = response.statusCode == 206 &&
          prefix.isNotEmpty &&
          prefix.length < session.validatedPrefix.length &&
          Iterable<int>.generate(prefix.length)
              .every((i) => prefix[i] == session.validatedPrefix[i]);
      if (_manifestPrefix(prefix) ||
          (request.method != 'HEAD' &&
              startsAtZero &&
              resource?.kind == HlsResourceKind.segment &&
              !_progressivePrefix(prefix) &&
              !_hlsSegmentPrefix(prefix)) ||
          (request.method != 'HEAD' &&
              resource == null &&
              startsAtZero &&
              !_progressivePrefix(prefix) &&
              !matchesShortPrefix)) {
        throw unsupportedRelayMedia;
      }
      request.response.statusCode = response.statusCode;
      // Never forward Location, cookies, auth challenges or Content-Location.
      for (final name in [
        'content-length',
        'content-type',
        'content-range',
        'accept-ranges',
        'etag',
        'last-modified'
      ]) {
        final values = response.headers[name];
        if (values != null) request.response.headers.set(name, values);
      }
      request.response.bufferOutput = false;
      if (request.method != 'HEAD') {
        final writer = cacheable
            ? diskCache?.writer(
                request.uri.path, response.statusCode, response.headers,
                reusable: reusable)
            : null;
        for (final chunk in chunks) {
          request.response.add(chunk);
          await writer?.add(chunk);
        }
        await session.wait(request.response.flush()).timeout(requestTimeout);
        while (await session
            .wait(opened.body.moveNext())
            .timeout(requestTimeout)) {
          request.response.add(opened.body.current);
          await writer?.add(opened.body.current);
          await session.wait(request.response.flush()).timeout(requestTimeout);
        }
      }
    } catch (_) {
      try {
        final errorBody =
            utf8.encode('Secure playback relay rejected the response');
        request.response.headers.clear();
        request.response.statusCode = HttpStatus.badGateway;
        request.response.contentLength = errorBody.length;
        request.response.add(errorBody);
      } catch (_) {}
    } finally {
      await cached?.close();
      await opened?.close();
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<_Opened> _open(
      _RelaySession session, String method, Map<String, List<String>> forwarded,
      {_RelayResource? resource, bool allowHls = false}) async {
    var uri = resource?.uri ?? session.current;
    final budget = _RequestBudget(requestTimeout, session);
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (session.closed || _closed || !isHttpUri(uri)) {
        throw const PlaybackRelayException();
      }
      if (_manifestPath(uri) && !(allowHls && _hlsPath(uri))) {
        throw unsupportedRelayMedia;
      }
      final client = _client();
      session.clients.add(client);
      var handedOff = false;
      try {
        final request = await budget.wait(client.openUrl(method, uri));
        request.followRedirects = false;
        request.maxRedirects = 0;
        forwarded.forEach((name, values) => request.headers.set(name, values));
        // Unknown custom auth headers are origin-bound too, not just Basic.
        for (final entry in session.headers.entries) {
          if (entry.key == 'cookie') continue;
          if (isSameHttpOrigin(session.origin, uri) ||
              const {'user-agent', 'accept'}.contains(entry.key)) {
            request.headers.set(entry.key, entry.value);
          }
        }
        request.headers.set('accept-encoding', 'identity');
        for (final cookie
            in session.cookies[uri.origin]?.values ?? <Cookie>[]) {
          if ((!cookie.secure || uri.scheme == 'https') &&
              (cookie.expires == null ||
                  cookie.expires!.isAfter(DateTime.now())) &&
              _cookiePathMatches(uri.path, cookie.path ?? '/')) {
            request.cookies.add(Cookie(cookie.name, cookie.value));
          }
        }
        final response = await budget.wait(request.close());
        _captureCookies(session, uri, response);
        if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers.value('location');
          if (hop == _maxRedirects ||
              location == null ||
              location.trim().isEmpty) {
            throw const PlaybackRelayException();
          }
          final next = uri.resolve(location);
          if (!isHttpUri(next) ||
              (uri.scheme == 'https' && next.scheme != 'https')) {
            throw const PlaybackRelayException();
          }
          uri = next;
          continue;
        }
        if (response.statusCode >= 300 && response.statusCode != 416) {
          throw const PlaybackRelayException();
        }
        final type = response.headers.contentType?.mimeType.toLowerCase() ?? '';
        final encoding =
            response.headers.value('content-encoding')?.toLowerCase();
        if ((!allowHls &&
                type.startsWith('text/') &&
                !(resource != null && type == 'text/vtt')) ||
            (!allowHls && type.contains('mpegurl')) ||
            type.contains('dash') ||
            type.contains('xml') ||
            type.contains('json') ||
            (encoding != null && encoding != 'identity')) {
          throw unsupportedRelayMedia;
        }
        if (resource == null) session.current = uri;
        handedOff = true;
        return _Opened(response, client, session, budget, uri);
      } finally {
        if (!handedOff) {
          client.close(force: true);
          session.clients.remove(client);
        }
      }
    }
    throw const PlaybackRelayException();
  }

  Future<List<int>> _manifest(
      _RelaySession session, _Opened opened, List<List<int>> chunks,
      {required int depth}) async {
    if (depth > 4 || opened.response.statusCode != 200) {
      throw unsupportedRelayMedia;
    }
    final bytes = <int>[];
    void append(List<int> chunk) {
      if (bytes.length + chunk.length > _maxManifestBytes) {
        throw unsupportedRelayMedia;
      }
      bytes.addAll(chunk);
    }

    for (final chunk in chunks) {
      append(chunk);
    }
    while (await opened.budget.wait(opened.body.moveNext())) {
      append(opened.body.current);
    }
    final now = clock();
    final staged = <String, _RelayResource>{};
    final stagedPaths = <String, String>{};
    final sourceText = utf8.decode(bytes);
    final vod =
        sourceText.split('\n').any((line) => line.trim() == '#EXT-X-ENDLIST');
    final text = rewritePlaybackHls(sourceText, (value, kind) {
      final uri = opened.uri.resolve(value);
      if (!isHttpUri(uri) ||
          uri.hasFragment ||
          (opened.uri.scheme == 'https' && uri.scheme != 'https') ||
          uri.toString().length > 8192) {
        throw unsupportedRelayMedia;
      }
      final key = '${kind.name}:$uri';
      var path = session.resourcePaths[key] ?? stagedPaths[key];
      if (path == null) {
        if (staged.length >= _maxResources) {
          throw unsupportedRelayMedia;
        }
        path =
            '${session.path.substring(0, session.path.lastIndexOf('/'))}/r${session.nextResourceId++}';
      }
      stagedPaths[key] = path;
      final previous = session.resources[path] ?? staged[path];
      staged[path] = _RelayResource(
          uri, kind, max(depth + 1, previous?.depth ?? 0), now,
          reusable: vod);
      return 'http://127.0.0.1:${_server!.port}$path';
    });
    // Publish only after the whole manifest validates. Keep recent segments for
    // engine buffering/seeks; expired capabilities are never reassigned.
    final expired = session.resources.entries
        .where((entry) =>
            entry.value.kind != HlsResourceKind.playlist &&
            !staged.containsKey(entry.key) &&
            now.difference(entry.value.lastSeen) > _resourceGrace)
        .map((entry) => entry.key)
        .toSet();
    if (session.resources.length -
            expired.length +
            staged.keys
                .where((path) => !session.resources.containsKey(path))
                .length >
        _maxResources) {
      throw unsupportedRelayMedia;
    }
    for (final path in expired) {
      session.resources.remove(path);
    }
    session.resourcePaths.removeWhere((_, path) => expired.contains(path));
    session.resources.addAll(staged);
    session.resourcePaths.addAll(stagedPaths);
    return utf8.encode(text);
  }

  HttpClient _client() {
    final proxy = networkProxyRuntime.config;
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = requestTimeout
      ..findProxy = proxy.proxyDirectiveFor;
    client.authenticateProxy = (host, port, scheme, realm) async {
      if (!proxy.isActive ||
          proxy.username.trim().isEmpty ||
          host.toLowerCase() != proxy.normalizedHost.toLowerCase() ||
          port != proxy.port) {
        return false;
      }
      client.addProxyCredentials(host, port, realm ?? '',
          HttpClientBasicCredentials(proxy.username.trim(), proxy.password));
      return true;
    };
    return client;
  }

  void _captureCookies(
      _RelaySession session, Uri uri, HttpClientResponse response) {
    final jar = session.cookies.putIfAbsent(uri.origin, () => {});
    for (final cookie in response.cookies) {
      // Even a broad Domain attribute never grants another origin access.
      cookie.path ??= uri.path.substring(0, uri.path.lastIndexOf('/') + 1);
      final key = '${cookie.name}|${cookie.path}';
      if (cookie.maxAge != null) {
        cookie.expires = DateTime.now().add(Duration(seconds: cookie.maxAge!));
      }
      if (cookie.maxAge == 0 ||
          (cookie.expires?.isBefore(DateTime.now()) ?? false)) {
        jar.remove(key);
      } else if (jar.length < 128 || jar.containsKey(key)) {
        jar[key] = cookie;
      }
    }
  }
}

Map<String, String> _normalizeHeaders(Map<String, String> raw) {
  final result = <String, String>{};
  for (final entry in raw.entries) {
    final name = entry.key.trim().toLowerCase();
    if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name) ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(entry.value)) {
      throw const PlaybackRelayException();
    }
    if (const {
      'host',
      'connection',
      'content-length',
      'transfer-encoding',
      'proxy-authorization',
      'proxy-authenticate',
      'te',
      'trailer',
      'upgrade',
      'keep-alive',
      'range',
      'accept-encoding'
    }.contains(name)) {
      continue;
    }
    result[name] = entry.value;
  }
  return result;
}

bool _cookiePathMatches(String request, String path) =>
    request == path ||
    (request.startsWith(path) &&
        (path.endsWith('/') || request.substring(path.length).startsWith('/')));

bool _manifestPath(Uri uri) =>
    RegExp(r'\.(m3u8?|mpd|ism|isml|pls|asx|xspf)(/|$)', caseSensitive: false)
        .hasMatch(uri.path);

bool _hlsPath(Uri uri) => uri.path.toLowerCase().endsWith('.m3u8');
bool _hlsPrefix(List<int> bytes) => utf8
    .decode(bytes, allowMalformed: true)
    .replaceFirst('\uFEFF', '')
    .trimLeft()
    .startsWith('#EXTM3U');

bool _hlsSegmentPrefix(List<int> bytes) {
  final text = ascii.decode(bytes.take(16).toList(), allowInvalid: true);
  return (text.startsWith('WEBVTT') &&
          (text.length == 6 || RegExp(r'[\s]').hasMatch(text[6]))) ||
      (bytes.length >= 8 &&
          const {'styp', 'moof', 'sidx'}
              .contains(ascii.decode(bytes.sublist(4, 8), allowInvalid: true)));
}

Future<List<List<int>>> _prefix(
    StreamIterator<List<int>> body, _RequestBudget budget) async {
  final chunks = <List<int>>[];
  var size = 0;
  while (size < _sampleSize && await budget.wait(body.moveNext())) {
    chunks.add(body.current);
    size += body.current.length;
  }
  return chunks;
}

bool _manifestPrefix(List<int> bytes) {
  if (bytes.isEmpty) return false;
  final text = utf8
      .decode(bytes, allowMalformed: true)
      .replaceFirst('\uFEFF', '')
      .trimLeft();
  return text.startsWith('#EXTM3U') ||
      text.startsWith('#EXT-X-') ||
      RegExp(r'^<(\?xml|MPD\b|SmoothStreamingMedia\b|ASX\b|playlist\b)',
              caseSensitive: false)
          .hasMatch(text) ||
      text.toLowerCase().startsWith('[playlist]');
}

bool _progressivePrefix(List<int> bytes) {
  if (bytes.length < 4 || _manifestPrefix(bytes)) return false;
  bool magic(int offset, List<int> signature) =>
      bytes.length >= offset + signature.length &&
      List.generate(signature.length, (i) => bytes[offset + i] == signature[i])
          .every((v) => v);
  bool ascii(int offset, String text) =>
      magic(offset, const AsciiEncoder().convert(text));
  return magic(0, [0x1a, 0x45, 0xdf, 0xa3]) ||
      ascii(4, 'ftyp') ||
      ascii(4, 'moov') ||
      ascii(4, 'mdat') ||
      ascii(4, 'free') ||
      ascii(0, 'RIFF') ||
      ascii(0, 'FLV') ||
      ascii(0, 'OggS') ||
      ascii(0, 'fLaC') ||
      ascii(0, 'ID3') ||
      (bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0) ||
      magic(0, [0, 0, 1, 0xba]) ||
      magic(0, [
        0x30,
        0x26,
        0xb2,
        0x75,
        0x8e,
        0x66,
        0xcf,
        0x11,
        0xa6,
        0xd9,
        0,
        0xaa,
        0,
        0x62,
        0xce,
        0x6c
      ]) ||
      (bytes.length > 376 &&
          bytes[0] == 0x47 &&
          bytes[188] == 0x47 &&
          bytes[376] == 0x47) ||
      (bytes.length > 388 &&
          bytes[4] == 0x47 &&
          bytes[196] == 0x47 &&
          bytes[388] == 0x47);
}

class _RelaySession {
  _RelaySession(this.origin, this.headers) : current = origin {
    final jar = cookies.putIfAbsent(origin.origin, () => {});
    for (final field in (headers['cookie'] ?? '').split(';')) {
      final i = field.indexOf('=');
      if (i > 0) {
        final cookie =
            Cookie(field.substring(0, i).trim(), field.substring(i + 1).trim())
              ..path = '/';
        jar['${cookie.name}|/'] = cookie;
      }
    }
  }
  final Uri origin;
  Uri current;
  final Map<String, String> headers;
  final cookies = <String, Map<String, Cookie>>{};
  final clients = <HttpClient>{};
  List<int> validatedPrefix = const [];
  bool hls = false;
  final resources = <String, _RelayResource>{};
  final resourcePaths = <String, String>{};
  int nextResourceId = 0;
  final _cancellations = <void Function()>{};
  String path = '';
  bool closed = false;

  Future<T> wait<T>(Future<T> operation) async {
    final cancelled = Completer<void>();
    void cancel() => cancelled.complete();
    _cancellations.add(cancel);
    if (closed) cancel();
    try {
      return await Future.any([
        operation,
        cancelled.future.then<T>((_) => throw const PlaybackRelayException()),
      ]);
    } finally {
      _cancellations.remove(cancel);
    }
  }

  void close() {
    if (closed) return;
    closed = true;
    for (final cancel in _cancellations) {
      cancel();
    }
    _cancellations.clear();
    for (final client in clients) {
      client.close(force: true);
    }
    clients.clear();
    cookies.clear();
    headers.clear();
    resources.clear();
    resourcePaths.clear();
  }
}

class _RelayResource {
  _RelayResource(this.uri, this.kind, this.depth, this.lastSeen,
      {this.reusable = false});
  final Uri uri;
  final HlsResourceKind kind;
  final int depth;
  final DateTime lastSeen;
  final bool reusable;
}

class _Opened {
  _Opened(this.response, this.client, this.session, this.budget, this.uri)
      : body = StreamIterator(response);
  final HttpClientResponse response;
  final HttpClient client;
  final _RelaySession session;
  final StreamIterator<List<int>> body;
  final _RequestBudget budget;
  final Uri uri;
  Future<void> close() async {
    client.close(force: true);
    session.clients.remove(client);
    await body.cancel();
  }
}

class _RequestBudget {
  _RequestBudget(this.timeout, this.session);
  final Duration timeout;
  final _RelaySession session;
  final clock = Stopwatch()..start();
  Future<T> wait<T>(Future<T> operation) {
    final remaining = timeout - clock.elapsed;
    return session
        .wait(operation)
        .timeout(remaining > Duration.zero ? remaining : Duration.zero);
  }
}
