import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

final _tvFocusLightweightEnabledProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider.select(
    (settings) => settings.performanceLightweightTvFocusEnabled,
  ));
});

enum TvButtonVariant {
  filled,
  outlined,
  text,
}

enum TvFocusVisualStyle {
  prominent,
  subtle,
  floating,
  none,
}

enum StarflowButtonVariant {
  primary,
  secondary,
  ghost,
  danger,
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
  }

  void clear(String scopeId) {
    final normalizedScopeId = scopeId.trim();
    if (normalizedScopeId.isEmpty) {
      return;
    }
    _rememberedFocusIds.remove(normalizedScopeId);
  }
}

class TvFocusMemoryScope extends InheritedWidget {
  const TvFocusMemoryScope({
    super.key,
    required this.controller,
    required this.scopeId,
    this.enabled = true,
    required super.child,
  });

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

String buildTvFocusId({
  required String prefix,
  Iterable<Object?> segments = const [],
}) {
  return _buildTvFocusKey(
    prefix: prefix,
    segments: segments,
  );
}

String buildTvFocusScopeId({
  required String prefix,
  Iterable<Object?> segments = const [],
}) {
  return _buildTvFocusKey(
    prefix: prefix,
    segments: segments,
  );
}

String _buildTvFocusKey({
  required String prefix,
  required Iterable<Object?> segments,
}) {
  final normalizedPrefix = prefix.trim();
  final normalizedSegments = segments
      .map((segment) => segment?.toString() ?? '')
      .map((segment) => segment.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (normalizedSegments.isEmpty) {
    return normalizedPrefix;
  }
  if (normalizedPrefix.isEmpty) {
    return normalizedSegments.join(':');
  }
  return '$normalizedPrefix:${normalizedSegments.join(':')}';
}

bool handleTvDirectionalFocusBoundary(
  BuildContext context,
  TraversalDirection direction, {
  VoidCallback? onMoveLeftOut,
}) {
  final primaryFocus = FocusManager.instance.primaryFocus;
  if (primaryFocus == null) {
    return false;
  }

  final moved = primaryFocus.focusInDirection(direction);
  if (moved) {
    return true;
  }

  if (direction == TraversalDirection.left) {
    final fallback = onMoveLeftOut ??
        TvMenuButtonScope.maybeOf(primaryFocus.context ?? context)
            ?.onMenuButtonPressed;
    fallback?.call();
    return fallback != null;
  }

  return false;
}

class TvDirectionalFocusBoundary extends StatelessWidget {
  const TvDirectionalFocusBoundary({
    super.key,
    required this.child,
    this.onMoveLeftOut,
  });

  final Widget child;
  final VoidCallback? onMoveLeftOut;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            handleTvDirectionalFocusBoundary(
              context,
              intent.direction,
              onMoveLeftOut: onMoveLeftOut,
            );
            return null;
          },
        ),
      },
      child: child,
    );
  }
}

class TvPageFocusScope extends StatelessWidget {
  const TvPageFocusScope({
    super.key,
    required this.controller,
    required this.scopeId,
    required this.isTelevision,
    required this.child,
    this.onMoveLeftOut,
  });

  final TvFocusMemoryController controller;
  final String scopeId;
  final bool isTelevision;
  final Widget child;
  final VoidCallback? onMoveLeftOut;

  @override
  Widget build(BuildContext context) {
    return TvFocusMemoryScope(
      controller: controller,
      scopeId: scopeId,
      enabled: isTelevision,
      child: TvDirectionalFocusBoundary(
        onMoveLeftOut: onMoveLeftOut,
        child: child,
      ),
    );
  }
}

class TvDirectionalActionPanel extends StatelessWidget {
  const TvDirectionalActionPanel({
    super.key,
    required this.child,
    this.enabled = true,
    this.onDirection,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.onMoveLeftOut,
  });

