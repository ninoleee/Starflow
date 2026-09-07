import 'package:flutter/material.dart';

/// Neutral page background without decorative glow layers.
class AppPageBackground extends StatelessWidget {
  const AppPageBackground({
    super.key,
    required this.child,
    this.contentPadding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: contentPadding,
        child: child,
      ),
    );
  }
}
