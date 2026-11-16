// Делит лист с несколькими деталями на отдельные картинки с прозрачным фоном.
// Использование: dart run tool/split_sheet.dart <лист.jpg> <папка> <префикс> [--mode black|edges] [--cols N --rows M]
//   black: лист на чёрном фоне, детали находятся как отдельные пятна (по умолчанию);
//   edges: лист на «дымном» фоне, детали делятся по сетке и вырезаются по резким краям.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avatar_studio/core/bg_removal.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('dart run tool/split_sheet.dart <лист> <папка> <префикс> [--mode black|edges] [--cols N --rows M] [--thr 22] [--gap 14]');
    exit(64);
  }
  String opt(String k, String d) {
    final i = args.indexOf('--$k');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : d;
  }

  final src = img.decodeImage(File(args[0]).readAsBytesSync())!;
  final out = Directory(args[1])..createSync(recursive: true);
  final prefix = args[2];
  final mode = opt('mode', 'black');
  final rgba = src.convert(numChannels: 4, format: img.Format.uint8);
  final w = rgba.width, h = rgba.height;
  final data = Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba));

  List<List<int>> boxes; // x0, y0, x1, y1
  if (mode == 'grid') {
    // чёрный фон, детали стоят по сетке, но могут заходить друг на друга: каждый пиксель отдаём ближайшему центру ячейки
    final cols = int.parse(opt('cols', '4')), rows = int.parse(opt('rows', '3'));
    final cw = w / cols, ch = h / rows;
    var n = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x0 = math.max(0, ((c - 0.4) * cw).floor()), x1 = math.min(w, ((c + 1.4) * cw).ceil());
        final y0 = math.max(0, ((r - 0.4) * ch).floor()), y1 = math.min(h, ((r + 1.4) * ch).ceil());
        final bw = x1 - x0, bh = y1 - y0;
        final crop = Uint8List(bw * bh * 4);
        for (var y = 0; y < bh; y++) {
          for (var x = 0; x < bw; x++) {
            final gx = x0 + x, gy = y0 + y;
            final cc = (gx / cw).floor().clamp(0, cols - 1), rr = (gy / ch).floor().clamp(0, rows - 1);
            // ближайший центр по нормированному расстоянию
            var best = 1e9, bc = 0, br = 0;
            for (var rr2 = math.max(0, rr - 1); rr2 <= math.min(rows - 1, rr + 1); rr2++) {
              for (var cc2 = math.max(0, cc - 1); cc2 <= math.min(cols - 1, cc + 1); cc2++) {
                final dx = (gx - (cc2 + 0.5) * cw) / cw, dy = (gy - (rr2 + 0.5) * ch) / ch;
                final d2 = dx * dx + dy * dy;
                if (d2 < best) {
                  best = d2;
                  bc = cc2;
                  br = rr2;
                }
              }
            }
            final si = (gy * w + gx) * 4, di = (y * bw + x) * 4;
            if (bc == c && br == r) {
              crop[di] = data[si];
              crop[di + 1] = data[si + 1];
              crop[di + 2] = data[si + 2];
            }
            crop[di + 3] = 255;
          }
        }
        removeBackground(crop, bw, bh, tol: 16, minIsland: 0.06);
        final t = _trim(crop, bw, bh);
        if (t == null) continue;
        n++;
        final im = img.Image.fromBytes(width: t.$2, height: t.$3, bytes: t.$1.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
        File('${out.path}/${prefix}_${n.toString().padLeft(2, '0')}.png').writeAsBytesSync(img.encodePng(im, level: 3));
      }
    }
    stdout.writeln('$prefix: $n деталей');
    return;
  }
  if (mode == 'edges') {
    final cols = int.parse(opt('cols', '4')), rows = int.parse(opt('rows', '3'));
    // ячейка шире на 20%: деталь может чуть выходить за свою ячейку; соседние куски отсекает «самое большое пятно»
    final mx = (w / cols * 0.2).round(), my = (h / rows * 0.2).round();
    boxes = [for (var r = 0; r < rows; r++) for (var c = 0; c < cols; c++) [math.max(0, c * w ~/ cols - mx), math.max(0, r * h ~/ rows - my), math.min(w, (c + 1) * w ~/ cols + mx), math.min(h, (r + 1) * h ~/ rows + my)]];
  } else {
    boxes = _components(data, w, h, int.parse(opt('thr', '22')), int.parse(opt('gap', '14')));
  }
  var n = 0;
  for (final b in boxes) {
    final pad = mode == 'edges' ? 0 : 14;
    final x0 = math.max(0, b[0] - pad), y0 = math.max(0, b[1] - pad), x1 = math.min(w, b[2] + pad), y1 = math.min(h, b[3] + pad);
    final cw = x1 - x0, ch = y1 - y0;
    final crop = Uint8List(cw * ch * 4);
    for (var y = 0; y < ch; y++) {
      crop.setRange(y * cw * 4, (y + 1) * cw * 4, data, ((y0 + y) * w + x0) * 4);
    }
    if (mode == 'edges') {
      cutByEdges(crop, cw, ch);
    } else {
      removeBackground(crop, cw, ch, tol: 16);
      final holes = int.parse(opt('holes', '0'));
      if (holes > 0) _clearDarkPockets(crop, cw, ch, holes);
    }
    final trimmed = _trim(crop, cw, ch);
    if (trimmed == null) continue;
    // парные детали (левая и правая рядом) делим по пустому столбцу между ними
    var pieces = args.contains('--pairs') ? _splitColumns(trimmed.$1, trimmed.$2, trimmed.$3, int.parse(opt('colgap', '4'))) : [trimmed];
    if (args.contains('--largest') && pieces.length > 1) {
      // кусок соседней детали, зашедший в ячейку, отбрасываем: оставляем самую большую часть
      pieces = [pieces.reduce((p, q) => p.$2 * p.$3 >= q.$2 * q.$3 ? p : q)];
    }
    for (final t in pieces) {
      n++;
      final name = '${prefix}_${n.toString().padLeft(2, '0')}.png';
      final im = img.Image.fromBytes(width: t.$2, height: t.$3, bytes: t.$1.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
      File('${out.path}/$name').writeAsBytesSync(img.encodePng(im, level: 3));
    }
  }
  stdout.writeln('$prefix: $n деталей');
}

