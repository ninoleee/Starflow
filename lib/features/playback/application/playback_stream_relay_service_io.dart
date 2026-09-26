import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/http_origin_policy.dart';
import 'package:starflow/core/network/network_proxy_runtime.dart';
import 'package:starflow/core/storage/local_storage_models.dart';
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
const _rangeChunkBytes = 2 * 1024 * 1024;
const _readAheadWindowBytes = 128 * 1024 * 1024;
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
    if (previous != null) unawaited(previous.disable('capacity_changed'));
    _sharedDiskCache = PlaybackRelayDiskCache(capacityBytes: bytes);
  }
  return _sharedDiskCache;
}

Future<void> clearPlaybackDiskCache() async {
  await Future.wait(_diskCaches.toList().map((cache) => cache.clear()));
  await PlaybackRelayDiskCache.clearInactiveFiles();
}

Future<void> disablePlaybackDiskCache() async {
  await Future.wait(
      _diskCaches.toList().map((cache) => cache.disable('settings_changed')));
}

Future<LocalStorageCacheSummary> inspectPlaybackDiskCache() =>
    PlaybackRelayDiskCache.inspectSummary();

PlaybackStreamRelayService createPlaybackStreamRelayService({
  Duration requestTimeout = _requestTimeout,
  DateTime Function()? clock,
  int diskCacheMiB = 0,
  PlaybackRelayDiskCache? diskCache,
}) =>
    _IoPlaybackStreamRelayService(requestTimeout, clock ?? DateTime.now,
        diskCache ?? _acquireDiskCache(diskCacheMiB));

