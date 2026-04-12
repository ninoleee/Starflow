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

class NoAnimationMaterialPageRoute<T> extends MaterialPageRoute<T> {
  NoAnimationMaterialPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}
