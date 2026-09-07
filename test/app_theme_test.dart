import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/app/theme/app_theme.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('neutral text is softer without changing white accents', () {
    final theme = AppTheme.dark();
    expect(theme.textTheme.titleLarge!.color, const Color(0xFFE8E8EC));
    expect(theme.textTheme.bodyLarge!.color, const Color(0xFFCECED4));
    expect(theme.textTheme.bodyMedium!.color, const Color(0xFFCECED4));
    expect(theme.textTheme.bodySmall!.color, const Color(0xFF9999A3));
    expect(AppAccent.bone.primary, const Color(0xFFFAFAFA));
    for (final accent in [
      AppAccent.indigo,
      AppAccent.coral,
      AppAccent.violet
    ]) {
      expect(accent.onPrimary, Colors.white);
    }
  });
  test('all accents share exactly the same neutral ColorScheme', () {
    final baseline = AppTheme.dark(accent: AppAccent.bone);
    for (final accent in AppAccent.values) {
      final theme = AppTheme.dark(accent: accent);
      final actions = AppActionColors.of(theme);
      expect(theme.colorScheme, baseline.colorScheme);
      expect(theme.colorScheme.surface, const Color(0xFF0E0E10));
      expect(theme.colorScheme.surfaceContainerLowest, const Color(0xFF08080A));
      expect(
          theme.colorScheme.surfaceContainerHighest, const Color(0xFF27272B));
      expect(theme.colorScheme.surfaceTint, Colors.transparent);
      expect(actions.primary, accent.primary);
      expect(actions.onPrimary, accent.onPrimary);
      expect(theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
          accent.primary);
      expect(theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
          accent.onPrimary);
      expect(theme.progressIndicatorTheme.color, accent.primary);
      expect(
        theme.switchTheme.trackColor!.resolve({WidgetState.selected}),
        accent.primary,
      );
      expect(
        theme.inputDecorationTheme.focusedBorder!.borderSide.color,
        accent.primary,
      );
      expect(theme.chipTheme.selectedColor,
          accent.primary.withValues(alpha: 0.18));
      expect(theme.chipTheme.checkmarkColor, accent.primary);
      expect(theme.sliderTheme.activeTrackColor, accent.primary);
      expect(theme.sliderTheme.thumbColor, accent.primary);
      expect(theme.checkboxTheme.fillColor!.resolve({WidgetState.selected}),
          accent.primary);
      expect(theme.radioTheme.fillColor!.resolve({WidgetState.selected}),
          accent.primary);
      expect(theme.switchTheme.thumbColor!.resolve({WidgetState.selected}),
          accent.onPrimary);
      expect(
        theme.switchTheme.trackColor!
            .resolve({WidgetState.selected, WidgetState.disabled}),
        AppColors.foreground.withValues(alpha: 0.12),
      );
      expect(theme.colorScheme.error, AppColors.danger);
      final expectedOnPrimary = switch (accent) {
        AppAccent.bone => AppColors.neutral1,
        AppAccent.indigo => Colors.white,
        AppAccent.coral => Colors.white,
        AppAccent.violet => Colors.white,
        _ => AppColors.neutral0,
      };
      expect(accent.onPrimary, expectedOnPrimary);
    }
  });

  test('accent survives JSON, unrelated copies and legacy settings', () {
    for (final accent in AppAccent.values) {
      final settings = SeedData.defaultSettings.copyWith(appAccent: accent);
      expect(settings.toJson()['appAccent'], accent.name);
      expect(AppSettings.fromJson(settings.toJson()).appAccent, accent);
      expect(AppSettings.fromCurrentJson(settings.toJson()).appAccent, accent);
      expect(
        settings.copyWith(translucentEffectsEnabled: false).appAccent,
        accent,
      );
    }
    for (final value in [null, 'warm', '', 42]) {
      final json = SeedData.defaultSettings.toJson();
      if (value == null) {
        json.remove('appAccent');
      } else {
        json['appAccent'] = value;
      }
      expect(AppSettings.fromJson(json).appAccent, AppAccent.teal);
    }
  });

  test('action colors interpolate without changing their roles', () {
    final a = AppActionColors.of(AppTheme.dark(accent: AppAccent.bone));
    final b = AppActionColors.of(AppTheme.dark(accent: AppAccent.coral));
    expect(a.lerp(b, 0).primary, a.primary);
    expect(a.lerp(b, 1).primary, b.primary);
    expect(a.lerp(b, 1).onPrimary, b.onPrimary);
    expect(a.lerp(null, 0.5), same(a));
  });
}
