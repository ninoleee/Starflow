import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/navigation/page_activity_mixin.dart';

void main() {
  testWidgets('idle lifecycle changes dispatch without a background frame',
      (tester) async {
    final key = GlobalKey<_PageState>();
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(home: _Page(key: key, changes: changes)));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(tester.binding.hasScheduledFrame, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(key.currentState!.isPageActive, isFalse);
    expect(changes, [true, false]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(changes, [true, false]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(key.currentState!.isPageActive, isTrue);
    expect(changes, [true, false, true]);
  });

  testWidgets('rapid inactive and resume preserves both transitions',
      (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(home: _Page(changes: changes)));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(changes, [true, false]);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(changes, [true, false, true]);
  });

  testWidgets('hidden page remains inactive on app resume', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: TickerMode(enabled: false, child: _Page(changes: changes)),
    ));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
  });

  testWidgets('backgrounding again cancels queued activation', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(home: _Page(changes: changes)));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(changes, [true, false]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(changes, [true, false, true]);
  });

  testWidgets('queued activation does not run after disposal', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(home: _Page(changes: changes)));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(tester.takeException(), isNull);
  });
}

class _Page extends StatefulWidget {
  const _Page({super.key, required this.changes});

  final List<bool> changes;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with PageActivityMixin<_Page> {
  @override
  void onPageBecameActive() => widget.changes.add(true);

  @override
  void onPageBecameInactive() => widget.changes.add(false);

  @override
  Widget build(BuildContext context) => const SizedBox();
}
