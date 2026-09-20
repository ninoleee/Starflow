import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/widgets/navigation_destination_dialog.dart';

void main() {
  for (final tv in [false, true]) {
    testWidgets('menu editing saves order and selection (TV: $tv)',
        (tester) async {
      List<String>? result;
      await _open(tester, tv: tv, onResult: (value) => result = value);
      expect(_order(tester).take(3), ['library', 'home', 'settings']);
      await _activate(tester, find.byTooltip('上移首页'), tv: tv);
      await _activate(tester, find.text('搜索'), tv: tv);
      await _activate(tester, find.text('保存'), tv: tv);
      expect(result, ['home', 'library', 'settings', 'search']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancel discards draft and settings cannot be hidden',
      (tester) async {
    List<String>? result = [];
    await _open(tester, onResult: (value) => result = value);
    final settings = tester.widget<StarflowCheckboxTile>(
      find.byWidgetPredicate(
          (widget) => widget is StarflowCheckboxTile && widget.title == '设置'),
    );
    expect(settings.onChanged, isNull);
    expect(settings.value, isTrue);
    await tester.tap(find.byTooltip('上移首页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('TV move button keeps focus at the boundary', (tester) async {
    await _open(tester, tv: true);
    final up = find.byWidgetPredicate((widget) =>
        widget is TvFocusableAction &&
        widget.focusId == 'navigation-editor:home:up');
    Focus.of(tester.element(
            find.descendant(of: up, matching: find.byType(Icon)).first))
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_order(tester).first, 'home');
    expect(
        Focus.of(tester.element(
                find.descendant(of: up, matching: find.byType(Icon)).first))
            .hasPrimaryFocus,
        isTrue);
    final button = tester.widget<StarflowIconButton>(find.byWidgetPredicate(
        (widget) =>
            widget is StarflowIconButton &&
            widget.focusId == 'navigation-editor:home:up'));
    expect(button.onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_order(tester).first, 'home');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
        Focus.of(tester.element(
                find.descendant(of: up, matching: find.byType(Icon)).first))
            .hasPrimaryFocus,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile drag handle reorders without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<String>? result;
    await _open(tester, onResult: (value) => result = value);
    final handle = find.byType(ReorderableDragStartListener).first;
    await tester.drag(handle, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(_order(tester).first, 'home');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result!.indexOf('home'), lessThan(result!.indexOf('library')));
    expect(tester.takeException(), isNull);
  });
}

List<String> _order(WidgetTester tester) => tester
    .widgetList<StarflowCheckboxTile>(find.byType(StarflowCheckboxTile))
    .map((tile) => tile.focusId!.split(':')[1])
    .toList();

Future<void> _activate(WidgetTester tester, Finder target,
    {required bool tv}) async {
  if (tv) {
    final leaf = find.descendant(
      of: target,
      matching: find.byWidgetPredicate(
        (widget) => widget is Icon || widget is Text,
      ),
      matchRoot: true,
    ).first;
    Focus.of(tester.element(leaf)).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await tester.tap(target);
  }
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester, {
  bool tv = false,
  ValueChanged<List<String>?>? onResult,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [isTelevisionProvider.overrideWith((ref) => tv)],
    child: MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        final result = await showDialog<List<String>>(
                          context: context,
                          builder: (_) => const NavigationDestinationDialog(
                            initialSelection: ['library', 'home', 'settings'],
                          ),
                        );
                        onResult?.call(result);
                      },
                      child: const Text('open')),
                ))),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