/// Пятна ярче порога, соединённые в группы (рядом стоящие куски одной детали), по строкам слева направо.
List<List<int>> _components(Uint8List d, int w, int h, int thr, int gap) {
  const k = 4;
  final sw = (w + k - 1) ~/ k, sh = (h + k - 1) ~/ k;
  final m = Uint8List(sw * sh);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      if (math.max(d[i], math.max(d[i + 1], d[i + 2])) > thr) m[(y ~/ k) * sw + x ~/ k] = 1;
    }
  }
  final r = (gap / k).ceil();
  final dil = Uint8List(sw * sh);
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      if (m[y * sw + x] == 0) continue;
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          final yy = y + dy, xx = x + dx;
          if (yy >= 0 && yy < sh && xx >= 0 && xx < sw) dil[yy * sw + xx] = 1;
        }
      }
    }
  }
  final lab = Int32List(sw * sh);
  final boxes = <List<int>>[];
  final q = <int>[];
  for (var s = 0; s < sw * sh; s++) {
    if (dil[s] == 0 || lab[s] != 0) continue;
    final id = boxes.length + 1;
    var x0 = sw, y0 = sh, x1 = 0, y1 = 0, cnt = 0;
    q
      ..clear()
      ..add(s);
    lab[s] = id;
    for (var qi = 0; qi < q.length; qi++) {
      final i = q[qi], x = i % sw, y = i ~/ sw;
      if (m[i] == 1) {
        x0 = math.min(x0, x);
        y0 = math.min(y0, y);
        x1 = math.max(x1, x);
        y1 = math.max(y1, y);
        cnt++;
      }
      for (final j in [if (x > 0) i - 1, if (x < sw - 1) i + 1, if (y > 0) i - sw, if (y < sh - 1) i + sw]) {
        if (dil[j] == 1 && lab[j] == 0) {
          lab[j] = id;
          q.add(j);
        }
      }
    }
    if (cnt * k * k < (w * h) * 0.002) continue; // пыль
    boxes.add([x0 * k, y0 * k, (x1 + 1) * k, (y1 + 1) * k]);
  }
  // строки: по центру по вертикали, внутри строки слева направо
  boxes.sort((a, b) => (a[1] + a[3]).compareTo(b[1] + b[3]));
  final rows = <List<List<int>>>[];
  for (final b in boxes) {
    final cy = (b[1] + b[3]) / 2;
    if (rows.isNotEmpty) {
      final last = rows.last;
      final lcy = last.map((e) => (e[1] + e[3]) / 2).reduce((a, c) => a + c) / last.length;
      final lh = last.map((e) => e[3] - e[1]).reduce(math.max);
      if ((cy - lcy).abs() < lh * 0.45) {
        last.add(b);
        continue;
      }
    }
    rows.add([b]);
  }
  return [for (final r in rows) ...(r..sort((a, b) => a[0].compareTo(b[0])))];
}

