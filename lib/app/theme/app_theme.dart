import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1C57D5),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCE7FF),
      onPrimaryContainer: Color(0xFF0E2455),
      secondary: Color(0xFF0E7490),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD7F0F7),
      onSecondaryContainer: Color(0xFF082E3A),
      tertiary: Color(0xFFB7791F),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFFBE7C2),
      onTertiaryContainer: Color(0xFF4B2E05),
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFFFCFF),
      onSurface: Color(0xFF111827),
      surfaceContainerHighest: Color(0xFFE9EEF7),
      onSurfaceVariant: Color(0xFF5C667A),
      outline: Color(0xFFD5DEED),
      outlineVariant: Color(0xFFE6EBF5),
      shadow: Color(0x1A0D1B2A),
      scrim: Color(0x660B1120),
      inverseSurface: Color(0xFF0C1627),
      onInverseSurface: Color(0xFFF5F8FF),
      inversePrimary: Color(0xFFB5CBFF),
      surfaceTint: Color(0xFF1C57D5),
    );
    final baseTextTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    ).textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF2F5FB),
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseTextTheme.copyWith(
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          color: colorScheme.onSurface,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: colorScheme.onSurface,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: colorScheme.onSurface,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurface,
          height: 1.5,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          height: 1.45,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
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
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white);
          }
          return const IconThemeData(color: Color(0xFFBDD2FF));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xFFBDD2FF),
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF1F5FF),
        selectedColor: colorScheme.primaryContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.72),
            width: 1.4,
          ),
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFFFFFCFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primaryContainer;
            }
            return const Color(0xFFF5F7FD);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimaryContainer;
            }
            return colorScheme.onSurfaceVariant;
          }),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w700),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          side: WidgetStateProperty.all(
            BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
        circularTrackColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0F1C2F),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
