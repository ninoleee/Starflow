import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'live_playlist_parser.dart';
import 'live_playlist_transfer_service.dart';

LivePlaylistTransferService createLivePlaylistTransferService() =>
    const IoLivePlaylistTransferService();

class IoLivePlaylistTransferService implements LivePlaylistTransferService {
  const IoLivePlaylistTransferService({
    this.uploadTimeout = const Duration(seconds: 30),
    this.sessionTimeout = const Duration(minutes: 10),
  });

  final Duration uploadTimeout;
  final Duration sessionTimeout;

  @override
  Future<LivePlaylistTransferSession> start() async {
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
      if (hosts.isEmpty) {
        throw const SocketException('No LAN address');
      }
      final urls = [
        for (final host in hosts)
          Uri(
              scheme: 'http',
              host: host,
              port: server.port,
              path: '/',
              queryParameters: {'token': token}).toString(),
      ]..sort();
      return _Session(server, token, urls, uploadTimeout, sessionTimeout);
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
  }
}

class _Session implements LivePlaylistTransferSession {
  _Session(this._server, this._token, this.urls, this._uploadTimeout,
      Duration sessionTimeout) {
    _server.idleTimeout = const Duration(seconds: 10);
    _subscription = _server.listen((request) => unawaited(_handle(request)),
        onError: (Object _) => _report('手机传输连接失败，请重新打开'));
    _expiry = Timer(sessionTimeout, () => unawaited(close()));
  }

  final HttpServer _server;
  final String _token;
  final Duration _uploadTimeout;
  @override
  final List<String> urls;
  final _errors = StreamController<String>.broadcast();
  final _received = Completer<LivePlaylistUpload?>();
  late final StreamSubscription<HttpRequest> _subscription;
  late final Timer _expiry;
  bool _busy = false;
  bool _closed = false;
  Future<void>? _closing;
  VoidCallback? _cancelRead;
  StreamSubscription<List<int>>? _readSubscription;

  @override
  Stream<String> get errors => _errors.stream;
  @override
  Future<LivePlaylistUpload?> get received => _received.future;

  void _report(String message) {
    if (!_closed) _errors.add(message);
  }

  Future<void> _handle(HttpRequest request) async {
    var ownsUpload = false;
    try {
      final allowedHosts = {
        ...urls.map((url) => Uri.parse(url).authority),
        '127.0.0.1:${_server.port}',
      };
      final host = request.headers.value(HttpHeaders.hostHeader);
      final origin = request.headers.value('origin');
      if (!allowedHosts.contains(host) ||
          (origin != null && origin != 'http://$host') ||
          request.uri.queryParameters['token'] != _token) {
        await _text(request, HttpStatus.forbidden, '地址已失效，请重新扫描电视二维码');
        return;
      }
      if (_closed || _received.isCompleted) {
        await _text(request, HttpStatus.gone, '本次传输已结束');
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/') {
        _headers(request.response);
        request.response.headers.contentType = ContentType.html;
        request.response.headers.set('Content-Security-Policy',
            "default-src 'none'; script-src 'nonce-$_token'; style-src 'nonce-$_token'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");
        request.response.write(_page(_token));
        await request.response.close();
        return;
      }
      if (request.method != 'POST' || request.uri.path != '/upload') {
        await _text(request, HttpStatus.notFound, '未找到请求路径');
        return;
      }
      if (_busy) {
        await _text(request, HttpStatus.conflict, '正在接收文件，请稍后重试');
        return;
      }
      if (request.headers.contentType?.mimeType != 'application/octet-stream') {
        await _text(request, HttpStatus.unsupportedMediaType, '请选择播放列表文件');
        return;
      }
      _busy = ownsUpload = true;
      final name = request.uri.queryParameters['name'] ?? '';
      if (name.isEmpty ||
          name.length > 160 ||
          RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(name) ||
          !RegExp(r'\.(m3u8?|txt)$', caseSensitive: false).hasMatch(name)) {
        throw const _UploadException('请选择 M3U、M3U8 或 TXT 文件');
      }
      final bytes = await _readBytes(request);
      if (_closed) return;
      // Validate off the UI isolate. The editor still owns the eventual save.
      final error = await compute(_validate, bytes);
      if (_closed) return;
      if (error != null) throw _UploadException(error);
      await _text(request, HttpStatus.ok, '文件已传到电视，请在电视确认保存');
      if (!_closed) {
        _received.complete(LivePlaylistUpload(name: name, bytes: bytes));
      }
    } catch (error) {
      if (_closed) return;
      final message = error is _UploadException
          ? error.message
          : error is TimeoutException
              ? '上传超时，请重试'
              : '文件接收失败，请重试';
      if (ownsUpload) _report(message);
      try {
        await _text(
            request,
            error is _UploadException
                ? error.status
                : error is TimeoutException
                    ? HttpStatus.requestTimeout
                    : HttpStatus.badRequest,
            message);
      } catch (_) {
        // The peer may have disconnected or the dialog may have closed.
      }
    } finally {
      if (ownsUpload) {
        await _readSubscription?.cancel();
        _readSubscription = null;
        _busy = false;
      }
    }
  }

