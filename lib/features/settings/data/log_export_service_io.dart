import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/settings/data/log_export_service.dart';

LogExportService createLogExportService() => const LocalLogExportService();

class LocalLogExportService implements LogExportService {
  const LocalLogExportService();

  static const MethodChannel _platformChannel = MethodChannel(
    'starflow/platform',
  );

  @override
  bool get isSupported => appLogger.isSupported;

  @override
  String get unsupportedReason =>
      appLogger.isSupported ? '' : '当前平台暂不支持导出本地日志。';

  @override
  bool get supportsSystemExport => Platform.isIOS;

  @override
  Future<String?> pickExportPath({String? suggestedName}) async {
    final exportDirectory = await _ensureExportDirectory();
    final fileName = _normalizeFileName(suggestedName);
    if (Platform.isIOS) {
      return p.join(exportDirectory.path, fileName);
    }
    try {
      final directory = await getDirectoryPath(
        initialDirectory: exportDirectory.path,
        confirmButtonText: '选择这个目录',
      );
      if (directory == null || directory.trim().isEmpty) {
        return null;
      }
      return p.join(directory, fileName);
    } on PlatformException catch (error) {
      throw FileSystemException(
        '当前设备无法打开目录选择器，请手动填写导出路径。',
        error.message,
      );
    } catch (error) {
      throw FileSystemException('当前设备无法打开目录选择器，请手动填写导出路径。', '$error');
    }
  }

  @override
  Future<String> buildSuggestedExportPath() async {
    final directory = await _ensureExportDirectory();
    return p.join(directory.path, _buildFileName());
  }

  @override
  Future<LogExportResult> exportLogs({required String targetPath}) async {
    final normalizedPath = targetPath.trim();
    if (normalizedPath.isEmpty) {
      throw const FileSystemException('导出路径不能为空。');
    }
    final data = await _loadExportData();
    final file = File(normalizedPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.bytes, flush: true);
    return LogExportResult(
      path: file.path,
      bytes: data.bytes.length,
      sourceFileCount: data.fileCount,
    );
  }

