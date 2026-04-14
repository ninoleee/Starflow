import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/settings_version_label.dart';

enum SettingsCloseAction {
  cancel,
  discard,
  save,
}

class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.children,
    this.onBack,
    this.trailing,
    this.listPadding,
    this.bottomSpacing = kBottomReservedSpacing,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.onDrag,
  });

  final List<Widget> children;
  final VoidCallback? onBack;
  final Widget? trailing;
  final EdgeInsets? listPadding;
  final double bottomSpacing;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ListView(
              padding: listPadding ?? overlayToolbarPagePadding(context),
              keyboardDismissBehavior: keyboardDismissBehavior,
              children: [
                ...children,
                _SettingsVersionFooter(bottomSpacing: bottomSpacing),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: onBack,
                trailing: trailing,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final Future<PackageInfo> _settingsPackageInfoFuture =
    PackageInfo.fromPlatform();

class _SettingsVersionFooter extends StatelessWidget {
  const _SettingsVersionFooter({
    required this.bottomSpacing,
  });

  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<PackageInfo>(
      future: _settingsPackageInfoFuture,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) {
          return SizedBox(height: bottomSpacing);
        }
        final footerInfo = resolveSettingsVersionFooterInfo(info);
        if (footerInfo == null) {
          return SizedBox(height: bottomSpacing);
        }
        return Padding(
          padding: EdgeInsets.only(
            top: 18,
            bottom: bottomSpacing,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  footerInfo.author,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.72,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TvFocusableAction(
                  focusId: 'settings-footer:version',
                  onPressed: () {},
                  visualStyle: TvFocusVisualStyle.subtle,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      footerInfo.version,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.82,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (footerInfo.buildDate.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    footerInfo.buildDate,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.72,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class SettingsToolbarButton extends StatelessWidget {
  const SettingsToolbarButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SettingsActionButton(
        label: label,
        icon: icon,
        onPressed: onPressed,
        loading: loading,
        variant: StarflowButtonVariant.ghost,
      ),
    );
  }
}

class SettingsActionButton extends ConsumerWidget {
  const SettingsActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = StarflowButtonVariant.secondary,
    this.loading = false,
    this.expand = false,
    this.autofocus = false,
    this.focusNode,
    this.focusId,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final StarflowButtonVariant variant;
  final bool loading;
  final bool expand;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    return StarflowButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      variant: variant,
      compact: !isTelevision,
      expand: expand,
      loading: loading,
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
    );
  }
}

class SettingsSelectionTile extends StatelessWidget {
  const SettingsSelectionTile({
    super.key,
    required this.title,
    required this.value,
    required this.onPressed,
    this.subtitle = '',
    this.leading,
    this.trailing,
    this.autofocus = false,
    this.focusNode,
    this.focusId,
  });

  final String title;
  final String value;
  final VoidCallback? onPressed;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;

  @override
  Widget build(BuildContext context) {
    return StarflowSelectionTile(
      title: title,
      value: value,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
    );
  }
}

class SettingsToggleTile extends StatelessWidget {
  const SettingsToggleTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle = '',
    this.autofocus = false,
    this.focusNode,
    this.focusId,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String subtitle;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;

  @override
  Widget build(BuildContext context) {
    return StarflowToggleTile(
      title: title,
      value: value,
      subtitle: subtitle,
      onChanged: onChanged,
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
    );
  }
}

class SettingsExpandableSection extends StatelessWidget {
  const SettingsExpandableSection({
    super.key,
    required this.title,
    required this.expanded,
    required this.onChanged,
    required this.children,
    this.subtitle = '',
  });

  final String title;
  final bool expanded;
  final ValueChanged<bool>? onChanged;
  final List<Widget> children;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSelectionTile(
          title: title,
          subtitle: subtitle,
          value: expanded ? '已展开' : '已收起',
          onPressed: onChanged == null ? null : () => onChanged!(!expanded),
          trailing: Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 12),
          ...children,
        ],
      ],
    );
  }
}

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({
    super.key,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class SettingsInfoCard extends StatelessWidget {
  const SettingsInfoCard({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> buildSettingsTileGroup(
  List<Widget> children, {
  double spacing = 18,
}) {
  if (children.isEmpty) {
    return const <Widget>[];
  }

  final result = <Widget>[];
  for (var index = 0; index < children.length; index++) {
    if (index > 0) {
      result.add(SizedBox(height: spacing));
    }
    result.add(children[index]);
  }
  return result;
}

class SettingsCheckboxDialogOption<T> {
  const SettingsCheckboxDialogOption({
    required this.value,
    required this.title,
    this.subtitle = '',
  });

  final T value;
  final String title;
  final String subtitle;
}

class SettingsCheckboxDialogSection<T> {
  const SettingsCheckboxDialogSection({
    required this.options,
    this.title = '',
  });

  final String title;
  final List<SettingsCheckboxDialogOption<T>> options;
}

Future<SettingsCloseAction> showSettingsCloseConfirmDialog(
  BuildContext context,
) async {
  final action = await showDialog<SettingsCloseAction>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('保存修改？'),
        content: const Text('当前页面有未保存的修改，返回前要怎么处理？'),
        actions: [
          StarflowButton(
            label: '取消',
            onPressed: () =>
                Navigator.of(dialogContext).pop(SettingsCloseAction.cancel),
            variant: StarflowButtonVariant.ghost,
            compact: true,
          ),
          StarflowButton(
            label: '不保存',
            onPressed: () =>
                Navigator.of(dialogContext).pop(SettingsCloseAction.discard),
            variant: StarflowButtonVariant.secondary,
            compact: true,
          ),
          StarflowButton(
            label: '保存',
            onPressed: () =>
                Navigator.of(dialogContext).pop(SettingsCloseAction.save),
            compact: true,
          ),
        ],
      );
    },
  );
  return action ?? SettingsCloseAction.cancel;
}

Future<T?> showSettingsOptionDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T option) labelBuilder,
  T? currentValue,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      return SimpleDialog(
        title: Text(title),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Text(
                option == currentValue
                    ? '${labelBuilder(option)}  当前'
                    : labelBuilder(option),
              ),
            ),
        ],
      );
    },
  );
}

