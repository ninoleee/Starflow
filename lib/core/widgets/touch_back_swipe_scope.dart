import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:starflow/app/router/app_navigator.dart';

class TouchBackSwipeScope extends StatelessWidget {
  const TouchBackSwipeScope({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!_supportsTouchBackSwipe) {
      return child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const _TouchBackSwipeOverlay(),
      ],
    );
  }

  bool get _supportsTouchBackSwipe {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }
}

class _TouchBackSwipeOverlay extends StatefulWidget {
  const _TouchBackSwipeOverlay();

  @override
  State<_TouchBackSwipeOverlay> createState() => _TouchBackSwipeOverlayState();
}

class _TouchBackSwipeOverlayState extends State<_TouchBackSwipeOverlay> {
  bool _tracking = false;
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final edgeWidth = _resolveEdgeWidth(constraints.maxWidth);
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: edgeWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (details) {
                final navigator = appNavigatorKey.currentState;
                if (navigator == null || !navigator.canPop()) {
                  _tracking = false;
                  return;
                }
                _tracking = true;
                _dragDistance = 0;
              },
              onHorizontalDragUpdate: (details) {
                if (!_tracking) {
                  return;
                }
                _dragDistance = math.max(
                  0,
                  _dragDistance + details.delta.dx,
                );
              },
              onHorizontalDragEnd: (details) {
                if (!_tracking) {
                  return;
                }
                final navigator = appNavigatorKey.currentState;
                final shouldPop = _dragDistance >=
                        _resolveTriggerDistance(constraints.maxWidth) ||
                    (details.primaryVelocity ?? 0) >= 420;
                _tracking = false;
                _dragDistance = 0;
                if (navigator == null || !shouldPop) {
                  return;
                }
                navigator.maybePop();
              },
              onHorizontalDragCancel: () {
                _tracking = false;
                _dragDistance = 0;
              },
            ),
          ),
        );
      },
    );
  }

  double _resolveEdgeWidth(double screenWidth) {
    return math.min(math.max(screenWidth * 0.11, 56), 96);
  }

  double _resolveTriggerDistance(double screenWidth) {
    return math.min(math.max(screenWidth * 0.045, 28), 52);
  }
}
