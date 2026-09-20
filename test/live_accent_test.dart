import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/live_tv/presentation/live_widgets.dart';

void main() {
  for (final accent in AppAccent.values) {
    for (final tv in [false, true]) {
      testWidgets('live selection colors and fixed bounds $accent tv=$tv',
          (tester) async {
        var selected = true;
        var enabled = true;
        late StateSetter rebuild;
        await tester.pumpWidget(ProviderScope(
            overrides: [isTelevisionProvider.overrideWith((_) => tv)],
            child: MaterialApp(
                theme: AppTheme.dark(accent: accent)
                    .copyWith(splashFactory: NoSplash.splashFactory),
                home: Scaffold(
                    body: StatefulBuilder(builder: (context, setState) {
                  rebuild = setState;
                  return Column(children: [
                    LiveIconButton(
                        icon: Icons.star,
                        label: 'Favorite',
                        selected: selected,
                        onPressed: enabled ? () {} : null),
                    SizedBox(
                        width: 180,
                        height: 48,
                        child: LiveSelectionLabel(
                            label: 'A long selected option that must truncate',
                            selected: selected,
                            enabled: enabled)),
                  ]);
                })))));
        await tester.pumpAndSettle();
        final label = find.byType(LiveSelectionLabel);
        final size = tester.getSize(label);
        expect(
            tester.widget<Icon>(find.byIcon(Icons.star)).color, accent.primary);
        expect(tester.widget<Icon>(find.byIcon(Icons.check)).color,
            accent.primary);
        expect(tester.widget<Text>(find.byType(Text)).style!.color,
            accent.primary);
        rebuild(() => enabled = false);
        await tester.pumpAndSettle();
        expect(tester.widget<Icon>(find.byIcon(Icons.star)).color,
            AppColors.fgDisabled);
        expect(tester.widget<Text>(find.byType(Text)).style!.color,
            AppColors.fgDisabled);
        rebuild(() {
          enabled = true;
          selected = false;
        });
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check), findsNothing);
        expect(tester.widget<Icon>(find.byIcon(Icons.star)).color, isNull);
        expect(tester.widget<Text>(find.byType(Text)).style!.color,
            AppColors.foregroundBody);
        expect(tester.getSize(label), size);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
