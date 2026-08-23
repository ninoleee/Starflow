import 'package:flutter/material.dart';

/// Registers a page-owned scroll controller as the route's primary controller.
///
/// This keeps explicit controllers compatible with iOS's status-bar tap gesture,
/// which asks the surrounding [Scaffold] to scroll the primary controller to
/// the top.
class AppPrimaryScrollController extends StatelessWidget {
  const AppPrimaryScrollController({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: controller,
      child: child,
    );
  }
}

/// 主 Tab 内列表底部尾距（当前为 0，与全屏无边距布局一致）。
const kShellScrollContentBottomPadding = 0.0;
const kAppPageHorizontalPadding = 14.0;
const kBottomReservedSpacing = 80.0;

/// 已弃用：主壳不再为底栏做 body 底部 inset，保留 API 以免外部引用报错。
@Deprecated('Shell body no longer applies vertical inset.')
double shellTabBodyBottomInset(BuildContext context) => 0;

double appPageTopInset(BuildContext context) => 0;

double appPageBottomInset(
  BuildContext context, {
  bool includeBottomNavigationBar = false,
}) =>
    0;

EdgeInsets appPageContentPadding(
  BuildContext context, {
  bool includeBottomNavigationBar = false,
  bool includeTopSafeArea = true,
  double bottomPadding = 0,
}) {
  return EdgeInsets.fromLTRB(
    kAppPageHorizontalPadding,
    includeTopSafeArea ? MediaQuery.paddingOf(context).top : 0,
    kAppPageHorizontalPadding,
    bottomPadding,
  );
}

double overlayToolbarTotalHeight(BuildContext context) {
  return MediaQuery.paddingOf(context).top + kToolbarHeight;
}

EdgeInsets overlayToolbarPagePadding(
  BuildContext context, {
  bool includeBottomNavigationBar = false,
  double bottomPadding = 0,
}) {
  return EdgeInsets.fromLTRB(
    kAppPageHorizontalPadding,
    overlayToolbarTotalHeight(context),
    kAppPageHorizontalPadding,
    bottomPadding,
  );
}

Widget appPageBottomSpacer({
  double height = kBottomReservedSpacing,
}) {
  return SizedBox(height: height);
}

Widget appPageBottomSliverSpacer({
  double height = kBottomReservedSpacing,
}) {
  return SliverToBoxAdapter(
    child: SizedBox(height: height),
  );
}
