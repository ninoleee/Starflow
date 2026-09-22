import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

void main() {
  testWidgets(
      'idle focus recovery schedules a frame and respects existing focus',
      (tester) async {
    final target = FocusNode();
    final other = FocusNode();
    addTearDown(target.dispose);
    addTearDown(other.dispose);
    late BuildContext pageContext;
    await tester.pumpWidget(_host(Builder(builder: (context) {
      pageContext = context;
      return Row(children: [
        TvFocusableAction(
            focusNode: target, onPressed: () {}, child: const Text('Target')),
        TvFocusableAction(
            focusNode: other, onPressed: () {}, child: const Text('Other')),
      ]);
    })));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    scheduleTvFocusRecovery(context: pageContext, focusNode: target);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(target.hasPrimaryFocus, isTrue);
    other.requestFocus();
    await tester.pumpAndSettle();
    scheduleTvFocusRecovery(context: pageContext, focusNode: target);
    await tester.pumpAndSettle();
    expect(other.hasPrimaryFocus, isTrue);

    Navigator.of(pageContext).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Cover')),
    ));
    await tester.pumpAndSettle();
    scheduleTvFocusRecovery(context: pageContext, focusNode: target);
    await tester.pumpAndSettle();
    expect(target.hasPrimaryFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
    scheduleTvFocusRecovery(context: pageContext, focusNode: target);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final key in [
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.contextMenu,
    LogicalKeyboardKey.gameButtonY,
  ]) {
    testWidgets('TV ${key.keyLabel} executes once even after focus moves',
        (tester) async {
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var firstCalls = 0;
      var secondCalls = 0;
      await tester.pumpWidget(_host(Row(children: [
        TvFocusableAction(
          focusNode: first,
          autofocus: true,
          onPressed: () => firstCalls++,
          onContextAction: () => firstCalls++,
          child: const Text('First'),
        ),
        TvFocusableAction(
          focusNode: second,
          onPressed: () => secondCalls++,
          onContextAction: () => secondCalls++,
          child: const Text('Second'),
        ),
      ])));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      expect(firstCalls, 0);
      second.requestFocus();
      await tester.pump();
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
      expect(firstCalls, 0, reason: 'Focus changes cancel a held command');
      expect(secondCalls, 0);
      await tester.sendKeyEvent(key);
      expect(secondCalls, 1);
    });
  }

  for (final keepFocusable in [false, true]) {
    testWidgets(
        'directional navigation respects disabled focus: $keepFocusable',
        (tester) async {
      final first = FocusNode();
      final disabled = FocusNode();
      final last = FocusNode();
      addTearDown(first.dispose);
      addTearDown(disabled.dispose);
      addTearDown(last.dispose);
      await tester.pumpWidget(_host(
        MediaQuery(
          data:
              const MediaQueryData(navigationMode: NavigationMode.directional),
          child: Row(children: [
            TvFocusableAction(
              focusNode: first,
              autofocus: true,
              onPressed: () {},
              child: const Text('First'),
            ),
            TvFocusableAction(
              focusNode: disabled,
              focusableWhenDisabled: keepFocusable,
              child: const Text('Disabled'),
            ),
            TvFocusableAction(
              focusNode: last,
              onPressed: () {},
              child: const Text('Last'),
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(disabled.canRequestFocus, keepFocusable);
      expect((keepFocusable ? disabled : last).hasPrimaryFocus, isTrue);
      if (keepFocusable) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(last.hasPrimaryFocus, isTrue);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    });
  }
}

Widget _host(Widget child) => ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => true)],
      child: MaterialApp(home: Scaffold(body: child)),
    );
