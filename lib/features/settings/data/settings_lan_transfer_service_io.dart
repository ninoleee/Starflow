import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:starflow/features/settings/domain/app_settings.dart';

typedef SettingsLanTransferLoadSettings = FutureOr<AppSettings> Function();
typedef SettingsLanTransferImportSettings = Future<void> Function(
  AppSettings settings,
);

class SettingsLanTransferEvent {
  const SettingsLanTransferEvent({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;
}

class SettingsLanTransferSession {
  SettingsLanTransferSession._({
    required HttpServer server,
    required StreamSubscription<HttpRequest> subscription,
    required StreamController<SettingsLanTransferEvent> eventsController,
    required this.accessCode,
    required this.port,
    required this.urls,
  })  : _server = server,
        _subscription = subscription,
        _eventsController = eventsController;

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _subscription;
  final StreamController<SettingsLanTransferEvent> _eventsController;

  final String accessCode;
  final int port;
  final List<String> urls;
  bool _closed = false;

  Stream<SettingsLanTransferEvent> get events => _eventsController.stream;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription.cancel();
    await _server.close(force: true);
    await _eventsController.close();
  }
}

class SettingsLanTransferService {
  const SettingsLanTransferService._();

  static Future<SettingsLanTransferSession> start({
    required SettingsLanTransferLoadSettings loadSettings,
    required SettingsLanTransferImportSettings importSettings,
  }) async {
    final accessCode = _generateAccessCode();
    final eventsController =
        StreamController<SettingsLanTransferEvent>.broadcast();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final urls = await _buildAccessUrls(
      port: server.port,
      accessCode: accessCode,
    );

    final subscription = server.listen(
      (request) {
        unawaited(
          _handleRequest(
            request,
            accessCode: accessCode,
            urls: urls,
            loadSettings: loadSettings,
            importSettings: importSettings,
            eventsController: eventsController,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        eventsController.add(
          SettingsLanTransferEvent(
            message: '局域网传输服务发生错误：$error',
            isError: true,
          ),
        );
      },
      cancelOnError: false,
    );

    return SettingsLanTransferSession._(
      server: server,
      subscription: subscription,
      eventsController: eventsController,
      accessCode: accessCode,
      port: server.port,
      urls: urls,
    );
  }

  static Future<void> _handleRequest(
    HttpRequest request, {
    required String accessCode,
    required List<String> urls,
    required SettingsLanTransferLoadSettings loadSettings,
    required SettingsLanTransferImportSettings importSettings,
    required StreamController<SettingsLanTransferEvent> eventsController,
  }) async {
    try {
      final path = request.uri.path;
      if (path == '/favicon.ico') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      if (_readToken(request.uri) != accessCode) {
        await _writeHtml(
          request.response,
          statusCode: HttpStatus.forbidden,
          title: '拒绝访问',
          body: '<p>访问码无效，请重新查看电视上显示的地址。</p>',
        );
        return;
      }

      if (request.method == 'GET' && path == '/') {
        await _writeHtml(
          request.response,
          title: 'Starflow 配置传输',
          body: _buildIndexPage(
            accessCode: accessCode,
            urls: urls,
          ),
        );
        return;
      }

      if (request.method == 'GET' && path == '/download') {
        final settings = await loadSettings();
        final fileName = _buildExportFileName();
        const encoder = JsonEncoder.withIndent('  ');
        final payload = encoder.convert(settings.toJson());
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.response.headers.set(
          'content-disposition',
          'attachment; filename="$fileName"',
        );
        request.response.write(payload);
        await request.response.close();
        return;
      }

      if (request.method == 'POST' && path == '/upload') {
        final body = await utf8.decoder.bind(request).join();
        if (body.trim().isEmpty) {
          throw const FormatException('上传内容为空，请重新选择配置文件。');
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map) {
          throw const FormatException('配置内容不是合法的 JSON 对象。');
        }
        final imported = AppSettings.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        try {
          await importSettings(imported);
        } catch (error) {
          throw StateError('配置已上传，但电视端保存失败：$error');
        }
        eventsController.add(
          const SettingsLanTransferEvent(
            message: '手机上传成功，电视端配置已直接替换并生效。',
          ),
        );
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'plain',
          charset: 'utf-8',
        );
        request.response.write('上传成功，电视端配置已替换。');
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType(
        'text',
        'plain',
        charset: 'utf-8',
      );
      request.response.write('未找到请求路径。');
      await request.response.close();
    } catch (error) {
      eventsController.add(
        SettingsLanTransferEvent(
          message: '配置上传失败：$error',
          isError: true,
        ),
      );
      try {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType(
          'text',
          'plain',
          charset: 'utf-8',
        );
        request.response.write('操作失败：$error');
        await request.response.close();
      } catch (_) {
        // Ignore response write failures after disconnects.
      }
    }
  }

  static Future<void> _writeHtml(
    HttpResponse response, {
    required String title,
    required String body,
    int statusCode = HttpStatus.ok,
  }) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType(
      'text',
      'html',
      charset: 'utf-8',
    );
    response.write('''
<!DOCTYPE html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${_escape(title)}</title>
    <style>
      :root {
        color-scheme: light;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      body {
        margin: 0;
        background: #f4f6fb;
        color: #172033;
      }
      main {
        max-width: 760px;
        margin: 0 auto;
        padding: 24px 18px 40px;
      }
      .card {
        background: #ffffff;
        border-radius: 18px;
        box-shadow: 0 18px 48px rgba(18, 31, 53, 0.12);
        padding: 20px;
        margin-bottom: 16px;
      }
      h1, h2 {
        margin-top: 0;
      }
      a.button, button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 44px;
        padding: 0 18px;
        border: 0;
        border-radius: 12px;
        background: #0d6efd;
        color: #ffffff;
        text-decoration: none;
        font-size: 15px;
        font-weight: 700;
      }
      button {
        cursor: pointer;
      }
      input[type="file"], textarea {
        width: 100%;
        box-sizing: border-box;
        margin-top: 12px;
      }
      textarea {
        min-height: 180px;
        padding: 12px;
        border-radius: 12px;
        border: 1px solid #c8d1e1;
        resize: vertical;
        font: inherit;
      }
      code {
        display: inline-block;
        padding: 3px 8px;
        border-radius: 999px;
        background: #eef3ff;
      }
      ul {
        padding-left: 20px;
      }
      .muted {
        color: #5d6a82;
      }
      .status {
        margin-top: 12px;
        min-height: 24px;
        font-weight: 600;
      }
      .status.error {
        color: #c62828;
      }
      .status.success {
        color: #17653a;
      }
    </style>
  </head>
  <body>
    <main>
      $body
    </main>
  </body>
</html>
''');
    await response.close();
  }

  static String _buildIndexPage({
    required String accessCode,
    required List<String> urls,
  }) {
    final escapedAccessCode = _escape(accessCode);
    final tokenQuery = Uri(queryParameters: {'token': accessCode}).query;
    final escapedDownloadPath = _escape('/download?$tokenQuery');
    final escapedUrls = urls
        .map(
          (url) => '<li><a href="${_escape(url)}">${_escape(url)}</a></li>',
        )
        .join();
    return '''
<section class="card">
  <h1>Starflow 配置传输</h1>
  <p>手机和电视连接同一个局域网后，打开下面任意地址即可下载当前配置，或上传新的 JSON 配置覆盖电视端设置。</p>
  <p class="muted">访问码：<code>$escapedAccessCode</code></p>
  <ul>$escapedUrls</ul>
</section>
<section class="card">
  <h2>下载当前配置</h2>
  <p class="muted">下载的是当前电视端正在使用的完整配置 JSON。</p>
  <a class="button" href="$escapedDownloadPath">下载配置</a>
</section>
<section class="card">
  <h2>上传并替换配置</h2>
  <p class="muted">上传后会直接覆盖电视端当前设置，请确认 JSON 来自可信设备。</p>
  <input id="fileInput" type="file" accept=".json,application/json">
  <textarea id="jsonInput" placeholder="也可以直接粘贴 JSON 内容"></textarea>
  <button id="uploadButton" type="button">上传并替换</button>
  <div id="status" class="status"></div>
</section>
<script>
  const token = ${jsonEncode(accessCode)};
  const statusElement = document.getElementById('status');
  const fileInput = document.getElementById('fileInput');
  const jsonInput = document.getElementById('jsonInput');
  const uploadButton = document.getElementById('uploadButton');

  function setStatus(message, isError) {
    statusElement.textContent = message;
    statusElement.className = isError ? 'status error' : 'status success';
  }

  uploadButton.addEventListener('click', async () => {
    let payload = jsonInput.value.trim();
    const selectedFile = fileInput.files && fileInput.files[0];

    if (selectedFile) {
      payload = await selectedFile.text();
    }

    if (!payload) {
      setStatus('请先选择 JSON 文件，或直接粘贴配置内容。', true);
      return;
    }

    uploadButton.disabled = true;
    setStatus('正在上传，请稍候...', false);

    try {
      const response = await fetch(`/upload?token=\${encodeURIComponent(token)}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json; charset=utf-8'
        },
        body: payload
      });
      const message = (await response.text()) || '上传完成。';
      setStatus(message, !response.ok);
    } catch (error) {
      setStatus(`上传失败：\${error}`, true);
    } finally {
      uploadButton.disabled = false;
    }
  });
</script>
''';
  }

  static Future<List<String>> _buildAccessUrls({
    required int port,
    required String accessCode,
  }) async {
    final urls = <String>{};
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final networkInterface in interfaces) {
      for (final address in networkInterface.addresses) {
        if (!_shouldExposeAddress(address)) {
          continue;
        }
        urls.add(
          Uri(
            scheme: 'http',
            host: address.address,
            port: port,
            queryParameters: {'token': accessCode},
          ).toString(),
        );
      }
    }

    if (urls.isEmpty) {
      urls.add(
        Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: port,
          queryParameters: {'token': accessCode},
        ).toString(),
      );
    }

    final sorted = urls.toList()..sort();
    return sorted;
  }

  static bool _shouldExposeAddress(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
      return false;
    }
    final raw = address.address.trim();
    if (raw.isEmpty || raw.startsWith('169.254.')) {
      return false;
    }
    return true;
  }

  static String _buildExportFileName() {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'starflow-settings-$timestamp.json';
  }

  static String _generateAccessCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      6,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static String _readToken(Uri uri) {
    return uri.queryParameters['token']?.trim() ?? '';
  }

  static String _escape(String value) {
    return const HtmlEscape(HtmlEscapeMode.element).convert(value);
  }
}
