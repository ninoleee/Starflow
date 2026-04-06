import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

enum TvButtonVariant {
  filled,
  outlined,
  text,
}

class TvFocusMemoryController extends ChangeNotifier {
  final Map<String, String> _rememberedFocusIds = <String, String>{};

  String? rememberedFocusId(String scopeId) {
    final normalizedScopeId = scopeId.trim();
    if (normalizedScopeId.isEmpty) {
      return null;
    }
    return _rememberedFocusIds[normalizedScopeId];
  }

  bool hasRememberedFocus(String scopeId) {
    return (rememberedFocusId(scopeId) ?? '').isNotEmpty;
  }

  void remember(String scopeId, String focusId) {
    final normalizedScopeId = scopeId.trim();
    final normalizedFocusId = focusId.trim();
    if (normalizedScopeId.isEmpty || normalizedFocusId.isEmpty) {
      return;
    }
    if (_rememberedFocusIds[normalizedScopeId] == normalizedFocusId) {
      return;
    }
    _rememberedFocusIds[normalizedScopeId] = normalizedFocusId;
    notifyListeners();
  }

  void clear(String scopeId) {
    final normalizedScopeId = scopeId.trim();
    if (normalizedScopeId.isEmpty) {
      return;
    }
    if (_rememberedFocusIds.remove(normalizedScopeId) != null) {
      notifyListeners();
    }
  }
}

class TvFocusMemoryScope extends InheritedNotifier<TvFocusMemoryController> {
  const TvFocusMemoryScope({
    super.key,
    required this.controller,
    required this.scopeId,
    this.enabled = true,
    required super.child,
  }) : super(notifier: controller);

  final TvFocusMemoryController controller;
  final String scopeId;
  final bool enabled;

  static TvFocusMemoryScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TvFocusMemoryScope>();
  }

  @override
  bool updateShouldNotify(covariant TvFocusMemoryScope oldWidget) {
    return controller != oldWidget.controller ||
        scopeId != oldWidget.scopeId ||
        enabled != oldWidget.enabled;
  }
}

class TvMenuButtonScope extends InheritedWidget {
  const TvMenuButtonScope({
    super.key,
    required this.onMenuButtonPressed,
    required super.child,
  });

  final VoidCallback onMenuButtonPressed;

  static TvMenuButtonScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TvMenuButtonScope>();
  }

  @override
  bool updateShouldNotify(TvMenuButtonScope oldWidget) {
    return onMenuButtonPressed != oldWidget.onMenuButtonPressed;
  }
}

class TvContextMenuIntent extends Intent {
  const TvContextMenuIntent();
}

