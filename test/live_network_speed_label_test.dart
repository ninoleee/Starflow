import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/live_tv/application/live_playback_controller.dart';
import 'package:starflow/features/live_tv/presentation/live_network_speed_label.dart';

class _SpeedSource implements LiveNetworkSpeedSource {
  final requests = <(int, Completer<int?>)>[];
  @override
  Future<int?> readNetworkSpeed(int generation) {
    final pending = Completer<int?>();
    requests.add((generation, pending));
    return pending.future;
  }
}

void main() {
  testWidgets('speed polls only while mounted and rejects stale results',
      (tester) async {
    final source = _SpeedSource();
    Widget label(int generation) => MaterialApp(
        home: LiveNetworkSpeedLabel(source: source, generation: generation));
    await tester.pumpWidget(label(1));
    expect(find.text('--'), findsOneWidget);
    source.requests.last.$2.complete(2048);
    await tester.pump();
    expect(find.text('2.00 KB/s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    final old = source.requests.last.$2;
    await tester.pump(const Duration(seconds: 1));
    expect(source.requests, hasLength(2), reason: 'No overlapping polls');
    await tester.pumpWidget(label(2));
    expect(find.text('--'), findsOneWidget);
    expect(source.requests.last.$1, 2);
    old.complete(999999);
    await tester.pump();
    expect(find.text('--'), findsOneWidget);
    source.requests.last.$2.complete(0);
    await tester.pump();
    await tester.pump();
    expect(find.text('0 B/s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    source.requests.last.$2.completeError(StateError('Unavailable'));
    await tester.pump();
    await tester.pump();
    expect(find.text('--'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    final count = source.requests.length;
    await tester.pumpWidget(const SizedBox());
    source.requests.last.$2.complete(1024);
    await tester.pump(const Duration(seconds: 3));
    expect(source.requests, hasLength(count));
    expect(tester.takeException(), isNull);
  });
}
