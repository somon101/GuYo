// Геометрия холста: слоты, положение деталей, кадр профиля. Чистая логика без интерфейса.
import 'dart:math' as math;
import 'dart:ui';

const double canvasW = 1200;
const double canvasH = 1600;
const String projectFormat = 'avatar-studio/1';

class BaseSlot {
  final String id, name, pivot;
  final double x, y, s, fit;
  const BaseSlot(this.id, this.name, this.pivot, this.x, this.y, this.s, this.fit);
}

/// Слоты по умолчанию снизу вверх. fit: доля ширины холста, в которую первый раз вписывается новая деталь.
const List<BaseSlot> baseSlots = [
  BaseSlot('bg', 'Фон', 'center', 600, 800, 1, 1),
  BaseSlot('handL', 'Рука левая', 'top', 250, 1030, 1, 0.16),
  BaseSlot('handR', 'Рука правая', 'top', 950, 1030, 1, 0.16),
  BaseSlot('cloth', 'Одежда', 'center', 600, 1180, 1, 0.82),
  BaseSlot('neck', 'Шея', 'center', 600, 760, 1, 0.42),
  BaseSlot('face', 'Голова с лицом', 'center', 600, 560, 1, 0.56),
  BaseSlot('glasses', 'Очки', 'center', 600, 580, 1, 0.42),
  BaseSlot('hair', 'Волосы', 'center', 600, 470, 1, 0.66),
];

BaseSlot? baseSlot(String id) {
  for (final b in baseSlots) {
    if (b.id == id) return b;
  }
  return null;
}

/// Положение слота: точка на холсте, масштаб, точка привязки детали, видимость.
class Geo {
  double x, y, s;
  String pivot;
  bool vis, placed;
  Geo({required this.x, required this.y, this.s = 1, this.pivot = 'center', this.vis = true, this.placed = false});
  factory Geo.fromBase(BaseSlot b) => Geo(x: b.x, y: b.y, s: b.s, pivot: b.pivot);
  Geo copy() => Geo(x: x, y: y, s: s, pivot: pivot, vis: vis, placed: placed);
  Map<String, dynamic> toJson() => {'x': x, 'y': y, 's': s, 'pivot': pivot, 'vis': vis ? 1 : 0, 'placed': placed ? 1 : 0};
  factory Geo.fromJson(Map j) => Geo(
        x: (j['x'] as num?)?.toDouble() ?? 600,
        y: (j['y'] as num?)?.toDouble() ?? 700,
        s: (j['s'] as num?)?.toDouble() ?? 1,
        pivot: (j['pivot'] as String?) ?? 'center',
        vis: (j['vis'] ?? 1) != 0 && j['vis'] != false,
        placed: (j['placed'] ?? 0) != 0 && j['placed'] != false,
      );
}

/// Прямоугольник детали на холсте: размер картинки * масштаб, привязка по pivot.
Rect? rectOf(double? w, double? h, Geo g) {
  if (w == null || h == null) return null;
  final ww = w * g.s, hh = h * g.s;
  final y = g.pivot == 'top' ? g.y : (g.pivot == 'bottom' ? g.y - hh : g.y - hh / 2);
  return Rect.fromLTWH(g.x - ww / 2, y, ww, hh);
}

/// Масштаб, при котором новая деталь занимает нужную долю ширины холста.
double fitScale(double partW, String slotId) {
  final fit = baseSlot(slotId)?.fit ?? 0.5;
  return (canvasW * fit / partW).clamp(0.02, 4.0).toDouble();
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
