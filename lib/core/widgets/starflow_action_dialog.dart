import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

class StarflowDialogAction<T> {
  const StarflowDialogAction({
    required this.label,
    required this.value,
    this.icon,
    this.variant = StarflowButtonVariant.secondary,
    this.autofocus = false,
  });

  final String label;
  final T value;
  final IconData? icon;
  final StarflowButtonVariant variant;
  final bool autofocus;
}

Future<T?> showStarflowActionDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  required List<StarflowDialogAction<T>> actions,
  bool barrierDismissible = true,
  bool allowSystemDismiss = true,
}) {
  assert(
    message == null || content == null,
    'Provide either message or content, not both.',
  );
  final isTelevision =
      ProviderScope.containerOf(context, listen: false)
          .read(isTelevisionProvider)
          .value ??
      false;
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final dialog = wrapTelevisionDialogFieldTraversal(
        enabled: isTelevision,
        child: AlertDialog(
          title: Text(title),
          content: content ?? (message == null ? null : Text(message)),
          actions: [
            for (final action in actions)
              StarflowButton(
                label: action.label,
                icon: action.icon,
                onPressed: () => Navigator.of(dialogContext).pop(action.value),
                variant: action.variant,
                compact: true,
                autofocus: isTelevision && action.autofocus,
              ),
          ],
        ),
      );
      if (allowSystemDismiss) {
        return dialog;
      }
      return PopScope(
        canPop: false,
        child: dialog,
      );
    },
  );
}
