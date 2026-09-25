import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/presentation/widgets/playback_network_speed_label.dart';

void main() {
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
    expect(find.text('3840x2160 · HEVC · AAC'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    final stale = requests.last;
    await tester.pumpWidget(label(2));
    expect(find.text('3840x2160 · HEVC · AAC'), findsNothing);
    expect(find.text('识别中'), findsOneWidget);
    requests.last.complete('1920x1080 · H.264 · AAC');
    await tester.pump();
    stale.complete('3840x2160 · HEVC · AAC');
    await tester.pump();
    expect(find.text('1920x1080 · H.264 · AAC'), findsOneWidget);
    expect(find.text('3840x2160 · HEVC · AAC'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('2.0 KB/s · -- · --'), findsOneWidget);
    expect(find.text('识别中'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cache is current, not smoothed, and survives speed failure',
      (tester) async {
    int? bytes = 32 * 1024 * 1024;
    var failSpeed = false;
    Widget label(int generation) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
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
    expect(find.text('2.0 KB/s · 32.0 MB · 18s'), findsOneWidget);
    expect(find.text('1920x1080 · HEVC · AAC'), findsOneWidget);
    expect(find.text('MPV'), findsNothing);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.textAlign, TextAlign.center);
    }
    expect(tester.getSize(find.byType(PlaybackNetworkSpeedLabel)),
        const Size(160, 36));
    final inheritedStyle = DefaultTextStyle.of(
            tester.element(find.text('2.0 KB/s · 32.0 MB · 18s')))
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
    expect(find.text('-- · 1.0 KB · 18s'), findsOneWidget);
    bytes = 0;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('-- · 0 B · 18s'), findsOneWidget);
    bytes = null;
    await tester.pumpWidget(label(2));
    await tester.pump();
    expect(find.text('-- · -- · 18s'), findsOneWidget);
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
    expect(find.text('1.0 KB/s · -- · --'), findsOneWidget);
    await tester.pumpWidget(label(2));
    pending.last.complete(2048);
    await tester.pump();
    await tester.pump();
    expect(find.text('1.0 KB/s · 2.0 KB · --'), findsOneWidget);
    pending.first.complete(999999);
    await tester.pump();
    expect(find.text('1.0 KB/s · 2.0 KB · --'), findsOneWidget);
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
    expect(find.text('-- · -- · --'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(requests, hasLength(2));
    requests.last.complete(2048);
    await tester.pump();
    await tester.pump();
    expect(find.text('2.0 KB/s · -- · --'), findsOneWidget);
    requests.first.complete(999999);
    await tester.pump();
    expect(find.text('2.0 KB/s · -- · --'), findsOneWidget);
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
    expect(find.text('-- · -- · --'), findsOneWidget);
    requests.last.complete(4096);
    await tester.pump();
    await tester.pump();
    expect(find.text('4.0 KB/s · -- · --'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'fixed bounds at large text scale, zero and errors reset smoothing',
      (tester) async {
    var speed = 1024;
    var fail = false;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
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
    expect(size, const Size(160, 36));
    speed = 3072;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('2.0 KB/s · -- · --'), findsOneWidget);
    speed = 0;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('0 B/s · -- · --'), findsOneWidget);
    speed = 1073741824;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('1.0 GB/s · -- · --'), findsOneWidget);
    expect(tester.getSize(find.byType(PlaybackNetworkSpeedLabel)), size);
    fail = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('-- · -- · --'), findsOneWidget);
    fail = false;
    speed = 1024;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('1.0 KB/s · -- · --'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