/// Тёмные «карманы» внутри детали (между пальцами, внутри сердечка): остатки чёрного фона, не связанные с краем.
void _clearDarkPockets(Uint8List d, int w, int h, int thr) {
  final n = w * h;
  final dark = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (d[i * 4 + 3] > 0 && math.max(d[i * 4], math.max(d[i * 4 + 1], d[i * 4 + 2])) <= thr) dark[i] = 1;
  }
  final seen = Uint8List(n);
  for (var s = 0; s < n; s++) {
    if (dark[s] == 0 || seen[s] == 1) continue;
    final comp = <int>[s];
    seen[s] = 1;
    for (var qi = 0; qi < comp.length; qi++) {
      final i = comp[qi], x = i % w, y = i ~/ w;
      for (final j in [if (x > 0) i - 1, if (x < w - 1) i + 1, if (y > 0) i - w, if (y < h - 1) i + w]) {
        if (dark[j] == 1 && seen[j] == 0) {
          seen[j] = 1;
          comp.add(j);
        }
      }
    }
    if (comp.length < 40) continue;
    for (final i in comp) {
      d[i * 4 + 3] = 0;
    }
  }
  // кайма у кармана: соседние тёмно-коричневые пиксели
  for (var pass = 0; pass < 3; pass++) {
    final del = <int>[];
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (d[i * 4 + 3] == 0) continue;
        if (d[(i - 1) * 4 + 3] == 0 || d[(i + 1) * 4 + 3] == 0 || d[(i - w) * 4 + 3] == 0 || d[(i + w) * 4 + 3] == 0) {
          if (math.max(d[i * 4], math.max(d[i * 4 + 1], d[i * 4 + 2])) < thr * 4) del.add(i);
        }
      }
    }
    for (final i in del) {
      d[i * 4 + 3] = 0;
    }
  }
}

