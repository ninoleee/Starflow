import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';

class MobileTextInputDismissal extends ConsumerWidget {
  const MobileTextInputDismissal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final enabled = isMobile && ref.watch(isTelevisionProvider).value == false;
    return Actions(
      actions: <Type, Action<Intent>>{
        if (enabled)
          EditableTextTapOutsideIntent:
              CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (intent) {
              // Keep Flutter's text-field tap regions and gesture dispatch intact.
              intent.focusNode.unfocus();
              return null;
            },
          ),
      },
      child: child,
    );
  }
}
