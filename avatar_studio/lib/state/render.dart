// Рисование: слои, фон и кадр профиля. Одни и те же функции для сцены, миниатюр и PNG.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/model.dart';
import 'studio.dart';

Color parseHex(String? s, [Color fallback = const Color(0xFFCCCCCC)]) {
  if (s == null || !s.startsWith('#') || s.length < 7) return fallback;
  return Color(0xFF000000 | int.parse(s.substring(1, 7), radix: 16));
}

final Paint _imagePaint = Paint()..filterQuality = FilterQuality.high..isAntiAlias = true;

void _drawImageIn(Canvas c, ui.Image im, Rect dst) {
  c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst, _imagePaint);
}

/// Фон внутри области area (в координатах холста). Фото вписывается «по покрытию» с приближением и сдвигом в процентах.
void paintBg(Canvas c, Studio s, ViewSpec v, Rect area) {
  final part = s.partOf('bg', v);
  final g = s.geoOf('bg', v);
  if (part == null || !s.visOf('bg', v)) return;
  if (part.kind == 'solid') {
    c.drawRect(area, Paint()..color = parseHex(part.c1));
  } else if (part.kind == 'grad') {
    final sh = ui.Gradient.linear(area.topLeft, area.bottomRight, [parseHex(part.c1), parseHex(part.c2)]);
    c.drawRect(area, Paint()..shader = sh);
  } else {
    final im = s.imageOf(part);
    if (im == null) return;
    final k = math.max(area.width / im.width, area.height / im.height) * g.s;
    final w = im.width * k, h = im.height * k;
    final dst = Rect.fromLTWH(area.left + (area.width - w) / 2 + g.x / 100 * area.width, area.top + (area.height - h) / 2 + g.y / 100 * area.height, w, h);
    c.save();
    c.clipRect(area);
    _drawImageIn(c, im, dst);
    c.restore();
  }
}

void paintLayers(Canvas c, Studio s, ViewSpec v) {
  for (final id in s.p.order) {
    if (id == 'bg' || !s.visOf(id, v)) continue;
    final part = s.partOf(id, v);
    final r = s.rectFor(id, v);
    final im = s.imageOf(part);
    if (im == null || r == null) continue;
    final g = s.geoOf(id, v);
    if (g.r == 0) {
      _drawImageIn(c, im, r);
    } else {
      // поворот вокруг точки слота (там, где деталь «прикреплена»)
      c.save();
      c.translate(g.x, g.y);
      c.rotate(g.r * math.pi / 180);
      c.translate(-g.x, -g.y);
      _drawImageIn(c, im, r);
      c.restore();
    }
  }
}

Path shapePath(Rect f, String shape) => shape == 'circle' ? (Path()..addOval(f)) : (Path()..addRRect(RRect.fromRectAndRadius(f, Radius.circular(f.width * .24))));

Rect frameRect(FrameState f) => Rect.fromCenter(center: Offset(f.x, f.y), width: f.size, height: f.size);

/// Квадрат px×px: фон и персонаж внутри кадра, обрезано по форме.
void paintProfile(Canvas c, Studio s, ViewSpec v, double px) {
  final f = frameRect(v.frame);
  c.save();
  c.clipPath(shapePath(Rect.fromLTWH(0, 0, px, px), v.frame.shape), doAntiAlias: true);
  c.scale(px / f.width);
  c.translate(-f.left, -f.top);
  paintBg(c, s, v, f);
  paintLayers(c, s, v);
  c.restore();
}
