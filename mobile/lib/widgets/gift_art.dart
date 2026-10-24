import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The season-pass gift: a glossy pink box with golden ribbons and a bow,
/// drawn in code (no image files). [background] adds the violet spotlight
/// scene, [confetti] the streamers and dots around it.
class GiftArt extends StatelessWidget {
  final double size;
  final bool background;
  final bool confetti;
  const GiftArt({
    super.key,
    this.size = 96,
    this.background = false,
    this.confetti = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size * 1.15,
    child: CustomPaint(
      painter: _GiftPainter(background: background, confetti: confetti),
    ),
  );
}

Paint _lin(
  Rect r,
  List<Color> cs, {
  Alignment a = Alignment.topLeft,
  Alignment b = Alignment.bottomRight,
  List<double>? stops,
}) => Paint()
  ..isAntiAlias = true
  ..shader = LinearGradient(
    begin: a,
    end: b,
    colors: cs,
    stops: stops,
  ).createShader(r);
Paint _rad(Offset c, double r, List<Color> cs, {List<double>? stops}) => Paint()
  ..shader = RadialGradient(
    colors: cs,
    stops: stops,
  ).createShader(Rect.fromCircle(center: c, radius: r));

class _GiftPainter extends CustomPainter {
  final bool background;
  final bool confetti;
  const _GiftPainter({required this.background, required this.confetti});

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    // Alone (no scene, no confetti) the box fills the space it is given.
    if (!background && !confetti) {
      c.translate(w / 2, h * 0.62);
      c.scale(1.55);
      c.translate(-w / 2, -h * 0.62);
    }
    // background: violet with a soft spotlight
    if (background) {
      c.drawRect(
        Offset.zero & s,
        _lin(
          Offset.zero & s,
          const [Color(0xFF8A2BFF), Color(0xFF5B12D6)],
          a: Alignment.topCenter,
          b: Alignment.bottomCenter,
        ),
      );
      c.drawCircle(
        Offset(w * 0.5, h * 0.48),
        w * 0.62,
        _rad(Offset(w * 0.5, h * 0.48), w * 0.62, [
          const Color(0xFFB57BFF).withValues(alpha: 0.55),
          const Color(0x00B57BFF),
        ]),
      );
    }

