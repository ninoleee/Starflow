import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/data/live_repository.dart';
import 'package:starflow/features/live_tv/domain/live_models.dart';
import 'package:starflow/features/live_tv/presentation/live_player_page.dart';

void main() {
  testWidgets(
      'failed playback shows safe HTTP details and retries on mobile and TV',
      (tester) async {
    // The global cleanup queue must stay within one fake-clock zone.
    for (final size in [const Size(320, 640), const Size(1280, 720)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final engine = ExoLiveEngine(63);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final opens = <int>[];
      messenger.setMockMethodCallHandler(engine.channel, (call) async {
        if (call.method == 'open') {
          opens.add(call.arguments['generation'] as int);
        }
        return null;
      });
      final repository = LiveRepository(
          openDatabase: () =>
              databaseFactoryMemory.openDatabase('failure-$size'),
          client: MockClient((_) async => http.Response('', 404)));
      const channel = LiveChannel(
          id: 'a',
          sourceId: 's',
          name: 'Channel',
          lines: [LiveLine('https://private.test/password')]);
      const snapshot = LiveSnapshot(channels: [channel]);
      try {
        await tester.pumpWidget(ProviderScope(
            overrides: [
              liveRepositoryProvider.overrideWithValue(repository),
              liveGuideProvider.overrideWith((_, __) async => []),
              isTelevisionProvider.overrideWith((_) => size.width > 1000),
            ],
            child: MaterialApp(
                home: LivePlayerPage(
                    initialChannel: channel,
                    snapshot: snapshot,
                    engineFactory: () => engine))));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        for (var attempt = 1; attempt <= 4; attempt++) {
          expect(opens, hasLength(attempt));
          await messenger.handlePlatformMessage(
              engine.channel.name,
              const StandardMethodCodec().encodeMethodCall(MethodCall('state', {
                'generation': opens.last,
                'state': 'error',
                'error': {
                  'errorCategory': 'http',
                  'httpStatus': 403,
                  'nativeErrorCode': 2000,
                  'message': 'https://private.test/password'
                },
              })),
              (_) {});
          await tester.pump();
          if (attempt < 4) {
            await tester.pump(Duration(seconds: attempt * 2));
            await tester.pump(const Duration(milliseconds: 180));
          }
        }
        expect(find.text('当前频道播放失败'), findsOneWidget);
        expect(find.text('直播源拒绝访问（HTTP 403）'), findsOneWidget);
        expect(find.textContaining('private.test'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('重试'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        expect(opens, hasLength(5));
        expect(find.text('直播源拒绝访问（HTTP 403）'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        messenger.setMockMethodCallHandler(engine.channel, null);
        repository.dispose();
      }
    }
  });
}
