import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/starflow_action_dialog.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

Iterable<Color> backgrounds(WidgetTester tester, Finder button) => tester
    .widgetList<DecoratedBox>(
      find.descendant(of: button, matching: find.byType(DecoratedBox)),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .map((decoration) => decoration.color)
    .whereType<Color>();

void main() {
  for (final television in [false, true]) {
    for (final surface in ['page', 'alert', 'simple', 'dialog', 'sheet']) {
      testWidgets('primary style on $surface, TV: $television', (tester) async {
        final buttons = Wrap(
          children: [
            StarflowButton(label: 'Confirm', onPressed: () {}),
            TvAdaptiveButton(
              label: 'Save',
              icon: Icons.save,
              onPressed: () {},
            ),
            StarflowButton(
              label: 'Cancel',
              variant: StarflowButtonVariant.ghost,
              onPressed: () {},
            ),
            StarflowButton(
              label: 'Delete',
              variant: StarflowButtonVariant.danger,
              onPressed: () {},
            ),
          ],
        );
        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWithValue(AsyncData(television)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(accent: AppAccent.bone),
            home: Scaffold(
              body: switch (surface) {
                'alert' => AlertDialog(actions: [buttons]),
                'simple' => SimpleDialog(children: [buttons]),
                'dialog' => Dialog(child: buttons),
                'sheet' =>
                  BottomSheet(onClosing: () {}, builder: (context) => buttons),
                _ => buttons,
              },
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final expected = television && surface != 'page'
            ? Colors.white.withValues(alpha: 0.06)
            : AppAccent.bone.primary;
        for (final label in ['Confirm', 'Save']) {
          expect(
              backgrounds(tester, find.widgetWithText(StarflowButton, label)),
              contains(expected));
        }
        expect(
          backgrounds(tester, find.widgetWithText(StarflowButton, 'Cancel')),
          contains(Colors.transparent),
        );
        expect(
          backgrounds(tester, find.widgetWithText(StarflowButton, 'Delete')),
          contains(
              AppTheme.darkTheme.colorScheme.error.withValues(alpha: 0.10)),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('shared dialog preserves results and visible remote focus',
      (tester) async {
    bool? result;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWithValue(const AsyncData(true))
      ],
      child: MaterialApp(
        theme: AppTheme.dark(accent: AppAccent.bone),
        home: Builder(builder: (context) {
          return TextButton(
            child: const Text('Open'),
            onPressed: () async {
              result = await showStarflowActionDialog<bool>(
                context: context,
                title: 'Confirm changes',
                actions: const [
                  StarflowDialogAction(
                    label: 'Cancel',
                    value: false,
                    autofocus: true,
                    variant: StarflowButtonVariant.ghost,
                  ),
                  StarflowDialogAction(
                    label: 'Confirm',
                    value: true,
                    variant: StarflowButtonVariant.primary,
                  ),
                ],
              );
            },
          );
        }),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(StarflowButton, 'Confirm');
    final cancel = find.widgetWithText(StarflowButton, 'Cancel');
    FocusNode node(Finder button) => tester
        .widget<FocusableActionDetector>(find.descendant(
            of: button, matching: find.byType(FocusableActionDetector)))
        .focusNode!;
    expect(node(cancel).hasPrimaryFocus, isTrue);
    expect(backgrounds(tester, confirm),
        contains(Colors.white.withValues(alpha: 0.06)));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(node(confirm).hasPrimaryFocus, isTrue);
    expect(node(cancel).hasPrimaryFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('TV focus outline is brighter than the unfocused border',
      (tester) async {
    final boundaryKey = GlobalKey();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var presses = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        isTelevisionProvider.overrideWithValue(const AsyncData(true))
      ],
      child: MaterialApp(
        theme: AppTheme.dark(accent: AppAccent.bone),
        home: Scaffold(
          body: AlertDialog(actions: [
            RepaintBoundary(
              key: boundaryKey,
              child: StarflowButton(
                label: 'Confirm',
                focusNode: focus,
                onPressed: () => presses++,
              ),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    Future<int> borderRed() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          return bytes.getUint8((image.width + image.width ~/ 2) * 4);
        } finally {
          image.dispose();
        }
      }))!;
    }

    final unfocusedRed = await borderRed();
    focus.requestFocus();
    await tester.pumpAndSettle();
    final focusedRed = await borderRed();
    expect(focusedRed, greaterThan(230));
    expect(focusedRed - unfocusedRed, greaterThan(100));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(presses, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
