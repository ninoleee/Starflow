import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/features/details/presentation/widgets/detail_hero_section.dart';
import 'package:starflow/features/details/presentation/widgets/detail_shared_widgets.dart';
import 'package:starflow/features/details/presentation/widgets/detail_image_preview.dart';

void main() {
  for (final television in [false, true]) {
    for (final useFallback in [false, true]) {
      testWidgets(
          'candidate updates retain decoded image (TV=$television, fallback=$useFallback)',
          (tester) async {
        final requests = <String>[];
        final server = await _imageServer(tester, (request, bytes) async {
          requests.add(request.uri.path);
          if (useFallback && request.uri.path == '/primary') {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.headers.contentType = ContentType('image', 'png');
            request.response.add(bytes);
          }
          await request.response.close();
        });
        final base = 'http://127.0.0.1:${server.port}';
        Widget build(List<String> fallbacks, {String token = 'original'}) =>
            ProviderScope(
              overrides: [
                isTelevisionProvider.overrideWith((ref) => television),
              ],
              child: MaterialApp(
                home: AppNetworkImage(
                  '$base/primary',
                  headers: {'x-image-auth': token},
                  cachePolicy: AppNetworkImageCachePolicy.networkOnly,
                  fallbackSources: [
                    for (final path in fallbacks)
                      AppNetworkImageSource(
                        url: '$base/$path',
                        cachePolicy: AppNetworkImageCachePolicy.networkOnly,
                      ),
                  ],
                ),
              ),
            );

        await tester.pumpWidget(build(['fallback']));
        await _pumpUntil(tester, () => _hasDecodedImage(tester));
        final state = tester.state(find.byType(Image));
        final requestCount = requests.length;
        for (final fallbacks in [
          ['unused', 'fallback'],
          ['fallback', 'new-poster'],
        ]) {
          await tester.pumpWidget(build(fallbacks));
          expect(_hasDecodedImage(tester), isTrue);
          expect(tester.state(find.byType(Image)), same(state));
          await tester.pump();
          expect(requests, hasLength(requestCount));
        }

        // Authentication changes must still resolve a fresh primary source.
        await tester.pumpWidget(build(['fallback'], token: 'updated'));
        expect(_hasDecodedImage(tester), isFalse);
        await _pumpUntil(tester, () => requests.length > requestCount);
        await _pumpUntil(tester, () => _hasDecodedImage(tester));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('detail backdrop keeps its decoded frame until replacement loads',
      (tester) async {
    final replacementReady = Completer<void>();
    final requests = <String>[];
    final server = await _imageServer(tester, (request, bytes) async {
      requests.add(request.uri.path);
      if (request.uri.path == '/replacement') {
        await replacementReady.future;
      }
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    addTearDown(() {
      if (!replacementReady.isCompleted) replacementReady.complete();
    });
    Widget build(String path) => ProviderScope(
          child: MaterialApp(
            home: DetailBackdropImage(
              imageUrl: 'http://127.0.0.1:${server.port}/$path',
              cachePolicy: AppNetworkImageCachePolicy.networkOnly,
            ),
          ),
        );
    await tester.pumpWidget(build('original'));
    await _pumpUntil(tester, () => _hasDecodedImage(tester));
    final originalProvider = tester.widget<Image>(find.byType(Image)).image;
    await tester.pumpWidget(build('replacement'));
    expect(_hasDecodedImage(tester), isTrue);
    await _pumpUntil(tester, () => requests.contains('/replacement'));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(_hasDecodedImage(tester), isTrue);
    }
    replacementReady.complete();
    await _pumpUntil(
      tester,
      () =>
          _hasDecodedImage(tester) &&
          tester
              .widgetList<Image>(find.byType(Image))
              .any((image) => image.image != originalProvider),
    );
    expect(requests, ['/original', '/replacement']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preview decode failure exposes a fresh network retry',
      (tester) async {
    final server = await _imageServer(tester, (request, bytes) async {
      expect(request.headers.value('x-image-auth'), 'preview-token');
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: DetailImagePreview(
          image: AppNetworkImageSource(
            url: 'http://127.0.0.1:${server.port}/retry',
            headers: const {'x-image-auth': 'preview-token'},
            cachePolicy: AppNetworkImageCachePolicy.networkOnly,
          ),
          initialProvider: MemoryImage(Uint8List.fromList([0, 1, 2])),
        ),
      ),
    ));
    await _pumpUntil(tester, () => find.text('图片加载失败').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('重新加载'));
    await tester.pump();
    await _pumpUntil(tester, () => _hasDecodedImage(tester));
    expect(find.text('图片加载失败'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preview double tap toggles a convenient zoom level',
      (tester) async {
    final server = await _imageServer(tester, (request, bytes) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    await tester.pumpWidget(MaterialApp(
      home: DetailImagePreview(
        image: AppNetworkImageSource(
          url: 'http://127.0.0.1:${server.port}/double-tap',
          cachePolicy: AppNetworkImageCachePolicy.networkOnly,
        ),
      ),
    ));
    await _pumpUntil(tester, () => _hasDecodedImage(tester));

    final viewer = find.byType(InteractiveViewer);
    final center = tester.getCenter(viewer);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump();
    expect(
      tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      closeTo(2.5, 0.01),
    );

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pump();
    expect(
      tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      closeTo(1, 0.01),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preview downward swipe closes when not zoomed', (tester) async {
    final server = await _imageServer(tester, (request, bytes) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    await tester.pumpWidget(MaterialApp(
      home: DetailImagePreview(
        image: AppNetworkImageSource(
          url: 'http://127.0.0.1:${server.port}/swipe-close',
          cachePolicy: AppNetworkImageCachePolicy.networkOnly,
        ),
      ),
    ));
    await _pumpUntil(tester, () => _hasDecodedImage(tester));

    final viewer = find.byType(InteractiveViewer);
    final gesture = await tester.startGesture(tester.getCenter(viewer));
    await gesture.moveBy(const Offset(0, 220));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(DetailImagePreview), findsNothing);
  });

  testWidgets('preview tap on the letterbox closes when not zoomed',
      (tester) async {
    final server = await _imageServer(tester, (request, bytes) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    await tester.pumpWidget(MaterialApp(
      home: DetailImagePreview(
        image: AppNetworkImageSource(
          url: 'http://127.0.0.1:${server.port}/blank-close',
          cachePolicy: AppNetworkImageCachePolicy.networkOnly,
        ),
      ),
    ));
    await _pumpUntil(tester, () => _hasDecodedImage(tester));

    await tester.tapAt(const Offset(40, 300));
    await tester.pumpAndSettle();

    expect(find.byType(DetailImagePreview), findsNothing);
  });

  testWidgets('preview pinch keeps its off-center focal point', (tester) async {
    final server = await _imageServer(tester, (request, bytes) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    await tester.pumpWidget(MaterialApp(
      home: DetailImagePreview(
        image: AppNetworkImageSource(
          url: 'http://127.0.0.1:${server.port}/focal-point',
          cachePolicy: AppNetworkImageCachePolicy.networkOnly,
        ),
      ),
    ));
    await _pumpUntil(tester, () => _hasDecodedImage(tester));

    final viewer = find.byType(InteractiveViewer);
    final viewerTopLeft = tester.getTopLeft(viewer);
    final focalPoint = viewerTopLeft + const Offset(180, 300);
    final left = await tester.startGesture(
      focalPoint - const Offset(24, 0),
      pointer: 1,
    );
    final right = await tester.startGesture(
      focalPoint + const Offset(24, 0),
      pointer: 2,
    );
    await left.moveTo(focalPoint - const Offset(80, 0));
    await right.moveTo(focalPoint + const Offset(80, 0));
    await tester.pump();

    final controller =
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    expect(
      controller.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(
      tester.widget<InteractiveViewer>(viewer).alignment,
      isNull,
    );
    final scenePoint = controller.toScene(focalPoint - viewerTopLeft);
    expect(scenePoint.dx, closeTo(152, 0.5));
    expect(scenePoint.dy, closeTo(300, 0.5));

    await left.up();
    await right.up();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'gallery reuses downloaded source and survives preview pinch/close',
      (tester) async {
    var requests = 0;
    final server = await _imageServer(tester, (request, bytes) async {
      requests++;
      // A second network request would fail, as with an expired signed URL.
      if (requests > 1) {
        request.response.statusCode = 403;
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(bytes);
      }
      await request.response.close();
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) async => false)],
      child: MaterialApp(
        home: Scaffold(
          body: DetailImageGallery(images: [
            DetailImageAsset(
              url: 'http://127.0.0.1:${server.port}/still',
              cachePolicy: AppNetworkImageCachePolicy.networkOnly,
            ),
          ]),
        ),
      ),
    ));
    await _pumpUntil(tester, () => _hasDecodedImage(tester));
    final thumbnailState = tester.state(find.byType(Image));
    await tester.tap(find.byType(AppNetworkImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntil(
      tester,
      () => tester
          .widgetList<RawImage>(find.descendant(
            of: find.byType(InteractiveViewer),
            matching: find.byType(RawImage),
          ))
          .any((image) => image.image != null),
    );
    expect(requests, 1);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final left =
        await tester.startGesture(center - const Offset(30, 0), pointer: 1);
    final right =
        await tester.startGesture(center + const Offset(30, 0), pointer: 2);
    await left.moveTo(center - const Offset(60, 0));
    await right.moveTo(center + const Offset(60, 0));
    await tester.pump();
    await left.moveTo(center - const Offset(100, 0));
    await right.moveTo(center + const Offset(100, 0));
    await tester.pump();
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1));
    await left.up();
    await right.up();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(Image)), same(thumbnailState));
    expect(_hasDecodedImage(tester), isTrue);
    expect(requests, 1);
    final galleryImageProvider = tester.widget<Image>(find.byType(Image)).image;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final galleryCacheStatus = await galleryImageProvider.obtainCacheStatus(
      configuration: ImageConfiguration.empty,
    );
    expect(galleryCacheStatus?.pending, isFalse);
    expect(galleryCacheStatus?.keepAlive, isFalse);
    expect(galleryCacheStatus?.live, isFalse);
  });

  testWidgets('TV preview back and select return to the detail page',
      (tester) async {
    final server = await _imageServer(tester, (request, bytes) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('首页')),
        routes: [
          GoRoute(
            path: 'details',
            builder: (_, __) => Scaffold(
              body: Column(children: [
                const Text('详情页'),
                DetailImageGallery(images: [
                  DetailImageAsset(
                    url: 'http://127.0.0.1:${server.port}/tv-focus',
                    cachePolicy: AppNetworkImageCachePolicy.networkOnly,
                  ),
                ]),
              ]),
            ),
          ),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) async => true)],
      child: MaterialApp.router(routerConfig: router),
    ));
    unawaited(router.push<void>('/details'));
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () => _hasDecodedImage(tester));

    for (final key in <LogicalKeyboardKey?>[
      LogicalKeyboardKey.goBack,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.gameButtonA,
      LogicalKeyboardKey.space,
      null,
    ]) {
      await tester.tap(find.byType(AppNetworkImage));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => tester
            .widgetList<RawImage>(find.descendant(
              of: find.byType(DetailImagePreview),
              matching: find.byType(RawImage),
            ))
            .any((image) => image.image != null),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DetailImagePreview), findsOneWidget);
      expect(find.byTooltip('重置缩放'), findsNothing);
      expect(find.byTooltip('关闭'), findsNothing);
      expect(find.byType(IconButton), findsNothing);

      if (key == null) {
        await tester.binding.handlePopRoute();
      } else {
        const physical = PhysicalKeyboardKey.escape;
        expect(
            await tester.sendKeyDownEvent(key, physicalKey: physical), isTrue);
        // Let focus and route transitions finish before the remote releases.
        await tester.pumpAndSettle();
        expect(await tester.sendKeyRepeatEvent(key, physicalKey: physical),
            isTrue);
        await tester.pump();
        final handled = await tester.sendKeyUpEvent(key, physicalKey: physical);
        if (!handled && key == LogicalKeyboardKey.goBack) {
          // Android redispatches an unhandled BACK release as system back.
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.text('详情页'), findsOneWidget);
        expect(handled, isTrue, reason: 'The preview must consume key release');
      }
      await tester.pumpAndSettle();
      expect(find.byType(DetailImagePreview), findsNothing);
      expect(find.text('详情页'), findsOneWidget);
      expect(router.canPop(), isTrue);
      final focusContext = FocusManager.instance.primaryFocus?.context;
      expect(focusContext, isNotNull);
      expect(focusContext!.findAncestorWidgetOfExactType<DetailImageGallery>(),
          isNotNull);
    }
    // A separate back press after closing the preview can leave details.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('详情页'), findsNothing);
  });

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
    // UI permit expiry must not prevent subsequent transport cancellation.
    await tester.pump(const Duration(seconds: 5));
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
