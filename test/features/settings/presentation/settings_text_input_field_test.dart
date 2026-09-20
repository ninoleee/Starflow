import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';
import 'package:starflow/features/settings/data/text_input_transfer_service.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

void main() {
  for (final kind in ['text', 'password', 'multiline', 'digits']) {
    for (final save in [true, false]) {
      testWidgets('shared scan $kind preserves confirmation, save=$save',
          (tester) async {
        final controller = TextEditingController(text: 'original');
        final service = _Service();
        await tester.pumpWidget(ProviderScope(
            overrides: [
              isTelevisionProvider.overrideWith((_) => true),
              textInputTransferServiceProvider.overrideWithValue(service),
            ],
            child: MaterialApp(
                home: Scaffold(
                    body: SettingsTextInputField(
              controller: controller,
              labelText: kind,
              autofocus: true,
              obscureText: kind == 'password',
              maxLines: kind == 'multiline' ? 4 : 1,
              inputFormatters: kind == 'digits'
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
            )))));
        await tester.pumpAndSettle();
        expect(find.byTooltip('手机扫码输入'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.byTooltip('手机扫码输入'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel,
            'settings-text-scan');
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(service.label, kind);
        expect(service.multiline, kind == 'multiline');
        expect(service.secret, kind == 'password');
        service.session.result.complete(' a12\nb34 ');
        await tester.pumpAndSettle();
        expect(controller.text, 'original');
        final expected = kind == 'digits'
            ? '1234'
            : kind == 'multiline'
                ? ' a12\nb34 '
                : ' a12b34 ';
        expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            expected);
        expect(FocusManager.instance.primaryFocus?.debugLabel,
            'settings-text-scan');
        expect(service.session.closes, 1);
        await tester.tap(find.text(save ? '保存' : '取消'));
        await tester.pumpAndSettle();
        expect(controller.text, save ? expected : 'original');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        controller.dispose();
        await service.session.errorsController.close();
      });
    }
  }

  testWidgets(
      'closing scan during startup closes late service and does not overwrite',
      (tester) async {
    final controller = TextEditingController(text: 'original');
    final service = _Service()
      ..starting = Completer<TextInputTransferSession>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((_) => true),
          textInputTransferServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SettingsTextInputField(
                    controller: controller,
                    labelText: 'Name',
                    autofocus: true)))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('手机扫码输入'));
    await tester.pumpAndSettle();
    expect(find.text('正在启动手机输入'), findsOneWidget);
    tester
        .widget<StarflowButton>(find
            .byWidgetPredicate((w) => w is StarflowButton && w.label == '关闭服务'))
        .onPressed!();
    await tester.pumpAndSettle();
    service.starting!.complete(service.session);
    await tester.pumpAndSettle();
    expect(service.session.closes, 1);
    expect(controller.text, 'original');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    controller.dispose();
    await service.session.errorsController.close();
  });
  for (final save in [false, true]) {
    testWidgets('editor resources survive the exit animation, save=$save',
        (tester) async {
      final controller = TextEditingController(text: 'original');
      addTearDown(controller.dispose);
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
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'updated');
      await tester.tap(find.text(save ? '保存' : '取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.text, save ? 'updated' : 'original');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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

class _Service implements TextInputTransferService {
  final session = _Session();
  Completer<TextInputTransferSession>? starting;
  String? label;
  bool? multiline, secret;
  @override
  Future<TextInputTransferSession> start(
      {required String label,
      bool multiline = false,
      bool obscureText = false}) async {
    this.label = label;
    this.multiline = multiline;
    secret = obscureText;
    return await (starting?.future ?? Future.value(session));
  }
}

class _Session implements TextInputTransferSession {
  final errorsController = StreamController<String>.broadcast();
  final result = Completer<String?>();
  int closes = 0;
  @override
  List<String> get urls => ['http://192.168.1.8:8123/?token=test'];
  @override
  Stream<String> get errors => errorsController.stream;
  @override
  Future<String?> get received => result.future;
  @override
  Future<void> close() async {
    closes++;
  }
}