/// Вырезание по резким краям: фон «дымный» и размытый, деталь с чёткой границей.
void cutByEdges(Uint8List d, int w, int h) {
  final n = w * h;
  final lum = Float32List(n);
  for (var i = 0; i < n; i++) {
    lum[i] = 0.3 * d[i * 4] + 0.59 * d[i * 4 + 1] + 0.11 * d[i * 4 + 2];
  }
  final edge = Uint8List(n);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final gx = -lum[i - w - 1] - 2 * lum[i - 1] - lum[i + w - 1] + lum[i - w + 1] + 2 * lum[i + 1] + lum[i + w + 1];
      final gy = -lum[i - w - 1] - 2 * lum[i - w] - lum[i - w + 1] + lum[i + w - 1] + 2 * lum[i + w] + lum[i + w + 1];
      if (math.sqrt(gx * gx + gy * gy) > 55) edge[i] = 1;
    }
  }
  // замыкаем щели в контуре
  const r = 2;
  final wall = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (edge[y * w + x] == 0) continue;
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          final yy = y + dy, xx = x + dx;
          if (yy >= 0 && yy < h && xx >= 0 && xx < w) wall[yy * w + xx] = 1;
        }
      }
    }
  }
  final bg = Uint8List(n);
  final q = <int>[];
  // фон дымный: серый (почти без цвета) и не яркий. Цветные и белые детали фоном не считаются даже при прорехе в контуре.
  bool greyish(int i) {
    final r = d[i * 4], g = d[i * 4 + 1], b = d[i * 4 + 2];
    final hi = math.max(r, math.max(g, b)), lo = math.min(r, math.min(g, b));
    return hi - lo <= 16 && lum[i] <= 215;
  }

  void push(int i) {
    if (wall[i] == 0 && bg[i] == 0 && greyish(i)) {
      bg[i] = 1;
      q.add(i);
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
  for (var qi = 0; qi < q.length; qi++) {
    final i = q[qi], x = i % w, y = i ~/ w;
    if (x > 0) push(i - 1);
    if (x < w - 1) push(i + 1);
    if (y > 0) push(i - w);
    if (y < h - 1) push(i + w);
  }
  // деталь = не фон; стенка толщиной r шире настоящего края, снимаем её обратно
  var fg = Uint8List(n);
  for (var i = 0; i < n; i++) {
    fg[i] = bg[i] == 1 ? 0 : 1;
  }
  // оставляем самое большое пятно
  final lab = Int32List(n);
  final sizes = <int>[0];
  var cnt = 0;
  for (var s = 0; s < n; s++) {
    if (fg[s] == 0 || lab[s] != 0) continue;
    cnt++;
    var c = 0;
    final qq = <int>[s];
    lab[s] = cnt;
    for (var qi = 0; qi < qq.length; qi++) {
      final i = qq[qi];
      c++;
      final x = i % w, y = i ~/ w;
      for (final j in [if (x > 0) i - 1, if (x < w - 1) i + 1, if (y > 0) i - w, if (y < h - 1) i + w]) {
        if (fg[j] == 1 && lab[j] == 0) {
          lab[j] = cnt;
          qq.add(j);
        }
      }
    }
    sizes.add(c);
  }
  var best = 1;
  for (var i = 1; i < sizes.length; i++) {
    if (sizes[i] > sizes[best]) best = i;
  }
  fg = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (lab[i] == best) fg[i] = 1;
  }
  // тонкие перемычки с соседней деталью обрезаем: сужаем, берём самое большое пятно, возвращаем ширину
  fg = _openKeepLargest(fg, w, h, 5);
  for (var p = 0; p < r; p++) {
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
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var s = 0, k = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final yy = y + dy, xx = x + dx;
          if (yy >= 0 && yy < h && xx >= 0 && xx < w) {
            s += fg[yy * w + xx];
            k++;
          }
        }
      }
      d[i * 4 + 3] = (255 * s / k).round();
    }
  }
}

