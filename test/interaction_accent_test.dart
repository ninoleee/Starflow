import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

void main() {
  testWidgets('TV chips keep white focus across selections and theme changes',
      (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    for (final accent in [AppAccent.teal, AppAccent.coral, AppAccent.bone]) {
      for (final selected in [false, true]) {
        await tester.pumpWidget(ProviderScope(
          overrides: [isTelevisionProvider.overrideWith((ref) => true)],
          child: MaterialApp(
            theme: AppTheme.dark(accent: accent),
            home: Scaffold(
              body: Center(
                child: StarflowChipButton(
                  label: 'Selected',
                  selected: selected,
                  icon: Icons.tune,
                  focusNode: node,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ));
        node.requestFocus();
        await tester.pumpAndSettle();
        expect(node.hasFocus, isTrue);
        if (selected) {
          expect(
              tester
                  .widget<Icon>(find.byIcon(Icons.check_circle_rounded))
                  .color,
              accent.primary);
        }
        final container = tester.widget<AnimatedContainer>(find.descendant(
          of: find.byType(StarflowChipButton),
          matching: find.byType(AnimatedContainer),
        ));
        final decoration = container.decoration! as BoxDecoration;
        if (selected) {
          expect(decoration.color, accent.primary.withValues(alpha: 0.18));
        }
        expect((decoration.border! as Border).top.color,
            Colors.white);
      }
    }
  });

  testWidgets('active toggle and checkbox use interaction accents',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [isTelevisionProvider.overrideWith((ref) => false)],
      child: MaterialApp(
        theme: AppTheme.dark(accent: AppAccent.rose),
        home: Scaffold(
            body: Column(children: [
          StarflowToggleTile(title: 'On', value: true, onChanged: (_) {}),
          StarflowToggleTile(title: 'Off', value: false, onChanged: (_) {}),
          StarflowCheckboxTile(
              title: 'Checked', value: true, onChanged: (_) {}),
        ])),
      ),
    ));
    expect(tester.widget<Icon>(find.byIcon(Icons.toggle_on_rounded)).color,
        AppAccent.rose.primary);
    expect(tester.widget<Icon>(find.byIcon(Icons.check_box_rounded)).color,
        AppAccent.rose.primary);
    expect(tester.widget<Icon>(find.byIcon(Icons.toggle_off_outlined)).color,
        AppColors.foregroundMuted);
  });
}
