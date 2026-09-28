import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/player_controls_layout.dart';

void main() {
  testWidgets('renders top bar preview with anchored actions', (tester) async {
    tester.view.physicalSize = const Size(844, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const fontPath = String.fromEnvironment('PREVIEW_FONT',
        defaultValue: '/System/Library/Fonts/Supplemental/Arial.ttf');
    if (File(fontPath).existsSync()) {
      final loader = FontLoader('Preview');
      loader.addFont(Future.value(
        ByteData.sublistView(File(fontPath).readAsBytesSync()),
      ));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Preview'),
      ),
      home: RepaintBoundary(
        key: boundaryKey,
        child: Material(
          color: Colors.black,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: playbackTopBarPadding(playbackControlsPadding(
                viewport: const Size(844, 390),
                safeArea: EdgeInsets.zero,
              )),
              child: SizedBox(
                height: playbackButtonBarHeight,
                child: PlayerMpvTopBarRow(
                  backButton: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  title: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('示例影片 · 第 01 集',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  metrics: const Text('12.8 MB/s · 86.0 MB · 18s',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                  actions: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.playlist_play_rounded),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('WRITE_PLAYER_PREVIEW')) {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/player-top-bar-preview.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
