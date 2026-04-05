import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';

enum TvButtonVariant {
  filled,
  outlined,
  text,
}

class TvFocusableAction extends ConsumerStatefulWidget {
  const TvFocusableAction({
    super.key,
    required this.child,
    this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;

  @override
  ConsumerState<TvFocusableAction> createState() => _TvFocusableActionState();
}

class _TvFocusableActionState extends ConsumerState<TvFocusableAction> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final enabled = widget.onPressed != null;

    if (!isTelevision) {
      return InkWell(
        onTap: widget.onPressed,
        borderRadius: widget.borderRadius,
        child: widget.child,
      );
    }

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: enabled,
      onShowFocusHighlight: (value) {
        if (_isFocused == value) {
          return;
        }
        setState(() {
          _isFocused = value;
        });
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: _isFocused ? 1.03 : 1,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _isFocused
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0),
              width: 2,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.18),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class TvAdaptiveButton extends ConsumerWidget {
  const TvAdaptiveButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = TvButtonVariant.filled,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final TvButtonVariant variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;

    if (!isTelevision) {
      switch (variant) {
        case TvButtonVariant.filled:
          return FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
        case TvButtonVariant.outlined:
          return OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
        case TvButtonVariant.text:
          return TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
      }
    }

    final backgroundColor = switch (variant) {
      TvButtonVariant.filled => Colors.white,
      TvButtonVariant.outlined => Colors.white.withValues(alpha: 0.08),
      TvButtonVariant.text => Colors.white.withValues(alpha: 0.04),
    };
    final foregroundColor = switch (variant) {
      TvButtonVariant.filled => const Color(0xFF081120),
      TvButtonVariant.outlined => Colors.white,
      TvButtonVariant.text => Colors.white,
    };
    final borderColor = switch (variant) {
      TvButtonVariant.filled => Colors.white,
      TvButtonVariant.outlined => Colors.white.withValues(alpha: 0.24),
      TvButtonVariant.text => Colors.white.withValues(alpha: 0.14),
    };

    return TvFocusableAction(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foregroundColor),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TvSelectionTile extends ConsumerWidget {
  const TvSelectionTile({
    super.key,
    required this.title,
    required this.value,
    required this.onPressed,
  });

  final String title;
  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: value.trim().isEmpty ? null : Text(value),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onPressed,
    );
    if (!isTelevision) {
      return tile;
    }
    return TvFocusableAction(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: tile,
      ),
    );
  }
}
