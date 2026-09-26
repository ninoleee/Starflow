import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/playback/application/playback_relay_disk_cache.dart';
import 'package:starflow/features/playback/application/playback_stream_relay_service_io.dart';
import 'package:starflow/features/playback/domain/playback_models.dart';

const _totalBytes = 16 * 1024;
const _cachedBytes = 8 * 1024;
const _wait = Duration(seconds: 5);

enum _Layout { partialSpan, sixteenBlocks }

enum _Validator { etag, lastModified }

enum _Invalidation { clear, truncatedFile }

void main() {
  for (final layout in _Layout.values) {
    for (final validator in _Validator.values) {
      for (final invalidation in _Invalidation.values) {
        final scenario = '${layout.name}, ${validator.name}, '
            '${invalidation.name}';
        for (final honorIfRange in [true, false]) {
          test(
              'rejects same-size changed origin after cached bytes: '
              '$scenario, honorIfRange=$honorIfRange', () async {
            await _exercise(
              layout: layout,
              validator: validator,
              invalidation: invalidation,
              changeOrigin: true,
              honorIfRange: honorIfRange,
            );
          });
        }
        test('unchanged origin completes without splicing: $scenario',
            () async {
          await _exercise(
            layout: layout,
            validator: validator,
            invalidation: invalidation,
            changeOrigin: false,
            honorIfRange: true,
          );
        });
      }
    }
  }
}

Future<void> _exercise({
  required _Layout layout,
  required _Validator validator,
  required _Invalidation invalidation,
  required bool changeOrigin,
  required bool honorIfRange,
}) async {
  final fixture = await _Fixture.create(validator, honorIfRange);
  addTearDown(fixture.close);
  final relay = createPlaybackStreamRelayService(diskCache: fixture.cache);
  addTearDown(relay.close);
  final target = await relay.prepareTarget(fixture.target);
  final relayUri = Uri.parse(target.streamUrl);
  expect(relayUri.port, isNot(fixture.server.port));

  // Sixteen small files exercise the handle-limited read path without a
  // 32 MiB fixture; one partial span exercises gap filling instead.
  final blockBytes = layout == _Layout.sixteenBlocks ? 512 : _cachedBytes;
  for (var start = 0; start < _cachedBytes; start += blockBytes) {
    await fixture.seed(relayUri.path, start, blockBytes);
  }
  expect(fixture.cache.storedBytes, _cachedBytes);
  final boundedRead = await fixture.cache.read(relayUri.path, null);
  if (layout == _Layout.sixteenBlocks) {
    expect(boundedRead, isNotNull);
    expect(boundedRead!.end, _cachedBytes - 1);
    await boundedRead.close();
  } else {
    expect(boundedRead, isNull);
  }

  var prefixBytes = _cachedBytes;
  if (invalidation == _Invalidation.truncatedFile) {
    // Preserve metadata but shorten a real file. The read must deliver an old
    // prefix before reaching EOF and disabling the disk cache itself.
    const retainedBytes = 128;
    final files = await fixture.root
        .list(recursive: true)
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    final lastBlockStart = _cachedBytes - blockBytes;
    final expectedBlock =
        fixture.original.sublist(lastBlockStart, _cachedBytes);
    final matches = <File>[];
    for (final file in files) {
      if (_sameBytes(await file.readAsBytes(), expectedBlock)) {
        matches.add(file);
      }
    }
    expect(matches, hasLength(1));
    final handle = await matches.single.open(mode: FileMode.writeOnlyAppend);
    try {
      await handle.truncate(retainedBytes);
    } finally {
      await handle.close();
    }
    prefixBytes = lastBlockStart + retainedBytes;
  }

  final gate = _RequestGate('bytes=$prefixBytes-${_totalBytes - 1}');
  fixture.gate = gate;
  final generation = fixture.cache.generation;
  final client = HttpClient();
  addTearDown(() => client.close(force: true));
  // Release an outstanding origin handler before relay.close, even if an
  // assertion fails while the request is held at the gate.
  addTearDown(gate.release);
  final request = await client.getUrl(relayUri).timeout(_wait);
  final response = await request.close().timeout(_wait);
  expect(response.statusCode, HttpStatus.ok);
  expect(response.contentLength, _totalBytes);
  final prefixReceived = Completer<void>();
  final completed = _receive(response, prefixBytes, prefixReceived);
  final upstream = await gate.entered.future.timeout(_wait);
  await prefixReceived.future.timeout(_wait);
  expect(fixture.cache.hitBytes, prefixBytes);

  if (invalidation == _Invalidation.clear) {
    await fixture.cache.clear().timeout(_wait);
    expect(fixture.cache.disabled, isFalse);
  } else {
    expect(fixture.cache.disabled, isTrue);
    expect(fixture.cache.disabledReason, 'read_failure');
    await fixture.cache.flushWrites().timeout(_wait);
  }
  expect(fixture.cache.generation, greaterThan(generation));
  expect(fixture.cache.storedBytes, 0);
  if (changeOrigin) fixture.changed = true;
  gate.release();

  final received = await completed.timeout(_wait);
  if (changeOrigin) {
    // A complete old-prefix/new-suffix body is a failure even if the cache was
    // disabled. Check the actual client stream, not just cache bookkeeping.
    expect(received.bytes.length, prefixBytes,
        reason: 'Changed-origin bytes must never follow the cached prefix. '
            'Origin status: ${gate.statusCode}; stream error: ${received.error}');
    expect(received.bytes, orderedEquals(fixture.original.take(prefixBytes)));
    expect(received.error, isA<HttpException>(),
        reason: 'The advertised response must terminate as incomplete.');
    expect(received.bytes.length, lessThan(response.contentLength));
    expect(gate.statusCode,
        honorIfRange ? HttpStatus.ok : HttpStatus.partialContent);
  } else {
    expect(received.error, isNull);
    expect(received.bytes, orderedEquals(fixture.original));
    expect(gate.statusCode, HttpStatus.partialContent);
    if (invalidation == _Invalidation.clear) {
      expect(fixture.cache.disabled, isFalse);
      expect(fixture.cache.disabledReason, isNull);
    }
  }
  expect(
      upstream.headers.value(HttpHeaders.ifRangeHeader), fixture.oldValidator,
      reason: 'Response identity survives cache invalidation.');
}

