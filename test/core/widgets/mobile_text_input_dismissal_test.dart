import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/mobile_text_input_dismissal.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group(platform.name, () {
      void testMobile(String description, WidgetTesterCallback callback) {
        testWidgets(description, callback,
            variant: TargetPlatformVariant({platform}));
      }

      Future<void> pumpPage(WidgetTester tester, Widget body,
          {bool television = false}) async {
        await tester.pumpWidget(ProviderScope(
          overrides: [isTelevisionProvider.overrideWith((ref) => television)],
          child: MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            builder: (context, child) =>
                MobileTextInputDismissal(child: child!),
            home: Scaffold(body: body),
          ),
        ));
        await tester.pumpAndSettle();
      }

      testMobile('touching blank space dismisses settings input',
          (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpPage(
            tester,
            Column(children: [
              SettingsTextInputField(controller: controller, labelText: 'Name'),
              const Expanded(child: SizedBox.expand(key: Key('blank'))),
            ]));
        await tester.enterText(find.byType(TextField), 'kept');
        await tester.pump();
        await tester.tapAt(tester.getCenter(find.byKey(const Key('blank'))));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isFalse);
        expect(controller.text, 'kept');
      });

      for (final action in [TextInputAction.done, TextInputAction.search]) {
        testMobile('${action.name} dismisses and submits once', (tester) async {
          final submissions = <String>[];
          await pumpPage(tester,
              TextField(textInputAction: action, onSubmitted: submissions.add));
          await tester.enterText(find.byType(TextField), 'query');
          await tester.testTextInput.receiveAction(action);
          await tester.pump();
          expect(tester.testTextInput.isVisible, isFalse);
          expect(submissions, ['query']);
        });
      }

      testMobile('next and tapping another input keep editing', (tester) async {
        final first = FocusNode();
        final second = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        await pumpPage(
            tester,
            Column(children: [
              TextField(
                  focusNode: first, textInputAction: TextInputAction.next),
              TextField(focusNode: second),
            ]));
        await tester.tap(find.byType(TextField).first);
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(second.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.tap(find.byType(TextField).first);
        await tester.pump();
        expect(first.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
      });

      testMobile('multiline newline keeps keyboard open', (tester) async {
        await pumpPage(
            tester,
            const TextField(
                maxLines: 4, textInputAction: TextInputAction.newline));
        await tester.enterText(find.byType(TextField), 'first\nsecond');
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
      });

      testMobile('outside button still receives its tap', (tester) async {
        var taps = 0;
        await pumpPage(
            tester,
            Column(children: [
              const TextField(),
              TextButton(onPressed: () => taps++, child: const Text('Apply')),
            ]));
        await tester.enterText(find.byType(TextField), 'value');
        await tester.pump();
        await tester.tap(find.text('Apply'));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isFalse);
        expect(taps, 1);
      });

      testMobile('dialog inputs inherit outside dismissal', (tester) async {
        await pumpPage(
            tester,
            Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const AlertDialog(
                            title: Text('Editor'),
                            content: TextField(),
                          ),
                        ),
                    child: const Text('Open'))));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'value');
        await tester.pump();
        await tester.tap(find.text('Editor'));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isFalse);
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testMobile('TV touch behavior is unchanged', (tester) async {
        await pumpPage(
            tester,
            const Column(children: [
              TextField(),
              Expanded(child: SizedBox.expand(key: Key('blank'))),
            ]),
            television: true);
        await tester.enterText(find.byType(TextField), 'value');
        await tester.pump();
        await tester.tapAt(tester.getCenter(find.byKey(const Key('blank'))));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
      });
    });
  }
}
