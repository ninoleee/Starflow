import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DesktopHorizontalPager extends StatefulWidget {
  const DesktopHorizontalPager({
    super.key,
    required this.builder,
    this.enabled = true,
    this.showButtonsOnAllPlatforms = false,
    this.scrollStep,
    this.leftInset = 10,
    this.rightInset = 10,
    this.buttonSize = 50,
    this.iconSize = 28,
  });

  final Widget Function(BuildContext context, ScrollController controller)
      builder;
  final bool enabled;
  final bool showButtonsOnAllPlatforms;
  final double? scrollStep;
  final double leftInset;
  final double rightInset;
  final double buttonSize;
  final double iconSize;

  @override
  State<DesktopHorizontalPager> createState() => _DesktopHorizontalPagerState();
}

class _DesktopHorizontalPagerState extends State<DesktopHorizontalPager> {
  late final ScrollController _controller;
  late final ValueNotifier<_DesktopPagerButtonVisibility>
      _buttonVisibilityNotifier;
  bool _visibilityUpdateScheduled = false;

  bool get _showsDesktopButtons {
    if (!widget.enabled) {
      return false;
    }
    if (widget.showButtonsOnAllPlatforms) {
      return true;
    }
    if (kIsWeb) {
      return true;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => true,
      TargetPlatform.macOS => true,
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    _buttonVisibilityNotifier =
        ValueNotifier<_DesktopPagerButtonVisibility>(
      const _DesktopPagerButtonVisibility(
        canScrollBackward: false,
        canScrollForward: false,
      ),
    );
    _controller = ScrollController()..addListener(_handleScrollMetricsChanged);
    _scheduleButtonVisibilityUpdate();
  }

  @override
  void didUpdateWidget(covariant DesktopHorizontalPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.scrollStep != widget.scrollStep) {
      _scheduleButtonVisibilityUpdate();
    }
  }

  @override
  void dispose() {
    _buttonVisibilityNotifier.dispose();
    _controller
      ..removeListener(_handleScrollMetricsChanged)
      ..dispose();
    super.dispose();
  }

  void _handleScrollMetricsChanged() {
    _updateButtonVisibility();
  }

  void _scheduleButtonVisibilityUpdate() {
    if (_visibilityUpdateScheduled) {
      return;
    }
    _visibilityUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _visibilityUpdateScheduled = false;
      _updateButtonVisibility();
    });
  }

  void _updateButtonVisibility() {
    final currentVisibility = _buttonVisibilityNotifier.value;
    if (!_showsDesktopButtons) {
      if (currentVisibility.canScrollBackward ||
          currentVisibility.canScrollForward) {
        _buttonVisibilityNotifier.value = const _DesktopPagerButtonVisibility(
          canScrollBackward: false,
          canScrollForward: false,
        );
      }
      return;
    }
    final hasUsableMetrics =
        _controller.hasClients && _controller.position.hasContentDimensions;
    final canScrollBackward = hasUsableMetrics &&
        _controller.position.pixels >
            _controller.position.minScrollExtent + 0.5;
    final canScrollForward = hasUsableMetrics &&
        _controller.position.pixels <
            _controller.position.maxScrollExtent - 0.5;
    if (currentVisibility.canScrollBackward == canScrollBackward &&
        currentVisibility.canScrollForward == canScrollForward) {
      return;
    }
    _buttonVisibilityNotifier.value = _DesktopPagerButtonVisibility(
      canScrollBackward: canScrollBackward,
      canScrollForward: canScrollForward,
    );
  }

  Future<void> _scrollBy(double direction) async {
    if (!_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    if (!position.hasContentDimensions) {
      return;
    }
    final scrollStep = widget.scrollStep ?? position.viewportDimension * 0.82;
    final targetOffset = (position.pixels + scrollStep * direction)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((targetOffset - position.pixels).abs() < 1) {
      return;
    }
    await _controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = RepaintBoundary(
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _updateButtonVisibility();
          return false;
        },
        child: widget.builder(context, _controller),
      ),
    );
    if (!_showsDesktopButtons) {
      return child;
    }

    return ValueListenableBuilder<_DesktopPagerButtonVisibility>(
      valueListenable: _buttonVisibilityNotifier,
      child: child,
      builder: (context, visibility, content) {
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            content!,
            if (visibility.canScrollBackward)
              Positioned(
                left: widget.leftInset,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _DesktopHorizontalPagerButton(
                    size: widget.buttonSize,
                    iconSize: widget.iconSize,
                    icon: Icons.chevron_left_rounded,
                    onPressed: () => _scrollBy(-1),
                  ),
                ),
              ),
            if (visibility.canScrollForward)
              Positioned(
                right: widget.rightInset,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _DesktopHorizontalPagerButton(
                    size: widget.buttonSize,
                    iconSize: widget.iconSize,
                    icon: Icons.chevron_right_rounded,
                    onPressed: () => _scrollBy(1),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DesktopPagerButtonVisibility {
  const _DesktopPagerButtonVisibility({
    required this.canScrollBackward,
    required this.canScrollForward,
  });

  final bool canScrollBackward;
  final bool canScrollForward;
}

class _DesktopHorizontalPagerButton extends StatelessWidget {
  const _DesktopHorizontalPagerButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    required this.iconSize,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