class _IoPlaybackStreamRelayService
    implements
        PlaybackStreamRelayService,
        PlaybackRelayCacheControl,
        PlaybackRelayBufferControl {
  _IoPlaybackStreamRelayService(
      this.requestTimeout, this.clock, this.diskCache) {
    if (diskCache != null) {
      _diskCaches.add(diskCache!);
      _cacheOwners.update(diskCache!, (count) => count + 1, ifAbsent: () => 1);
      diskCache!.invalidationListeners.add(_cancelPrefetch);
    }
  }
  final PlaybackRelayDiskCache? diskCache;
  final Duration requestTimeout;
  final DateTime Function() clock;
  final _sessions = <String, _RelaySession>{};
  final _preparing = <_RelaySession>{};
  final _activeServeTasks = <Future<void>>{};
  final _random = Random.secure();
  HttpServer? _server;
  Future<void>? _starting;
  bool _closed = false;
  bool _cacheReleased = false;
  Future<void>? _closing;

  Iterable<_RelaySession> _selectedSessions(String? url) {
    if (_closed || _server == null) return const [];
    if (url == null) return _sessions.values;
    final uri = Uri.tryParse(url);
    if (uri?.port != _server?.port) return const [];
    return _sessions.values.where((s) => s.path == uri?.path);
  }

  @override
  PlaybackRelayCacheSnapshot? cacheSnapshot({String? url}) {
    final cache = diskCache;
    if (cache == null || _closed) return null;
    final sessions = _selectedSessions(url).toList();
    if (sessions.isEmpty) return null;
    var stored = 0;
    int? forward;
    for (final s in sessions) {
      stored += cache.storedBytesForPrefix(
          s.path.substring(0, s.path.lastIndexOf('/') + 1));
      if (!s.hls && s.cursor != null) {
        final span = cache.firstAvailableRange(s.path, 'bytes=${s.cursor}-');
        forward = (forward ?? 0) +
            (span?.start == s.cursor ? span!.end - s.cursor! + 1 : 0);
      }
    }
    return PlaybackRelayCacheSnapshot(
        storedBytes: stored,
        forwardBytes: forward,
        disabledReason: cache.disabledReason);
  }

  @override
  void updateBufferState({required bool memoryReady, String? url}) {
    for (final session in _selectedSessions(url)) {
      session.bufferLease?.cancel();
      session.bufferLease = null;
      session.memoryReady = memoryReady && session.playbackActive;
      if (!session.memoryReady) {
        _stopPrefetch(session, 'memory_refill');
        continue;
      }
      session.bufferLease = Timer(const Duration(seconds: 4), () {
        session.memoryReady = false;
        session.bufferLease = null;
        _stopPrefetch(session, 'buffer_state_expired');
      });
      final candidate = session.prefetchCandidate;
      if (candidate != null &&
          session.prefetchTimer == null &&
          session.prefetchTask == null) {
        _schedulePrefetch(
            session,
            candidate.$1,
            candidate.$2,
            session.hls ? candidate.$3 : session.cursor ?? candidate.$3,
            candidate.$4);
      }
    }
  }

  void _revokeBufferPermission(_RelaySession session) {
    session.memoryReady = false;
    session.bufferLease?.cancel();
    session.bufferLease = null;
  }

  @override
  void setPlaybackActive(bool active, {String? url}) {
    for (final session in _selectedSessions(url)) {
      session.playbackActive = active;
      if (!active) {
        _revokeBufferPermission(session);
        _stopPrefetch(session, 'paused');
      } else if (session.cursor != null && session.mediaInfo != null) {
        _schedulePrefetch(session, session.path, null, session.cursor!,
            session.mediaInfo!.total);
      }
    }
  }

  @override
  void cancelReadAhead({String? url}) {
    for (final session in _selectedSessions(url)) {
      _revokeBufferPermission(session);
      session.prefetchCandidate = null;
      diskCache?.clearReadCursor(session.path);
      session.foregroundEpoch++;
      _stopPrefetch(session, 'seek');
      session.cursor = null;
    }
  }

  void _stopPrefetch(_RelaySession session, String reason) {
    if (session.prefetchTransfer?.promoted == true &&
        const {'memory_refill', 'buffer_state_expired', 'paused'}
            .contains(reason)) {
      session.prefetchTimer?.cancel();
      session.prefetchTimer = null;
      return;
    }
    final hadWork =
        session.prefetchTimer != null || session.prefetchTask != null;
    session.prefetchTimer?.cancel();
    session.prefetchTimer = null;
    session.prefetchEpoch++;
    session.prefetchCancelled?.complete();
    session.prefetchCancelled = null;
    session.prefetchClient?.close(force: true);
    if (hadWork) _logPrefetch(session, reason);
  }

  void _logPrefetch(_RelaySession session, String reason) {
    if (session.lastPrefetchReason == reason &&
        clock().difference(session.lastPrefetchLog) <
            const Duration(seconds: 5)) {
      return;
    }
    session.lastPrefetchReason = reason;
    session.lastPrefetchLog = clock();
    appLogInfo('playback.cache', 'Read ahead', fields: {
      'reason': reason,
      'cursor': session.cursor,
      'storedBytes': cacheSnapshot()?.storedBytes,
      'forwardBytes': cacheSnapshot()?.forwardBytes,
      'queuedBytes': diskCache?.queuedBytes,
      'activeRequests': session.activeRequests,
      'foregroundNetwork': session.foregroundNetwork,
      'originBytesPerSecond': session.originBytesPerSecond,
      'memoryReady': session.memoryReady,
    });
  }

  void _cancelPrefetch() {
    for (final session in {..._sessions.values, ..._preparing}) {
      _revokeBufferPermission(session);
      session.prefetchCandidate = null;
      diskCache?.clearReadCursor(session.path);
      session.foregroundEpoch++;
      session.cursor = null;
      _stopPrefetch(session, diskCache?.disabledReason ?? 'cleared');
    }
  }

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
      if (!needsSecurityRelay) return target;
      throw unsupportedRelayMedia;
    }
    final session = _RelaySession(uri, _normalizeHeaders(target.headers));
    session.bitrate = target.bitrate ?? 0;
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
          final range = RegExp(r'^bytes 0-\d+/(\d+)$')
              .firstMatch(opened.response.headers.value('content-range') ?? '');
          if (opened.response.statusCode == 206 && range != null) {
            final etag = opened.response.headers.value('etag');
            session.mediaInfo = PlaybackCachedRange(
                0,
                -1,
                int.parse(range[1]!),
                opened.response.headers.contentType?.toString() ??
                    'application/octet-stream',
                etag != null && !etag.startsWith('W/')
                    ? etag
                    : opened.response.headers.value('last-modified'));
          }
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
    server.listen(_trackServeTask);
  }

  void _trackServeTask(HttpRequest request) {
    final task = _serve(request);
    _activeServeTasks.add(task);
    unawaited(task.then<void>(
      (_) => _activeServeTasks.remove(task),
      onError: (Object _, StackTrace __) {
        _activeServeTasks.remove(task);
      },
    ));
  }

  @override
  Future<void> clear({String reason = ''}) async {
    final sessions = {..._sessions.values, ..._preparing};
    _sessions.clear();
    _preparing.clear();
    for (final session in sessions) {
      _stopPrefetch(session, reason.isEmpty ? 'closed' : reason);
      session.close();
    }
    await Future.wait(sessions.map((session) async {
      await session.prefetchTask;
      final path = session.path;
      final slash = path.lastIndexOf('/');
      if (slash <= 0) return;
      await diskCache?.removePrefix(path.substring(0, slash + 1));
    }));
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _server?.close(force: true);
    await clear();
    while (_activeServeTasks.isNotEmpty) {
      await Future.wait(_activeServeTasks.toList().map((task) async {
        try {
          await task;
        } catch (_) {
          // A cancelled client must not prevent cache ownership from closing.
        }
      }));
    }
    _server = null;
    if (!_cacheReleased && diskCache != null) {
      _cacheReleased = true;
      diskCache!.invalidationListeners.remove(_cancelPrefetch);
      final count = (_cacheOwners[diskCache] ?? 1) - 1;
      if (count == 0) {
        _cacheOwners.remove(diskCache);
        _diskCaches.remove(diskCache);
        appLogInfo('playback.cache', 'Disk cache session closed', fields: {
          'hitBytes': diskCache!.hitBytes,
          'writtenBytes': diskCache!.writtenBytes,
          'droppedBytes': diskCache!.droppedBytes,
          'writeMilliseconds': diskCache!.writeMicroseconds ~/ 1000,
          'disabledReason': diskCache!.disabledReason,
        });
        await diskCache!.close();
      } else {
        _cacheOwners[diskCache!] = count;
      }
    }
  }

  Future<void> _serve(HttpRequest request) async {
    _Opened? opened;
    PlaybackCacheWriter? writer;
    _RelaySession? servingSession;
    final consumer = _RelayConsumer(request.response);
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
      servingSession = session;
      session.responses.add(request.response);
      session.activeRequests++;
      final foregroundEpoch = ++session.foregroundEpoch;
      final cacheGeneration = diskCache?.generation;
      bool ownsReadAhead() =>
          !session.closed &&
          !consumer.closed &&
          foregroundEpoch == session.foregroundEpoch &&
          cacheGeneration == diskCache?.generation;
      final requestedRange = request.headers.value('range');
      final requestedStart = requestedRange == null
          ? 0
          : int.tryParse(RegExp(r'^bytes=(\d+)-\d*$')
                  .firstMatch(requestedRange)
                  ?.group(1) ??
              '');
      final transfer = session.prefetchTransfer;
      final canPromote = request.method == 'GET' &&
          requestedStart != null &&
          const ['if-range', 'if-none-match', 'if-modified-since']
              .every((name) => request.headers[name] == null) &&
          transfer?.contains(request.uri.path, requestedStart) == true;
      if (!canPromote) {
        _stopPrefetch(session, 'foreground');
        await session.prefetchTask;
      }
      if (consumer.closed) return;
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
        final available = diskCache!.firstAvailableRange(
            request.uri.path, request.headers.value('range'));
        final info = available ??
            (resource == null && !session.hls ? session.mediaInfo : null);
        final rangeValue = request.headers.value('range');
        if (available != null &&
            resource != null &&
            available.validator == null) {
          final local = await diskCache!.read(request.uri.path, rangeValue);
          if (local != null) {
            final match = rangeValue == null
                ? null
                : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(rangeValue);
            final end = match == null || match[2]!.isEmpty
                ? local.total - 1
                : min(int.parse(match[2]!), local.total - 1);
            try {
              if (local.end == end) {
                // A complete VOD segment can be reused without splicing an
                // unvalidated network response onto bytes already delivered.
                await session.wait(local.send(request.response,
                    timeout: requestTimeout,
                    flush: () => consumer.wait(request.response.flush())));
                if (ownsReadAhead()) {
                  _schedulePrefetch(session, request.uri.path, resource,
                      local.end + 1, local.total);
                }
                return;
              }
            } finally {
              await local.close();
            }
          }
        }
        // Without a validator, one origin response is safer than combining
        // separately fetched ranges of a possibly changing resource.
        if (info != null &&
            info.validator != null &&
            (rangeValue == null ||
                RegExp(r'^bytes=\d+-\d*$').hasMatch(rangeValue))) {
          await _serveCachedRanges(request, session, resource, reusable, info,
              ownsReadAhead, consumer);
          return;
        }
      }
      opened = await _open(
          session, playlist ? 'GET' : request.method, forwarded,
          resource: resource, allowHls: playlist, consumer: consumer);
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
        final hasValidator = _responseValidator(response.headers) != null;
        writer =
            cacheable && ownsReadAhead() && (resource != null || hasValidator)
                ? diskCache?.writer(
                    request.uri.path, response.statusCode, response.headers,
                    reusable: reusable)
                : null;
        for (final chunk in chunks) {
          request.response.add(chunk);
          await writer?.add(chunk);
        }
        await session.wait(consumer.wait(request.response.flush()));
        while (await session
            .wait(opened.body.moveNext())
            .timeout(requestTimeout)) {
          if (consumer.closed) return;
          request.response.add(opened.body.current);
          await writer?.add(opened.body.current);
          await session.wait(consumer.wait(request.response.flush()));
        }
        if (writer != null && ownsReadAhead()) {
          if (resource == null && !session.hls) {
            session.mediaInfo = PlaybackCachedRange(
                0, -1, writer.total, writer.type, writer.validator);
            session.cursor = writer.position;
            diskCache?.setReadCursor(session.path, writer.position);
          }
          _schedulePrefetch(session, request.uri.path, resource,
              writer.position, writer.total);
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
      consumer.close();
      writer?.close();
      servingSession?.responses.remove(request.response);
      if (servingSession != null) servingSession.activeRequests--;
      await opened?.close();
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveCachedRanges(
      HttpRequest request,
      _RelaySession session,
      _RelayResource? resource,
      bool reusable,
      PlaybackCachedRange available,
      bool Function() ownsReadAhead,
      _RelayConsumer consumer) async {
    final cache = diskCache!;
    final range = request.headers.value('range');
    final parsed =
        range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (range != null && parsed == null) {
      throw const PlaybackRelayException();
    }
    final start = parsed == null ? 0 : int.parse(parsed[1]!);
    final end = parsed == null || parsed[2]!.isEmpty
        ? available.total - 1
        : min(int.parse(parsed[2]!), available.total - 1);
    if (start < 0 || end < start) {
      throw const PlaybackRelayException();
    }

    request.response.statusCode =
        range == null ? HttpStatus.ok : HttpStatus.partialContent;
    request.response.contentLength = end - start + 1;
    request.response.headers.set('content-type', available.type);
    request.response.headers.set('accept-ranges', 'bytes');
    if (range != null) {
      request.response.headers
          .set('content-range', 'bytes $start-$end/${available.total}');
    }
    request.response.bufferOutput = false;

    void updateCursor(int position) {
      if (ownsReadAhead() && resource == null && !session.hls) {
        session.cursor = position;
        cache.setReadCursor(request.uri.path, position);
      }
    }

    void schedule(int position) {
      if (ownsReadAhead()) {
        _schedulePrefetch(
            session, request.uri.path, resource, position, available.total);
      }
    }

    var position = start;
    while (position <= end) {
      if (session.closed || consumer.closed) return;
      updateCursor(position);
      final next =
          cache.firstAvailableRange(request.uri.path, 'bytes=$position-$end');
      if (next != null &&
          (next.total != available.total ||
              next.validator != available.validator)) {
        throw const PlaybackRelayException();
      }
      final currentNext = next;
      if (currentNext != null && currentNext.start == position) {
        final local = await cache.read(request.uri.path,
            'bytes=$position-${min(currentNext.end, position + _rangeChunkBytes - 1)}');
        if (local != null) {
          schedule(position);
          final generation = cache.generation;
          final deliveredBefore = local.delivered;
          try {
            await session.wait(local.send(request.response,
                headers: false,
                timeout: requestTimeout,
                flush: () => consumer.wait(request.response.flush())));
          } on FileSystemException {
            if (session.closed) return;
            if (cache.generation == generation) {
              unawaited(cache.disable('read_failure'));
            }
          } on TimeoutException {
            if (session.closed) return;
          } finally {
            await local.close();
          }
          final delivered = local.delivered - deliveredBefore;
          position += delivered;
          updateCursor(position);
          if (delivered > 0) continue;
        }
      }

      // Cached bytes never wait behind speculation. Only a real miss needs
      // the origin slot; cancel first, then recheck any just-committed block.
      final transfer = session.prefetchTransfer;
      if (transfer != null &&
          !transfer.promoted &&
          transfer.contains(request.uri.path, position) &&
          transfer.total == available.total &&
          transfer.validator == available.validator) {
        transfer.promoted = true;
        _logPrefetch(session, 'promoted_to_memory');
        try {
          while (position <= min(end, transfer.end)) {
            if (consumer.closed || session.closed) return;
            final chunk = transfer.chunkAt(position, end);
            if (chunk != null) {
              request.response.add(chunk);
              await session.wait(consumer.wait(request.response.flush()));
              position += chunk.length;
              updateCursor(position);
            } else if (transfer.finished) {
              break;
            } else {
              await session
                  .wait(consumer.wait(transfer.changed.future))
                  .timeout(requestTimeout);
            }
          }
        } finally {
          // A partial client range must not turn its remainder into a second
          // speculative round after permission has been withdrawn.
          if (!transfer.finished) {
            _stopPrefetch(session, 'foreground_handoff_complete');
          }
          await session.prefetchTask;
        }
        continue;
      }
      if (session.prefetchTask != null) {
        _stopPrefetch(session, 'foreground_miss');
        await session.prefetchTask;
        continue;
      }

      final nextGap = currentNext != null && currentNext.start > position
          ? currentNext.start - 1
          : cache.nextCachedStart(request.uri.path, position, end + 1) - 1;
      final bounded = resource == null &&
          session.mediaInfo != null &&
          !session.rangeUnsupported &&
          !cache.disabled;
      final gapEnd = min(min(end, max(position, nextGap)),
          bounded ? position + _rangeChunkBytes - 1 : end);
      if (gapEnd < position) {
        throw const PlaybackRelayException();
      }

      _Opened? opened;
      PlaybackCacheWriter? writer;
      var networkCounted = false;
      try {
        session.foregroundNetwork++;
        networkCounted = true;
        final transferWatch = Stopwatch()..start();
        var transferBytes = 0;
        opened = await _open(
            session,
            'GET',
            {
              'range': ['bytes=$position-$gapEnd'],
              if (available.validator != null)
                'if-range': [available.validator!],
            },
            resource: resource,
            consumer: consumer);
        final expectedStart = position;
        final partial =
            opened.response.statusCode == HttpStatus.partialContent &&
                opened.response.headers.value('content-range') ==
                    'bytes $expectedStart-$gapEnd/${available.total}';
        final full = opened.response.statusCode == HttpStatus.ok &&
            opened.response.contentLength == available.total;
        final validator = available.validator;
        if (validator != null &&
            opened.response.headers.value('etag') != validator &&
            opened.response.headers.value('last-modified') != validator) {
          unawaited(cache.disable('resource_changed'));
          throw const PlaybackRelayException();
        }
        if (!partial && !full) {
          throw const PlaybackRelayException();
        }

        if (full) session.rangeUnsupported = true;
        final responseEnd = full && bounded ? end : gapEnd;
        var skip = full ? expectedStart : 0;
        var remaining = responseEnd - expectedStart + 1;
        final boundedOutput = bounded && partial;
        final initial = await _prefix(opened.body, opened.budget);
        final prefix =
            initial.expand((chunk) => chunk).take(_sampleSize).toList();
        if (_manifestPrefix(prefix) ||
            ((full || expectedStart == 0) &&
                resource?.kind != HlsResourceKind.encryptedSegment &&
                !_progressivePrefix(prefix) &&
                !(resource != null && _hlsSegmentPrefix(prefix)) &&
                !(prefix.isNotEmpty &&
                    prefix.length < session.validatedPrefix.length &&
                    Iterable<int>.generate(prefix.length).every(
                        (i) => prefix[i] == session.validatedPrefix[i])))) {
          throw unsupportedRelayMedia;
        }

        writer = partial && ownsReadAhead()
            ? cache.writer(request.uri.path, opened.response.statusCode,
                opened.response.headers,
                reusable: reusable)
            : null;
        Future<void> forward(List<int> chunk) async {
          if (consumer.closed) throw const PlaybackRelayException();
          transferBytes += chunk.length;
          final offset = min(skip, chunk.length);
          skip -= offset;
          final count = min(remaining, chunk.length - offset);
          if (count > 0) {
            final bytes = chunk.sublist(offset, offset + count);
            // Unbuffered HTTP output starts immediately; only defer the drain
            // until this bounded range ends, never stage a full block first.
            request.response.add(bytes);
            if (!boundedOutput) {
              await session.wait(consumer.wait(request.response.flush()));
            }
            remaining -= count;
          }
          await writer?.add(chunk);
        }

        for (final chunk in initial) {
          await forward(chunk);
        }
        while (remaining > 0 &&
            await session
                .wait(opened.body.moveNext())
                .timeout(requestTimeout)) {
          await forward(opened.body.current);
        }
        if (remaining != 0) {
          throw const PlaybackRelayException();
        }
        if (boundedOutput) {
          await opened.close();
          opened = null;
          session.foregroundNetwork--;
          networkCounted = false;
          // Measure origin time only, excluding player backpressure and disk flush.
          if (ownsReadAhead()) {
            session.originBytesPerSecond = transferWatch.elapsedMicroseconds > 0
                ? transferBytes * 1000000 ~/ transferWatch.elapsedMicroseconds
                : null;
          }
          updateCursor(responseEnd + 1);
          schedule(responseEnd + 1);
          await session.wait(consumer.wait(request.response.flush()));
        }
        position = responseEnd + 1;
      } finally {
        if (networkCounted) session.foregroundNetwork--;
        writer?.close();
        await opened?.close();
      }
    }
    updateCursor(end + 1);
    schedule(end + 1);
  }

  void _schedulePrefetch(_RelaySession session, String key,
      _RelayResource? resource, int start, int total) {
    session.prefetchCandidate = (key, resource, start, total);
    final cache = diskCache;
    if (cache == null ||
        cache.disabled ||
        session.closed ||
        !session.memoryReady ||
        !session.playbackActive ||
        session.rangeUnsupported) {
      return;
    }
    if (resource == null && session.mediaInfo?.validator == null) return;
    if (resource == null && !session.hls) session.cursor ??= start;
    session.prefetchTimer?.cancel();
    final epoch = session.prefetchEpoch;
    final generation = cache.generation;
    session.prefetchTimer = Timer(const Duration(milliseconds: 500), () {
      session.prefetchTimer = null;
      if (session.closed ||
          !session.memoryReady ||
          !session.playbackActive ||
          session.prefetchEpoch != epoch ||
          session.activeRequests > 1 ||
          session.foregroundNetwork > 0 ||
          session.prefetchTask != null ||
          cache.disabled ||
          cache.generation != generation) {
        return;
      }
      final cancelled = Completer<void>();
      session.prefetchCancelled = cancelled;
      late final Future<void> task;
      task = _prefetch(session, key, resource, start, total, epoch, generation,
              cancelled.future)
          .catchError((Object _) {
        _logPrefetch(session, 'failed');
      }).whenComplete(() {
        if (identical(session.prefetchTask, task)) session.prefetchTask = null;
        if (identical(session.prefetchCancelled, cancelled)) {
          session.prefetchCancelled = null;
        }
      });
      session.prefetchTask = task;
    });
  }

  Future<void> _prefetch(
      _RelaySession session,
      String key,
      _RelayResource? resource,
      int start,
      int total,
      int epoch,
      int generation,
      Future<void> cancelled) async {
    final cache = diskCache!;
    final int budget = min(32 * 1024 * 1024, cache.capacityBytes ~/ 4);
    if (budget <= 0) return;
    if (session.bitrate > 0 &&
        session.originBytesPerSecond != null &&
        session.originBytesPerSecond! * 8 < session.bitrate * 1.25) {
      _logPrefetch(session, 'slow_origin');
      return;
    }
    if (cache.queuedBytes >= PlaybackRelayDiskCache.maxWriteQueueBytes ~/ 2) {
      _logPrefetch(session, 'write_congestion');
      return;
    }
    final anchor = session.cursor ?? start;
    final int windowEnd = min<int>(total - 1,
        anchor + min<int>(_readAheadWindowBytes, cache.capacityBytes ~/ 2) - 1);
    final targets = <(String, _RelayResource?, int, int)>[];
    if (resource == null && !session.hls && start < total) {
      var position = max(start, anchor);
      var admitted = 0;
      while (position <= windowEnd && admitted < budget) {
        final hit =
            cache.firstAvailableRange(key, 'bytes=$position-$windowEnd');
        if (hit?.start == position) {
          position = hit!.end + 1;
          continue;
        }
        final end = min<int>(
            min<int>(windowEnd,
                position + min<int>(_rangeChunkBytes, budget - admitted) - 1),
            hit == null ? windowEnd : hit.start - 1);
        targets.add((key, null, position, end));
        admitted += end - position + 1;
        position = end + 1;
      }
      if (targets.isEmpty) {
        _logPrefetch(session, 'window_ready');
        return;
      }
    } else if (resource != null && resource.reusable) {
      final sequence = session.playlistResources.values
          .where((paths) => paths.contains(key))
          .firstOrNull;
      final following = (sequence ?? const <String>[])
          .skipWhile((path) => path != key)
          .skip(1)
          .where((path) =>
              session.resources[path]?.reusable == true &&
              const {HlsResourceKind.segment, HlsResourceKind.encryptedSegment}
                  .contains(session.resources[path]?.kind))
          .take(2);
      for (final path in following) {
        targets.add((path, session.resources[path], 0, -1));
      }
    }
    var remaining = budget;
    var prefetched = 0;
    final droppedBefore = cache.droppedBytes;
    for (final (path, target, offset, end) in targets) {
      _Opened? opened;
      PlaybackCacheWriter? writer;
      _PrefetchTransfer? transfer;
      try {
        if (session.closed ||
            !session.memoryReady ||
            !session.playbackActive ||
            session.foregroundNetwork > 0 ||
            session.prefetchEpoch != epoch ||
            cache.generation != generation ||
            cache.disabled) {
          return;
        }
        final range = end < 0 ? null : 'bytes=$offset-$end';
        final hit = cache.firstAvailableRange(path, range);
        if (hit != null) {
          final requestedEnd =
              end < 0 ? hit.total - 1 : min(end, hit.total - 1);
          final complete = hit.start == offset && hit.end >= requestedEnd;
          if (complete) continue;
        }
        opened = await _open(
            session,
            'GET',
            {
              if (range != null) 'range': [range],
              if (target == null && session.mediaInfo?.validator != null)
                'if-range': [session.mediaInfo!.validator!],
            },
            resource: target,
            prefetchEpoch: epoch);
        session.prefetchClient = opened.client;
        if (session.prefetchEpoch != epoch || session.closed) return;
        if (end >= 0 &&
            (opened.response.statusCode != 206 ||
                opened.response.headers.value('content-range') !=
                    'bytes $offset-$end/$total')) {
          return;
        }
        if (end < 0 && opened.response.statusCode != 200) return;
        final validator = target == null ? session.mediaInfo?.validator : null;
        if (validator != null &&
            opened.response.headers.value('etag') != validator &&
            opened.response.headers.value('last-modified') != validator) {
          _logPrefetch(session, 'resource_changed');
          return;
        }
        if (opened.response.contentLength <= 0 ||
            opened.response.contentLength > remaining) {
          return;
        }
        final chunks = await _prefix(opened.body, opened.budget);
        final prefix = chunks.expand((c) => c).take(_sampleSize).toList();
        if (_manifestPrefix(prefix) ||
            (target?.kind == HlsResourceKind.segment &&
                !_progressivePrefix(prefix) &&
                !_hlsSegmentPrefix(prefix))) {
          return;
        }
        writer = cache.writer(
            path, opened.response.statusCode, opened.response.headers);
        if (writer == null) return;
        if (target == null && end >= offset) {
          transfer = _PrefetchTransfer(path, offset, end, total, validator);
          session.prefetchTransfer = transfer;
        }
        for (final chunk in chunks) {
          if (session.prefetchEpoch != epoch ||
              (!session.memoryReady && transfer?.promoted != true) ||
              cache.generation != generation ||
              (!session.playbackActive && transfer?.promoted != true) ||
              chunk.length > remaining) {
            return;
          }
          transfer?.add(chunk);
          await writer.add(chunk);
          remaining -= chunk.length;
          prefetched += chunk.length;
        }
        while (await opened.budget.wait(opened.body.moveNext())) {
          if (session.prefetchEpoch != epoch ||
              (!session.memoryReady && transfer?.promoted != true) ||
              cache.generation != generation ||
              !writer.accepting ||
              remaining <= 0) {
            return;
          }
          final chunk = opened.body.current;
          if (chunk.length > remaining) return;
          transfer?.add(chunk);
          await writer.add(chunk);
          remaining -= chunk.length;
          prefetched += chunk.length;
        }
        if (writer.remaining != 0) return;
        transfer?.finish();
        await opened.close();
        if (identical(session.prefetchClient, opened.client)) {
          session.prefetchClient = null;
        }
        opened = null;
        if (transfer?.promoted == true) return;
        // Disk writes remain owned by the cache, but cannot hold up a new
        // foreground request after speculative work has been cancelled.
        await Future.any([cache.flushWrites(), cancelled])
            .timeout(const Duration(seconds: 2));
        if (session.prefetchEpoch != epoch || cache.generation != generation) {
          return;
        }
        if (cache.disabled || cache.droppedBytes != droppedBefore) {
          _logPrefetch(session, cache.disabledReason ?? 'write_congestion');
          return;
        }
      } catch (_) {
        _logPrefetch(session, 'cancelled_or_failed');
        return;
      } finally {
        transfer?.finish();
        if (identical(session.prefetchTransfer, transfer)) {
          session.prefetchTransfer = null;
        }
        writer?.close();
        if (identical(session.prefetchClient, opened?.client)) {
          session.prefetchClient = null;
        }
        await opened?.close();
      }
    }
    if (prefetched > 0) _logPrefetch(session, 'filled');
    if (resource == null &&
        !session.hls &&
        !session.closed &&
        session.playbackActive &&
        session.prefetchEpoch == epoch &&
        cache.generation == generation &&
        !cache.disabled) {
      _schedulePrefetch(session, key, resource, session.cursor ?? start, total);
    }
  }

  Future<_Opened> _open(
      _RelaySession session, String method, Map<String, List<String>> forwarded,
      {_RelayResource? resource,
      bool allowHls = false,
      int? prefetchEpoch,
      _RelayConsumer? consumer}) async {
    var uri = resource?.uri ?? session.current;
    final budget = _RequestBudget(requestTimeout, session);
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (session.closed ||
          _closed ||
          consumer?.closed == true ||
          !isHttpUri(uri) ||
          (prefetchEpoch != null && session.prefetchEpoch != prefetchEpoch)) {
        throw const PlaybackRelayException();
      }
      if (_manifestPath(uri) && !(allowHls && _hlsPath(uri))) {
        throw unsupportedRelayMedia;
      }
      final client = _client();
      consumer?.clients.add(client);
      if (prefetchEpoch != null) session.prefetchClient = client;
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
        return _Opened(response, client, session, budget, uri, consumer);
      } finally {
        if (!handedOff) {
          client.close(force: true);
          session.clients.remove(client);
          consumer?.clients.remove(client);
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
    session.playlistResources[opened.uri.toString()] = staged.keys.toList();
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

String? _responseValidator(HttpHeaders headers) {
  final etag = headers.value('etag');
  return etag != null && !etag.startsWith('W/')
      ? etag
      : headers.value('last-modified');
}

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
  final responses = <HttpResponse>{};
  Timer? prefetchTimer;
  HttpClient? prefetchClient;
  int prefetchEpoch = 0;
  int foregroundEpoch = 0;
  Completer<void>? prefetchCancelled;
  Future<void>? prefetchTask;
  _PrefetchTransfer? prefetchTransfer;
  bool playbackActive = true;
  bool memoryReady = false;
  Timer? bufferLease;
  (String, _RelayResource?, int, int)? prefetchCandidate;
  bool rangeUnsupported = false;
  int foregroundNetwork = 0;
  int bitrate = 0;
  int? originBytesPerSecond;
  int? cursor;
  PlaybackCachedRange? mediaInfo;
  String? lastPrefetchReason;
  DateTime lastPrefetchLog = DateTime.fromMillisecondsSinceEpoch(0);
  int activeRequests = 0;
  List<int> validatedPrefix = const [];
  bool hls = false;
  final resources = <String, _RelayResource>{};
  final resourcePaths = <String, String>{};
  final playlistResources = <String, List<String>>{};
  int nextResourceId = 0;
  final _cancellations = <void Function()>{};
  String path = '';
  bool closed = false;

  Future<T> wait<T>(Future<T> operation) async {
    final cancelled = Completer<void>();
    void cancel() {
      if (!cancelled.isCompleted) cancelled.complete();
    }

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
    bufferLease?.cancel();
    bufferLease = null;
    memoryReady = false;
    prefetchTimer?.cancel();
    prefetchEpoch++;
    for (final response in responses.toList()) {
      // The response may already have written headers. Closing it works for
      // both states; detachSocket throws once the response has started.
      try {
        unawaited(response.close().catchError((Object _) {}));
      } catch (_) {
        // An active flush owns the sink until cancellation unwinds _serve.
      }
    }
    responses.clear();
    for (final cancel in _cancellations.toList()) {
      cancel();
    }
    _cancellations.clear();
    for (final client in clients.toList()) {
      client.close(force: true);
    }
    clients.clear();
    cookies.clear();
    headers.clear();
    resources.clear();
    resourcePaths.clear();
    playlistResources.clear();
  }
}

// One bounded origin range can be handed to a reader before disk commit.
class _PrefetchTransfer {
  _PrefetchTransfer(
      this.path, this.start, this.end, this.total, this.validator);
  final String path;
  final int start, end, total;
  final String? validator;
  final chunks = <List<int>>[];
  int received = 0;
  bool promoted = false;
  bool finished = false;
  Completer<void> changed = Completer<void>();

  bool contains(String key, int position) =>
      key == path && position >= start && position <= end;

  void add(List<int> bytes) {
    if (finished || received + bytes.length > end - start + 1) return;
    chunks.add(bytes);
    received += bytes.length;
    _notify();
  }

  List<int>? chunkAt(int position, int limit) {
    var offset = position - start;
    for (final chunk in chunks) {
      if (offset < chunk.length) {
        return chunk.sublist(
            offset, min(chunk.length, offset + limit - position + 1));
      }
      offset -= chunk.length;
    }
    return null;
  }

  void finish() {
    finished = true;
    _notify();
  }

  void _notify() {
    final previous = changed;
    changed = Completer<void>();
    previous.complete();
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

// HttpResponse can silently discard add/flush after disconnection. Observe
// both done and connectionInfo so abandoned readers release their origin work.
class _RelayConsumer {
  _RelayConsumer(this.response) {
    unawaited(response.done.then<void>((_) => close(),
        onError: (Object _, StackTrace __) => close()));
    _monitor = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (response.connectionInfo == null) close();
    });
  }

  final HttpResponse response;
  final clients = <HttpClient>{};
  final _cancellations = <void Function()>{};
  Timer? _monitor;
  bool _closed = false;

  bool get closed {
    if (!_closed && response.connectionInfo == null) close();
    return _closed;
  }

  Future<T> wait<T>(Future<T> operation) async {
    final cancelled = Completer<void>();
    void cancel() {
      if (!cancelled.isCompleted) cancelled.complete();
    }

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
    if (_closed) return;
    _closed = true;
    _monitor?.cancel();
    for (final cancel in _cancellations.toList()) {
      cancel();
    }
    _cancellations.clear();
    for (final client in clients.toList()) {
      client.close(force: true);
    }
    clients.clear();
  }
}

class _Opened {
  _Opened(this.response, this.client, this.session, this.budget, this.uri,
      this.consumer)
      : body = StreamIterator(response);
  final HttpClientResponse response;
  final HttpClient client;
  final _RelaySession session;
  final StreamIterator<List<int>> body;
  final _RequestBudget budget;
  final Uri uri;
  final _RelayConsumer? consumer;
  Future<void> close() async {
    client.close(force: true);
    session.clients.remove(client);
    consumer?.clients.remove(client);
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
