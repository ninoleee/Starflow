import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const privateUrl = 'https://private.test/account/password?token=secret';

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('starflow-live-errors-');
    messenger.setMockMethodCallHandler(
        pathChannel, (_) async => directory.path);
    await appLogger.configure(
        enabled: true,
        maxBytes: 1024 * 1024,
        recordedLevels: AppLogLevel.values.toSet());
  });
  tearDownAll(() async {
    await appLogger.configure(
        enabled: false,
        maxBytes: 1024 * 1024,
        recordedLevels: AppLogLevel.values.toSet());
    messenger.setMockMethodCallHandler(pathChannel, null);
    await directory.delete(recursive: true);
  });
  setUp(() => appLogger.clear());

  Future<void> expectPrivateDataAbsent() async {
    final text = utf8.decode((await appLogger.export()).bytes);
    for (final secret in ['private.test', 'password', 'secret', 'Set-Cookie']) {
      expect(text, isNot(contains(secret)));
    }
  }

  testWidgets(
      'exported playback failures carry native codes without exception text',
      (tester) async {
    final engine = ExoLiveEngine(61);
    messenger.setMockMethodCallHandler(engine.channel, (_) async => null);
    final controller =
        LivePlaybackController(engine: engine, onReady: (_, __) async {});
    try {
      controller.select(const LiveChannel(
          id: 'channel',
          sourceId: 'source',
          name: 'Channel',
          lines: [LiveLine(privateUrl)]));
      await tester.pump(const Duration(milliseconds: 180));
      await messenger.handlePlatformMessage(
          engine.channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall('state', {
            'generation': controller.generation,
            'state': 'error',
            'error': {
              'errorCategory': 'http',
              'nativeErrorCode': 2000,
              'httpStatus': 403,
              'message': privateUrl,
              'Set-Cookie': 'secret'
            },
          })),
          (_) {});
      await controller.close();
      await tester.runAsync(() async {
        final entry = (await appLogger.read()).last;
        expect(entry.fields['httpStatus'], 403);
        expect(entry.fields['nativeErrorCode'], 2000);
        expect(entry.fields['errorCategory'], 'http');
        expect(entry.fields['reason'], 'engineError');
        expect(entry.fields['willRetry'], true);
        await expectPrivateDataAbsent();
      });
    } finally {
      await controller.close();
      controller.dispose();
      messenger.setMockMethodCallHandler(engine.channel, null);
    }
  });

  for (final epg in [false, true]) {
    test(
        'HTTP refresh failure records ${epg ? 'epg' : 'playlist'} stage and retains channels',
        () async {
      final db = await databaseFactoryMemory.openDatabase('http-$epg');
      final repository = LiveRepository(
          openDatabase: () async => db,
          client: MockClient((_) async => http.Response(privateUrl, 403)));
      addTearDown(repository.dispose);
      await repository.saveSource(
          LiveSource(
              id: 'source',
              name: 'Source',
              url: epg ? '' : privateUrl,
              epgUrl: epg ? privateUrl : ''),
          imported: Uint8List.fromList(
              utf8.encode('Channel,https://example.test/live')));
      await expectLater(
          repository.refresh('source'),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('HTTP 403'))));
      expect((await repository.load()).channels, hasLength(1));
      final entry = (await appLogger.read()).last;
      expect(entry.fields['stage'], epg ? 'epg' : 'playlist');
      expect(entry.fields['errorCategory'], 'httpStatus');
      expect(entry.fields['httpStatus'], 403);
      await expectPrivateDataAbsent();
    });
  }

  test('refresh timeout, size and parse failures remain distinct and private',
      () async {
    for (final category in ['timeout', 'sizeLimit', 'format']) {
      final db = await databaseFactoryMemory.openDatabase(category);
      final repository = LiveRepository(
          openDatabase: () async => db,
          client: MockClient((_) async {
            if (category == 'timeout') throw TimeoutException(privateUrl);
            if (category == 'sizeLimit') {
              throw http.ClientException(
                  'Response exceeds byte limit', Uri.parse(privateUrl));
            }
            return http.Response('<html>$privateUrl</html>', 200);
          }));
      addTearDown(repository.dispose);
      await repository.saveSource(
          const LiveSource(id: 'source', name: 'Source', url: privateUrl));
      await expectLater(repository.refresh('source'),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())));
      final entry = (await appLogger.read()).last;
      expect(entry.fields['errorCategory'], category);
      expect(entry.fields.containsKey('httpStatus'), isFalse);
      await expectPrivateDataAbsent();
    }
  });
}
