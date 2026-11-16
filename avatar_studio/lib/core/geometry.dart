// Геометрия холста: слоты, положение деталей, кадр профиля. Чистая логика без интерфейса.
import 'dart:math' as math;
import 'dart:ui';

const double canvasW = 1200;
const double canvasH = 1600;
const String projectFormat = 'avatar-studio/1';

class BaseSlot {
  final String id, name, pivot;
  final double x, y, fit;
  const BaseSlot(this.id, this.name, this.pivot, this.x, this.y, this.fit);

  /// Стандартная ширина детали слота в пикселях холста.
  double get width => fit * canvasW;
}

/// Слоты по умолчанию снизу вверх. fit: доля ширины холста, которую по умолчанию занимает деталь слота.
const List<BaseSlot> baseSlots = [
  BaseSlot('bg', 'Фон', 'center', 600, 800, 1),
  BaseSlot('handL', 'Рука левая', 'top', 250, 1030, 0.16),
  BaseSlot('handR', 'Рука правая', 'top', 950, 1030, 0.16),
  BaseSlot('cloth', 'Одежда', 'center', 600, 1180, 0.82),
  BaseSlot('neck', 'Шея', 'center', 600, 760, 0.42),
  BaseSlot('face', 'Голова с лицом', 'center', 600, 560, 0.56),
  BaseSlot('glasses', 'Очки', 'center', 600, 580, 0.42),
  BaseSlot('hair', 'Волосы', 'center', 600, 470, 0.66),
];

BaseSlot? baseSlot(String id) {
  for (final b in baseSlots) {
    if (b.id == id) return b;
  }
  return null;
}

/// Положение: точка на холсте, ширина детали в пикселях холста, точка привязки и поворот (градусы, вокруг этой точки).
/// У слота это стандарт, у детали (Part.geo) её собственное положение. s и vis нужны слоту: приближение фона и видимость.
class Geo {
  double x, y, w, s, r;
  String pivot;
  bool vis;
  Geo({required this.x, required this.y, this.w = 400, this.s = 1, this.r = 0, this.pivot = 'center', this.vis = true});
  /// Фон: x и y это сдвиг в процентах, s приближение; у остальных слотов точка на холсте.
  factory Geo.fromBase(BaseSlot b) => b.id == 'bg' ? Geo(x: 0, y: 0, w: b.width) : Geo(x: b.x, y: b.y, w: b.width, pivot: b.pivot);
  factory Geo.generic() => Geo(x: 600, y: 700, w: 500);
  Geo copy() => Geo(x: x, y: y, w: w, s: s, r: r, pivot: pivot, vis: vis);
  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 's': s, 'r': r, 'pivot': pivot, 'vis': vis ? 1 : 0};
  factory Geo.fromJson(Map j, {double fallbackW = 500}) => Geo(
        x: (j['x'] as num?)?.toDouble() ?? 600,
        y: (j['y'] as num?)?.toDouble() ?? 700,
        w: (j['w'] as num?)?.toDouble() ?? fallbackW,
        s: (j['s'] as num?)?.toDouble() ?? 1,
        r: (j['r'] as num?)?.toDouble() ?? 0,
        pivot: (j['pivot'] as String?) ?? 'center',
        vis: (j['vis'] ?? 1) != 0 && j['vis'] != false,
      );
}

/// Прямоугольник детали на холсте: ширина задана положением, высота по пропорциям картинки.
Rect? rectOf(double? partW, double? partH, Geo g) {
  if (partW == null || partH == null || partW <= 0) return null;
  final hh = partH * g.w / partW;
  final y = g.pivot == 'top' ? g.y : (g.pivot == 'bottom' ? g.y - hh : g.y - hh / 2);
  return Rect.fromLTWH(g.x - g.w / 2, y, g.w, hh);
}

/// Описанный прямоугольник детали после поворота на deg градусов вокруг точки (cx, cy).
Rect rotatedBounds(Rect r, double cx, double cy, double deg) {
  if (deg == 0) return r;
  final a = deg * math.pi / 180, c = math.cos(a), s = math.sin(a);
  double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
  for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
    final dx = p.dx - cx, dy = p.dy - cy;
    final x = cx + dx * c - dy * s, y = cy + dx * s + dy * c;
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

Rect? unionRects(Iterable<Rect?> rs) {
  Rect? u;
  for (final r in rs) {
    if (r == null) continue;
    u = u == null ? r : u.expandToInclude(r);
  }
  return u;
}

class FrameBox {
  final double x, y, size;
  const FrameBox(this.x, this.y, this.size);
}

/// Готовые кадры профиля по видимым деталям: head, bust или full.
FrameBox framePreset(String mode, Map<String, Rect?> rects) {
  final head = unionRects([rects['face'], rects['hair'], rects['neck']]) ?? const Rect.fromLTWH(300, 200, 600, 620);
  final all = unionRects(rects.entries.where((e) => e.key != 'bg').map((e) => e.value)) ?? head;
  if (mode == 'head') {
    final top = head.top;
    final face = rects['face'];
    final bottom = face != null ? face.bottom : head.bottom;
    final size = math.max(head.width, bottom - top) * 1.12;
    return FrameBox(head.center.dx, top + (bottom - top) / 2, size);
  }
  if (mode == 'bust') {
    final cl = rects['cloth'];
    final bottom = cl != null ? cl.top + cl.height * 0.55 : head.top + head.height * 1.7;
    final top = head.top;
    final size = math.max(head.width * 1.25, bottom - top) * 1.08;
    return FrameBox(head.center.dx, top + (bottom - top) / 2, size);
  }
  return FrameBox(all.center.dx, all.center.dy, math.max(all.width, all.height) * 1.06);
}
