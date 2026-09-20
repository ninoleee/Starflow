import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/data/live_logo_provider.dart';
import 'package:starflow/features/live_tv/presentation/live_logo.dart';

const _logoUrl = 'https://example.test/logo.png';
const _slotSize = Size(64, 40);

void main() {
  for (final (source, decoded) in [
    (const Size(480, 120), const Size(192, 48)),
    (const Size(240, 240), const Size(120, 120)),
    (const Size(120, 480), const Size(30, 120)),
    (const Size(80, 20), const Size(80, 20)),
    (const Size(20, 80), const Size(20, 80)),
  ]) {
    testWidgets('logo preserves $source aspect ratio during decoding',
        (tester) async {
      final bytes = await tester.runAsync(() => _png(source));
      final response = Completer<Uint8List>();
      await _pumpLogo(tester, () => response.future);
      expect(find.byIcon(Icons.live_tv), findsOneWidget);
      expect(tester.getSize(find.byType(LiveLogo)), _slotSize);

      response.complete(bytes!);
      await tester.pump();
      await _decodeLogo(tester);

      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.image, isNotNull);
      expect(Size(raw.image!.width.toDouble(), raw.image!.height.toDouble()),
          decoded);
      expect(raw.image!.width / raw.image!.height, source.aspectRatio);
      expect(raw.fit, BoxFit.contain);
      expect(tester.getSize(find.byType(LiveLogo)), _slotSize);
      expect(find.byIcon(Icons.live_tv), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('failed logo download keeps the placeholder and slot size',
      (tester) async {
    final response = Completer<Uint8List>();
    await _pumpLogo(tester, () => response.future);
    expect(find.byIcon(Icons.live_tv), findsOneWidget);
    expect(tester.getSize(find.byType(LiveLogo)), _slotSize);

    response.completeError(StateError('Logo unavailable'));
    await tester.pump();
    expect(find.byIcon(Icons.live_tv), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.getSize(find.byType(LiveLogo)), _slotSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid image bytes keep the placeholder and slot size',
      (tester) async {
    await _pumpLogo(tester, () async => Uint8List.fromList([0, 1, 2]));
    await _decodeLogo(tester);
    expect(find.byIcon(Icons.live_tv), findsOneWidget);
    expect(tester.getSize(find.byType(LiveLogo)), _slotSize);
    expect(tester.takeException(), isNull);
  });

  for (final url in ['', 'file:///tmp/logo.png']) {
    testWidgets('missing or unsupported logo URL uses a placeholder: $url',
        (tester) async {
      var requests = 0;
      await _pumpLogo(tester, () async {
        requests++;
        return Uint8List(0);
      }, url: url);
      expect(requests, 0);
      expect(find.byIcon(Icons.live_tv), findsOneWidget);
      expect(tester.getSize(find.byType(LiveLogo)), _slotSize);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpLogo(
  WidgetTester tester,
  Future<Uint8List> Function() load, {
  String url = _logoUrl,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [liveLogoProvider(url).overrideWith((_) => load())],
    child: MaterialApp(home: Center(child: LiveLogo(url: url))),
  ));
  await tester.pump();
}

Future<void> _decodeLogo(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final image = find.byType(Image);
  await tester.runAsync(() => precacheImage(
        tester.widget<Image>(image).image,
        tester.element(image),
        onError: (_, __) {},
      ));
  await tester.pump();
}

Future<Uint8List> _png(Size size) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.red, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