  @override
  Future<LogExportResult?> exportLogsWithSystemPicker({
    String? suggestedName,
  }) async {
    if (!Platform.isIOS) {
      throw const FileSystemException('当前平台不支持系统文件导出器。');
    }
    final data = await _loadExportData();
    final fileName = _normalizeFileName(suggestedName);
    final temporaryDirectory = await getTemporaryDirectory();
    final temporaryFile = File(
      p.join(temporaryDirectory.path, 'exports', 'logs', fileName),
    );
    await temporaryFile.parent.create(recursive: true);
    await temporaryFile.writeAsBytes(data.bytes, flush: true);

    try {
      final response = await _platformChannel.invokeMapMethod<String, dynamic>(
        'exportDocument',
        <String, dynamic>{'sourcePath': temporaryFile.path},
      );
      if (response == null) {
        return null;
      }
      final exportedPath = (response['path'] as String?)?.trim();
      return LogExportResult(
        path: exportedPath == null || exportedPath.isEmpty
            ? fileName
            : exportedPath,
        bytes: data.bytes.length,
        sourceFileCount: data.fileCount,
      );
    } on PlatformException catch (error) {
      throw FileSystemException(
        '当前设备无法打开系统文件导出器。',
        error.message,
      );
    } catch (error) {
      throw FileSystemException('当前设备无法打开系统文件导出器。', '$error');
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }

  @override
  Future<LogLanExportSession> startTelevisionExport() async {
    await _loadExportData();
    return _IoLogLanExportSession.start();
  }

  Future<Directory> _ensureExportDirectory() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(documentsDirectory.path, 'exports', 'logs'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<AppLogExportData> _loadExportData() async {
    final data = await appLogger.export();
    if (data.isEmpty) {
      throw const FileSystemException('当前没有可导出的日志。');
    }
    return data;
  }

  static String _buildFileName() {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'starflow-logs-$timestamp.log';
  }

  static String _normalizeFileName(String? suggestedName) {
    final trimmed = (suggestedName ?? '').trim();
    if (trimmed.isEmpty) {
      return _buildFileName();
    }
    return trimmed.toLowerCase().endsWith('.log') ? trimmed : '$trimmed.log';
  }
}

class _IoLogLanExportSession implements LogLanExportSession {
  _IoLogLanExportSession._({
    required HttpServer server,
    required StreamSubscription<HttpRequest> subscription,
    required StreamController<LogLanExportEvent> eventsController,
    required this.accessCode,
    required this.urls,
  })  : _server = server,
        _subscription = subscription,
        _eventsController = eventsController,
        port = server.port;

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _subscription;
  final StreamController<LogLanExportEvent> _eventsController;
  bool _closed = false;

  @override
  final String accessCode;

  @override
  final int port;

  @override
  final List<String> urls;

  @override
  Stream<LogLanExportEvent> get events => _eventsController.stream;

  static Future<_IoLogLanExportSession> start() async {
    final accessCode = _generateAccessCode();
    final eventsController = StreamController<LogLanExportEvent>.broadcast();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final urls = await _buildAccessUrls(
      port: server.port,
      accessCode: accessCode,
    );
    late final StreamSubscription<HttpRequest> subscription;
    subscription = server.listen(
      (request) {
        unawaited(
          _handleRequest(
            request,
            accessCode: accessCode,
            eventsController: eventsController,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        eventsController.add(
          LogLanExportEvent(
            message: '局域网日志服务发生错误：$error',
            isError: true,
          ),
        );
      },
      cancelOnError: false,
    );
    return _IoLogLanExportSession._(
      server: server,
      subscription: subscription,
      eventsController: eventsController,
      accessCode: accessCode,
      urls: urls,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription.cancel();
    await _server.close(force: true);
    await _eventsController.close();
  }

  static Future<void> _handleRequest(
    HttpRequest request, {
    required String accessCode,
    required StreamController<LogLanExportEvent> eventsController,
  }) async {
    try {
      if (request.uri.path == '/favicon.ico') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      if (request.uri.queryParameters['token']?.trim() != accessCode) {
        await _writeHtml(
          request.response,
          statusCode: HttpStatus.forbidden,
          title: '拒绝访问',
          body: '<p>访问码无效，请重新查看电视上显示的地址。</p>',
        );
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/') {
        final tokenQuery = Uri(
          queryParameters: <String, String>{'token': accessCode},
        ).query;
        await _writeHtml(
          request.response,
          title: 'Starflow 日志导出',
          body: '''
<section class="card">
  <h1>Starflow 日志导出</h1>
  <p>点击下方按钮下载电视当前保存的完整日志。日志已经自动隐藏常见的 Cookie、Token、密码和授权信息。</p>
  <p class="muted">访问码：<code>${_escape(accessCode)}</code></p>
  <a class="button" href="/download?$tokenQuery">下载日志</a>
</section>
''',
        );
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/download') {
        final data = await appLogger.export();
        if (data.isEmpty) {
          throw const FileSystemException('当前没有可导出的日志。');
        }
        final fileName = LocalLogExportService._buildFileName();
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'plain',
          charset: 'utf-8',
        );
        request.response.headers.set(
          'content-disposition',
          'attachment; filename="$fileName"',
        );
        request.response.add(data.bytes);
        await request.response.close();
        eventsController.add(
          LogLanExportEvent(
            message: '手机已下载日志（${data.bytes.length} 字节）。',
          ),
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('未找到请求路径。');
      await request.response.close();
    } catch (error) {
      eventsController.add(
        LogLanExportEvent(
          message: '日志下载失败：$error',
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
        // Ignore response failures after the client disconnects.
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
      :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      body { margin: 0; background: #f4f6fb; color: #172033; }
      main { max-width: 720px; margin: 0 auto; padding: 24px 18px 40px; }
      .card { background: #fff; border-radius: 18px; box-shadow: 0 18px 48px rgba(18,31,53,.12); padding: 20px; }
      h1 { margin-top: 0; }
      .muted { color: #5d6a82; }
      code { padding: 3px 8px; border-radius: 999px; background: #eef3ff; }
      .button { display: inline-flex; align-items: center; justify-content: center; min-height: 44px; padding: 0 18px; border-radius: 12px; background: #0d6efd; color: #fff; text-decoration: none; font-weight: 700; }
    </style>
  </head>
  <body><main>$body</main></body>
</html>
''');
    await response.close();
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
        final raw = address.address.trim();
        if (address.type != InternetAddressType.IPv4 ||
            address.isLoopback ||
            raw.isEmpty ||
            raw.startsWith('169.254.')) {
          continue;
        }
        urls.add(
          Uri(
            scheme: 'http',
            host: raw,
            port: port,
            queryParameters: <String, String>{'token': accessCode},
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
          queryParameters: <String, String>{'token': accessCode},
        ).toString(),
      );
    }
    return urls.toList()..sort();
  }

  static String _generateAccessCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List<String>.generate(
      6,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static String _escape(String value) {
    return const HtmlEscape(HtmlEscapeMode.element).convert(value);
  }
}
