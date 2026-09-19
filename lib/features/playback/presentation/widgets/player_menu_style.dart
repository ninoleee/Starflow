import 'package:flutter/material.dart';

/// Menu surfaces are 20% transparent; foreground controls remain opaque.
const playbackMenuBackground = Color(0xCC18181B);

class PlaybackMenuTheme extends StatelessWidget {
  const PlaybackMenuTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        dialogTheme: theme.dialogTheme.copyWith(
          backgroundColor: playbackMenuBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      child: child,
    );
  }
}

Future<T?> showPlaybackMenuDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  AnimationStyle? animationStyle,
}) =>
    showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      animationStyle: animationStyle,
      builder: (context) => PlaybackMenuTheme(child: Builder(builder: builder)),
    );
