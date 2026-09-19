import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Defers IME attachment until the remote key that opened it has been released.
class TvTextInputLauncher extends StatefulWidget {
  const TvTextInputLauncher({
    super.key,
    required this.onOpen,
    required this.builder,
  });

  final Future<void> Function() onOpen;
  final Widget Function(VoidCallback) builder;

  @override
  State<TvTextInputLauncher> createState() => _TvTextInputLauncherState();
}

class _TvTextInputLauncherState extends State<TvTextInputLauncher> {
  static final _activationKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  bool _opening = false;
  Completer<void>? _release;
  bool Function(KeyEvent)? _keyHandler;

  void _stopWaiting() {
    final handler = _keyHandler;
    if (handler != null) {
      HardwareKeyboard.instance.removeHandler(handler);
      _keyHandler = null;
    }
    final release = _release;
    _release = null;
    if (release != null && !release.isCompleted) release.complete();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    final origin = FocusManager.instance.primaryFocus;
    try {
      final held = HardwareKeyboard.instance.logicalKeysPressed
          .intersection(_activationKeys);
      if (held.isNotEmpty) {
        final release = Completer<void>();
        _release = release;
        _keyHandler = (event) {
          if (!held.contains(event.logicalKey)) return false;
          if (event is KeyUpEvent) {
            held.remove(event.logicalKey);
            if (held.isEmpty) _stopWaiting();
          }
          return true;
        };
        HardwareKeyboard.instance.addHandler(_keyHandler!);
        await release.future;
        await Future<void>.delayed(Duration.zero);
        if (!mounted || origin?.hasFocus != true) return;
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      await widget.onOpen();
    } finally {
      _stopWaiting();
      _opening = false;
    }
  }

  @override
  void dispose() {
    _stopWaiting();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_open);
}