/// Делит картинку по пустым столбцам (ширина промежутка не меньше colgap px, по умолчанию 4), каждую часть обрезает.
List<(Uint8List, int, int)> _splitColumns(Uint8List d, int w, int h, int minGap) {
  final filled = List<bool>.filled(w, false);
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      if (d[(y * w + x) * 4 + 3] > 40) {
        filled[x] = true;
        break;
      }
    }
  }
  final spans = <List<int>>[];
  var start = -1, gap = 0;
  for (var x = 0; x <= w; x++) {
    final f = x < w && filled[x];
    if (f) {
      if (start < 0) start = x;
      gap = 0;
    } else if (start >= 0) {
      gap++;
      if (gap >= minGap || x == w) {
        spans.add([start, x - gap]);
        start = -1;
      }
    }
  }
  final out = <(Uint8List, int, int)>[];
  for (final s in spans) {
    final cw = s[1] - s[0] + 1;
    if (cw < w * 0.12) continue; // обрывок
    final c = Uint8List(cw * h * 4);
    for (var y = 0; y < h; y++) {
      c.setRange(y * cw * 4, (y + 1) * cw * 4, d, (y * w + s[0]) * 4);
    }
    final t = _trim(c, cw, h);
    if (t != null) out.add(t);
  }
  return out.isEmpty ? [(d, w, h)] : out;
}

/// Сужает маску на k, оставляет самое большое пятно и возвращает его на k обратно (только в пределах исходной маски).
Uint8List _openKeepLargest(Uint8List fg, int w, int h, int k) {
  final n = w * h;
  var cur = fg;
  for (var p = 0; p < k; p++) {
    final nx = Uint8List(n);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (cur[i] == 0) continue;
        if ((x > 0 && cur[i - 1] == 0) || (x < w - 1 && cur[i + 1] == 0) || (y > 0 && cur[i - w] == 0) || (y < h - 1 && cur[i + w] == 0)) continue;
        nx[i] = 1;
      }
    }
    cur = nx;
  }
  final lab = Int32List(n);
  final sizes = <int>[0];
  var cnt = 0;
  for (var s = 0; s < n; s++) {
    if (cur[s] == 0 || lab[s] != 0) continue;
    cnt++;
    var c = 0;
    final qq = <int>[s];
    lab[s] = cnt;
    for (var qi = 0; qi < qq.length; qi++) {
      final i = qq[qi];
      c++;
      final x = i % w, y = i ~/ w;
      for (final j in [if (x > 0) i - 1, if (x < w - 1) i + 1, if (y > 0) i - w, if (y < h - 1) i + w]) {
        if (cur[j] == 1 && lab[j] == 0) {
          lab[j] = cnt;
          qq.add(j);
        }
      }
    }
    sizes.add(c);
  }
  if (cnt == 0) return fg;
  var best = 1;
  for (var i = 1; i < sizes.length; i++) {
    if (sizes[i] > sizes[best]) best = i;
  }
  cur = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (lab[i] == best) cur[i] = 1;
  }
  for (var p = 0; p < k; p++) {
    final nx = Uint8List.fromList(cur);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (cur[i] == 1 || fg[i] == 0) continue;
        if ((x > 0 && cur[i - 1] == 1) || (x < w - 1 && cur[i + 1] == 1) || (y > 0 && cur[i - w] == 1) || (y < h - 1 && cur[i + w] == 1)) nx[i] = 1;
      }
    }
    cur = nx;
  }
  return cur;
}

/// Обрезает по непрозрачной части. Возвращает (байты, ширина, высота) или null, если пусто.
(Uint8List, int, int)? _trim(Uint8List d, int w, int h) {
  var x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (d[(y * w + x) * 4 + 3] > 40) {
        x0 = math.min(x0, x);
        y0 = math.min(y0, y);
        x1 = math.max(x1, x);
        y1 = math.max(y1, y);
      }
    }
  }
  if (x1 < 0) return null;
  const p = 3;
  x0 = math.max(0, x0 - p);
  y0 = math.max(0, y0 - p);
  x1 = math.min(w - 1, x1 + p);
  y1 = math.min(h - 1, y1 + p);
  final nw = x1 - x0 + 1, nh = y1 - y0 + 1;
  final o = Uint8List(nw * nh * 4);
  for (var y = 0; y < nh; y++) {
    o.setRange(y * nw * 4, (y + 1) * nw * 4, d, ((y0 + y) * w + x0) * 4);
  }
  return (o, nw, nh);
}
