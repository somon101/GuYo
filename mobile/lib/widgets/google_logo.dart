import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The four-colour Google "G", drawn (no image asset needed).
class GoogleLogo extends StatelessWidget {
  final double size;
  const GoogleLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _GooglePainter()));
}

class _GooglePainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.21;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    double rad(double deg) => deg * math.pi / 180;
    void arc(double from, double to, Color color) => canvas.drawArc(
          rect,
          rad(from),
          rad(to - from),
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke,
        );
    // Angles clockwise from 3 o'clock; the gap above the bar is the "G".
    arc(-8, 48, _blue);
    arc(48, 135, _green);
    arc(135, 218, _yellow);
    arc(218, 318, _red);
    // The bar.
    final c = size.center(Offset.zero);
    canvas.drawRect(
      Rect.fromLTRB(c.dx - size.width * 0.02, c.dy - stroke / 2, size.width - stroke * 0.02, c.dy + stroke / 2),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}
