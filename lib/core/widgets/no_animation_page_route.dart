import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NoAnimationMaterialPage<T> extends Page<T> {
  const NoAnimationMaterialPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
    this.fullscreenDialog = false,
  });

  final Widget child;
  final bool fullscreenDialog;

  @override
  Route<T> createRoute(BuildContext context) {
    return NoAnimationMaterialPageRoute<T>(
      settings: this,
      fullscreenDialog: fullscreenDialog,
      builder: (context) => child,
    );
  }
}

class SettingsMaterialPage<T> extends Page<T> {
  const SettingsMaterialPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
    this.fullscreenDialog = false,
  });

  final Widget child;
  final bool fullscreenDialog;

  @override
  Route<T> createRoute(BuildContext context) {
    return SettingsMaterialPageRoute<T>(
      settings: this,
      fullscreenDialog: fullscreenDialog,
      builder: (context) => child,
    );
  }
}

class NoAnimationMaterialPageRoute<T> extends MaterialPageRoute<T> {
  NoAnimationMaterialPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
    this.enableNativeIosTransition = false,
  });

  final bool enableNativeIosTransition;

  bool get _usesNativeIosTransition =>
      enableNativeIosTransition &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Duration get transitionDuration =>
      _usesNativeIosTransition ? super.transitionDuration : Duration.zero;

  @override
  Duration get reverseTransitionDuration => _usesNativeIosTransition
      ? super.reverseTransitionDuration
      : Duration.zero;
}

class SettingsMaterialPageRoute<T> extends NoAnimationMaterialPageRoute<T> {
  SettingsMaterialPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(enableNativeIosTransition: true);
}