class TvFocusableAction extends ConsumerStatefulWidget {
  const TvFocusableAction({
    super.key,
    required this.child,
    this.onPressed,
    this.onContextAction,
    this.autofocus = false,
    this.focusNode,
    this.focusId,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onContextAction;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;
  final BorderRadius borderRadius;

  @override
  ConsumerState<TvFocusableAction> createState() => _TvFocusableActionState();
}

class _TvFocusableActionState extends ConsumerState<TvFocusableAction> {
  bool _isFocused = false;
  FocusNode? _ownedFocusNode;
  String? _queuedRestoreFocusId;
  bool _didAttemptFocusRestore = false;
  String _lastRestoreKey = '';
  int _centeringRequestVersion = 0;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??=
          FocusNode(debugLabel: 'tv-focus:${widget.focusId ?? widget.key}'));

  @override
  void didUpdateWidget(covariant TvFocusableAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == null && widget.focusNode != null) {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    if (oldWidget.focusId != widget.focusId) {
      _didAttemptFocusRestore = false;
      _lastRestoreKey = '';
    }
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _scheduleFocusRestore(FocusNode focusNode, String focusId) {
    if (_queuedRestoreFocusId == focusId) {
      return;
    }
    _queuedRestoreFocusId = focusId;
    _didAttemptFocusRestore = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_queuedRestoreFocusId != focusId) {
        return;
      }
      _queuedRestoreFocusId = null;
      final currentPrimaryFocus = FocusManager.instance.primaryFocus;
      if (currentPrimaryFocus != null &&
          currentPrimaryFocus != focusNode &&
          currentPrimaryFocus.context != null) {
        return;
      }
      if (!focusNode.canRequestFocus ||
          focusNode.hasPrimaryFocus ||
          focusNode.hasFocus) {
        return;
      }
      focusNode.requestFocus();
    });
  }

  void _handleFocusHighlightChange({
    required bool value,
    required bool memoryEnabled,
    required TvFocusMemoryScope? memoryScope,
    required String focusId,
  }) {
    if (value && memoryEnabled && memoryScope != null && focusId.isNotEmpty) {
      memoryScope.controller.remember(memoryScope.scopeId, focusId);
    }
    if (value) {
      _scheduleViewportCentering();
    }
    if (_isFocused == value) {
      return;
    }
    setState(() {
      _isFocused = value;
    });
  }

  void _scheduleViewportCentering() {
    final requestVersion = ++_centeringRequestVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requestVersion != _centeringRequestVersion) {
        return;
      }

      final scrollable = Scrollable.maybeOf(context);
      if (scrollable == null) {
        return;
      }

      final position = scrollable.position;
      if (!position.hasPixels ||
          !position.hasViewportDimension ||
          position.axis != Axis.vertical) {
        return;
      }

      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) {
        return;
      }

      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) {
        return;
      }

      final revealedOffset =
          viewport.getOffsetToReveal(renderObject, 0.5).offset;
      final targetOffset = revealedOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final delta = (targetOffset - position.pixels).abs();
      final threshold = (position.viewportDimension * 0.08).clamp(24.0, 72.0);
      if (delta <= threshold) {
        return;
      }

      final duration = Duration(
        milliseconds: delta > position.viewportDimension * 0.45 ? 220 : 140,
      );
      position.animateTo(
        targetOffset,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;
    final highPerformanceModeEnabled = ref.watch(
      appSettingsProvider
          .select((settings) => settings.highPerformanceModeEnabled),
    );
    final enabled = widget.onPressed != null;
    final hasContextAction = widget.onContextAction != null;
    final memoryScope = TvFocusMemoryScope.maybeOf(context);
    final memoryEnabled = memoryScope?.enabled ?? false;
    final focusId = widget.focusId?.trim() ?? '';
    final restoreKey = memoryScope == null
        ? focusId
        : '${memoryScope.scopeId.trim()}::$focusId';
    if (_lastRestoreKey != restoreKey) {
      _lastRestoreKey = restoreKey;
      _didAttemptFocusRestore = false;
    }
    final rememberedFocusId = memoryEnabled && memoryScope != null
        ? memoryScope.controller.rememberedFocusId(memoryScope.scopeId)
        : null;
    final shouldRestoreFocus = focusId.isNotEmpty &&
        rememberedFocusId == focusId &&
        enabled &&
        isTelevision &&
        !_didAttemptFocusRestore;
    final shouldAutofocus = widget.autofocus &&
        !(memoryEnabled &&
            memoryScope != null &&
            memoryScope.controller.hasRememberedFocus(memoryScope.scopeId));

    if (!isTelevision) {
      return InkWell(
        onTap: widget.onPressed,
        onSecondaryTap: widget.onContextAction,
        onLongPress: widget.onContextAction,
        borderRadius: widget.borderRadius,
        child: widget.child,
      );
    }

    final effectiveFocusNode = _effectiveFocusNode;
    if (shouldRestoreFocus) {
      _scheduleFocusRestore(effectiveFocusNode, focusId);
    }

    final useHighPerformanceFocusStyle =
        isTelevision && highPerformanceModeEnabled;

    if (useHighPerformanceFocusStyle) {
      return FocusableActionDetector(
        focusNode: effectiveFocusNode,
        autofocus: shouldAutofocus,
        enabled: enabled,
        onShowFocusHighlight: (value) {
          _handleFocusHighlightChange(
            value: value,
            memoryEnabled: memoryEnabled,
            memoryScope: memoryScope,
            focusId: focusId,
          );
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.contextMenu):
              TvContextMenuIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonY):
              TvContextMenuIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
          TvContextMenuIntent: CallbackAction<TvContextMenuIntent>(
            onInvoke: (_) {
              final contextAction = widget.onContextAction;
              if (contextAction != null) {
                contextAction();
              } else {
                TvMenuButtonScope.maybeOf(context)?.onMenuButtonPressed();
              }
              return null;
            },
          ),
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _isFocused
                  ? Colors.white
                  : hasContextAction
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.white.withValues(alpha: 0),
              width: _isFocused ? 2 : 1,
            ),
            color: _isFocused
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.transparent,
          ),
          child: widget.child,
        ),
      );
    }

    return FocusableActionDetector(
      focusNode: effectiveFocusNode,
      autofocus: shouldAutofocus,
      enabled: enabled,
      onShowFocusHighlight: (value) {
        _handleFocusHighlightChange(
          value: value,
          memoryEnabled: memoryEnabled,
          memoryScope: memoryScope,
          focusId: focusId,
        );
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.contextMenu): TvContextMenuIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonY): TvContextMenuIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
        TvContextMenuIntent: CallbackAction<TvContextMenuIntent>(
          onInvoke: (_) {
            final contextAction = widget.onContextAction;
            if (contextAction != null) {
              contextAction();
            } else {
              TvMenuButtonScope.maybeOf(context)?.onMenuButtonPressed();
            }
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
                  : hasContextAction
                      ? Colors.white.withValues(alpha: 0.04)
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
    this.autofocus = false,
    this.focusNode,
    this.focusId,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final TvButtonVariant variant;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;

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
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
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
    this.autofocus = false,
    this.focusNode,
    this.focusId,
  });

  final String title;
  final String value;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;

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
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
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

