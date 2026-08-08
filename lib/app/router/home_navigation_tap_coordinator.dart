import 'dart:async';

class HomeNavigationTapCoordinator {
  HomeNavigationTapCoordinator({
    this.doubleTapWindow = const Duration(milliseconds: 280),
  });

  final Duration doubleTapWindow;
  Timer? _pendingSingleTap;

  void registerTap({
    required void Function() onSingleTap,
    required void Function() onDoubleTap,
  }) {
    if (_pendingSingleTap?.isActive ?? false) {
      _pendingSingleTap?.cancel();
      _pendingSingleTap = null;
      onDoubleTap();
      return;
    }

    _pendingSingleTap = Timer(doubleTapWindow, () {
      _pendingSingleTap = null;
      onSingleTap();
    });
  }

  void cancel() {
    _pendingSingleTap?.cancel();
    _pendingSingleTap = null;
  }

  void dispose() {
    cancel();
  }
}
