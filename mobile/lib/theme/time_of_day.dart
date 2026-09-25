import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The part of the day the greeting's sky object reflects.
///
/// Decided entirely from the DEVICE's own clock -- never the server's. Two
/// people opening GuYo at the same instant in Dushanbe and in Berlin must
/// each see their own sky, so nothing here may go near a backend time.
enum DayPart { morning, day, evening, night }

/// One boundary in the day: this part begins at [startHour] local time and
/// runs until the next window starts.
class DayPartWindow {
  final DayPart part;

  /// Local hour, 0-23, at which this part begins.
  final int startHour;

  const DayPartWindow(this.part, this.startHour);
}

/// Where a moment in the day maps to a part.
///
/// The boundaries live here, in one list, precisely so they can be moved
/// without touching the widget that draws them -- change the hours (or
/// hand the greeting a different scheme entirely, e.g. one fetched from
/// the backend later) and everything downstream follows. The widget asks
/// "which part is it", never "what hour is it".
class TimeOfDayScheme {
  /// Windows in ascending start order. The last one wraps past midnight.
  final List<DayPartWindow> windows;

  const TimeOfDayScheme(this.windows);

  /// GuYo's default boundaries.
  static const standard = TimeOfDayScheme([
    DayPartWindow(DayPart.night, 0),
    DayPartWindow(DayPart.morning, 5),
    DayPartWindow(DayPart.day, 11),
    DayPartWindow(DayPart.evening, 17),
    DayPartWindow(DayPart.night, 22),
  ]);

  /// The part [at] falls in. Takes an explicit moment rather than reading
  /// the clock itself, so a test can pin it -- and so the caller is the
  /// one that decides the time is local (see [DayPartIcon]).
  DayPart partAt(DateTime at) {
    final hour = at.hour;
    var current = windows.first.part;
    for (final window in windows) {
      if (hour >= window.startHour) {
        current = window.part;
      } else {
        break;
      }
    }
    return current;
  }
}

/// How each part looks: the two colours of its sky, top to bottom, and the
/// name read out by screen readers. Kept beside the scheme so adding a part
/// means adding one entry here, one window above and one scene in
/// [DaySkyPainter] -- nothing else changes.
const Map<DayPart, ({Color skyTop, Color skyBottom, String label})> dayPartLooks = {
  DayPart.morning: (skyTop: Color(0xFFFFE2B8), skyBottom: Color(0xFFFFB38A), label: 'Утро'),
  DayPart.day: (skyTop: Color(0xFF7CCBFF), skyBottom: Color(0xFFBDE7FF), label: 'День'),
  DayPart.evening: (skyTop: Color(0xFF7B5CD6), skyBottom: Color(0xFFFF8C7A), label: 'Вечер'),
  DayPart.night: (skyTop: Color(0xFF1E2257), skyBottom: Color(0xFF3B3F8F), label: 'Ночь'),
};

/// The sky object beside the greeting: a small round window onto the sky
/// as it is right now ON THIS DEVICE -- sunrise over hills, sun behind a
/// cloud, sunset, or moon and stars.
///
/// [now] exists only so tests can pin the clock; in the app it is left
/// null and the device's own local time is read.
class DayPartIcon extends StatelessWidget {
  final double size;
  final TimeOfDayScheme scheme;
  final DateTime? now;

  const DayPartIcon({super.key, this.size = 18, this.scheme = TimeOfDayScheme.standard, this.now});

  @override
  Widget build(BuildContext context) {
    // DateTime.now() is the device's own local wall clock -- the whole
    // point of this widget. Nothing here consults the backend.
    final part = scheme.partAt(now ?? DateTime.now());
    return DaySkyBadge(part: part, size: size);
  }
}

/// One part of the day drawn as a round sky badge, independent of any
/// clock -- so a screen that wants to show every part (or a test) can draw
/// a specific one directly.
class DaySkyBadge extends StatelessWidget {
  final DayPart part;
  final double size;

  const DaySkyBadge({super.key, required this.part, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: dayPartLooks[part]!.label,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: DaySkyPainter(part)),
      ),
    );
  }
}

/// Paints one [DayPart] as a sky inside a circle.
///
/// Everything is laid out on a 64x64 grid and scaled to the real size, so
/// the badge stays the same picture from 18px beside the greeting up to a
/// large hero illustration.
class DaySkyPainter extends CustomPainter {
  final DayPart part;

  const DaySkyPainter(this.part);

  static const _grid = 64.0;
  static const _center = Offset(32, 32);
  static const _radius = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / _grid;
    canvas.save();
    canvas.scale(scale);

