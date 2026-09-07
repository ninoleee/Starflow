import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:starflow/app/theme/app_colors.dart';

class AppTheme {
  static const String _webFontFamily = 'system-ui';
  static const _cjkFontFallback = <String>[
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'sans-serif',
  ];

  static ThemeData get darkTheme => dark();

  static ThemeData dark({AppAccent accent = AppAccent.teal}) {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.foreground,
      onPrimary: AppColors.neutral1,
      primaryContainer: AppColors.neutral5,
      onPrimaryContainer: AppColors.foreground,
      secondary: AppColors.foregroundMuted,
      onSecondary: AppColors.neutral1,
      secondaryContainer: AppColors.neutral4,
      onSecondaryContainer: AppColors.foreground,
      tertiary: AppColors.foregroundMuted,
      onTertiary: AppColors.neutral1,
      tertiaryContainer: AppColors.neutral4,
      onTertiaryContainer: AppColors.foreground,
      error: AppColors.danger,
      onError: AppColors.onDanger,
      errorContainer: AppColors.dangerContainer,
      onErrorContainer: AppColors.onDangerContainer,
      surface: AppColors.neutral1,
      onSurface: AppColors.foreground,
      surfaceContainerLowest: AppColors.neutral0,
      surfaceContainerLow: AppColors.neutral2,
      surfaceContainer: AppColors.neutral3,
      surfaceContainerHigh: AppColors.neutral4,
      surfaceContainerHighest: AppColors.neutral5,
      onSurfaceVariant: AppColors.foregroundMuted,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineSoft,
      shadow: Color(0xFF000000),
      scrim: AppColors.scrim,
      inverseSurface: AppColors.foreground,
      onInverseSurface: AppColors.neutral3,
      inversePrimary: AppColors.neutral3,
      // M3 默认会把 primary 按高度叠到表面上，中性方案里这层会让卡片泛色。
      surfaceTint: Colors.transparent,
    );
    return _buildTheme(
      colorScheme,
      AppActionColors(primary: accent.primary, onPrimary: accent.onPrimary),
    );
  }

  static ThemeData _buildTheme(
    ColorScheme colorScheme,
    AppActionColors actions,
  ) {
    final baseTextTheme = _applyAppFonts(
      ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
      ).textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      extensions: [actions],
      fontFamily: kIsWeb ? _webFontFamily : null,
      scaffoldBackgroundColor: colorScheme.surface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseTextTheme.copyWith(
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: AppColors.foregroundBody,
          height: 1.5,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: AppColors.foregroundBody,
          height: 1.45,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          color: AppColors.foregroundBody,
          fontWeight: FontWeight.w700,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: AppColors.foregroundMuted,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          color: AppColors.foregroundMuted,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          color: AppColors.foregroundMuted,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: actions.primary,
          foregroundColor: actions.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.foregroundBody,
          side: BorderSide(color: colorScheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.foregroundBody,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: actions.primary.withValues(alpha: 0.18),
        secondarySelectedColor: actions.primary.withValues(alpha: 0.18),
        checkmarkColor: actions.primary,
        labelStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: TextStyle(
          color: actions.primary,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(
            color: actions.primary,
            width: 1.4,
          ),
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return actions.onPrimary;
          }
          return colorScheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.selected)) {
            return actions.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: actions.primary,
        thumbColor: actions.primary,
        overlayColor: actions.primary.withValues(alpha: 0.12),
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return null;
          return states.contains(WidgetState.selected) ? actions.primary : null;
        }),
        checkColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled)
              ? null
              : actions.onPrimary;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return null;
          return states.contains(WidgetState.selected) ? actions.primary : null;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: actions.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    );
  }

  static TextTheme _applyAppFonts(TextTheme textTheme) {
    return textTheme.copyWith(
      displayLarge: _withAppFont(textTheme.displayLarge),
      displayMedium: _withAppFont(textTheme.displayMedium),
      displaySmall: _withAppFont(textTheme.displaySmall),
      headlineLarge: _withAppFont(textTheme.headlineLarge),
      headlineMedium: _withAppFont(textTheme.headlineMedium),
      headlineSmall: _withAppFont(textTheme.headlineSmall),
      titleLarge: _withAppFont(textTheme.titleLarge),
      titleMedium: _withAppFont(textTheme.titleMedium),
      titleSmall: _withAppFont(textTheme.titleSmall),
      bodyLarge: _withAppFont(textTheme.bodyLarge),
      bodyMedium: _withAppFont(textTheme.bodyMedium),
      bodySmall: _withAppFont(textTheme.bodySmall),
      labelLarge: _withAppFont(textTheme.labelLarge),
      labelMedium: _withAppFont(textTheme.labelMedium),
      labelSmall: _withAppFont(textTheme.labelSmall),
    );
  }

  static TextStyle? _withAppFont(TextStyle? style) {
    if (style == null) {
      return null;
    }
    return style.copyWith(
      fontFamily: kIsWeb ? _webFontFamily : null,
      fontFamilyFallback: _cjkFontFallback,
    );
  }
}
