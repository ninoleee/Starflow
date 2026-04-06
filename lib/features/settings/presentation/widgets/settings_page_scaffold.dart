import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

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
    this.keyboardDismissBehavior =
        ScrollViewKeyboardDismissBehavior.onDrag,
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
                SizedBox(height: bottomSpacing),
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
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final StarflowButtonVariant variant;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    return StarflowButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      variant: variant,
      compact: !isTelevision,
      expand: expand,
      loading: loading,
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
