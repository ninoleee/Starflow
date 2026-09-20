import 'package:flutter/material.dart';
import 'package:starflow/app/theme/app_colors.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

import '../domain/live_models.dart';

class LiveCurrentProgramme extends StatelessWidget {
  const LiveCurrentProgramme({super.key, this.programme, this.compact = false});

  final LiveProgramme? programme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final title = programme?.title.trim() ?? '';
    final label = title.isEmpty ? '暂无节目信息' : '正在播出 $title';
    return Tooltip(
        message: label,
        child: Text(compact && title.isNotEmpty ? title : label,
            semanticsLabel: label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis));
  }
}

class LiveIconButton extends StatelessWidget {
  const LiveIconButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed,
      this.selected = false,
      this.autofocus = false,
      this.focusNode});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => Tooltip(
      message: label,
      child: Semantics(
          label: label,
          button: true,
          selected: selected,
          child: TvFocusableAction(
              autofocus: autofocus,
              focusNode: focusNode,
              onPressed: onPressed,
              focusableWhenDisabled: true,
              child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(icon,
                      color: onPressed == null
                          ? AppColors.fgDisabled
                          : selected
                              ? AppActionColors.of(Theme.of(context)).primary
                              : null)))));
}

class LiveSelectionLabel extends StatelessWidget {
  const LiveSelectionLabel(
      {super.key,
      required this.label,
      required this.selected,
      this.enabled = true});

  final String label;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.fgDisabled
        : selected
            ? AppActionColors.of(Theme.of(context)).primary
            : AppColors.foregroundBody;
    return Semantics(
        selected: selected,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 24,
              child:
                  selected ? Icon(Icons.check, size: 18, color: color) : null),
          Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color))),
        ]));
  }
}

void liveMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String liveTime(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
