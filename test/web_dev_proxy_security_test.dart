import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/network/http_origin_policy.dart';
import 'package:starflow/core/network/starflow_http_client.dart';

import '../tool/web_dev_proxy.dart';

void main() {
  late HttpServer upstream;
  late HttpServer foreign;
  late HttpServer proxy;
  late StarflowHttpClient client;
  late Uri root;
  late Uri proxyRoot;
  late List<String> seen;
  late List<String> bodies;
  late List<Map<String, String>> headers;
  late int foreignRequests;

  setUp(() async {
    seen = [];
    bodies = [];
    headers = [];
    foreignRequests = 0;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    root = Uri.parse('http://127.0.0.1:${upstream.port}/dav/');
    proxyRoot = Uri.parse('http://127.0.0.1:${proxy.port}');
    foreign.listen((request) async {
      foreignRequests++;
      await request.response.close();
    });
    proxy.listen(handleWebDevProxyRequest);
    upstream.listen((request) async {
      seen.add(request.uri.path);
      bodies.add(await utf8.decoder.bind(request).join());
      final captured = <String, String>{};
      request.headers.forEach((key, values) => captured[key] = values.join(','));
      headers.add(captured);
      if (request.uri.path.endsWith('/start')) {
        request.response.statusCode = 307;
        request.response.headers.set('location', 'next');
      } else if (request.uri.path.endsWith('/foreign')) {
        request.response.statusCode = 302;
        request.response.headers.set(
            'location', 'http://127.0.0.1:${foreign.port}/stolen');
      } else if (request.uri.path.endsWith('/escape')) {
        request.response.statusCode = 307;
        request.response.headers.set('location', '/private/');
      } else if (request.uri.path.endsWith('/loop')) {
        request.response.statusCode = 307;
        request.response.headers.set('location', 'loop');
      } else {
        request.response.statusCode = 207;
        request.response.headers.set('x-starflow-proxy-status', '302');
        request.response.headers.set('x-starflow-proxy-location', '/spoofed');
        request.response.write('ok');
      }
      await request.response.close();
    });
    client = StarflowHttpClient.withWebProxyForTesting(IOClient(),
        proxyBase: proxyRoot.toString());
  });

  tearDown(() async {
    client.close();
    await proxy.close(force: true);
    await upstream.close(force: true);
    await foreign.close(force: true);
  });

  test('bounded authenticated PROPFIND follows same-origin hops through proxy',
      () async {
    final response = await sendBoundedRequest(client, 'PROPFIND', root.resolve('start'),
        headers: {'Authorization': 'Basic synthetic', 'Depth': '1'},
        body: '<propfind/>',
        allowUri: (uri) => isWithinHttpDirectory(uri, root),
        timeout: const Duration(seconds: 5), maxBytes: 100);
    expect(response.statusCode, 207);
    expect(response.body, 'ok');
    expect(response.headers['location'], isNull);
    expect(seen, ['/dav/start', '/dav/next']);
    expect(bodies, ['<propfind/>', '<propfind/>']);
    expect(headers.every((h) => h['authorization'] == 'Basic synthetic'), isTrue);
    expect(headers.every((h) => h.keys.every((k) => !k.startsWith('x-starflow-'))), isTrue);
  });

  for (final auth in [
    {'X-Emby-Token': 'synthetic'},
    {'Authorization': 'Basic synthetic'},
    {'Cookie': 'session=synthetic'},
    {'Authx': 'synthetic'},
    {'Trim-MC-token': 'synthetic'},
  ]) {
    test('proxy refuses foreign redirect for ${auth.keys.single}', () async {
      await expectLater(client.get(root.resolve('foreign'), headers: auth),
          throwsA(isA<http.ClientException>()));
      expect(seen, ['/dav/foreign']);
      expect(foreignRequests, 0);
      expect(headers.single[auth.keys.single.toLowerCase()], auth.values.single);
    });
  }

  test('permissive allowUri cannot override credential origin boundary', () async {
    await expectLater(sendBoundedRequest(client, 'GET', root.resolve('foreign'),
        headers: {'X-Emby-Token': 'synthetic'}, allowUri: (_) => true,
        timeout: const Duration(seconds: 5), maxBytes: 100),
        throwsA(isA<http.ClientException>()));
    expect(foreignRequests, 0);
  });

  test('proxy preserves directory checks and bounded redirect count', () async {
    for (final path in ['escape', 'loop']) {
      seen.clear();
      await expectLater(sendBoundedRequest(client, 'GET', root.resolve(path),
          allowUri: (uri) => isWithinHttpDirectory(uri, root),
          timeout: const Duration(seconds: 5), maxBytes: 100),
          throwsA(isA<http.ClientException>()));
      expect(seen.length, path == 'loop' ? 6 : 1);
    }
  });

  test('raw no-redirect request exposes upstream status without following', () async {
    final request = http.Request('GET', root.resolve('foreign'))
      ..followRedirects = false;
    final response = await client.send(request);
    expect(response.statusCode, 302);
    expect(response.request, same(request));
    expect(response.headers['location'], contains(':${foreign.port}/stolen'));
    await response.stream.drain<void>();
    expect(foreignRequests, 0);
  });

  test('wire envelope is HTTP 200 with no browser-visible Location', () async {
    final direct = IOClient();
    addTearDown(direct.close);
    final response = await direct.get(proxyRoot.replace(path: '/proxy-v1',
        queryParameters: {'url': root.resolve('foreign').toString()}));
    expect(response.statusCode, 200);
    expect(response.headers['location'], isNull);
    expect(response.headers['x-starflow-proxy-status'], '302');
    expect(response.headers['access-control-expose-headers'], '*');
    expect(foreignRequests, 0);
  });

  test('legacy media proxy refuses credential redirects including query tokens', () async {
    final direct = IOClient();
    addTearDown(direct.close);
    for (final queryAuth in [true, false]) {
      final response = await direct.get(proxyRoot.replace(path: '/proxy',
          queryParameters: {
            'url': root.resolve(queryAuth ? 'foreign?api_key=synthetic' : 'foreign').toString(),
            if (!queryAuth) 'headers': base64Url.encode(utf8.encode(jsonEncode({'X-Emby-Token': 'synthetic'}))),
          }));
      expect(response.statusCode, 502);
      expect(response.headers['location'], isNull);
    }
    expect(foreignRequests, 0);
  });

  test('proxy rejects userInfo and non-HTTP targets before connecting', () async {
    final direct = IOClient();
    addTearDown(direct.close);
    for (final url in ['file:///etc/passwd', root.replace(userInfo: 'u:p').toString()]) {
      final response = await direct.get(proxyRoot.replace(path: '/proxy-v1', queryParameters: {'url': url}));
      expect(response.statusCode, 400);
    }
    expect(seen, isEmpty);
  });

  test('CORS preflight supports authenticated API and WebDAV requests', () async {
    final direct = IOClient();
    addTearDown(direct.close);
    final response = await direct.send(http.Request('OPTIONS', proxyRoot.resolve('/proxy-v1')));
    expect(response.statusCode, 204);
    expect(response.headers['access-control-allow-methods'], contains('MKCOL'));
    for (final header in ['Authx', 'Trim-MC-token', 'If-Match', 'If-None-Match', 'Cache-Control']) {
      expect(response.headers['access-control-allow-headers'], contains(header));
    }
    await response.stream.drain<void>();
  });

  test('old proxy fails closed on versioned path without credentials in URL', () async {
    final transport = MockClient((request) async {
      expect(request.url.path, '/proxy-v1');
      expect(request.url.queryParameters.containsKey('headers'), isFalse);
      expect(request.followRedirects, isFalse);
      return http.Response('Not Found', 404);
    });
    final old = StarflowHttpClient.withWebProxyForTesting(transport, proxyBase: 'http://localhost:8787');
    addTearDown(old.close);
    await expectLater(old.get(root, headers: {'Authorization': 'Basic synthetic'}),
        throwsA(isA<http.ClientException>()));
  });

  test('proxy transport forwards cancellation without closing shared client', () async {
    final aborted = Completer<void>();
    final transport = _AbortClient(aborted);
    final wrapped = StarflowHttpClient.withWebProxyForTesting(transport,
        proxyBase: 'http://localhost:8787', requestTimeout: const Duration(milliseconds: 30));
    await expectLater(wrapped.get(root, headers: {'Authorization': 'Basic synthetic'}),
        throwsA(isA<TimeoutException>()));
    await aborted.future.timeout(const Duration(seconds: 1));
    expect(transport.closed, isFalse);
    wrapped.close();
  });
}

class _AbortClient extends http.BaseClient {
  _AbortClient(this.aborted);
  final Completer<void> aborted;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    await (request as http.Abortable).abortTrigger;
    aborted.complete();
    throw http.RequestAbortedException(request.url);
  }

  @override
  void close() => closed = true;
}
