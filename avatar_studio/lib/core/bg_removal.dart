// Автоматическое вырезание фона (чёрный, белый, «шахматка», однотонный).
// Работает на RGBA-байтах на месте. Порт проверенной версии из веб-студии.
import 'dart:typed_data';

/// Возвращает режим: 'alpha' (уже есть прозрачность), 'black', 'neutral' или 'color'.
String removeBackground(Uint8List d, int w, int h, {int tol = 16, int erode = 1, int blur = 1, int open = -1, double minIsland = 0.004}) {
  final n = w * h;
  int a(int i) => d[i * 4 + 3];
  final corners = [0, w - 1, (h - 1) * w, n - 1];
  if (corners.every((i) => a(i) < 200)) return 'alpha';
  double cr = 0, cg = 0, cb = 0;
  for (final i in corners) {
    cr += d[i * 4];
    cg += d[i * 4 + 1];
    cb += d[i * 4 + 2];
  }
  cr /= 4;
  cg /= 4;
  cb /= 4;
  final mx = [cr, cg, cb].reduce((p, q) => p > q ? p : q);
  final mn = [cr, cg, cb].reduce((p, q) => p < q ? p : q);
  final String mode;
  if (mx <= 70) {
    mode = 'black';
  } else if (mx - mn <= 28 && mn >= 110) {
    mode = 'neutral';
  } else {
    mode = 'color';
  }
  // тонкие щели фона в тёмной одежде: на чёрном раскрытие маски сильнее
  if (open < 0) open = mode == 'black' ? 5 : 2;
  var t = tol;
  if (mode == 'black') {
    // порог по шуму самой картинки: у JPEG чёрный фон обычно 0..6
    final hist = List<int>.filled(256, 0);
    var cnt = 0;
    void sample(int i) {
      final m = [d[i * 4], d[i * 4 + 1], d[i * 4 + 2]].reduce((p, q) => p > q ? p : q);
      hist[m]++;
      cnt++;
    }

    for (var x = 0; x < w; x++) {
      sample(x);
      sample((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      sample(y * w);
      sample(y * w + w - 1);
    }
    var acc = 0, p90 = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= cnt * 0.9) {
        p90 = v;
        break;
      }
    }
    t = tol < (p90 + 3 > 3 ? p90 + 3 : 3) ? tol : (p90 + 3 > 3 ? p90 + 3 : 3);
  }
  final isBg = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final r = d[i * 4], g = d[i * 4 + 1], b = d[i * 4 + 2];
    final hi = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final lo = r < g ? (r < b ? r : b) : (g < b ? g : b);
    if (mode == 'black') {
      isBg[i] = hi <= t ? 1 : 0;
    } else if (mode == 'neutral') {
      isBg[i] = (hi - lo <= t + 6 && lo >= 120) ? 1 : 0;
    } else {
      isBg[i] = ((r - cr).abs() + (g - cg).abs() + (b - cb).abs()) <= t * 4 ? 1 : 0;
    }
  }
  // заливка от границы
  final bg = Uint8List(n);
  final q = Int32List(n);
  var qh = 0, qt = 0;
  void push(int i) {
    if (isBg[i] == 1 && bg[i] == 0) {
      bg[i] = 1;
      q[qt++] = i;
    }
  }

  for (var x = 0; x < w; x++) {
    push(x);
    push((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    push(y * w);
    push(y * w + w - 1);
  }
  while (qh < qt) {
    final i = q[qh++];
    final x = i % w, y = i ~/ w;
    if (x > 0) push(i - 1);
    if (x < w - 1) push(i + 1);
    if (y > 0) push(i - w);
    if (y < h - 1) push(i + w);
  }
  if (open > 0) {
    final e = _box(bg, w, h, open, true);
    final o = _box(e, w, h, open, false);
    for (var i = 0; i < n; i++) {
      bg[i] = (bg[i] == 1 && o[i] == 1) ? 1 : 0;
    }
  }
  var fg = Uint8List(n);
  for (var i = 0; i < n; i++) {
    fg[i] = bg[i] == 1 ? 0 : 1;
  }
  fg = _dropIslands(fg, w, h, minIsland);
  // тёмная кайма у светлых предметов (след старого фона): снимаем по слою края, которые заметно темнее
  // соседних пикселей внутри предмета, а совсем тёмные края (меньше 70) снимаем всегда
  if (mode == 'black') {
    int bright(int i) {
      final r = d[i * 4], g = d[i * 4 + 1], b = d[i * 4 + 2];
      return r > g ? (r > b ? r : b) : (g > b ? g : b);
    }

    for (var p = 0; p < 6; p++) {
      final edges = <int>[];
      final mask = Uint8List(n);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          if (fg[i] == 0) continue;
          if ((x > 0 && fg[i - 1] == 0) || (x < w - 1 && fg[i + 1] == 0) || (y > 0 && fg[i - w] == 0) || (y < h - 1 && fg[i + w] == 0)) {
            edges.add(i);
            mask[i] = 1;
          }
        }
      }
      final del = <int>[];
      for (final i in edges) {
        final m = bright(i);
        if (m < 70) {
          del.add(i);
          continue;
        }
        final x = i % w, y = i ~/ w;
        var sum = 0, k = 0;
        for (var dy = -4; dy <= 4; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -4; dx <= 4; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            final j = yy * w + xx;
            if (fg[j] == 1 && mask[j] == 0) {
              sum += bright(j);
              k++;
            }
          }
        }
        if (k >= 4 && m < 0.62 * (sum / k)) del.add(i);
      }
      if (del.isEmpty) break;
      for (final i in del) {
        fg[i] = 0;
      }
    }
  }
  for (var p = 0; p < erode; p++) {
    final nx = Uint8List(n);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (fg[i] == 0) continue;
        if ((x > 0 && fg[i - 1] == 0) || (x < w - 1 && fg[i + 1] == 0) || (y > 0 && fg[i - w] == 0) || (y < h - 1 && fg[i + w] == 0)) continue;
        nx[i] = 1;
      }
    }
    fg = nx;
  }
  // мягкий край
  var al = Float32List(n);
  for (var i = 0; i < n; i++) {
    al[i] = fg[i].toDouble();
  }
  if (blur > 0) {
    for (var pass = 0; pass < 2; pass++) {
      final tmp = Float32List(n), dst = Float32List(n);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          double s = 0;
          var k = 0;
          for (var dx = -blur; dx <= blur; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            s += al[y * w + xx];
            k++;
          }
          tmp[y * w + x] = s / k;
        }
      }
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          double s = 0;
          var k = 0;
          for (var dy = -blur; dy <= blur; dy++) {
            final yy = y + dy;
            if (yy < 0 || yy >= h) continue;
            s += tmp[yy * w + x];
            k++;
          }
          dst[y * w + x] = s / k;
        }
      }
      al = dst;
    }
  }
  // цвет мягкого края: среднее соседей из плотной части, чтобы старый фон не просвечивал
  const r = 3;
  final src = Uint8List.fromList(d);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (al[i] >= 0.999 || al[i] <= 0.001) continue;
      var sr = 0, sg = 0, sb = 0, k = 0;
      for (var dy = -r; dy <= r; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -r; dx <= r; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final j = yy * w + xx;
          if (al[j] >= 0.999) {
            sr += src[j * 4];
            sg += src[j * 4 + 1];
            sb += src[j * 4 + 2];
            k++;
          }
        }
      }
      if (k > 0) {
        d[i * 4] = sr ~/ k;
        d[i * 4 + 1] = sg ~/ k;
        d[i * 4 + 2] = sb ~/ k;
      }
    }
  }
  for (var i = 0; i < n; i++) {
    final v = (al[i] * 255).round();
    d[i * 4 + 3] = v < a(i) ? v : a(i);
  }
  return mode;
}

