import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

final _sectionPanelReduceDecorationsProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider.select(
    (settings) => settings.performanceReduceDecorationsEnabled,
  ));
});

class SectionPanel extends ConsumerWidget {
  const SectionPanel({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.actionLabel,
    this.onActionPressed,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final EdgeInsets padding;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasSubtitle = subtitle.trim().isNotEmpty;
    final reduceDecorationsEnabled =
        ref.watch(_sectionPanelReduceDecorationsProvider);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.92),
        ),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surfaceContainerHigh,
            theme.colorScheme.surfaceContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: reduceDecorationsEnabled
            ? null
            : [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              if (actionLabel != null &&
                  actionLabel!.trim().isNotEmpty &&
                  onActionPressed != null)
                StarflowButton(
                  label: actionLabel!,
                  onPressed: onActionPressed,
                  variant: StarflowButtonVariant.secondary,
                  compact: true,
                ),
            ],
          ),
          if (hasSubtitle) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}
