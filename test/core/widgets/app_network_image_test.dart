import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';

void main() {
  for (final television in [false, true]) {
    testWidgets('slow fallback does not inherit primary error (TV=$television)',
        (tester) async {
      final requests = <String>[];
      final fallbackReady = Completer<void>();
      final server = await _imageServer(tester, (request, bytes) async {
        requests.add(request.uri.path);
        if (request.uri.path == '/primary') {
          request.response.statusCode = 418;
        } else {
          await fallbackReady.future;
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(bytes);
        }
        await request.response.close();
      });
      addTearDown(() {
        if (!fallbackReady.isCompleted) fallbackReady.complete();
      });

      await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) async => television),
        ],
        child: MaterialApp(
          home: AppNetworkImage(
            'http://127.0.0.1:${server.port}/primary',
            cachePolicy: AppNetworkImageCachePolicy.networkOnly,
            fallbackSources: [
              AppNetworkImageSource(
                url: 'http://127.0.0.1:${server.port}/fallback',
                cachePolicy: AppNetworkImageCachePolicy.networkOnly,
              ),
            ],
          ),
        ),
      ));
      await _pumpUntil(tester, () => requests.contains('/fallback'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 30),
          ));
      await tester.pump();
      expect(requests, ['/primary', '/fallback']);
      fallbackReady.complete();
      await _pumpUntil(tester, () => _hasDecodedImage(tester));
      expect(requests, ['/primary', '/fallback']);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('hidden TV images release active and queued permits immediately',
      (tester) async {
    final requests = <String>[];
    final finishRequests = Completer<void>();
    final server = await _imageServer(tester, (request, bytes) async {
      requests.add(request.uri.path);
      await finishRequests.future;
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    addTearDown(() {
      if (!finishRequests.isCompleted) finishRequests.complete();
    });

    Widget page(String name, bool enabled, int count) => TickerMode(
          enabled: enabled,
          child: Column(children: [
            for (var index = 0; index < count; index++)
              AppNetworkImage(
                'http://127.0.0.1:${server.port}/$name/$index',
                width: 20,
                height: 20,
                cachePolicy: AppNetworkImageCachePolicy.networkOnly,
              ),
          ]),
        );
    Widget build(bool oldPageActive) => ProviderScope(
          overrides: [isTelevisionProvider.overrideWith((ref) async => true)],
          child: MaterialApp(
            home: Row(children: [
              page('old', oldPageActive, 8),
              page('new', !oldPageActive, 4),
            ]),
          ),
        );

    await tester.pumpWidget(build(true));
    await _pumpUntil(tester, () => requests.length == 4);
    expect(requests.every((path) => path.startsWith('/old/')), isTrue);
    await tester.pumpWidget(build(false));
    await _pumpUntil(
      tester,
      () => requests.where((path) => path.startsWith('/new/')).length == 4,
    );
    expect(requests.where((path) => path.startsWith('/old/')), hasLength(4));
    finishRequests.complete();
    await _pumpUntil(tester, () => _hasDecodedImage(tester));
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

bool _hasDecodedImage(WidgetTester tester) => tester
    .widgetList<RawImage>(find.byType(RawImage))
    .any((image) => image.image != null);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 20),
        ));
    await tester.pump();
  }
  expect(condition(), isTrue);
}

Future<HttpServer> _imageServer(
  WidgetTester tester,
  Future<void> Function(HttpRequest, List<int>) handle,
) async {
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
    server.listen((request) {
      request.response.persistentConnection = false;
      unawaited(handle(request, bytes));
    });
  });
  addTearDown(() => server.close(force: true));
  return server;
}
