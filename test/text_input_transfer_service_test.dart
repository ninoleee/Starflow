import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/settings/data/text_input_transfer_service.dart';
import 'package:starflow/features/settings/data/text_input_transfer_service_io.dart';

void main() {
  Future<TextInputTransferSession> start(
      {bool multiline = false,
      bool secret = false,
      Duration timeout = const Duration(seconds: 30),
      Duration expiry = const Duration(minutes: 10)}) async {
    final s = await IoTextInputTransferService(
            receiveTimeout: timeout, sessionTimeout: expiry)
        .start(
            label: '<script>private</script>',
            multiline: multiline,
            obscureText: secret);
    addTearDown(s.close);
    return s;
  }

  Future<(int, String)> request(TextInputTransferSession s,
      {String path = '/input',
      String method = 'POST',
      String? token,
      String? host,
      String? origin,
      String type = 'text/plain',
      List<int> bytes = const [],
      bool declared = true}) async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    var url = Uri.parse(s.urls.first).replace(host: '127.0.0.1', path: path);
    if (token != null) url = url.replace(queryParameters: {'token': token});
    final req = await client.openUrl(method, url);
    req.headers.set('Content-Type', type);
    if (host != null) req.headers.set('Host', host);
    if (origin != null) req.headers.set('Origin', origin);
    if (declared) req.contentLength = bytes.length;
    req.add(bytes);
    final response = await req.close();
    return (response.statusCode, await utf8.decoder.bind(response).join());
  }

  test('page escapes labels, masks secrets and contains no existing values',
      () async {
    final s = await start(secret: true);
    final page = await request(s, path: '/', method: 'GET');
    expect(page.$1, 200);
    expect(page.$2,
        contains(const HtmlEscape().convert('<script>private</script>')));
    expect(page.$2, isNot(contains('<script>private</script>')));
    expect(page.$2, contains('type="password"'));
    expect(page.$2, isNot(contains('navigator.clipboard')));
    expect(page.$2, isNot(contains('src="https://')));
    expect(page.$2, contains("if (sent) input.value = ''"));
    final multi = await start(multiline: true);
    expect((await request(multi, path: '/', method: 'GET')).$2,
        contains('<textarea'));
  });

  for (final text in [
    '',
    '  password with spaces  ',
    '频道\nhttps://test/a?key=x\n'
  ]) {
    test('text remains exact and is only accepted once: ${text.length}',
        () async {
      final s = await start();
      final result = await request(s, bytes: utf8.encode(text));
      expect(result.$1, 200);
      expect(result.$2, '已发送，请在电视输入窗口确认保存');
      expect(await s.received, text);
      expect((await request(s)).$1, 410);
    });
  }

  test('token, host, origin, type and invalid UTF-8 do not consume session',
      () async {
    final s = await start();
    expect((await request(s, token: 'wrong')).$1, 403);
    expect((await request(s, host: 'evil.test')).$1, 403);
    expect((await request(s, origin: 'https://evil.test')).$1, 403);
    expect((await request(s, type: 'application/json')).$1, 415);
    expect((await request(s, path: '/upload')).$1, 404);
    expect((await request(s, bytes: [255])).$1, 400);
    expect((await request(s, bytes: utf8.encode('valid'))).$1, 200);
    expect(await s.received, 'valid');
  });

  for (final declared in [true, false]) {
    test('64 KiB body limit, declared=$declared', () async {
      final s = await start();
      final result = await request(s,
          declared: declared,
          bytes: List.filled(textInputTransferMaxBytes + 1, 65));
      expect(result.$1, 413);
      expect(result.$2, '文本超过 64 KiB');
      expect((await request(s)).$1, 200);
      expect(await s.received, '');
    });
  }

  test('close and expiry invalidate the server and return no input', () async {
    final s = await start();
    await s.close();
    await s.close();
    expect(await s.received, isNull);
    await expectLater(request(s), throwsA(isA<SocketException>()));
    final expired = await start(expiry: const Duration(milliseconds: 40));
    expect(await expired.received.timeout(const Duration(seconds: 2)), isNull);
  });

  for (final cancel in [true, false]) {
    test(
        'in-flight input is exclusive and can ${cancel ? 'cancel' : 'time out'}',
        () async {
      final s = await start(timeout: const Duration(milliseconds: 300));
      final root = Uri.parse(s.urls.first).replace(host: '127.0.0.1');
      final socket = await Socket.connect(root.host, root.port);
      addTearDown(socket.destroy);
      socket.listen((_) {});
      socket.write('POST /input?${root.query} HTTP/1.1\r\n'
          'Host: ${root.authority}\r\nContent-Type: text/plain\r\n'
          'Content-Length: 100\r\n\r\nx');
      final error = s.errors.first
          .then<String?>((value) => value, onError: (Object _) => null);
      await socket.flush();
      await request(s, path: '/', method: 'GET');
      expect((await request(s)).$1, 409);
      if (cancel) {
        await s.close();
        expect(await s.received, isNull);
        // A cancelled session closes the error stream without an event.
        expect(await error, isNull);
      } else {
        expect(await error, '接收超时，请重试');
        expect((await request(s)).$1, 200);
      }
    });
  }
}
