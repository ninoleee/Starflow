import 'package:flutter/material.dart';

/// 主 Tab 内列表底部尾距（当前为 0，与全屏无边距布局一致）。
const kShellScrollContentBottomPadding = 0.0;

/// 已弃用：主壳不再为底栏做 body 底部 inset，保留 API 以免外部引用报错。
@Deprecated('Shell body no longer applies bottom inset.')
double shellTabBodyBottomInset(BuildContext context) => 0;
