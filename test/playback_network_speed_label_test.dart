import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/playback_network_speed_label.dart';

void main() {
  testWidgets('split labels keep format left and network metrics right',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      PlaybackNetworkSpeedLabel(
          sampleKey: 1, readSpeed: () async => 2048, showFormat: false),
      PlaybackNetworkSpeedLabel(
          sampleKey: 2,
          readSpeed: () async => null,
          formatOnly: true,
          readFormat: () async => '1920x1080 · HEVC · AAC'),
    ])));
    await tester.pump();
    final metrics = tester.widget<Text>(find.text('2.0 KB/s · -- · --'));
    final format = tester.widget<Text>(find.text('1920x1080 · HEVC · AAC'));
    expect(metrics.textAlign, TextAlign.right);
    expect(format.textAlign, TextAlign.left);
    expect(metrics.maxLines, 1);
    expect(format.maxLines, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('metrics and format share one line even in narrow bounds',
      (tester) async {
    for (final width in [160.0, 240.0]) {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            child: PlaybackNetworkSpeedLabel(
              sampleKey: width,
              readSpeed: () async => 2048,
              readCacheBytes: () async => 33554432,
              readBufferDurationMs: () async => 18000,
              readFormat: () async => '1920x1080 · HEVC · AAC',
            ),
          ),
        ),
      ));
      await tester.pump();
      final finder =
          find.text('2.0 KB/s · 32.0 MB · 18s · 1920x1080 · HEVC · AAC');
      expect(finder, findsOneWidget);
      final text = tester.widget<Text>(finder);
      expect(text.maxLines, 1);
      expect(text.softWrap, false);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('format resets on generation change and ignores late results',
      (tester) async {
    final requests = <Completer<String?>>[];
    Widget label(int generation) => MaterialApp(
          home: PlaybackNetworkSpeedLabel(
            sampleKey: generation,
            readSpeed: () async => 2048,
            readFormat: () {
              final pending = Completer<String?>();
              requests.add(pending);
              return pending.future;
            },
          ),
        );
    await tester.pumpWidget(label(1));
    requests.last.complete('3840x2160 · HEVC · AAC');
    await tester.pump();
    expect(find.textContaining('3840x2160 · HEVC · AAC'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    final stale = requests.last;
    await tester.pumpWidget(label(2));
    expect(find.textContaining('3840x2160 · HEVC · AAC'), findsNothing);
    expect(find.textContaining('识别中'), findsOneWidget);
    requests.last.complete('1920x1080 · H.264 · AAC');
    await tester.pump();
    stale.complete('3840x2160 · HEVC · AAC');
    await tester.pump();
    expect(find.textContaining('1920x1080 · H.264 · AAC'), findsOneWidget);
    expect(find.textContaining('3840x2160 · HEVC · AAC'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('2.0 KB/s · -- · --'), findsOneWidget);
    expect(find.textContaining('识别中'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cache is current, not smoothed, and survives speed failure',
      (tester) async {
    int? bytes = 32 * 1024 * 1024;
    var failSpeed = false;
    Widget label(int generation) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
                size: Size(800, 600), textScaler: TextScaler.linear(2)),
            child: Center(
              child: PlaybackNetworkSpeedLabel(
                sampleKey: generation,
                readSpeed: () async {
                  if (failSpeed) throw StateError('unavailable');
                  return 2048;
                },
                readCacheBytes: () async => bytes,
                readBufferDurationMs: () async => 18000,
                readFormat: () async => '1920x1080 · HEVC · AAC',
              ),
            ),
          ),
        );
    await tester.pumpWidget(label(1));
    await tester.pump();
    expect(find.textContaining('2.0 KB/s · 32.0 MB · 18s'), findsOneWidget);
    expect(find.textContaining('1920x1080 · HEVC · AAC'), findsOneWidget);
    expect(find.textContaining('MPV'), findsNothing);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.textAlign, TextAlign.right);
    }
    expect(tester.getSize(find.byType(PlaybackNetworkSpeedLabel)),
        const Size(480, 36));
    final inheritedStyle = DefaultTextStyle.of(
            tester.element(find.textContaining('2.0 KB/s · 32.0 MB · 18s')))
        .style;
    expect(
        inheritedStyle.fontFamily,
        DefaultTextStyle.of(
                tester.element(find.byType(PlaybackNetworkSpeedLabel)))
            .style
            .fontFamily);
    failSpeed = true;
    bytes = 1024;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('-- · 1.0 KB · 18s'), findsOneWidget);
    bytes = 0;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('-- · 0 B · 18s'), findsOneWidget);
    bytes = null;
    await tester.pumpWidget(label(2));
    await tester.pump();
    expect(find.textContaining('-- · -- · 18s'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cache timeout and old generation cannot overwrite new cache',
      (tester) async {
    final pending = <Completer<int?>>[];
    Widget label(int generation) => MaterialApp(
          home: PlaybackNetworkSpeedLabel(
            sampleKey: generation,
            readSpeed: () async => 1024,
            readCacheBytes: () {
              final result = Completer<int?>();
              pending.add(result);
              return result.future;
            },
          ),
        );
    await tester.pumpWidget(label(1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('1.0 KB/s · -- · --'), findsOneWidget);
    await tester.pumpWidget(label(2));
    pending.last.complete(2048);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('1.0 KB/s · 2.0 KB · --'), findsOneWidget);
    pending.first.complete(999999);
    await tester.pump();
    expect(find.textContaining('1.0 KB/s · 2.0 KB · --'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('timeout recovers and ignores the late original result',
      (tester) async {
    final requests = <Completer<int?>>[];
    await tester.pumpWidget(MaterialApp(
      home: PlaybackNetworkSpeedLabel(
        sampleKey: 1,
        readSpeed: () {
          final pending = Completer<int?>();
          requests.add(pending);
          return pending.future;
        },
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(requests, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('-- · -- · --'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(requests, hasLength(2));
    requests.last.complete(2048);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('2.0 KB/s · -- · --'), findsOneWidget);
    requests.first.complete(999999);
    await tester.pump();
    expect(find.textContaining('2.0 KB/s · -- · --'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hiding stops polling and discards pending samples',
      (tester) async {
    final requests = <Completer<int?>>[];
    Widget label(bool visible) => MaterialApp(
          home: PlaybackNetworkSpeedLabel(
            sampleKey: 1,
            visible: visible,
            readSpeed: () {
              final pending = Completer<int?>();
              requests.add(pending);
              return pending.future;
            },
          ),
        );
    await tester.pumpWidget(label(true));
    await tester.pumpWidget(label(false));
    requests.first.complete(1024);
    await tester.pump(const Duration(seconds: 3));
    expect(requests, hasLength(1));
    expect(find.byType(Text), findsNothing);
    await tester.pumpWidget(label(true));
    expect(find.textContaining('-- · -- · --'), findsOneWidget);
    requests.last.complete(4096);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('4.0 KB/s · -- · --'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'fixed bounds at large text scale, zero and errors reset smoothing',
      (tester) async {
    var speed = 1024;
    var fail = false;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(800, 600), textScaler: TextScaler.linear(2)),
        child: Center(
          child: PlaybackNetworkSpeedLabel(
            sampleKey: 1,
            readSpeed: () async {
              if (fail) throw StateError('Unavailable');
              return speed;
            },
          ),
        ),
      ),
    ));
    await tester.pump();
    final size = tester.getSize(find.byType(PlaybackNetworkSpeedLabel));
    expect(size, const Size(480, 36));
    speed = 3072;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('2.0 KB/s · -- · --'), findsOneWidget);
    speed = 0;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('0 B/s · -- · --'), findsOneWidget);
    speed = 1073741824;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('1.0 GB/s · -- · --'), findsOneWidget);
    expect(tester.getSize(find.byType(PlaybackNetworkSpeedLabel)), size);
    fail = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('-- · -- · --'), findsOneWidget);
    fail = false;
    speed = 1024;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('1.0 KB/s · -- · --'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