  final Widget child;
  final bool enabled;
  final bool Function(TraversalDirection direction)? onDirection;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onMoveLeftOut;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            DirectionalFocusIntent(TraversalDirection.left),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            DirectionalFocusIntent(TraversalDirection.right),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            DirectionalFocusIntent(TraversalDirection.up),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            DirectionalFocusIntent(TraversalDirection.down),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
            onInvoke: (intent) {
              final directionalHandler = onDirection;
              if (directionalHandler != null &&
                  directionalHandler(intent.direction)) {
                return null;
              }
              final callback = switch (intent.direction) {
                TraversalDirection.left => onMoveLeft,
                TraversalDirection.right => onMoveRight,
                TraversalDirection.up => onMoveUp,
                TraversalDirection.down => onMoveDown,
              };
              if (callback != null) {
                callback();
                return null;
              }
              handleTvDirectionalFocusBoundary(
                context,
                intent.direction,
                onMoveLeftOut: onMoveLeftOut,
              );
              return null;
            },
          ),
        },
        child: child,
      ),
    );
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
    this.visualStyle = TvFocusVisualStyle.prominent,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onContextAction;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;
  final BorderRadius borderRadius;
  final TvFocusVisualStyle visualStyle;

  @override
  ConsumerState<TvFocusableAction> createState() => _TvFocusableActionState();
}

class _TvFocusableActionState extends ConsumerState<TvFocusableAction> {
  final ValueNotifier<bool> _isFocusedNotifier = ValueNotifier<bool>(false);
  FocusNode? _ownedFocusNode;
  String? _queuedRestoreFocusId;
  bool _didAttemptFocusRestore = false;
  String _lastRestoreKey = '';

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
    _isFocusedNotifier.dispose();
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
    required bool trackVisualFocus,
  }) {
    if (value && memoryEnabled && memoryScope != null && focusId.isNotEmpty) {
      memoryScope.controller.remember(memoryScope.scopeId, focusId);
    }
    if (!trackVisualFocus || _isFocusedNotifier.value == value) {
      return;
    }
    _isFocusedNotifier.value = value;
  }

  Map<Type, Action<Intent>> _buildTelevisionActions(BuildContext context) {
    return <Type, Action<Intent>>{
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
    };
  }

  Widget _buildFocusVisualFrame({
    required bool isFocused,
    required bool lightweightTvFocusEnabled,
    required bool hasContextAction,
    required Widget child,
  }) {
    final useSubtleVisualStyle =
        widget.visualStyle == TvFocusVisualStyle.subtle;
    final useFloatingVisualStyle =
        widget.visualStyle == TvFocusVisualStyle.floating;

    if (widget.visualStyle == TvFocusVisualStyle.none) {
      return child;
    }

    if (lightweightTvFocusEnabled) {
      if (useFloatingVisualStyle) {
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Transform.translate(
            offset: Offset(0, isFocused ? -5 : 0),
            child: child,
          ),
        );
      }
      return Container(
        padding: EdgeInsets.all(useSubtleVisualStyle ? 1 : 2),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: isFocused
                ? Colors.white
                : hasContextAction
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0),
            width: isFocused ? (useSubtleVisualStyle ? 1.8 : 2.2) : 1,
          ),
          color: isFocused
              ? Colors.white.withValues(
                  alpha: useSubtleVisualStyle ? 0.02 : 0.035,
                )
              : Colors.transparent,
        ),
        child: child,
      );
    }

    if (useFloatingVisualStyle) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, isFocused ? -6 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: child,
      );
    }

    return AnimatedScale(
      scale: isFocused ? (useSubtleVisualStyle ? 1.008 : 1.03) : 1,
      duration: const Duration(milliseconds: 140),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: isFocused
                ? Colors.white
                : hasContextAction
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white.withValues(alpha: 0),
            width: useSubtleVisualStyle ? 1.6 : 2,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: useSubtleVisualStyle
                        ? Colors.black.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.18),
                    blurRadius: useSubtleVisualStyle ? 12 : 28,
                    spreadRadius: useSubtleVisualStyle ? 0 : 2,
                  ),
                ]
              : null,
          color: isFocused && useSubtleVisualStyle
              ? Colors.white.withValues(alpha: 0.018)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final lightweightTvFocusEnabled =
        ref.watch(_tvFocusLightweightEnabledProvider);
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

    final trackVisualFocus = widget.visualStyle != TvFocusVisualStyle.none;
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
          trackVisualFocus: trackVisualFocus,
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
      actions: _buildTelevisionActions(context),
      child: ValueListenableBuilder<bool>(
        valueListenable: _isFocusedNotifier,
        child: widget.child,
        builder: (context, isFocused, child) {
          return _buildFocusVisualFrame(
            isFocused: isFocused,
            lightweightTvFocusEnabled: lightweightTvFocusEnabled,
            hasContextAction: hasContextAction,
            child: child!,
          );
        },
      ),
    );
  }
}

