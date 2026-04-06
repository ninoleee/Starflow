import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class StarflowLogo extends StatefulWidget {
  const StarflowLogo({
    super.key,
    this.iconSize = 96,
    this.showWordmark = true,
    this.wordmarkSize,
    this.showIconPlate = true,
    this.showPulseGlow = false,
  });

  final double iconSize;
  final bool showWordmark;
  final double? wordmarkSize;
  final bool showIconPlate;
  final bool showPulseGlow;

  @override
  State<StarflowLogo> createState() => _StarflowLogoState();
}

class _StarflowLogoState extends State<StarflowLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedWordmarkSize = widget.wordmarkSize ?? widget.iconSize * 0.29;
    final borderRadius = BorderRadius.circular(widget.iconSize * 0.253);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final glowOpacity =
                widget.showPulseGlow ? 0.6 + (_controller.value * 0.4) : 0.0;
            final glowScale =
                widget.showPulseGlow ? 1.0 + (_controller.value * 0.06) : 1.0;
            return SizedBox(
              width: widget.iconSize,
              height: widget.iconSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (widget.showPulseGlow)
                    Positioned.fill(
                      child: Transform.scale(
                        scale: glowScale,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(widget.iconSize * 0.4),
                            gradient: RadialGradient(
                              center: const Alignment(0, 0.2),
                              radius: 0.86,
                              colors: [
                                const Color(0xFF64A0FF)
                                    .withValues(alpha: 0.18 * glowOpacity),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      boxShadow: widget.showIconPlate
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.28),
                                blurRadius: widget.iconSize * 0.24,
                                offset: Offset(0, widget.iconSize * 0.08),
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: borderRadius,
                      child: SizedBox(
                        width: widget.iconSize,
                        height: widget.iconSize,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (widget.showIconPlate)
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF1C2C4D),
                                      Color(0xFF0B1424),
                                    ],
                                    begin: Alignment(-0.64, -1),
                                    end: Alignment(1, 1),
                                  ),
                                ),
                              ),
                            if (widget.showIconPlate)
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: Alignment(0, -0.56),
                                    radius: 0.72,
                                    colors: [
                                      Color(0x1F78A5FF),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            if (widget.showIconPlate)
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Color(0x2E000000),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: [0.54, 1],
                                  ),
                                ),
                              ),
                            Padding(
                              padding: EdgeInsets.all(
                                widget.showIconPlate
                                    ? widget.iconSize * 0.11
                                    : 0,
                              ),
                              child: SvgPicture.asset(
                                'assets/branding/starflow_logo_primary.svg',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (widget.showWordmark) ...[
          SizedBox(height: widget.iconSize * 0.21),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Star',
                style: TextStyle(
                  fontSize: resolvedWordmarkSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -resolvedWordmarkSize * 0.03,
                  color: Colors.white,
                ),
              ),
              Text(
                'flow',
                style: TextStyle(
                  fontSize: resolvedWordmarkSize,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -resolvedWordmarkSize * 0.04,
                  color: Colors.white.withValues(alpha: 0.48),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