bool _sameBytes(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((index) => a[index] == b[index]);

Future<({Uint8List bytes, Object? error})> _receive(HttpClientResponse response,
    int prefixBytes, Completer<void> prefixReceived) async {
  final bytes = BytesBuilder(copy: false);
  Object? error;
  try {
    await for (final chunk in response.timeout(_wait)) {
      bytes.add(chunk);
      if (bytes.length >= prefixBytes && !prefixReceived.isCompleted) {
        prefixReceived.complete();
      }
    }
  } catch (caught) {
    error = caught;
  }
  return (bytes: bytes.takeBytes(), error: error);
}

class _RequestGate {
  _RequestGate(this.range);

  final String range;
  final entered = Completer<HttpRequest>();
  final _released = Completer<void>();
  int? statusCode;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  Future<void> hold(HttpRequest request) async {
    entered.complete(request);
    await _released.future;
  }
}

class _Fixture {
  _Fixture(this.root, this.server, this.validator, this.honorIfRange)
      : cache = PlaybackRelayDiskCache(
          capacityBytes: 64 * 1024,
          directoryProvider: () => root.createTemp('session-'),
          freeBytes: () async => 1024 * 1024 * 1024,
        );

  final Directory root;
  final HttpServer server;
  final PlaybackRelayDiskCache cache;
  final _Validator validator;
  final bool honorIfRange;
  final original = _media(false);
  final replacement = _media(true);
  final _handlers = <Future<void>>{};
  final _serverErrors = <Object>[];
  _RequestGate? gate;
  bool changed = false;

  String get oldValidator => validator == _Validator.etag
      ? '"original"'
      : 'Mon, 01 Jun 2026 00:00:00 GMT';
  String get currentValidator => !changed
      ? oldValidator
      : validator == _Validator.etag
          ? '"replacement"'
          : 'Tue, 02 Jun 2026 00:00:00 GMT';

  PlaybackTarget get target => PlaybackTarget(
        title: 'Integrity test',
        sourceId: 'integrity',
        sourceName: 'integrity',
        sourceKind: MediaSourceKind.nas,
        streamUrl: 'http://127.0.0.1:${server.port}/video',
      );

  static Future<_Fixture> create(
      _Validator validator, bool honorIfRange) async {
    final root = await Directory.systemTemp.createTemp('relay-integrity-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _Fixture(root, server, validator, honorIfRange);
    server.listen((request) {
      final task = fixture._serve(request);
      fixture._handlers.add(task);
      unawaited(task.then<void>((_) => fixture._handlers.remove(task),
          onError: (Object error, StackTrace _) {
        fixture._handlers.remove(task);
        fixture._serverErrors.add(error);
      }));
    });
    return fixture;
  }

  static Uint8List _media(bool changed) {
    final bytes = Uint8List.fromList(List<int>.generate(_totalBytes,
        (index) => (index * 17 + index ~/ 251 + (changed ? 113 : 0)) % 256));
    bytes.setRange(4, 8, ascii.encode('ftyp'));
    return bytes;
  }

  Future<void> _serve(HttpRequest request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final activeGate = gate;
    final held = request.uri.path == '/video' &&
        activeGate != null &&
        range == activeGate.range &&
        !activeGate.entered.isCompleted;
    if (held) await activeGate.hold(request);

    // Select headers and body only after release so the mutation necessarily
    // occurs between the old cached prefix and this actual origin response.
    final bytes = changed ? replacement : original;
    final ifRange = request.headers.value(HttpHeaders.ifRangeHeader);
    final parsed = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range ?? '');
    final partial = parsed != null &&
        (!honorIfRange || ifRange == null || ifRange == currentValidator);
    final start = partial ? int.parse(parsed[1]!) : 0;
    final end = partial && parsed[2]!.isNotEmpty
        ? int.parse(parsed[2]!).clamp(start, bytes.length - 1)
        : bytes.length - 1;
    final response = request.response;
    response.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers.contentType = ContentType('video', 'mp4');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(
        validator == _Validator.etag
            ? HttpHeaders.etagHeader
            : HttpHeaders.lastModifiedHeader,
        currentValidator);
    response.contentLength = end - start + 1;
    if (partial) {
      response.headers.set(
          HttpHeaders.contentRangeHeader, 'bytes $start-$end/${bytes.length}');
    }
    if (held) activeGate.statusCode = response.statusCode;
    response.add(Uint8List.sublistView(bytes, start, end + 1));
    try {
      await response.close();
    } on SocketException {
      // Rejection intentionally closes the origin socket before consuming it.
    } on HttpException {
      // The prepare probe may also stop after the bounded media prefix.
    }
  }

  Future<void> seed(String key, int start, int length) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/seed'));
      request.headers
          .set(HttpHeaders.rangeHeader, 'bytes=$start-${start + length - 1}');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.partialContent);
      final writer = cache.writer(key, response.statusCode, response.headers)!;
      try {
        await for (final chunk in response) {
          await writer.add(chunk);
        }
      } finally {
        writer.close();
      }
      await cache.flushWrites();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> close() async {
    gate?.release();
    await server.close(force: true);
    await Future.wait(_handlers.toList()).timeout(_wait);
    await cache.close();
    if (await root.exists()) await root.delete(recursive: true);
    expect(_serverErrors, isEmpty);
  }
}
