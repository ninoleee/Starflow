import 'package:flutter/material.dart';

/// 无 AppBar 全屏页顶栏：左侧返回，右侧可选控件（高度 [kToolbarHeight]，无标题）。
class OverlayToolbar extends StatelessWidget {
  const OverlayToolbar({
    super.key,
    this.onBack,
    this.leadingColor,
    this.trailing,
  });

  final VoidCallback? onBack;
  final Color? leadingColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = leadingColor ?? Theme.of(context).colorScheme.onSurface;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: kToolbarHeight,
        width: double.infinity,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              color: color,
              onPressed: onBack ?? () => Navigator.maybePop(context),
            ),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
