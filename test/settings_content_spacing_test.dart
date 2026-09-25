import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

void main() {
  test('settings group preserves explicit spacing and empty groups', () {
    expect(buildSettingsTileGroup([]), isEmpty);
    expect(buildSettingsTileGroup([const Text('one')]), hasLength(1));
    final defaults = buildSettingsTileGroup(
      [const Text('one'), const Text('two')],
    );
    expect((defaults[1] as SizedBox).height, 8);
    final children = buildSettingsTileGroup(
      [const Text('one'), const Text('two')],
      spacing: 18,
    );
    expect((children[1] as SizedBox).height, 18);
  });

  testWidgets('settings section title uses compact content spacing',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SettingsSectionTitle(label: 'Section'),
      ),
    ));
    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(SettingsSectionTitle),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, const EdgeInsets.only(top: 12, bottom: 10));
  });

  for (final television in [false, true]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('settings spacing TV $television scale $scale',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(ProviderScope(
          overrides: [
            isTelevisionProvider.overrideWith((ref) => television),
            appSettingsProvider.overrideWithValue(SeedData.defaultSettings),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: buildSettingsTileGroup([
                  const SettingsInfoCard(
                    title: 'Playback settings',
                    description: 'Long supporting text wraps across lines.',
                  ),
                  SettingsStepperTile(
                    title: 'Subtitle size',
                    subtitle: 'Adjust the current value',
                    value: '24',
                    onDecrease: () {},
                    onIncrease: () {},
                  ),
                ]),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final info = tester.getRect(find.byType(SettingsInfoCard));
        final stepper = tester.getRect(find.byType(SettingsStepperTile));
        expect(stepper.top - info.bottom, 8);
        expect(stepper.height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
