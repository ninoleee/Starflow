import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/playback/data/mpv_playback_cache.dart';
import 'package:starflow/features/playback/domain/playback_network_speed.dart';
import 'package:starflow/features/playback/presentation/widgets/playback_network_speed_label.dart';

void main() {
  testWidgets('MPV JSON memory bytes show independently from relay disk bytes',
      (tester) async {
    var cacheState = '{"fw-bytes":33554432,"total-bytes":41943040}';
    await tester.pumpWidget(MaterialApp(
      home: PlaybackNetworkSpeedLabel(
        sampleKey: 1,
        readSpeed: () async => 2048,
        readCacheBytes: () => readMpvForwardCacheBytes((_) async => cacheState),
        readDiskCacheBytes: () async => 128 * 1024 * 1024,
        readBufferDurationMs: () async => 18000,
        showFormat: false,
      ),
    ));
    await tester.pump();
    expect(find.text('2.0 KB/s · 32.0 MB | 128.0 MB · 18s'), findsOneWidget);
    cacheState = '{"fw-bytes":0,"total-bytes":41943040}';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('2.0 KB/s · 0 B | 128.0 MB · 18s'), findsOneWidget);
    cacheState = '';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('2.0 KB/s · -- | 128.0 MB · 18s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('MPV shows byte size and duration without disk cache',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PlaybackNetworkSpeedLabel(
        sampleKey: 1,
        readSpeed: () async => 2048,
        readCacheBytes: () async => 32 * 1024 * 1024,
        readBufferDurationMs: () async => 18000,
        showFormat: false,
      ),
    ));
    await tester.pump();
    expect(find.text('2.0 KB/s · 32.0 MB · 18s'), findsOneWidget);
    expect(find.textContaining('前向包约'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabling disk metrics drops late values and stops disk reads',
      (tester) async {
    final pending = Completer<int?>();
    var diskReads = 0;
    Widget label(bool enabled) => MaterialApp(
          home: PlaybackNetworkSpeedLabel(
            sampleKey: 1,
            readSpeed: () async => 1024,
            readCacheBytes: () async => 2048,
            readDiskCacheBytes: enabled
                ? () {
                    diskReads++;
                    return diskReads == 1 ? pending.future : Future.value(4096);
                  }
                : null,
            readBufferDurationMs: () async => 3000,
            readFormat: () async => '1920x1080 · H264 · AAC',
          ),
        );
    await tester.pumpWidget(label(true));
    await tester.pumpWidget(label(false));
    await tester.pump();
    pending.complete(999999);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(diskReads, 1);
    expect(find.textContaining('1.0 KB/s · 2.0 KB · 3s'), findsOneWidget);
    expect(find.textContaining('1920x1080 · H264 · AAC'), findsOneWidget);
    expect(find.textContaining('|'), findsNothing);
    await tester.pumpWidget(label(true));
    await tester.pump();
    expect(
        find.textContaining('1.0 KB/s · 2.0 KB | 4.0 KB · 3s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('cache metrics omit memory and disk labels', () {
    expect(
        formatPlaybackMetrics(1024, 2048, 3000,
            diskCacheBytes: 4096, memoryCacheLabel: '前向包约'),
        '1.0 KB/s · 前向包约 2.0 KB | 4.0 KB · 3s');
    expect(formatPlaybackMetrics(1024, 2048, 3000, diskCacheBytes: 4096),
        '1.0 KB/s · 2.0 KB | 4.0 KB · 3s');
    expect(formatPlaybackMetrics(null, null, null, showDiskCache: true),
        '-- · -- | -- · --');
  });

  testWidgets('disk owner generation and hiding reject late samples',
      (tester) async {
    final reads = <Completer<int?>>[];
    Widget label(int generation, {bool visible = true}) => MaterialApp(
            home: Center(
          child: PlaybackNetworkSpeedLabel(
              sampleKey: generation,
              visible: visible,
              readSpeed: () async => 1024,
              readCacheBytes: () async => 2048,
              readDiskCacheBytes: () {
                final result = Completer<int?>();
                reads.add(result);
                return result.future;
              }),
        ));
    await tester.pumpWidget(label(1));
    final old = reads.single;
    await tester.pumpWidget(label(2));
    reads.last.complete(4096);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('2.0 KB | 4.0 KB'), findsOneWidget);
    old.complete(999999);
    await tester.pump();
    expect(find.textContaining('2.0 KB | 4.0 KB'), findsOneWidget);
    await tester.pumpWidget(label(2, visible: false));
    final count = reads.length;
    await tester.pump(const Duration(seconds: 5));
    expect(reads.length, count);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background pauses sampling and resume requests a fresh snapshot',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: PlaybackNetworkSpeedLabel(
            sampleKey: 1,
            readSpeed: () async => 0,
            readDiskCacheBytes: () async {
              reads++;
              return 1024;
            })));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final count = reads;
    await tester.pump(const Duration(seconds: 5));
    expect(reads, count);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, count + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('font size stays fixed for long and short metrics',
      (tester) async {
    Widget label(int generation, int speed, int cache, int disk) => MaterialApp(
          home: PlaybackNetworkSpeedLabel(
            sampleKey: generation,
            readSpeed: () async => speed,
            readCacheBytes: () async => cache,
            readDiskCacheBytes: () async => disk,
            readBufferDurationMs: () async => 3599000,
            readFormat: () async => '3840x2160 · HEVC · EAC3',
            memoryCacheLabel: '前向包约',
          ),
        );
    await tester.pumpWidget(
        label(1, 10 * 1024 * 1024, 512 * 1024 * 1024, 1024 * 1024 * 1024));
    await tester.pump();
    final longLabel =
        find.textContaining('10.0 MB/s · 前向包约 512.0 MB | 1.0 GB · 3599s');
    expect(longLabel, findsOneWidget);
    expect(tester.widget<Text>(longLabel).style!.fontSize, 10);
    expect(
        tester
            .widget<Text>(find.textContaining('3840x2160 · HEVC · EAC3'))
            .style!
            .fontSize,
        10);

    await tester.pumpWidget(label(2, 1024, 1024, 1024));
    await tester.pump();
    final shortLabel =
        find.textContaining('1.0 KB/s · 前向包约 1.0 KB | 1.0 KB · 3599s');
    expect(shortLabel, findsOneWidget);
    expect(tester.widget<Text>(shortLabel).style!.fontSize, 10);
    await tester.pumpWidget(const SizedBox());
  });
}
