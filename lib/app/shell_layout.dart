import 'package:flutter/material.dart';

/// Tab 内滚动列表最后一项下方的「内容尾距」（主壳已统一为底栏让位）。
const kShellScrollContentBottomPadding = 24.0;

/// 主壳 `extendBody` + 浮动底栏时，为 **整个 Tab 内容区** 预留的底部高度。
/// 含系统 home 指示区、底栏视觉高度及与内容之间的空隙。
double shellTabBodyBottomInset(BuildContext context) {
  final safeBottom = MediaQuery.of(context).viewPadding.bottom;
  const floatingBarVisualHeight = 72.0;
  const gapAboveBar = 16.0;
  /// 底栏与屏幕下缘的「悬浮」间距（与 app_router 中 Padding 一致）。
  const floatingBarBottomFloatMargin = 12.0;
  return safeBottom +
      floatingBarVisualHeight +
      gapAboveBar +
      floatingBarBottomFloatMargin;
}
