import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/widgets/tv_remote_input.dart';

void main() {
  testWidgets('modified shortcuts require modifiers and fire once on release',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: TvRemoteShortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            calls++;
            return null;
          }),
        },
        child: const Focus(autofocus: true, child: SizedBox()),
      ),
    )));
    await tester.pump();
    // Shift+Enter must not match the Control+Enter command.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(calls, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.enter), isTrue);
    expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter), isTrue);
    expect(calls, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.enter), isTrue);
    expect(calls, 1);
  });

  for (final key in [...tvBackKeys, ...tvConfirmKeys]) {
    testWidgets('${key.keyLabel} closes only the top route on release',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ));
      navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Detail')),
      ));
      await tester.pumpAndSettle();
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (context) => TvRemoteShortcuts(
          shortcuts: {SingleActivator(key): const DismissIntent()},
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
                Navigator.pop(context);
                return null;
              }),
            },
            child: const Focus(
                autofocus: true,
                child: AlertDialog(
                  content: Text('Preview'),
                )),
          ),
        ),
      );
      await tester.pumpAndSettle();
      const physical = PhysicalKeyboardKey.escape;
      expect(await tester.sendKeyDownEvent(key, physicalKey: physical), isTrue);
      await tester.pumpAndSettle();
      expect(
          await tester.sendKeyRepeatEvent(key, physicalKey: physical), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Preview'), findsOneWidget);
      expect(await tester.sendKeyUpEvent(key, physicalKey: physical), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Preview'), findsNothing);
      expect(find.text('Detail'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    });
  }

  testWidgets('rebuilds preserve press; background and focus changes cancel it',
      (tester) async {
    final node = FocusNode();
    final other = FocusNode();
    final revision = ValueNotifier(0);
    addTearDown(node.dispose);
    addTearDown(other.dispose);
    addTearDown(revision.dispose);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (_, value, __) => TvRemoteShortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent()
        },
        child: Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
              calls++;
              return null;
            })
          },
          child: Row(children: [
            Focus(focusNode: node, autofocus: true, child: Text('$value')),
            Focus(focusNode: other, child: const Text('Other')),
          ]),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    revision.value++;
    await tester.pump();
    expect(calls, 0);
    expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.enter), isTrue);
    expect(calls, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    other.requestFocus();
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 2);
  });
}