    final look = dayPartLooks[part]!;
    final disc = Rect.fromCircle(center: _center, radius: _radius);
    canvas.drawCircle(
      _center,
      _radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [look.skyTop, look.skyBottom],
        ).createShader(disc),
    );
    // Hills and clouds run off the edge of the window, never past it.
    canvas.clipPath(Path()..addOval(disc));

    switch (part) {
      case DayPart.morning:
        _paintMorning(canvas);
      case DayPart.day:
        _paintDay(canvas);
      case DayPart.evening:
        _paintEvening(canvas);
      case DayPart.night:
        _paintNight(canvas);
    }
    canvas.restore();
  }

  /// A pale sun just clearing two layers of warm hills.
  void _paintMorning(Canvas canvas) {
    canvas.drawCircle(const Offset(32, 42), 12, _fill(const Color(0xFFFFF3C4)));
    canvas.drawPath(
      _hill(
        const Offset(0, 44),
        const Offset(16, 36),
        const Offset(32, 44),
        const Offset(48, 52),
        const Offset(64, 42),
      ),
      _fill(const Color(0xFFFF9466)),
    );
    canvas.drawPath(
      _hill(
        const Offset(0, 50),
        const Offset(20, 44),
        const Offset(40, 50),
        const Offset(60, 56),
        const Offset(64, 50),
      ),
      _fill(const Color(0xFFF07448)),
    );
  }

  /// A full sun with rays, half hidden behind a white cloud.
  void _paintDay(Canvas canvas) {
    const sun = Offset(30, 28);
    final ray = Paint()
      ..color = const Color(0xFFFFD84D)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(sun + direction * 14, sun + direction * 18, ray);
    }
    canvas.drawCircle(sun, 10, _fill(const Color(0xFFFFD84D)));
    _paintCloud(canvas, const Offset(36, 44), 1.1, Colors.white);
  }

  /// A warm sun sinking behind a dark violet hill, first star already out.
  void _paintEvening(Canvas canvas) {
    canvas.drawCircle(const Offset(32, 42), 12, _fill(const Color(0xFFFFC66B)));
    canvas.drawPath(
      _hill(
        const Offset(0, 46),
        const Offset(16, 40),
        const Offset(32, 46),
        const Offset(48, 52),
        const Offset(64, 44),
      ),
      _fill(const Color(0xFF5A3FA8)),
    );
    _paintStar(canvas, const Offset(16, 16), 2.2);
  }

  /// A crescent moon among a few stars.
  void _paintNight(Canvas canvas) {
    const c = _center;
    const r = 13.0;
    final tip = Offset(c.dx + r * 0.35, c.dy - r);
    final moon = Path()
      ..moveTo(tip.dx, tip.dy)
      ..arcToPoint(
        Offset(c.dx + r, c.dy + r * 0.45),
        radius: const Radius.circular(r),
        largeArc: true,
        clockwise: false,
      )
      ..arcToPoint(tip, radius: const Radius.circular(r * 0.8), clockwise: true)
      ..close();
    canvas.drawPath(moon, _fill(const Color(0xFFFFE89A)));
    _paintStar(canvas, const Offset(47, 18), 3);
    _paintStar(canvas, const Offset(17, 20), 2);
    _paintStar(canvas, const Offset(46, 44), 1.8);
    canvas.drawCircle(const Offset(20, 46), 1, _fill(Colors.white));
  }

  /// Ground from the left edge to the right one, as two joined curves: the
  /// second bends back the other way, so the horizon rolls.
  Path _hill(Offset start, Offset control1, Offset mid, Offset control2, Offset end) {
    return Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control1.dx, control1.dy, mid.dx, mid.dy)
      ..quadraticBezierTo(control2.dx, control2.dy, end.dx, end.dy)
      ..lineTo(_grid, _grid)
      ..lineTo(0, _grid)
      ..close();
  }

  /// A puffy cloud with a flat base, drawn around [at].
  void _paintCloud(Canvas canvas, Offset at, double scale, Color color) {
    Offset p(double x, double y) => at + Offset(x, y) * scale;
    final cloud = Path()
      ..moveTo(p(-14, 6).dx, p(-14, 6).dy)
      ..arcToPoint(p(-12, -9.5), radius: Radius.circular(8 * scale))
      ..arcToPoint(p(9, -10), radius: Radius.circular(11 * scale))
      ..arcToPoint(p(14, 6), radius: Radius.circular(8 * scale))
      ..close();
    canvas.drawPath(cloud, _fill(color));
  }

  /// A four-pointed twinkle with softly pinched sides.
  void _paintStar(Canvas canvas, Offset c, double r) {
    final star = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(star, _fill(Colors.white));
  }

  Paint _fill(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  @override
  bool shouldRepaint(DaySkyPainter oldDelegate) => oldDelegate.part != part;
}