class _StarflowButtonPalette {
  const _StarflowButtonPalette({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
}

_StarflowButtonPalette _starflowButtonPalette(
  ThemeData theme, {
  required StarflowButtonVariant variant,
  required bool enabled,
}) {
  final isDark = theme.brightness == Brightness.dark;
  final palette = switch (variant) {
    StarflowButtonVariant.primary => _StarflowButtonPalette(
        backgroundColor: isDark ? Colors.white : theme.colorScheme.primary,
        foregroundColor:
            isDark ? const Color(0xFF081120) : theme.colorScheme.onPrimary,
        borderColor: isDark ? Colors.white : theme.colorScheme.primary,
      ),
    StarflowButtonVariant.secondary => _StarflowButtonPalette(
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerHighest,
        foregroundColor: isDark ? Colors.white : theme.colorScheme.onSurface,
        borderColor: isDark
            ? Colors.white.withValues(alpha: 0.24)
            : theme.colorScheme.outlineVariant,
      ),
    StarflowButtonVariant.ghost => _StarflowButtonPalette(
        backgroundColor:
            isDark ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
        foregroundColor: isDark ? Colors.white : theme.colorScheme.primary,
        borderColor:
            isDark ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
      ),
    StarflowButtonVariant.danger => _StarflowButtonPalette(
        backgroundColor: isDark
            ? theme.colorScheme.error.withValues(alpha: 0.16)
            : theme.colorScheme.errorContainer,
        foregroundColor: isDark
            ? const Color(0xFFFFD3D3)
            : theme.colorScheme.onErrorContainer,
        borderColor: isDark
            ? theme.colorScheme.error.withValues(alpha: 0.35)
            : theme.colorScheme.errorContainer,
      ),
  };
  if (enabled) {
    return palette;
  }
  return _StarflowButtonPalette(
    backgroundColor: palette.backgroundColor.withValues(alpha: 0.45),
    foregroundColor: palette.foregroundColor.withValues(alpha: 0.6),
    borderColor: palette.borderColor.withValues(alpha: 0.45),
  );
}

class StarflowButton extends StatelessWidget {
  const StarflowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = StarflowButtonVariant.primary,
    this.autofocus = false,
    this.focusNode,
    this.focusId,
    this.compact = false,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final StarflowButtonVariant variant;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;
  final bool compact;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = _starflowButtonPalette(
      Theme.of(context),
      variant: variant,
      enabled: onPressed != null && !loading,
    );
    final radius = BorderRadius.circular(compact ? 16 : 18);
    final button = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundColor,
        borderRadius: radius,
        border: Border.all(color: palette.borderColor),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 18,
          vertical: compact ? 11 : 15,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: compact ? 16 : 18,
                height: compact ? 16 : 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(palette.foregroundColor),
                ),
              )
            else if (icon != null)
              Icon(
                icon,
                size: compact ? 18 : 20,
                color: palette.foregroundColor,
              ),
            if ((loading || icon != null) && label.trim().isNotEmpty)
              const SizedBox(width: 10),
            if (label.trim().isNotEmpty)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: palette.foregroundColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
    return TvFocusableAction(
      onPressed: loading ? null : onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
      borderRadius: radius,
      visualStyle:
          compact ? TvFocusVisualStyle.subtle : TvFocusVisualStyle.prominent,
      child: expand
          ? SizedBox(
              width: double.infinity,
              child: button,
            )
          : button,
    );
  }
}

class StarflowIconButton extends StatelessWidget {
  const StarflowIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.variant = StarflowButtonVariant.ghost,
    this.autofocus = false,
    this.focusNode,
    this.focusId,
    this.tooltip = '',
    this.size = 42,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final StarflowButtonVariant variant;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = _starflowButtonPalette(
      Theme.of(context),
      variant: variant,
      enabled: onPressed != null,
    );
    final radius = BorderRadius.circular(14);
    final child = TvFocusableAction(
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
      borderRadius: radius,
      visualStyle: TvFocusVisualStyle.subtle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.backgroundColor,
          borderRadius: radius,
          border: Border.all(color: palette.borderColor),
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: 20,
            color: palette.foregroundColor,
          ),
        ),
      ),
    );
    if (tooltip.trim().isEmpty) {
      return child;
    }
    return Tooltip(
      message: tooltip,
      child: child,
    );
  }
}

