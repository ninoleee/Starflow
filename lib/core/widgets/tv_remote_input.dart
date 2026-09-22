import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const tvConfirmKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.gameButtonA,
];

const tvBackKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.goBack,
  LogicalKeyboardKey.escape,
];

/// Owns a command through release, before allowing it to change focus/routes.
/// Directional navigation and continuous seeking must not use this handler.
class TvRemoteKeyHandler with WidgetsBindingObserver {
  final _pending = <PhysicalKeyboardKey, VoidCallback>{};
  FocusNode? _origin;

  bool owns(KeyEvent event) => _pending.containsKey(event.physicalKey);

  KeyEventResult handle(KeyEvent event, {required VoidCallback onPressed}) {
    if (event is KeyDownEvent && !event.synthesized) {
      if (_pending.isEmpty) {
        _origin = FocusManager.instance.primaryFocus;
        _origin?.addListener(_onFocusChanged);
        WidgetsBinding.instance.addObserver(this);
      }
      _pending[event.physicalKey] = onPressed;
    } else if (event is KeyUpEvent) {
      final action = _pending.remove(event.physicalKey);
      final canInvoke =
          !event.synthesized && _origin != null && _origin!.hasPrimaryFocus;
      if (_pending.isEmpty) reset();
      if (canInvoke) action?.call();
    }
    return KeyEventResult.handled;
  }

  void _onFocusChanged() {
    if (_origin?.hasPrimaryFocus != true) reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) reset();
  }

  void reset() {
    _pending.clear();
    _origin?.removeListener(_onFocusChanged);
    _origin = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  void dispose() => reset();
}

/// Release-triggered command shortcuts. Touch and semantics actions are unchanged.
class TvRemoteShortcuts extends StatefulWidget {
  const TvRemoteShortcuts({
    super.key,
    required this.shortcuts,
    required this.child,
  });

  final Map<SingleActivator, Intent> shortcuts;
  final Widget child;

  @override
  State<TvRemoteShortcuts> createState() => _TvRemoteShortcutsState();
}

class _TvRemoteShortcutsState extends State<TvRemoteShortcuts> {
  final _manager = _TvRemoteShortcutManager();

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _manager.commands = widget.shortcuts;
    return Shortcuts.manager(manager: _manager, child: widget.child);
  }
}

class _TvRemoteShortcutManager extends ShortcutManager {
  final _keys = TvRemoteKeyHandler();
  Map<SingleActivator, Intent> commands = const {};

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (_keys.owns(event)) {
      return _keys.handle(event, onPressed: () {});
    }
    for (final entry in commands.entries) {
      if (entry.key.trigger != event.logicalKey) continue;
      final target = FocusManager.instance.primaryFocus?.context;
      if (target == null) return KeyEventResult.ignored;
      final action = Actions.maybeFind<Intent>(target, intent: entry.value);
      if (action == null || !action.isEnabled(entry.value)) continue;
      if (event is KeyDownEvent &&
          !entry.key.accepts(event, HardwareKeyboard.instance)) {
        continue;
      }
      return _keys.handle(event, onPressed: () {
        if (target.mounted && ModalRoute.of(target)?.isCurrent != false) {
          Actions.maybeInvoke(target, entry.value);
        }
      });
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }
}
