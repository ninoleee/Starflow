import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

void main() {
  for (final useSystemBack in [false, true]) {
    testWidgets(
        'dialog back leaves input on an actionable button '
        '(system back: $useSystemBack)', (tester) async {
      final input = FocusNode();
      final missingAction = FocusNode();
      final confirm = FocusNode();
      addTearDown(input.dispose);
      addTearDown(missingAction.dispose);
      addTearDown(confirm.dispose);
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            return TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => wrapTelevisionDialogBackHandling(
                  enabled: true,
                  dialogContext: dialogContext,
                  inputFocusNodes: [input],
                  contentFocusNodes: [input],
                  actionFocusNodes: [missingAction, confirm],
                  child: AlertDialog(
                    content: TextField(focusNode: input, autofocus: true),
                    actions: [
                      TextButton(
                        focusNode: confirm,
                        onPressed: () => confirmed = true,
                        child: const Text('Confirm'),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('Open'),
            );
          }),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(input.hasPrimaryFocus, isTrue);

      if (useSystemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(confirm.hasPrimaryFocus, isTrue);
      expect(missingAction.hasPrimaryFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);

      if (useSystemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
}