    // floor shadow
    c.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.86),
        width: w * 0.62,
        height: h * 0.06,
      ),
      Paint()
        ..color = const Color(0xFF2A0570).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    final l = w * 0.24, r = w * 0.76, top = h * 0.52, bottom = h * 0.83;
    final rr = Radius.circular(w * 0.07);
    // box body
    final body = RRect.fromLTRBAndCorners(
      l,
      top,
      r,
      bottom,
      bottomLeft: rr,
      bottomRight: rr,
      topLeft: const Radius.circular(6),
      topRight: const Radius.circular(6),
    );
    c.drawRRect(
      body,
      _lin(
        body.outerRect,
        const [Color(0xFFFF7D9B), Color(0xFFF2416F), Color(0xFFC81D55)],
        a: Alignment.centerLeft,
        b: Alignment.centerRight,
        stops: const [0, 0.45, 1],
      ),
    );
    // inner shading at the bottom and a soft reflection on the left
    c.save();
    c.clipRRect(body);
    c.drawRect(
      Rect.fromLTRB(l, bottom - h * 0.08, r, bottom),
      _lin(
        Rect.fromLTRB(l, bottom - h * 0.08, r, bottom),
        [const Color(0x00000000), Colors.black.withValues(alpha: 0.18)],
        a: Alignment.topCenter,
        b: Alignment.bottomCenter,
      ),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(l + w * 0.03, top + h * 0.05, w * 0.035, h * 0.2),
        const Radius.circular(10),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    c.restore();

    // lid: front strip + top face
    final lidL = w * 0.205, lidR = w * 0.795;
    final lidFront = RRect.fromLTRBR(
      lidL,
      h * 0.44,
      lidR,
      h * 0.545,
      Radius.circular(w * 0.04),
    );
    c.drawRRect(
      lidFront.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0xFF8E0F3C).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    c.drawRRect(
      lidFront,
      _lin(
        lidFront.outerRect,
        const [Color(0xFFFF8DA7), Color(0xFFF5527C), Color(0xFFD42A60)],
        a: Alignment.centerLeft,
        b: Alignment.centerRight,
        stops: const [0, 0.45, 1],
      ),
    );
    final lidTop = RRect.fromLTRBR(
      lidL + 2,
      h * 0.395,
      lidR - 2,
      h * 0.47,
      Radius.circular(w * 0.06),
    );
    c.drawRRect(
      lidTop,
      _lin(
        lidTop.outerRect,
        const [Color(0xFFFFB7C8), Color(0xFFFF7E9C)],
        a: Alignment.topLeft,
        b: Alignment.bottomRight,
      ),
    );
    c.drawRRect(
      RRect.fromLTRBR(
        lidL + w * 0.05,
        h * 0.405,
        lidL + w * 0.2,
        h * 0.418,
        const Radius.circular(6),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // golden ribbon: vertical band over lid + body, cross band on the lid top
    const gold = [Color(0xFFFFE27A), Color(0xFFFFB52E), Color(0xFFE88A12)];
    final bandL = w * 0.445, bandR = w * 0.555;
    final bandBody = Rect.fromLTRB(bandL, top, bandR, bottom);
    c.drawRect(
      bandBody,
      _lin(bandBody, gold, a: Alignment.centerLeft, b: Alignment.centerRight),
    );
    final bandLid = Rect.fromLTRB(bandL - 3, h * 0.44, bandR + 3, h * 0.545);
    c.drawRect(
      bandLid,
      _lin(bandLid, gold, a: Alignment.centerLeft, b: Alignment.centerRight),
    );
    final bandTop = Rect.fromLTRB(bandL - 4, h * 0.398, bandR + 4, h * 0.468);
    c.drawRect(
      bandTop,
      _lin(
        bandTop,
        const [Color(0xFFFFF0A8), Color(0xFFFFC447)],
        a: Alignment.topCenter,
        b: Alignment.bottomCenter,
      ),
    );
    c.drawRect(
      Rect.fromLTRB(lidL + 6, h * 0.42, lidR - 6, h * 0.445),
      _lin(
        Rect.fromLTRB(lidL, h * 0.42, lidR, h * 0.445),
        const [Color(0xFFFFE27A), Color(0xFFFFB52E)],
        a: Alignment.topCenter,
        b: Alignment.bottomCenter,
      ),
    );
    c.drawRect(
      Rect.fromLTRB(bandL + 4, top + 4, bandL + 9, bottom - 8),
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );

    // bow: two filled loops with a darker inside, plus tails and the knot
    void loopShape(bool left) {
      final sgn = left ? -1.0 : 1.0;
      final o = Offset(w * 0.5, h * 0.4);
      final outer = Path()
        ..moveTo(o.dx, o.dy)
        ..cubicTo(
          o.dx + sgn * w * 0.06,
          o.dy - h * 0.2,
          o.dx + sgn * w * 0.3,
          o.dy - h * 0.18,
          o.dx + sgn * w * 0.24,
          o.dy - h * 0.03,
        )
        ..cubicTo(
          o.dx + sgn * w * 0.2,
          o.dy + h * 0.03,
          o.dx + sgn * w * 0.08,
          o.dy + h * 0.02,
          o.dx,
          o.dy,
        )
        ..close();
      c.drawPath(
        outer.shift(const Offset(0, 3)),
        Paint()
          ..color = const Color(0xFF9A4A00).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      c.drawPath(
        outer,
        _lin(
          outer.getBounds(),
          const [Color(0xFFFFE07A), Color(0xFFFFA928), Color(0xFFE67E0F)],
          a: left ? Alignment.topRight : Alignment.topLeft,
          b: left ? Alignment.bottomLeft : Alignment.bottomRight,
        ),
      );
      final hole = Path()
        ..moveTo(o.dx + sgn * w * 0.05, o.dy - h * 0.02)
        ..cubicTo(
          o.dx + sgn * w * 0.09,
          o.dy - h * 0.12,
          o.dx + sgn * w * 0.21,
          o.dy - h * 0.11,
          o.dx + sgn * w * 0.19,
          o.dy - h * 0.04,
        )
        ..cubicTo(
          o.dx + sgn * w * 0.16,
          o.dy - h * 0.01,
          o.dx + sgn * w * 0.09,
          o.dy - h * 0.005,
          o.dx + sgn * w * 0.05,
          o.dy - h * 0.02,
        )
        ..close();
      c.drawPath(
        hole,
        _lin(
          hole.getBounds(),
          const [Color(0xFFC86A08), Color(0xFFE88A12)],
          a: Alignment.topCenter,
          b: Alignment.bottomCenter,
        ),
      );
      c.drawPath(
        Path()
          ..moveTo(o.dx + sgn * w * 0.1, o.dy - h * 0.135)
          ..quadraticBezierTo(
            o.dx + sgn * w * 0.17,
            o.dy - h * 0.165,
            o.dx + sgn * w * 0.23,
            o.dy - h * 0.12,
          ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );
    }

    loopShape(true);
    loopShape(false);
    final knot = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.4),
        width: w * 0.11,
        height: h * 0.07,
      ),
      const Radius.circular(10),
    );
    c.drawRRect(
      knot,
      _lin(
        knot.outerRect,
        const [Color(0xFFFFEC9E), Color(0xFFFFB52E), Color(0xFFE88A12)],
        a: Alignment.topCenter,
        b: Alignment.bottomCenter,
      ),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(knot.left + 6, knot.top + 4, knot.width * 0.45, 4),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );

    // confetti: streamers with depth, ribbons, dots and a tiny star
    if (!confetti) return;
    void streamer(
      Offset o,
      double size,
      List<Color> cs,
      double turn,
      double width, {
      double blur = 0,
    }) {
      final p = Path()..moveTo(o.dx, o.dy);
      for (var i = 1; i <= 40; i++) {
        final t = i / 40;
        final a = turn + t * math.pi * 3;
        p.lineTo(
          o.dx + math.cos(a) * size * (0.3 + 0.35 * t) + t * size * 0.7,
          o.dy + math.sin(a) * size * 0.32 + t * size * 0.5,
        );
      }
      final paint = _lin(p.getBounds(), cs)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      c.drawPath(p, paint);
    }

    streamer(
      Offset(w * 0.12, h * 0.14),
      w * 0.13,
      const [Color(0xFFFFD36B), Color(0xFFFF8A1F)],
      0.3,
      7,
    );
    streamer(
      Offset(w * 0.7, h * 0.12),
      w * 0.12,
      const [Color(0xFF6FF2E0), Color(0xFF1FB8C9)],
      2.4,
      6,
    );
    streamer(
      Offset(w * 0.08, h * 0.62),
      w * 0.08,
      const [Color(0xFFFF9BC0), Color(0xFFFF5A8E)],
      1.2,
      4,
      blur: 1.2,
    );
    void chip(Offset o, double ww, double hh, double rot, Color col) {
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate(rot);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: ww, height: hh),
          const Radius.circular(2),
        ),
        Paint()..color = col,
      );
      c.restore();
    }

    chip(Offset(w * 0.86, h * 0.36), 7, 14, 0.6, const Color(0xFFFFC857));
    chip(Offset(w * 0.16, h * 0.4), 6, 12, -0.5, const Color(0xFFFF7AA2));
    chip(Offset(w * 0.84, h * 0.66), 6, 12, 1.1, const Color(0xFF6FF2E0));
    chip(Offset(w * 0.55, h * 0.1), 5, 10, 0.2, Colors.white);
    for (final d in [
      (0.33, 0.2, 3.5, Color(0xFFFFFFFF)),
      (0.9, 0.5, 3.0, Color(0xFFFFD36B)),
      (0.14, 0.76, 3.0, Color(0xFFFFB52E)),
      (0.62, 0.24, 2.5, Color(0xFFFF9BC0)),
    ]) {
      c.drawCircle(Offset(w * d.$1, h * d.$2), d.$3, Paint()..color = d.$4);
    }
  }

  @override
  bool shouldRepaint(_GiftPainter old) =>
      old.background != background || old.confetti != confetti;
}
