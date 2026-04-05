import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class StarflowLogo extends StatelessWidget {
  const StarflowLogo({
    super.key,
    this.iconSize = 96,
    this.showWordmark = true,
    this.wordmarkSize,
    this.showIconPlate = true,
  });

  final double iconSize;
  final bool showWordmark;
  final double? wordmarkSize;
  final bool showIconPlate;

  @override
  Widget build(BuildContext context) {
    final resolvedWordmarkSize = wordmarkSize ?? iconSize * 0.29;
    final borderRadius = BorderRadius.circular(iconSize * 0.24);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: iconSize,
          height: iconSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: showIconPlate
                  ? const LinearGradient(
                      colors: [
                        Color(0xFF0D1117),
                        Color(0xFF161B27),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              border: showIconPlate
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    )
                  : null,
              boxShadow: showIconPlate
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: iconSize * 0.22,
                        offset: Offset(0, iconSize * 0.07),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: CustomPaint(
                painter: _StarflowIconPainter(),
              ),
            ),
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(height: 16),
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

class _StarflowIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final artRect = Rect.fromLTWH(
      size.width * 0.03,
      size.height * 0.03,
      size.width * 0.94,
      size.height * 0.94,
    );

    Offset point(double x, double y) {
      return Offset(
        artRect.left + artRect.width * x / 96,
        artRect.top + artRect.height * y / 96,
      );
    }

    Paint strokePaint({
      required List<Color> colors,
      List<double>? stops,
      required double width,
      required Offset start,
      required Offset end,
    }) {
      return Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width * size.width / 96
        ..shader = ui.Gradient.linear(start, end, colors, stops);
    }

    final line1 = Path()
      ..moveTo(point(18, 62).dx, point(18, 62).dy)
      ..cubicTo(
        point(28, 62).dx,
        point(28, 62).dy,
        point(32, 52).dx,
        point(32, 52).dy,
        point(42, 52).dx,
        point(42, 52).dy,
      )
      ..cubicTo(
        point(52, 52).dx,
        point(52, 52).dy,
        point(56, 60).dx,
        point(56, 60).dy,
        point(66, 58).dx,
        point(66, 58).dy,
      )
      ..cubicTo(
        point(72, 57).dx,
        point(72, 57).dy,
        point(76, 53).dx,
        point(76, 53).dy,
        point(80, 50).dx,
        point(80, 50).dy,
      );
    canvas.drawPath(
      line1,
      strokePaint(
        colors: const [
          Color(0x003D7FFF),
          Color(0xFF6EB3FF),
          Color(0x33A5D0FF),
        ],
        stops: const [0, 0.4, 1],
        width: 1.5,
        start: point(18, 56),
        end: point(80, 56),
      ),
    );

    final line2 = Path()
      ..moveTo(point(18, 68).dx, point(18, 68).dy)
      ..cubicTo(
        point(30, 68).dx,
        point(30, 68).dy,
        point(34, 56).dx,
        point(34, 56).dy,
        point(46, 56).dx,
        point(46, 56).dy,
      )
      ..cubicTo(
        point(56, 56).dx,
        point(56, 56).dy,
        point(60, 64).dx,
        point(60, 64).dy,
        point(72, 61).dx,
        point(72, 61).dy,
      )
      ..cubicTo(
        point(76, 60).dx,
        point(76, 60).dy,
        point(79, 57).dx,
        point(79, 57).dy,
        point(82, 54).dx,
        point(82, 54).dy,
      );
    canvas.drawPath(
      line2,
      strokePaint(
        colors: const [
          Color(0x002D5FE0),
          Color(0xFF5599EE),
          Color(0x3390C0FF),
        ],
        stops: const [0, 0.4, 1],
        width: 1.2,
        start: point(18, 62),
        end: point(82, 62),
      ),
    );

    final line3 = Path()
      ..moveTo(point(18, 74).dx, point(18, 74).dy)
      ..cubicTo(
        point(32, 74).dx,
        point(32, 74).dy,
        point(36, 62).dx,
        point(36, 62).dy,
        point(50, 62).dx,
        point(50, 62).dy,
      )
      ..cubicTo(
        point(60, 62).dx,
        point(60, 62).dy,
        point(64, 68).dx,
        point(64, 68).dy,
        point(76, 65).dx,
        point(76, 65).dy,
      );
    canvas.drawPath(
      line3,
      strokePaint(
        colors: const [
          Color(0x001A3DA8),
          Color(0xFF4477CC),
          Color(0x267AACEE),
        ],
        stops: const [0, 0.5, 1],
        width: 0.9,
        start: point(18, 68),
        end: point(76, 68),
      ),
    );

    final starPath = Path()
      ..moveTo(point(48, 20).dx, point(48, 20).dy)
      ..lineTo(point(50.4, 33.6).dx, point(50.4, 33.6).dy)
      ..lineTo(point(64, 36).dx, point(64, 36).dy)
      ..lineTo(point(50.4, 38.4).dx, point(50.4, 38.4).dy)
      ..lineTo(point(48, 52).dx, point(48, 52).dy)
      ..lineTo(point(45.6, 38.4).dx, point(45.6, 38.4).dy)
      ..lineTo(point(32, 36).dx, point(32, 36).dy)
      ..lineTo(point(45.6, 33.6).dx, point(45.6, 33.6).dy)
      ..close();
    final starPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = ui.Gradient.linear(
        point(32, 20),
        point(64, 52),
        const [
          Color(0xFFE8F4FF),
          Color(0xFF7AB8FF),
        ],
      );
    canvas.drawPath(starPath, starPaint);

    final sparklePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width / 96
      ..color = const Color(0x99B4D2FF);
    canvas.drawLine(point(48, 16), point(48, 22), sparklePaint);
    canvas.drawLine(point(48, 50), point(48, 56), sparklePaint);
    canvas.drawLine(point(28, 36), point(34, 36), sparklePaint);
    canvas.drawLine(point(62, 36), point(68, 36), sparklePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
