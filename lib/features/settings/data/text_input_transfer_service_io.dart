import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'text_input_transfer_service.dart';

TextInputTransferService createTextInputTransferService() =>
    const IoTextInputTransferService();

class IoTextInputTransferService implements TextInputTransferService {
  const IoTextInputTransferService({
    this.receiveTimeout = const Duration(seconds: 30),
    this.sessionTimeout = const Duration(minutes: 10),
  });
  final Duration receiveTimeout, sessionTimeout;

  @override
  Future<TextInputTransferSession> start({
    required String label,
    bool multiline = false,
    bool obscureText = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    try {
      final random = Random.secure();
      final token =
          base64Url.encode(List.generate(18, (_) => random.nextInt(256)));
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      final hosts = {
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (!address.isLoopback && !address.address.startsWith('169.254.'))
              address.address,
      };
      if (hosts.isEmpty) throw const SocketException('No LAN address');
      final urls = [
        for (final host in hosts)
          Uri(
              scheme: 'http',
              host: host,
              port: server.port,
              path: '/',
              queryParameters: {'token': token}).toString(),
      ]..sort();
      return _Session(
          server,
          token,
          urls,
          _page(token, label, multiline, obscureText),
          receiveTimeout,
          sessionTimeout);
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
  }
}

class _Session implements TextInputTransferSession {
  _Session(this._server, this._token, this.urls, this._html,
      this._receiveTimeout, Duration sessionTimeout) {
    _server.idleTimeout = const Duration(seconds: 10);
    _subscription = _server.listen((request) => unawaited(_handle(request)),
        onError: (Object _) => _report('手机输入连接失败，请重新打开'));
    _expiry = Timer(sessionTimeout, () => unawaited(close()));
  }
  final HttpServer _server;
  final String _token, _html;
  final Duration _receiveTimeout;
  @override
  final List<String> urls;
  final _errors = StreamController<String>.broadcast();
  final _received = Completer<String?>();
  late final StreamSubscription<HttpRequest> _subscription;
  late final Timer _expiry;
  StreamSubscription<List<int>>? _body;
  void Function()? _cancelRead;
  bool _busy = false, _closed = false;
  Future<void>? _closing;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Future<String?> get received => _received.future;

  void _report(String message) {
    if (!_closed) _errors.add(message);
  }

  Future<void> _handle(HttpRequest request) async {
    var ownsRead = false;
    try {
      final hosts = {
        ...urls.map((url) => Uri.parse(url).authority),
        '127.0.0.1:${_server.port}'
      };
      final host = request.headers.value('host');
      final origin = request.headers.value('origin');
      if (!hosts.contains(host) ||
          (origin != null && origin != 'http://$host') ||
          request.uri.queryParameters['token'] != _token) {
        await _reply(request, 403, '地址已失效，请重新扫码');
        return;
      }
      if (_closed || _received.isCompleted) {
        await _reply(request, 410, '本次输入已结束');
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/') {
        request.response.headers.set('Content-Security-Policy',
            "default-src 'none'; script-src 'nonce-$_token'; style-src 'nonce-$_token'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");
        await _reply(request, 200, _html, html: true);
        return;
      }
      if (request.method != 'POST' || request.uri.path != '/input') {
        await _reply(request, 404, '未找到请求路径');
        return;
      }
      if (_busy) {
        await _reply(request, 409, '正在接收，请稍后重试');
        return;
      }
      if (request.headers.contentType?.mimeType != 'text/plain') {
        await _reply(request, 415, '请发送文本');
        return;
      }
      _busy = ownsRead = true;
      final bytes = await _read(request);
      if (_closed) return;
      final text = utf8.decode(bytes);
      await _reply(request, 200, '已发送，请在电视输入窗口确认保存');
      if (!_closed) _received.complete(text);
    } catch (error) {
      if (_closed) return;
      final status = error is _TooLarge
          ? 413
          : error is TimeoutException
              ? 408
              : 400;
      final message = error is _TooLarge
          ? '文本超过 64 KiB'
          : error is TimeoutException
              ? '接收超时，请重试'
              : '文本接收失败，请重试';
      if (ownsRead) _report(message);
      try {
        await _reply(request, status, message);
      } catch (_) {
        // The peer or the owning dialog may already have closed.
      }
    } finally {
      if (ownsRead) {
        await _body?.cancel();
        _body = null;
        _busy = false;
      }
    }
  }

  Future<Uint8List> _read(HttpRequest request) async {
    if (request.contentLength > textInputTransferMaxBytes) {
      throw const _TooLarge();
    }
    final result = Completer<Uint8List>();
    final bytes = BytesBuilder(copy: false);
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    _body = request.listen(
        (chunk) {
          if (result.isCompleted) return;
          if (bytes.length + chunk.length > textInputTransferMaxBytes) {
            fail(const _TooLarge());
          } else {
            bytes.add(chunk);
          }
        },
        onError: (Object error) => fail(error),
        onDone: () {
          if (!result.isCompleted) result.complete(bytes.takeBytes());
        });
    final timer = Timer(_receiveTimeout, () => fail(TimeoutException('input')));
    _cancelRead = () => fail(StateError('closed'));
    try {
      return await result.future;
    } finally {
      timer.cancel();
      _cancelRead = null;
    }
  }

  Future<void> _reply(HttpRequest request, int status, String message,
      {bool html = false}) async {
    final response = request.response;
    response.persistentConnection = false;
    response.statusCode = status;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('X-Frame-Options', 'DENY');
    response.headers.contentType =
        ContentType('text', html ? 'html' : 'plain', charset: 'utf-8');
    response.write(message);
    await response.close();
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _expiry.cancel();
    _cancelRead?.call();
    if (!_received.isCompleted) _received.complete(null);
    await _server.close(force: true);
    await _subscription.cancel();
    await _errors.close();
  }
}

class _TooLarge implements Exception {
  const _TooLarge();
}

String _page(String token, String label, bool multiline, bool secret) {
  final escapedLabel = const HtmlEscape().convert(label);
  final input = multiline && !secret
      ? '<textarea id="input" rows="6" autocomplete="off" spellcheck="false"></textarea>'
      : '<input id="input" type="${secret ? 'password' : 'text'}" autocomplete="off" autocapitalize="none" spellcheck="false">';
  return '''<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Starflow 手机输入</title>
<style nonce="$token">
:root { color-scheme: light; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
* { box-sizing: border-box; }
body { margin: 0; color: #24272b; background: #f6f7f8; }
main { max-width: 640px; margin: 0 auto; padding: 32px 20px; }
h1 { font-size: 24px; margin: 0 0 28px; }
label { display: block; font-weight: 600; margin-bottom: 12px; overflow-wrap: anywhere; }
input, textarea { display: block; width: 100%; min-height: 48px; padding: 12px; font: inherit; border: 1px solid #969da5; border-radius: 6px; background: white; margin-bottom: 20px; }
textarea { resize: vertical; }
button { min-height: 48px; padding: 10px 18px; border: 0; border-radius: 6px; background: #176840; color: white; font: inherit; cursor: pointer; }
button:disabled { opacity: .55; cursor: default; }
#status { min-height: 48px; overflow-wrap: anywhere; }
#status[data-error="true"] { color: #b3261e; }
</style></head><body><main>
<h1>Starflow 手机输入</h1><label for="input">$escapedLabel</label>
$input
<button id="send" type="button">发送到电视</button>
<p id="status" role="status" aria-live="polite"></p>
</main><script nonce="$token">
const input = document.getElementById('input');
const button = document.getElementById('send');
const status = document.getElementById('status');
function show(message, error = false) {
  status.textContent = message; status.dataset.error = String(error);
}
button.addEventListener('click', async () => {
  if (new TextEncoder().encode(input.value).length > $textInputTransferMaxBytes) {
    show('文本超过 64 KiB', true); return;
  }
  button.disabled = input.disabled = true;
  show('正在发送');
  let sent = false;
  try {
    const response = await fetch('/input?token=$token', {
      method: 'POST', headers: {'Content-Type': 'text/plain; charset=utf-8'},
      body: input.value, credentials: 'omit', cache: 'no-store'
    });
    show(await response.text(), !response.ok);
    sent = response.ok;
    if (sent) input.value = '';
  } catch (_) { show('连接已断开，请重新扫码后重试', true); }
  finally { button.disabled = input.disabled = sent; }
});
</script></body></html>''';
}
