import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

class SettingsManagementItem extends StatelessWidget {
  const SettingsManagementItem({
    super.key,
    required this.title,
    required this.enabled,
    required this.onChanged,
    required this.onEdit,
    this.autofocus = false,
    this.focusIdPrefix,
  });

  final String title;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;
  final bool autofocus;
  final String? focusIdPrefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final toggleLabel = enabled ? '已开启' : '已关闭';
        final toggleIcon =
            enabled ? Icons.toggle_on_rounded : Icons.toggle_off_outlined;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      toggleLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (compact)
                StarflowIconButton(
                  icon: Icons.edit_outlined,
                  onPressed: onEdit,
                  variant: StarflowButtonVariant.secondary,
                  tooltip: '编辑',
                  autofocus: autofocus,
                  focusId: focusIdPrefix == null ? null : '$focusIdPrefix:edit',
                )
              else
                StarflowButton(
                  label: '编辑',
                  icon: Icons.edit_outlined,
                  onPressed: onEdit,
                  variant: StarflowButtonVariant.secondary,
                  compact: true,
                  autofocus: autofocus,
                  focusId: focusIdPrefix == null ? null : '$focusIdPrefix:edit',
                ),
              const SizedBox(width: 8),
              if (compact)
                StarflowIconButton(
                  icon: toggleIcon,
                  iconColor: enabled ? null : scheme.onSurfaceVariant,
                  onPressed: () => onChanged(!enabled),
                  variant: enabled
                      ? StarflowButtonVariant.primary
                      : StarflowButtonVariant.secondary,
                  tooltip: toggleLabel,
                  focusId:
                      focusIdPrefix == null ? null : '$focusIdPrefix:toggle',
                )
              else
                StarflowButton(
                  label: toggleLabel,
                  icon: toggleIcon,
                  iconColor: enabled ? null : scheme.onSurfaceVariant,
                  onPressed: () => onChanged(!enabled),
                  variant: enabled
                      ? StarflowButtonVariant.primary
                      : StarflowButtonVariant.secondary,
                  compact: true,
                  focusId:
                      focusIdPrefix == null ? null : '$focusIdPrefix:toggle',
                ),
            ],
          ),
        );
      },
    );
  }
}
