import 'package:flutter/material.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

class LiveIconButton extends StatelessWidget {
  const LiveIconButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed,
      this.autofocus = false,
      this.focusNode});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => Tooltip(
      message: label,
      child: Semantics(
          label: label,
          button: true,
          child: TvFocusableAction(
              autofocus: autofocus,
              focusNode: focusNode,
              onPressed: onPressed,
              focusableWhenDisabled: true,
              child: SizedBox(width: 48, height: 48, child: Icon(icon)))));
}

void liveMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String liveTime(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
