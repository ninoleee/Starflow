import 'dart:async';

import 'package:flutter/material.dart';

const kPlayerAdaptiveTopChromeRootKey = Key(
  'player-adaptive-top-chrome-root',
);
const kPlayerAdaptiveTopChromeBackButtonKey = Key(
  'player-adaptive-top-chrome-back-button',
);
const kPlayerAdaptiveTopChromeMoreButtonKey = Key(
  'player-adaptive-top-chrome-more-button',
);

class PlayerAdaptiveTopChromeController extends ChangeNotifier {
  PlayerAdaptiveTopChromeController({
    bool visible = true,
    bool autoHideEnabled = true,
    Duration autoHideDelay = const Duration(seconds: 3),
  })  : _visible = visible,
        _autoHideEnabled = autoHideEnabled,
        _autoHideDelay = autoHideDelay;

  bool _visible;
  bool _autoHideEnabled;
  Duration _autoHideDelay;
  int _activityTick = 0;

  bool get visible => _visible;
  bool get autoHideEnabled => _autoHideEnabled;
  Duration get autoHideDelay => _autoHideDelay;
  int get activityTick => _activityTick;

  void setVisible(bool value) {
    if (_visible == value) {
      return;
    }
    _visible = value;
    notifyListeners();
  }

  void setAutoHideEnabled(bool value) {
    if (_autoHideEnabled == value) {
      return;
    }
    _autoHideEnabled = value;
    notifyListeners();
  }

  void setAutoHideDelay(Duration value) {
    if (_autoHideDelay == value) {
      return;
    }
    _autoHideDelay = value;
    notifyListeners();
  }

  void pingActivity() {
    _activityTick += 1;
    notifyListeners();
  }
}

class PlayerAdaptiveTopChrome extends StatefulWidget {
  const PlayerAdaptiveTopChrome({
    super.key,
    required this.controller,
    required this.onBack,
    this.onMore,
    this.backTooltip = '返回',
    this.moreTooltip = '更多',
  });

  final PlayerAdaptiveTopChromeController controller;
  final VoidCallback onBack;
  final VoidCallback? onMore;
  final String backTooltip;
  final String moreTooltip;

  @override
  State<PlayerAdaptiveTopChrome> createState() =>
      _PlayerAdaptiveTopChromeState();
}

class _PlayerAdaptiveTopChromeState extends State<PlayerAdaptiveTopChrome> {
  Timer? _hideTimer;
  late bool _visible;
  late int _activityTick;

  @override
  void initState() {
    super.initState();
    _visible = widget.controller.visible;
    _activityTick = widget.controller.activityTick;
    widget.controller.addListener(_handleControllerUpdated);
    _syncAutoHide();
  }

  @override
  void didUpdateWidget(covariant PlayerAdaptiveTopChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) {
      return;
    }
    oldWidget.controller.removeListener(_handleControllerUpdated);
    _cancelHideTimer();
    _visible = widget.controller.visible;
    _activityTick = widget.controller.activityTick;
    widget.controller.addListener(_handleControllerUpdated);
    _syncAutoHide();
  }

  @override
  void dispose() {
    _cancelHideTimer();
    widget.controller.removeListener(_handleControllerUpdated);
    super.dispose();
  }

  void _handleControllerUpdated() {
    if (!mounted) {
      return;
    }
    final controller = widget.controller;
    final hasActivityPing = controller.activityTick != _activityTick;
    _activityTick = controller.activityTick;
    final shouldShow = hasActivityPing ? true : controller.visible;
    final shouldNotifyController =
        hasActivityPing && shouldShow != controller.visible;
    _applyVisibility(shouldShow);
    if (shouldNotifyController) {
      controller.setVisible(true);
    }
  }

  void _applyVisibility(bool visible) {
    if (!mounted) {
      return;
    }
    if (_visible != visible) {
      setState(() {
        _visible = visible;
      });
    }
    _syncAutoHide();
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _syncAutoHide() {
    _cancelHideTimer();
    final controller = widget.controller;
    if (!controller.autoHideEnabled || !_visible) {
      return;
    }
    final delay = controller.autoHideDelay;
    if (delay <= Duration.zero) {
      controller.setVisible(false);
      return;
    }
    _hideTimer = Timer(delay, () {
      if (!mounted || !widget.controller.autoHideEnabled || !_visible) {
        return;
      }
      widget.controller.setVisible(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        key: kPlayerAdaptiveTopChromeRootKey,
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: Align(
          alignment: Alignment.topCenter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.48),
                  Colors.black.withValues(alpha: 0),
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, topInset > 0 ? 4 : 10, 8, 8),
                child: Row(
                  children: [
                    _TopActionButton(
                      key: kPlayerAdaptiveTopChromeBackButtonKey,
                      icon: Icons.arrow_back_rounded,
                      tooltip: widget.backTooltip,
                      onPressed: widget.onBack,
                    ),
                    const Spacer(),
                    if (widget.onMore != null)
                      _TopActionButton(
                        key: kPlayerAdaptiveTopChromeMoreButtonKey,
                        icon: Icons.more_horiz_rounded,
                        tooltip: widget.moreTooltip,
                        onPressed: widget.onMore!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.28),
        hoverColor: Colors.white.withValues(alpha: 0.1),
        highlightColor: Colors.white.withValues(alpha: 0.12),
      ),
    );
  }
}