class StarflowChipButton extends StatelessWidget {
  const StarflowChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.focusId,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onPressed != null;
    final backgroundColor = selected
        ? (isDark ? Colors.white : theme.colorScheme.primaryContainer)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerHighest);
    final foregroundColor = selected
        ? (isDark
            ? const Color(0xFF081120)
            : theme.colorScheme.onPrimaryContainer)
        : (isDark ? Colors.white : theme.colorScheme.onSurface);
    final borderColor = selected
        ? (isDark ? Colors.white : theme.colorScheme.primaryContainer)
        : (isDark
            ? Colors.white.withValues(alpha: 0.18)
            : theme.colorScheme.outlineVariant);
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: foregroundColor,
      fontWeight: FontWeight.w700,
      fontFamilyFallback: theme.textTheme.titleSmall?.fontFamilyFallback,
      height: 1.2,
      leadingDistribution: TextLeadingDistribution.even,
    );
    return TvFocusableAction(
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
      borderRadius: BorderRadius.circular(999),
      visualStyle: TvFocusVisualStyle.subtle,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: foregroundColor),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      strutStyle: labelStyle == null
                          ? null
                          : StrutStyle.fromTextStyle(labelStyle),
                      style: labelStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StarflowSelectionTile extends StatelessWidget {
  const StarflowSelectionTile({
    super.key,
    required this.title,
    required this.onPressed,
    this.value = '',
    this.subtitle = '',
    this.leading,
    this.trailing,
    this.autofocus = false,
    this.focusNode,
    this.focusId,
  });

  final String title;
  final String value;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveSubtitle =
        value.trim().isNotEmpty ? value.trim() : subtitle.trim();
    return TvFocusableAction(
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
      borderRadius: BorderRadius.circular(18),
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title),
                    if (effectiveSubtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          effectiveSubtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class StarflowToggleTile extends StatelessWidget {
  const StarflowToggleTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle = '',
    this.focusNode,
    this.focusId,
    this.autofocus = false,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String subtitle;
  final FocusNode? focusNode;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return StarflowSelectionTile(
      title: title,
      subtitle: subtitle,
      value: value ? '已开启' : '已关闭',
      onPressed: onChanged == null ? null : () => onChanged!.call(!value),
      focusNode: focusNode,
      focusId: focusId,
      autofocus: autofocus,
      trailing: Icon(
        value ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
        size: 28,
        color: value
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class StarflowCheckboxTile extends StatelessWidget {
  const StarflowCheckboxTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle = '',
    this.leading,
    this.focusNode,
    this.focusId,
    this.autofocus = false,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String subtitle;
  final Widget? leading;
  final FocusNode? focusNode;
  final String? focusId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StarflowSelectionTile(
      title: title,
      subtitle: subtitle,
      value: value ? '已选中' : '未选中',
      leading: leading,
      onPressed: onChanged == null ? null : () => onChanged!.call(!value),
      focusNode: focusNode,
      focusId: focusId,
      autofocus: autofocus,
      trailing: Icon(
        value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        size: 22,
        color: value ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}

class TvAdaptiveButton extends StatelessWidget {
  const TvAdaptiveButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = TvButtonVariant.filled,
    this.compact = false,
    this.autofocus = false,
    this.focusNode,
    this.focusId,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final TvButtonVariant variant;
  final bool compact;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? focusId;

  @override
  Widget build(BuildContext context) {
    final mappedVariant = switch (variant) {
      TvButtonVariant.filled => StarflowButtonVariant.primary,
      TvButtonVariant.outlined => StarflowButtonVariant.secondary,
      TvButtonVariant.text => StarflowButtonVariant.ghost,
    };
    return StarflowButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      variant: mappedVariant,
      compact: compact,
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
    );
  }
}

class TvSelectionTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return StarflowSelectionTile(
      title: title,
      value: value,
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      focusId: focusId,
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

  final shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
    const SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
  };
  if (inputFocusNodes.isEmpty) {
    shortcuts[const SingleActivator(LogicalKeyboardKey.backspace)] =
        DismissIntent();
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
    shortcuts: shortcuts,
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
