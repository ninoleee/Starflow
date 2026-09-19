import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

void main() {
  testWidgets('moving focus while holding confirm cancels the pending editor',
      (tester) async {
    final controller = TextEditingController();
    final other = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(other.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => true)],
      child: MaterialApp(
          home: Scaffold(
              body: Column(children: [
        SettingsTextInputField(
            controller: controller, labelText: 'Name', autofocus: true),
        TextButton(
            focusNode: other, onPressed: () {}, child: const Text('Other')),
      ]))),
    ));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    other.requestFocus();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(other.hasPrimaryFocus, isTrue);
  });

  for (final key in [LogicalKeyboardKey.select, LogicalKeyboardKey.enter]) {
    testWidgets('TV editor waits for ${key.keyLabel} release', (tester) async {
      final controller = TextEditingController(text: 'original');
      await tester.pumpWidget(ProviderScope(
        overrides: [isTelevisionProvider.overrideWith((ref) => true)],
        child: MaterialApp(
            home: Scaffold(
                body: SettingsTextInputField(
          controller: controller,
          labelText: 'Name',
          autofocus: true,
        ))),
      ));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(key);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.sendKeyRepeatEvent(key);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.sendKeyUpEvent(key);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'original');
      await tester.enterText(find.byType(TextField), 'keep k');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'keep k');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
    });
  }
  testWidgets('disposing a waiting launcher does not open an editor',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => true)],
      child: MaterialApp(
          home: Scaffold(
              body: SettingsTextInputField(
        controller: controller,
        labelText: 'Name',
        autofocus: true,
      ))),
    ));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}
