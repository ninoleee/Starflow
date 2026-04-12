import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

const double _kOverlayToolbarBackButtonWidth = 64;
const double _kOverlayToolbarBackButtonHorizontalPadding = 16;

/// 无 AppBar 全屏页顶栏：左侧返回，右侧可选控件（高度 [kToolbarHeight]，无标题）。
class OverlayToolbar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final color = leadingColor ?? Theme.of(context).colorScheme.onSurface;
    final topInset = MediaQuery.paddingOf(context).top;
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final backAction = onBack ?? () => Navigator.maybePop(context);
    final showBackButton = !isTelevision;
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: SizedBox(
          height: kToolbarHeight,
          width: double.infinity,
          child: Row(
            children: [
              if (showBackButton)
                TvFocusableAction(
                  onPressed: backAction,
                  borderRadius: BorderRadius.circular(18),
                  visualStyle: TvFocusVisualStyle.subtle,
                  child: SizedBox(
                    width: _kOverlayToolbarBackButtonWidth,
                    height: kToolbarHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal:
                              _kOverlayToolbarBackButtonHorizontalPadding,
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
