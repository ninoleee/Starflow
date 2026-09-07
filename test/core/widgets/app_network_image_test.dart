import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';

void main() {
  testWidgets('TV image stays mounted after loading and parent rebuilds',
      (tester) async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    late HttpServer server;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.persistentConnection = false;
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(bytes);
        await request.response.close();
      });
    });
    addTearDown(() => server.close(force: true));

    Widget buildImage() => ProviderScope(
          overrides: [isTelevisionProvider.overrideWith((ref) async => true)],
          child: MaterialApp(
            home: AppNetworkImage(
              'http://127.0.0.1:${server.port}/hero.png',
              cachePolicy: AppNetworkImageCachePolicy.networkOnly,
            ),
          ),
        );

    await tester.pumpWidget(buildImage());
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 20),
          ));
      await tester.pump();
      final images = tester.widgetList<RawImage>(find.byType(RawImage));
      if (images.any((image) => image.image != null)) {
        break;
      }
    }
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    final imageState = tester.state(find.byType(Image));
    for (var rebuild = 0; rebuild < 3; rebuild++) {
      await tester.pumpWidget(buildImage());
      expect(tester.state(find.byType(Image)), same(imageState));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
