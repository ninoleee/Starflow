import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DesktopHorizontalPager extends StatefulWidget {
  const DesktopHorizontalPager({
    super.key,
    required this.builder,
    this.enabled = true,
    this.scrollStep,
    this.leftInset = 10,
    this.rightInset = 10,
    this.buttonSize = 50,
    this.iconSize = 28,
  });

  final Widget Function(BuildContext context, ScrollController controller)
      builder;
  final bool enabled;
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
  bool _canScrollBackward = false;
  bool _canScrollForward = false;
  bool _visibilityUpdateScheduled = false;

  bool get _showsDesktopButtons {
    if (!widget.enabled) {
      return false;
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
      _visibilityUpdateScheduled = false;
      _updateButtonVisibility();
    });
  }

  void _updateButtonVisibility() {
    if (!mounted) {
      return;
    }
    if (!_showsDesktopButtons) {
      if (_canScrollBackward || _canScrollForward) {
        setState(() {
          _canScrollBackward = false;
          _canScrollForward = false;
        });
      }
      return;
    }
    final hasClients = _controller.hasClients;
    final canScrollBackward = hasClients &&
        _controller.position.pixels >
            _controller.position.minScrollExtent + 0.5;
    final canScrollForward = hasClients &&
        _controller.position.pixels <
            _controller.position.maxScrollExtent - 0.5;
    if (_canScrollBackward == canScrollBackward &&
        _canScrollForward == canScrollForward) {
      return;
    }
    setState(() {
      _canScrollBackward = canScrollBackward;
      _canScrollForward = canScrollForward;
    });
  }

  Future<void> _scrollBy(double direction) async {
    if (!_controller.hasClients) {
      return;
    }
    final position = _controller.position;
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
    final child = NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _updateButtonVisibility();
        return false;
      },
      child: widget.builder(context, _controller),
    );
    if (!_showsDesktopButtons) {
      return child;
    }

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        child,
        if (_canScrollBackward)
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
        if (_canScrollForward)
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
  }
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