Future<Set<T>?> showSettingsCheckboxSelectionDialog<T>({
  required BuildContext context,
  required String title,
  required Set<T> initialSelection,
  required List<SettingsCheckboxDialogSection<T>> sections,
  required String allLabel,
  required String allSubtitle,
  String cancelLabel = '取消',
  String clearLabel = '全部来源',
  String confirmLabel = '保存',
}) {
  return showDialog<Set<T>>(
    context: context,
    builder: (dialogContext) {
      var draft = <T>{...initialSelection};
      return StatefulBuilder(
        builder: (context, setState) {
          final visibleSections = sections
              .where((section) => section.options.isNotEmpty)
              .toList(growable: false);
          final theme = Theme.of(context);
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StarflowCheckboxTile(
                      title: allLabel,
                      subtitle: allSubtitle,
                      value: draft.isEmpty,
                      onChanged: (_) {
                        setState(() {
                          draft = <T>{};
                        });
                      },
                    ),
                    for (var index = 0;
                        index < visibleSections.length;
                        index++) ...[
                      const Divider(height: 16),
                      if (visibleSections[index].title.trim().isNotEmpty) ...[
                        Text(
                          visibleSections[index].title,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                      ],
                      for (final option in visibleSections[index].options)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: StarflowCheckboxTile(
                            title: option.title,
                            subtitle: option.subtitle,
                            value: draft.contains(option.value),
                            onChanged: (checked) {
                              setState(() {
                                if (checked) {
                                  draft.add(option.value);
                                } else {
                                  draft.remove(option.value);
                                }
                              });
                            },
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              StarflowButton(
                label: cancelLabel,
                onPressed: () => Navigator.of(dialogContext).pop(),
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
              StarflowButton(
                label: clearLabel,
                onPressed: () => Navigator.of(dialogContext).pop(<T>{}),
                variant: StarflowButtonVariant.secondary,
                compact: true,
              ),
              StarflowButton(
                label: confirmLabel,
                onPressed: () => Navigator.of(dialogContext).pop(draft),
                compact: true,
              ),
            ],
          );
        },
      );
    },
  );
}
