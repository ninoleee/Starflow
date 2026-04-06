import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class AppPageBackground extends ConsumerWidget {
  const AppPageBackground({
    super.key,
    required this.child,
    this.contentPadding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final highPerformanceModeEnabled = ref.watch(
      appSettingsProvider.select((settings) => settings.highPerformanceModeEnabled),
    );
    final simplifyTelevisionEffects =
        isTelevision && highPerformanceModeEnabled;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.surfaceContainerLow,
            scheme.surface,
            scheme.surfaceContainerHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!simplifyTelevisionEffects)
            const IgnorePointer(
              child: Stack(
                children: [
                  _GlowBlob(
                    alignment: Alignment.topLeft,
                    offset: Offset(-36, -44),
                    size: 220,
                    colors: [
                      Color(0x40215FEE),
                      Color(0x00215FEE),
                    ],
                  ),
                  _GlowBlob(
                    alignment: Alignment.topRight,
                    offset: Offset(42, -24),
                    size: 196,
                    colors: [
                      Color(0x2617B26A),
                      Color(0x0017B26A),
                    ],
                  ),
                  _GlowBlob(
                    alignment: Alignment.bottomCenter,
                    offset: Offset(0, 84),
                    size: 260,
                    colors: [
                      Color(0x18F59E0B),
                      Color(0x00F59E0B),
                    ],
                  ),
                ],
              ),
            ),
          Padding(
            padding: contentPadding,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.alignment,
    required this.offset,
    required this.size,
    required this.colors,
  });

  final Alignment alignment;
  final Offset offset;
  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: colors),
          ),
        ),
      ),
    );
  }
}