  Future<Uint8List> _readBytes(HttpRequest request) async {
    if (request.contentLength > livePlaylistMaxBytes) {
      throw const _UploadException(
          '文件超过 8 MiB', HttpStatus.requestEntityTooLarge);
    }
    final result = Completer<Uint8List>();
    final bytes = BytesBuilder(copy: false);
    void fail(Object error) {
      if (result.isCompleted) return;
      result.completeError(error);
    }

    // Drain without retaining more bytes on rejection, until the error response
    // has been sent. Cancelling the body early can reset a chunked connection.
    _readSubscription = request.listen(
        (chunk) {
          if (result.isCompleted) return;
          if (bytes.length + chunk.length > livePlaylistMaxBytes) {
            fail(const _UploadException(
                '文件超过 8 MiB', HttpStatus.requestEntityTooLarge));
          } else {
            bytes.add(chunk);
          }
        },
        onError: (Object error) => fail(error),
        onDone: () {
          if (!result.isCompleted) result.complete(bytes.takeBytes());
        });
    final timer = Timer(_uploadTimeout, () => fail(TimeoutException('upload')));
    _cancelRead = () => fail(StateError('closed'));
    try {
      return await result.future;
    } finally {
      timer.cancel();
      _cancelRead = null;
    }
  }

  void _headers(HttpResponse response) {
    response.persistentConnection = false;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('X-Frame-Options', 'DENY');
  }

  Future<void> _text(HttpRequest request, int status, String message) async {
    _headers(request.response);
    request.response.statusCode = status;
    request.response.headers.contentType =
        ContentType('text', 'plain', charset: 'utf-8');
    request.response.write(message);
    await request.response.close();
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

class _UploadException implements Exception {
  const _UploadException(this.message, [this.status = HttpStatus.badRequest]);
  final String message;
  final int status;
}

String? _validate(Uint8List bytes) {
  try {
    parseLivePlaylist(decodeLiveText(bytes), 'upload');
    return null;
  } catch (_) {
    return '文件不是有效的 HTTP/HTTPS 频道列表，请检查内容后重试';
  }
}

String _page(String token) => '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Starflow 直播文件传输</title>
<style nonce="$token">
:root { color-scheme: light; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
* { box-sizing: border-box; }
body { margin: 0; color: #24272b; background: #f6f7f8; }
main { max-width: 640px; margin: 0 auto; padding: 32px 20px; }
h1 { font-size: 24px; margin: 0 0 28px; }
label { display: block; font-weight: 600; margin-bottom: 12px; }
input { width: 100%; min-height: 48px; font: inherit; }
input::file-selector-button { padding: 10px 14px; margin-right: 12px; border: 1px solid #969da5; border-radius: 6px; background: white; font: inherit; }
p { color: #626a73; line-height: 1.6; }
button { display: inline-flex; align-items: center; gap: 8px; min-height: 48px; padding: 10px 18px; border: 0; border-radius: 6px; background: #176840; color: white; font: inherit; cursor: pointer; }
button:disabled { opacity: .55; cursor: default; }
#status { min-height: 48px; margin-top: 20px; overflow-wrap: anywhere; }
#status[data-error="true"] { color: #b3261e; }
</style>
</head>
<body><main>
<h1>Starflow 直播文件传输</h1>
<label for="file">播放列表</label>
<input id="file" type="file" accept=".m3u,.m3u8,.txt">
<p>M3U / M3U8 / TXT · 最大 8 MiB</p>
<button id="upload" type="button">上传到电视</button>
<p id="status" role="status" aria-live="polite"></p>
</main>
<script nonce="$token">
const fileInput = document.getElementById('file');
const button = document.getElementById('upload');
const status = document.getElementById('status');
function show(message, error = false) {
  status.textContent = message;
  status.dataset.error = String(error);
}
button.addEventListener('click', async () => {
  const file = fileInput.files[0];
  if (!file || !/\\.(m3u8?|txt)\$/i.test(file.name)) {
    show('请选择 M3U、M3U8 或 TXT 文件', true);
    return;
  }
  if (file.size > $livePlaylistMaxBytes) {
    show('文件超过 8 MiB', true);
    return;
  }
  button.disabled = fileInput.disabled = true;
  show('正在上传');
  let uploaded = false;
  try {
    const response = await fetch('/upload?token=$token&name=' + encodeURIComponent(file.name), {
      method: 'POST', headers: {'Content-Type': 'application/octet-stream'}, body: file,
      credentials: 'omit', cache: 'no-store'
    });
    show(await response.text(), !response.ok);
    uploaded = response.ok;
  } catch (_) {
    show('连接已断开，请重新扫描电视二维码后重试', true);
  } finally {
    button.disabled = fileInput.disabled = uploaded;
  }
});
</script></body></html>''';
