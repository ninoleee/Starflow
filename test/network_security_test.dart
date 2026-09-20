import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/network/http_origin_policy.dart';
import 'package:starflow/core/network/starflow_http_client.dart';

void main() {
  final uri = Uri.parse('https://nas.test/api');

  test('HEAD allows large resource length without buffering media', () async {
    final client = StarflowHttpClient(
        MockClient((_) async =>
            http.Response('', 200, headers: {'content-length': '40000000000'})),
        maxResponseBytes: 1);
    final response = await client.head(uri);
    expect(response.headers['content-length'], '40000000000');
    expect(response.bodyBytes, isEmpty);
  });

  test('buffered POST preserves form and byte request bodies', () async {
    final bodies = <String>[];
    final client = StarflowHttpClient(MockClient((request) async {
      bodies.add(request.body);
      return http.Response('ok', 200);
    }));
    await client.post(uri, body: {'q': 'space value'});
    await client.put(uri, body: [65, 66]);
    expect(bodies, ['q=space+value', 'AB']);
  });

  test('authenticated redirect loops are bounded', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.followRedirects, isFalse);
      return http.Response('', 307, headers: {'location': '/loop'});
    });
    await expectLater(
        sendBoundedRequest(client, 'GET', uri,
            headers: {'Authorization': 'Basic synthetic'},
            timeout: const Duration(seconds: 2),
            maxBytes: 10),
        throwsA(isA<http.ClientException>()));
    expect(requests, 6);
  });

  test('origin and directory reject protocol/port/userInfo/path escapes', () {
    final root = Uri.parse('https://nas.test/dav/');
    expect(isSameHttpOrigin(root, Uri.parse('https://NAS.test:443/')), isTrue);
    for (final address in [
      'http://nas.test/dav/a',
      'https://nas.test:444/dav/a',
      'https://u:p@nas.test/dav/a',
      'https://nas.test.evil/dav/a',
      'https://nas.test/dav-other/a',
      'https://nas.test/private/a',
      'https://nas.test/dav/%2e%2e/private',
      'https://nas.test/dav/a%2f..%2fprivate',
      'https://nas.test/dav/%252e%252e/private',
    ]) {
      expect(isWithinHttpDirectory(Uri.parse(address), root), isFalse,
          reason: address);
    }
    expect(isWithinHttpDirectory(Uri.parse('https://nas.test/dav/a%20b'), root),
        isTrue);
  });

  test('buffered API stalls abort body but do not close the shared client',
      () async {
    final transport = _StallingClient();
    final client = StarflowHttpClient(transport,
        requestTimeout: const Duration(milliseconds: 40));
    await expectLater(client.get(uri), throwsA(isA<TimeoutException>()));
    expect(transport.aborted, isTrue);
    expect(transport.cancelled, isTrue);
    expect(transport.closed, isFalse);
    transport.succeed = true;
    expect((await client.get(uri)).body, 'ok');
  });

  test('send preserves media streaming beyond buffered deadline and limit',
      () async {
    final transport = _StallingClient();
    final client = StarflowHttpClient(transport,
        requestTimeout: const Duration(milliseconds: 20), maxResponseBytes: 1);
    final response = await client.send(http.Request('GET', uri));
    final bytes = response.stream.toBytes();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    transport.body.add([1, 2, 3, 4]);
    await transport.body.close();
    expect(await bytes, [1, 2, 3, 4]);
    expect(transport.aborted, isFalse);
  });

  for (final declared in [true, false]) {
    test(
        'bounded body rejects ${declared ? "declared" : "chunked"} oversize and cancels',
        () async {
      final transport = _StallingClient(contentLength: declared ? 9 : null);
      final future = sendBoundedRequest(transport, 'GET', uri,
          timeout: const Duration(seconds: 1), maxBytes: 8);
      final assertion =
          expectLater(future, throwsA(isA<http.ClientException>()));
      if (!declared) transport.body.add(List.filled(9, 1));
      await assertion;
      expect(transport.aborted, isTrue);
      expect(transport.cancelled, isTrue);
    });
  }

  test('explicit cancellation interrupts noncooperative headers and late body',
      () async {
    final pending = Completer<http.StreamedResponse>();
    final transport = _CallbackClient((_) => pending.future);
    final cancel = Completer<void>();
    final future = sendBoundedRequest(transport, 'GET', uri,
        cancel: cancel.future,
        timeout: const Duration(seconds: 5),
        maxBytes: 8);
    final assertion =
        expectLater(future, throwsA(isA<http.RequestAbortedException>()));
    cancel.complete();
    await assertion;
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () {
      cancelled = true;
    });
    pending.complete(http.StreamedResponse(body.stream, 200));
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isTrue);
  });

  test('explicit cancellation interrupts stalled body', () async {
    final transport = _StallingClient();
    final cancel = Completer<void>();
    final future = sendBoundedRequest(transport, 'GET', uri,
        cancel: cancel.future,
        timeout: const Duration(seconds: 5),
        maxBytes: 8);
    final assertion =
        expectLater(future, throwsA(isA<http.RequestAbortedException>()));
    await Future<void>.delayed(Duration.zero);
    cancel.complete();
    await assertion;
    expect(transport.cancelled, isTrue);
    expect(transport.aborted, isTrue);
  });

  test('real IO redirects cannot forward custom auth to another port',
      () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final foreignPort = foreign.port;
    addTearDown(() => origin.close(force: true));
    addTearDown(() => foreign.close(force: true));
    var foreignRequests = 0;
    foreign.listen((request) {
      foreignRequests++;
      request.response.close();
    });
    final seen = <String>[];
    origin.listen((request) {
      seen.add(request.uri.path);
      expect(request.headers.value('x-emby-token'), 'synthetic');
      if (request.uri.path == '/start') {
        request.response.statusCode = 307;
        request.response.headers.set('location', '/next');
      } else {
        request.response.statusCode = 302;
        request.response.headers
            .set('location', 'http://127.0.0.1:$foreignPort/stolen');
      }
      request.response.close();
    });
    final client = IOClient();
    addTearDown(client.close);
    await expectLater(
        sendBoundedRequest(
            client, 'GET', Uri.parse('http://127.0.0.1:${origin.port}/start'),
            headers: {'X-Emby-Token': 'synthetic'},
            timeout: const Duration(seconds: 30),
            maxBytes: 1024),
        throwsA(isA<http.ClientException>()));
    expect(seen, ['/start', '/next']);
    expect(foreignRequests, 0);
  });
}

class _CallbackClient extends http.BaseClient {
  _CallbackClient(this.callback);
  final Future<http.StreamedResponse> Function(http.BaseRequest) callback;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      callback(request);
}

class _StallingClient extends http.BaseClient {
  _StallingClient({this.contentLength}) {
    body = StreamController<List<int>>(onCancel: () {
      cancelled = true;
    });
  }
  final int? contentLength;
  late final StreamController<List<int>> body;
  bool aborted = false;
  bool cancelled = false;
  bool closed = false;
  bool succeed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Abortable) {
      unawaited(request.abortTrigger?.then((_) {
        aborted = true;
      }));
    }
    if (succeed) return http.StreamedResponse(Stream.value([111, 107]), 200);
    return http.StreamedResponse(body.stream, 200,
        contentLength: contentLength);
  }

  @override
  void close() {
    closed = true;
  }
}
