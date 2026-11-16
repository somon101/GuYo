// Ручная правка вырезки: маска прозрачности поверх исходных цветов, кисти «стереть» и «вернуть»,
// удаление цвета, сглаживание края, отмена и повтор. Чистая логика без экрана.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'bg_removal.dart';

/// Изменение прямоугольника маски: что было и что стало (для отмены и повтора).
class _Patch {
  final int x, y, w, h;
  final Uint8List before, after;
  _Patch(this.x, this.y, this.w, this.h, this.before, this.after);
}

/// Результат авто-вырезки: новая маска и найденный режим фона.
class AutoAlpha {
  final Uint8List alpha;
  final String mode;
  AutoAlpha(this.alpha, this.mode);
}

/// Считает маску авто-вырезкой фона (тяжёлая часть, вызывается в отдельном потоке).
AutoAlpha autoAlpha(({Uint8List rgba, int w, int h, int tol}) a) {
  final d = Uint8List.fromList(a.rgba);
  final mode = removeBackground(d, a.w, a.h, tol: a.tol);
  final out = Uint8List(a.w * a.h);
  for (var i = 0; i < out.length; i++) {
    out[i] = d[i * 4 + 3];
  }
  if (mode == 'color') {
    // у цветного фона бывает градиент: добираем остатки заливкой по шагу от краёв, начиная с точек, похожих на фон
    final w = a.w, h = a.h;
    final cs = [0, w - 1, (h - 1) * w, w * h - 1];
    var r = 0, g = 0, b = 0;
    for (final i in cs) {
      r += a.rgba[i * 4];
      g += a.rgba[i * 4 + 1];
      b += a.rgba[i * 4 + 2];
    }
    r ~/= 4;
    g ~/= 4;
    b ~/= 4;
    final seeds = <int>[];
    void edge(int i) {
      final dr = a.rgba[i * 4] - r, dg = a.rgba[i * 4 + 1] - g, db = a.rgba[i * 4 + 2] - b;
      if (dr * dr + dg * dg + db * db < 70 * 70) seeds.add(i);
    }

    for (var x = 0; x < w; x++) {
      edge(x);
      edge((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      edge(y * w);
      edge(y * w + w - 1);
    }
    final fl = floodByStep(a.rgba, w, h, seeds, 12);
    for (var i = 0; i < out.length; i++) {
      if (fl[i] == 1) out[i] = 0;
    }
  }
  return AutoAlpha(out, mode);
}

/// Заливка по шагу: от заданных точек идёт по соседним пикселям, пока цвет меняется плавно
/// (разница с соседом не больше [step]) и не уходит далеко от цвета начала ([cap]). Так проходится градиент,
/// а резкий край детали останавливает заливку. Возвращает 1 у достигнутых пикселей.
Uint8List floodByStep(Uint8List rgba, int w, int h, List<int> seeds, int step, {int cap = 150}) {
  final seen = Uint8List(w * h);
  final stack = <int>[];
  final origin = Int32List(w * h);
  for (final s in seeds) {
    if (seen[s] == 0) {
      seen[s] = 1;
      origin[s] = s;
      stack.add(s);
    }
  }
  int d2(int a, int b) {
    final dr = rgba[a * 4] - rgba[b * 4], dg = rgba[a * 4 + 1] - rgba[b * 4 + 1], db = rgba[a * 4 + 2] - rgba[b * 4 + 2];
    return dr * dr + dg * dg + db * db;
  }

  final step2 = step * step, cap2 = cap * cap;
  void tryAdd(int from, int to) {
    if (seen[to] == 1) return;
    if (d2(from, to) > step2) return;
    if (d2(origin[from], to) > cap2) return;
    seen[to] = 1;
    origin[to] = origin[from];
    stack.add(to);
  }

  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    if (x > 0) tryAdd(i, i - 1);
    if (x < w - 1) tryAdd(i, i + 1);
    if (y > 0) tryAdd(i, i - w);
    if (y < h - 1) tryAdd(i, i + w);
  }
  return seen;
}

class CutOut {
  final Uint8List rgba;
  final int w, h;
  CutOut(this.rgba, this.w, this.h);
}

class MaskEditor {
  MaskEditor(this.w, this.h, Uint8List source)
      : rgba = Uint8List.fromList(source),
        alpha = Uint8List(w * h),
        orig = Uint8List(w * h) {
    for (var i = 0; i < w * h; i++) {
      alpha[i] = orig[i] = rgba[i * 4 + 3];
    }
  }

  final int w, h;

  /// Исходные цвета (альфа здесь не меняется: настоящая прозрачность лежит в [alpha]).
  final Uint8List rgba;

  /// Текущая маска и исходная (куда возвращает кисть «вернуть»).
  final Uint8List alpha, orig;

  /// Растёт при любом изменении: по нему экран понимает, что пора перерисовать.
  int version = 0;

  final _undo = <_Patch>[], _redo = <_Patch>[];
  static const _maxHistory = 40;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ---- кисть ----
  Uint8List? _cover, _base;
  int _sx0 = 0, _sy0 = 0, _sx1 = -1, _sy1 = -1;
  bool get stroking => _cover != null && _stroking;
  bool _stroking = false;

  void beginStroke() {
    _cover ??= Uint8List(w * h);
    _base ??= Uint8List(w * h);
    _sx0 = w;
    _sy0 = h;
    _sx1 = -1;
    _sy1 = -1;
    _stroking = true;
  }

  /// Один отпечаток кисти. r в пикселях картинки, soft 0..1 (0 резкий край, 1 максимально мягкий).
  void stamp(double cx, double cy, double r, double soft, {required bool erase}) {
    if (!_stroking) beginStroke();
    final cover = _cover!, base = _base!;
    final x0 = math.max(0, (cx - r).floor()), x1 = math.min(w - 1, (cx + r).ceil());
    final y0 = math.max(0, (cy - r).floor()), y1 = math.min(h - 1, (cy + r).ceil());
    final inner = (1 - soft).clamp(0.0, 0.97);
    var touched = false;
    for (var y = y0; y <= y1; y++) {
      final dy = y + 0.5 - cy;
      for (var x = x0; x <= x1; x++) {
        final dx = x + 0.5 - cx;
        final d = math.sqrt(dx * dx + dy * dy) / r;
        if (d >= 1) continue;
        double wgt;
        if (d <= inner) {
          wgt = 1;
        } else {
          final t = 1 - (d - inner) / (1 - inner);
          wgt = t * t * (3 - 2 * t);
        }
        final c = (wgt * 255).round();
        final i = y * w + x;
        if (c <= cover[i]) continue;
        if (cover[i] == 0) base[i] = alpha[i];
        cover[i] = c;
        final target = erase ? 0 : orig[i];
        alpha[i] = (base[i] + (target - base[i]) * c / 255).round();
        touched = true;
      }
    }
    if (touched) {
      _sx0 = math.min(_sx0, x0);
      _sy0 = math.min(_sy0, y0);
      _sx1 = math.max(_sx1, x1);
      _sy1 = math.max(_sy1, y1);
      version++;
    }
  }

  /// Мазок от точки a до точки b: отпечатки с шагом в четверть радиуса.
  void line(double ax, double ay, double bx, double by, double r, double soft, {required bool erase}) {
    final dist = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    final step = math.max(0.75, r * 0.25);
    final n = math.max(1, (dist / step).ceil());
    for (var i = 1; i <= n; i++) {
      final t = i / n;
      stamp(ax + (bx - ax) * t, ay + (by - ay) * t, r, soft, erase: erase);
    }
  }

  /// Закончить мазок: он становится одним шагом истории.
  void endStroke() {
    if (!_stroking) return;
    _stroking = false;
    if (_sx1 < _sx0) return;
    final cover = _cover!, base = _base!;
    final pw = _sx1 - _sx0 + 1, ph = _sy1 - _sy0 + 1;
    final before = Uint8List(pw * ph), after = Uint8List(pw * ph);
    for (var y = 0; y < ph; y++) {
      for (var x = 0; x < pw; x++) {
        final i = (_sy0 + y) * w + _sx0 + x;
        before[y * pw + x] = cover[i] > 0 ? base[i] : alpha[i];
        after[y * pw + x] = alpha[i];
        cover[i] = 0;
      }
    }
    _push(_Patch(_sx0, _sy0, pw, ph, before, after));
  }

  /// Отменить текущий мазок (например, если на экран лёг второй палец).
  void cancelStroke() {
    if (!_stroking) return;
    _stroking = false;
    if (_sx1 < _sx0) return;
    final cover = _cover!, base = _base!;
    for (var y = _sy0; y <= _sy1; y++) {
      for (var x = _sx0; x <= _sx1; x++) {
        final i = y * w + x;
        if (cover[i] > 0) {
          alpha[i] = base[i];
          cover[i] = 0;
        }
      }
    }
    version++;
  }

  // ---- целые операции ----
  void _push(_Patch p) {
    _undo.add(p);
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
    version++;
  }

  /// Заменяет маску на [next]; в историю идёт только изменённый прямоугольник.
  bool apply(Uint8List next) {
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (alpha[y * w + x] != next[y * w + x]) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) return false;
    final pw = x1 - x0 + 1, ph = y1 - y0 + 1;
    final before = Uint8List(pw * ph), after = Uint8List(pw * ph);
    for (var y = 0; y < ph; y++) {
      for (var x = 0; x < pw; x++) {
        final i = (y0 + y) * w + x0 + x;
        before[y * pw + x] = alpha[i];
        after[y * pw + x] = next[i];
      }
    }
    alpha.setAll(0, next);
    _push(_Patch(x0, y0, pw, ph, before, after));
    return true;
  }

  /// Убирает цвет (r,g,b) по всей детали. tol 0..100: чем больше, тем более далёкие оттенки уходят; край мягкий.
  bool removeColor(int r, int g, int b, double tol) {
    final tmax = tol * 2.4;
    if (tmax <= 0) return false;
    final hard = tmax * 0.6;
    final next = Uint8List.fromList(alpha);
    for (var i = 0; i < w * h; i++) {
      if (next[i] == 0) continue;
      final dr = rgba[i * 4] - r, dg = rgba[i * 4 + 1] - g, db = rgba[i * 4 + 2] - b;
      final d = math.sqrt((dr * dr + dg * dg + db * db).toDouble());
      if (d <= hard) {
        next[i] = 0;
      } else if (d < tmax) {
        next[i] = (next[i] * (d - hard) / (tmax - hard)).round();
      }
    }
    return apply(next);
  }

  /// «Волшебная палочка»: убирает фон, связанный с точкой (x, y), проходя плавные переходы цвета (градиент).
  bool floodRemove(int x, int y, int step) {
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    final fl = floodByStep(rgba, w, h, [y * w + x], step);
    final next = Uint8List.fromList(alpha);
    for (var i = 0; i < next.length; i++) {
      if (fl[i] == 1) next[i] = 0;
    }
    return apply(next);
  }

  /// Подтягивает край на пиксель внутрь и смягчает: убирает бахрому и ступеньки.
  bool smoothEdge() {
    final er = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var m = 255;
        for (var yy = math.max(0, y - 1); yy <= math.min(h - 1, y + 1); yy++) {
          for (var xx = math.max(0, x - 1); xx <= math.min(w - 1, x + 1); xx++) {
            final v = alpha[yy * w + xx];
            if (v < m) m = v;
          }
        }
        er[y * w + x] = m;
      }
    }
    final next = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0, n = 0;
        for (var yy = math.max(0, y - 1); yy <= math.min(h - 1, y + 1); yy++) {
          for (var xx = math.max(0, x - 1); xx <= math.min(w - 1, x + 1); xx++) {
            s += er[yy * w + xx];
            n++;
          }
        }
        next[y * w + x] = math.min(alpha[y * w + x], (s / n).round());
      }
    }
    return apply(next);
  }

  void clearHistory() {
    _undo.clear();
    _redo.clear();
  }

  void undo() => _swap(_undo, _redo, true);
  void redo() => _swap(_redo, _undo, false);

  void _swap(List<_Patch> from, List<_Patch> to, bool back) {
    if (from.isEmpty) return;
    final p = from.removeLast();
    final src = back ? p.before : p.after;
    for (var y = 0; y < p.h; y++) {
      for (var x = 0; x < p.w; x++) {
        alpha[(p.y + y) * w + p.x + x] = src[y * p.w + x];
      }
    }
    to.add(p);
    version++;
  }

  /// Цвет исходной картинки в точке (для пипетки).
  (int, int, int)? colorAt(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return null;
    final i = (y * w + x) * 4;
    return (rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  /// Записывает текущую прозрачность в буфер показа (цвета в нём уже исходные).
  void paintAlphaInto(Uint8List out) {
    for (var i = 0; i < w * h; i++) {
      out[i * 4 + 3] = alpha[i];
    }
  }

  /// Готовая деталь: обрезана по границе видимого, с небольшим запасом. null, если ничего не осталось.
  CutOut? result({int thr = 8, int pad = 2}) {
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (alpha[y * w + x] > thr) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) return null;
    x0 = math.max(0, x0 - pad);
    y0 = math.max(0, y0 - pad);
    x1 = math.min(w - 1, x1 + pad);
    y1 = math.min(h - 1, y1 + pad);
    final cw = x1 - x0 + 1, ch = y1 - y0 + 1;
    final out = Uint8List(cw * ch * 4);
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        final si = (y0 + y) * w + x0 + x, di = (y * cw + x) * 4;
        out[di] = rgba[si * 4];
        out[di + 1] = rgba[si * 4 + 1];
        out[di + 2] = rgba[si * 4 + 2];
        out[di + 3] = alpha[si];
      }
    }
    return CutOut(out, cw, ch);
  }
}

/// Кодирует RGBA в PNG (для отдельного потока).
Uint8List encodePngRgba(({Uint8List rgba, int w, int h}) a) {
  final im = img.Image.fromBytes(width: a.w, height: a.h, bytes: a.rgba.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  return Uint8List.fromList(img.encodePng(im, level: 3));
}
