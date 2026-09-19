import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger_impl_io.dart';
import 'package:starflow/core/storage/persistent_image_cache_impl_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('starflow-perf-io-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('log flush preserves batching, critical ordering and clear', () async {
    final logger = createAppLogService();
    await logger.configure(
        enabled: true,
        maxBytes: 1024 * 1024,
        recordedLevels: AppLogLevel.values.toSet());
    logger.log(AppLogLevel.info, 'test', 'first');
    logger.log(AppLogLevel.info, 'test', 'second');
    await logger.logCritical('test', 'critical');
    expect((await logger.read()).map((entry) => entry.message),
        ['first', 'second', 'critical']);
    logger.log(AppLogLevel.info, 'test', 'before-clear');
    await logger.clear();
    expect(await logger.read(), isEmpty);
    for (var i = 0; i < 1000; i++) {
      logger.log(AppLogLevel.info, 'test', 'burst-$i');
    }
    await logger.flush();
    final entries = await logger.read(limit: 1000);
    expect(entries.length, 257);
    expect(entries.last.message, 'Log queue capacity reached');
  });

  test('one canceled image consumer does not abort another consumer', () async {
    final oldOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = oldOverrides);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<void>();
    final finish = Completer<void>();
    var requests = 0;
    server.listen((request) async {
      requests++;
      if (!received.isCompleted) received.complete();
      await finish.future;
      request.response.headers.contentType = ContentType('image', 'svg+xml');
      request.response.write('<svg xmlns="http://www.w3.org/2000/svg"/>');
      await request.response.close();
    });
    final cache = createPersistentImageCache();
    final cancel = Completer<void>();
    final url = 'http://127.0.0.1:${server.port}/shared.svg';
    final first = cache.load(url, cancel: cancel.future);
    final second = cache.load(url);
    await received.future;
    cancel.complete();
    await Future<void>.delayed(Duration.zero);
    finish.complete();
    final results = await Future.wait([first, second]);
    expect(results[0], orderedEquals(results[1]));
    expect(requests, 1);
    // Let best-effort maintenance finish before removing the temp directory.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}