/// min/max по квадрату радиуса r (раскрытие и закрытие маски)
Uint8List _box(Uint8List src, int w, int h, int r, bool isMin) {
  final tmp = Uint8List(w * h), dst = Uint8List(w * h);
  final edge = isMin ? 1 : 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = isMin ? 1 : 0;
      for (var d = -r; d <= r; d++) {
        final xx = x + d;
        final val = (xx < 0 || xx >= w) ? edge : src[y * w + xx];
        if (isMin ? val == 0 : val == 1) {
          v = isMin ? 0 : 1;
          break;
        }
      }
      tmp[y * w + x] = v;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = isMin ? 1 : 0;
      for (var d = -r; d <= r; d++) {
        final yy = y + d;
        final val = (yy < 0 || yy >= h) ? edge : tmp[yy * w + x];
        if (isMin ? val == 0 : val == 1) {
          v = isMin ? 0 : 1;
          break;
        }
      }
      dst[y * w + x] = v;
    }
  }
  return dst;
}

/// Оставляем связные области не меньше доли minFrac от самой большой.
Uint8List _dropIslands(Uint8List fg, int w, int h, double minFrac) {
  final n = w * h;
  final lab = Int32List(n), q = Int32List(n);
  final sizes = <int>[0];
  var count = 0;
  for (var s = 0; s < n; s++) {
    if (fg[s] == 0 || lab[s] != 0) continue;
    count++;
    var qh = 0, qt = 0;
    q[qt++] = s;
    lab[s] = count;
    var c = 0;
    while (qh < qt) {
      final i = q[qh++];
      c++;
      final x = i % w, y = i ~/ w;
      void tryAdd(int j) {
        if (fg[j] == 1 && lab[j] == 0) {
          lab[j] = count;
          q[qt++] = j;
        }
      }

      if (x > 0) tryAdd(i - 1);
      if (x < w - 1) tryAdd(i + 1);
      if (y > 0) tryAdd(i - w);
      if (y < h - 1) tryAdd(i + w);
    }
    sizes.add(c);
  }
  var big = 0;
  for (final s in sizes) {
    if (s > big) big = s;
  }
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (lab[i] != 0 && sizes[lab[i]] >= big * minFrac) out[i] = 1;
  }
  return out;
}
