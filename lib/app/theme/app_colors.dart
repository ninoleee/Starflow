import 'package:flutter/material.dart';
import 'package:starflow/features/settings/domain/app_accent.dart';

export 'package:starflow/features/settings/domain/app_accent.dart';

/// Fixed near-neutral surfaces, independent of the selected accent.
class AppColors {
  const AppColors._();

  static const Color neutral0 = Color(0xFF08080A); // surfaceContainerLowest
  static const Color neutral1 = Color(0xFF0E0E10); // surface
  static const Color neutral2 = Color(0xFF141416); // surfaceContainerLow
  static const Color neutral3 = Color(0xFF18181B); // surfaceContainer
  static const Color neutral4 = Color(0xFF1F1F23); // surfaceContainerHigh
  static const Color neutral5 = Color(0xFF27272B); // surfaceContainerHighest

  static const Color foreground = Color(0xFFE8E8EC);
  static const Color foregroundBody = Color(0xFFCECED4);
  static const Color foregroundMuted = Color(0xFF9999A3);
  static const Color outline = Color(0xFF3A3A40);
  static const Color outlineSoft = Color(0xFF26262A);

  static const Color danger = Color(0xFFFF6B6B);
  static const Color onDanger = Color(0xFF2A0A0A);
  static const Color dangerContainer = Color(0xFF3A1618);
  static const Color onDangerContainer = Color(0xFFFFD9D9);

  static const Color layerHover = Color(0x0DFAFAFA); // 5%
  static const Color layerBorder = Color(0x1FFAFAFA); // 12%
  static const Color layerActive = Color(0x29FAFAFA); // 16%
  static const Color fgDisabled = Color(0x66FAFAFA); // 40%
  static const Color scrim = Color(0xCC000000);
}

extension AppAccentPalette on AppAccent {
  Color get primary => switch (this) {
        AppAccent.bone => const Color(0xFFFAFAFA),
        AppAccent.teal => const Color(0xFF2DD4BF),
        AppAccent.indigo => const Color(0xFF4FA3FF),
        AppAccent.coral => const Color(0xFFFF5C6C),
        AppAccent.amber => const Color(0xFFF0A93C),
        AppAccent.rose => const Color(0xFFF58FD8),
        AppAccent.lime => const Color(0xFFA8DF65),
        AppAccent.violet => const Color(0xFFA78BFA),
      };

  Color get onPrimary => switch (this) {
        AppAccent.bone => AppColors.neutral1,
        AppAccent.indigo => Colors.white,
        AppAccent.coral => Colors.white,
        AppAccent.violet => Colors.white,
        _ => AppColors.neutral0,
      };

  String get label => switch (this) {
        AppAccent.bone => '纯白（无彩）',
        AppAccent.teal => '松石青',
        AppAccent.indigo => '天蓝',
        AppAccent.coral => '绯红',
        AppAccent.amber => '琥珀金',
        AppAccent.rose => '海棠粉',
        AppAccent.lime => '青柠绿',
        AppAccent.violet => '紫罗兰',
      };
}

/// Explicit interaction accents, independent of neutral surfaces and TV focus.
@immutable
class AppActionColors extends ThemeExtension<AppActionColors> {
  const AppActionColors({required this.primary, required this.onPrimary});

  final Color primary;
  final Color onPrimary;

  static AppActionColors of(ThemeData theme) =>
      theme.extension<AppActionColors>() ??
      AppActionColors(
        primary: theme.colorScheme.primary,
        onPrimary: theme.colorScheme.onPrimary,
      );

  @override
  AppActionColors copyWith({Color? primary, Color? onPrimary}) =>
      AppActionColors(
        primary: primary ?? this.primary,
        onPrimary: onPrimary ?? this.onPrimary,
      );

  @override
  AppActionColors lerp(covariant AppActionColors? other, double t) {
    if (other == null) return this;
    return AppActionColors(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
    );
  }
}

/// Shared shape scale.
class AppRadii {
  const AppRadii._();

  /// 标签、小按钮、缩略图。
  static const double sm = 12;

  /// 卡片、面板、对话框、输入框——事实上的主圆角。
  static const double md = 18;

  /// 大容器、底部导航壳。
  static const double lg = 28;

  /// 胶囊。
  static const double pill = 999;
}
