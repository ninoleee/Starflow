import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:starflow/features/live_tv/data/live_channel_probe.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';

const _line = LiveLine('https://example.test/live');

void main() {
  test('real HTTP stream returns on first data without waiting for stream end',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = Completer<HttpRequest>();
    server.listen((request) async {
      seen.complete(request);
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType('video', 'mp2t');
      request.response.add(List.filled(188, 0x47));
      await request.response.flush();
    });
    final result = await LiveChannelProbe().probe(
        LiveLine('http://127.0.0.1:${server.port}/live'),
        cancel: Completer<void>().future);
    expect(result.status, LiveProbeStatus.responded);
    final request = await seen.future;
    expect(request.headers.value('range'), 'bytes=0-1023');
    expect(request.headers.value('user-agent'), 'Starflow');
  });

  test('real connection waiting for headers is cancelled promptly', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = Completer<void>();
    server.listen((_) => seen.complete());
    final cancel = Completer<void>();
    final pending = LiveChannelProbe().probe(
        LiveLine('http://127.0.0.1:${server.port}/live'),
        cancel: cancel.future);
    await seen.future;
    cancel.complete();
    expect((await pending.timeout(const Duration(seconds: 1))).status,
        LiveProbeStatus.cancelled);
  });

  test('GET measures first nonempty chunk and closes an endless response',
      () async {
    var bodyCancelled = false;
    final stream =
        StreamController<List<int>>(onCancel: () => bodyCancelled = true);
    final client = _Client((request) async {
      expect(request.method, 'GET');
      expect(request.headers['range'], 'bytes=0-1023');
      expect(request.headers['user-agent'], 'Starflow');
      expect(request.followRedirects, isFalse);
      stream.add([]);
      stream.add(List.filled(8192, 1));
      return http.StreamedResponse(stream.stream, 200,
          contentLength: 999999999);
    });
    final result = await LiveChannelProbe(clientFactory: () => client)
        .probe(_line, cancel: Completer<void>().future);
    expect(result.status, LiveProbeStatus.responded);
    expect(result.latency, isNotNull);
    expect(result.label, endsWith(' ms'));
    expect(client.closed, isTrue);
    expect(bodyCancelled, isTrue);
    await stream.close();
  });

  for (final status in [403, 404, 500]) {
    test('HTTP $status is reported without reading the body', () async {
      final client = _Client(
          (_) async => http.StreamedResponse(const Stream.empty(), status));
      final result = await LiveChannelProbe(clientFactory: () => client)
          .probe(_line, cancel: Completer<void>().future);
      expect(result.status, LiveProbeStatus.httpError);
      expect(result.label, 'HTTP $status');
      expect(client.closed, isTrue);
    });
  }

  test('empty and HTML responses are not successful media responses', () async {
    for (final html in [false, true]) {
      final client = _Client((_) async => http.StreamedResponse(
          const Stream.empty(), 200,
          headers: html ? {'content-type': 'text/html; charset=utf-8'} : {}));
      final result = await LiveChannelProbe(clientFactory: () => client)
          .probe(_line, cancel: Completer<void>().future);
      expect(result.status,
          html ? LiveProbeStatus.nonMedia : LiveProbeStatus.empty);
    }
  });

  test('timeout includes waiting for headers and first data', () async {
    for (final headers in [false, true]) {
      final body = StreamController<List<int>>();
      final client = _Client((_) => headers
          ? Future.value(http.StreamedResponse(body.stream, 200))
          : Completer<http.StreamedResponse>().future);
      final result = await LiveChannelProbe(
              clientFactory: () => client,
              timeout: const Duration(milliseconds: 20))
          .probe(_line, cancel: Completer<void>().future);
      expect(result.status, LiveProbeStatus.timeout);
      expect(client.closed, isTrue);
      unawaited(body.close());
    }
  });

  test('cancel closes transport and rejects late headers', () async {
    final cancel = Completer<void>();
    final headers = Completer<http.StreamedResponse>();
    final client = _Client((_) => headers.future);
    final pending = LiveChannelProbe(clientFactory: () => client)
        .probe(_line, cancel: cancel.future);
    cancel.complete();
    expect((await pending).status, LiveProbeStatus.cancelled);
    expect(client.closed, isTrue);
    var discarded = false;
    final body = StreamController<List<int>>(onCancel: () => discarded = true);
    headers.complete(http.StreamedResponse(body.stream, 200));
    await Future<void>.delayed(Duration.zero);
    expect(discarded, isTrue);
    await body.close();
  });

  test('cancel closes client immediately and awaits response cleanup',
      () async {
    final cleanup = Completer<void>();
    final listening = Completer<void>();
    final body = StreamController<List<int>>(
        onListen: () => listening.complete(), onCancel: () => cleanup.future);
    final client =
        _Client((_) async => http.StreamedResponse(body.stream, 200));
    final cancel = Completer<void>();
    var finished = false;
    final pending = LiveChannelProbe(clientFactory: () => client)
        .probe(_line, cancel: cancel.future)
        .then((result) {
      finished = true;
      return result;
    });
    await listening.future;
    cancel.complete();
    await Future<void>.delayed(Duration.zero);
    expect(client.closed, isTrue);
    expect(finished, isFalse);
    cleanup.complete();
    expect((await pending).status, LiveProbeStatus.cancelled);
    await body.close();
  });

  test('slow cleanup reports safely and does not pretend to have completed',
      () async {
    final cleanup = Completer<void>();
    final listening = Completer<void>();
    final slow = Completer<void>();
    final events = <String>[];
    final fields = <Map<String, Object?>>[];
    final body = StreamController<List<int>>(
        onListen: listening.complete, onCancel: () => cleanup.future);
    final client =
        _Client((_) async => http.StreamedResponse(body.stream, 200));
    final cancel = Completer<void>();
    var finished = false;
    final pending = LiveChannelProbe(
            clientFactory: () => client,
            cleanupWarningAfter: const Duration(milliseconds: 10),
            diagnostics: (event, data) {
              events.add(event);
              fields.add(data);
              if (event == 'slow') slow.complete();
            })
        .probe(
            const LiveLine('https://private.test/live?token=secret',
                headers: {'Authorization': 'private-token'}),
            cancel: cancel.future)
        .then((result) {
      finished = true;
      return result;
    });
    await listening.future;
    cancel.complete();
    await slow.future.timeout(const Duration(seconds: 1));
    expect(client.closed, isTrue);
    expect(finished, isFalse);
    expect(events, ['slow']);
    cleanup.complete();
    await pending;
    expect(events, ['slow', 'complete']);
    expect(fields.last['elapsedMs'], isA<int>());
    expect(fields.toString(), isNot(contains('private')));
    expect(fields.toString(), isNot(contains('secret')));
    await body.close();
  });

  test(
      'real connection waiting for body is cancelled without waiting for deadline',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final sent = Completer<void>();
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType('video', 'mp2t');
      await request.response.flush();
      sent.complete();
    });
    final cancel = Completer<void>();
    final pending = LiveChannelProbe().probe(
        LiveLine('http://127.0.0.1:${server.port}/live'),
        cancel: cancel.future);
    await sent.future;
    cancel.complete();
    expect((await pending.timeout(const Duration(seconds: 1))).status,
        LiveProbeStatus.cancelled);
  });

  test('cross-origin redirects strip media credentials and custom headers',
      () async {
    final requests = <http.BaseRequest>[];
    final client = _Client((request) async {
      requests.add(request);
      if (requests.length == 1) {
        return http.StreamedResponse(const Stream.empty(), 302,
            headers: {'location': '/same'});
      }
      if (requests.length == 2) {
        return http.StreamedResponse(const Stream.empty(), 307,
            headers: {'location': 'https://cdn.test/live'});
      }
      return http.StreamedResponse(Stream.value([1]), 206);
    });
    final result = await LiveChannelProbe(clientFactory: () => client).probe(
        const LiveLine('https://example.test/live', headers: {
          'Authorization': 'secret',
          'Cookie': 'session',
          'Referer': 'private',
          'Origin': 'private',
          'X-Custom-Secret': 'private',
          'user-agent': 'Custom',
        }),
        cancel: Completer<void>().future);
    expect(result.status, LiveProbeStatus.responded);
    expect(requests, hasLength(3));
    expect(requests[1].headers['authorization'], 'secret');
    expect({
      for (final e in requests[2].headers.entries) e.key.toLowerCase(): e.value
    }, {
      'user-agent': 'Custom',
      'range': 'bytes=0-1023'
    });
  });

  for (final location in [
    'file:///etc/passwd',
    'http://example.test/live',
    '/loop'
  ]) {
    test('unsafe or looping redirect is bounded: $location', () async {
      var requests = 0;
      final client = _Client((_) async {
        requests++;
        return http.StreamedResponse(const Stream.empty(), 302,
            headers: {'location': location});
      });
      final result = await LiveChannelProbe(clientFactory: () => client)
          .probe(_line, cancel: Completer<void>().future);
      expect(result.status, LiveProbeStatus.redirectBlocked);
      expect(requests, lessThanOrEqualTo(4));
      expect(client.closed, isTrue);
    });
  }

  test('invalid URL is rejected before a client is created', () async {
    final probe =
        LiveChannelProbe(clientFactory: () => throw StateError('must not run'));
    for (final url in [
      'file:///tmp/live',
      'https://user:pass@example.test/live'
    ]) {
      expect(
          (await probe.probe(LiveLine(url), cancel: Completer<void>().future))
              .status,
          LiveProbeStatus.invalidUrl);
    }
  });
}

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() => closed = true;
}