Widget wrapTelevisionDialogFieldTraversal({
  required bool enabled,
  required Widget child,
}) {
  if (!enabled) {
    return child;
  }
  return Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
      SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
    },
    child: Builder(
      builder: (context) {
        return Actions(
          actions: <Type, Action<Intent>>{
            NextFocusIntent: CallbackAction<NextFocusIntent>(
              onInvoke: (_) {
                FocusScope.of(context).nextFocus();
                return null;
              },
            ),
            PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
              onInvoke: (_) {
                FocusScope.of(context).previousFocus();
                return null;
              },
            ),
          },
          child: child,
        );
      },
    ),
  );
}

Widget wrapTelevisionDialogBackHandling({
  required bool enabled,
  required BuildContext dialogContext,
  required List<FocusNode> inputFocusNodes,
  required List<FocusNode> contentFocusNodes,
  required List<FocusNode> actionFocusNodes,
  required Widget child,
}) {
  if (!enabled) {
    return child;
  }

  void handleDismiss() {
    if (_hasFocusedTvDialogNode(inputFocusNodes)) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (_hasFocusedTvDialogNode(contentFocusNodes)) {
      if (_focusFirstAvailableTvDialogNode(actionFocusNodes)) {
        return;
      }
    }
    if (!_hasFocusedTvDialogNode(actionFocusNodes) &&
        _focusFirstAvailableTvDialogNode(actionFocusNodes)) {
      return;
    }
    Navigator.of(dialogContext).pop();
  }

  return Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      SingleActivator(LogicalKeyboardKey.backspace): DismissIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            handleDismiss();
            return null;
          },
        ),
      },
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            return;
          }
          handleDismiss();
        },
        child: child,
      ),
    ),
  );
}

bool _hasFocusedTvDialogNode(Iterable<FocusNode> nodes) {
  return nodes.any((node) => node.hasFocus || node.hasPrimaryFocus);
}

bool _focusFirstAvailableTvDialogNode(Iterable<FocusNode> nodes) {
  for (final node in nodes) {
    if (node.canRequestFocus) {
      node.requestFocus();
      return true;
    }
  }
  return false;
}
