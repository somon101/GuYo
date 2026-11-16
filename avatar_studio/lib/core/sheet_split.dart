// Поиск отдельных предметов на листе: рамки, по которым деталь открывается в «Вырезалке».
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'bg_removal.dart';

class Box {
  final int x0, y0, x1, y1; // x1, y1 не включены
  const Box(this.x0, this.y0, this.x1, this.y1);
  int get w => x1 - x0;
  int get h => y1 - y0;
  @override
  String toString() => 'Box($x0,$y0,$x1,$y1)';
}

/// Лист в виде RGBA-байтов.
class Sheet {
  final Uint8List rgba;
  final int w, h;
  Sheet(this.rgba, this.w, this.h);
}

/// Читает картинку, поворачивает по EXIF и уменьшает до [maxSide].
Sheet decodeSheet(({Uint8List bytes, int maxSide}) a) {
  var im = img.decodeImage(a.bytes);
  if (im == null) throw const FormatException('Не удалось открыть картинку');
  im = img.bakeOrientation(im);
  final big = math.max(im.width, im.height);
  if (big > a.maxSide) {
    final k = a.maxSide / big;
    im = img.copyResize(im, width: (im.width * k).round(), height: (im.height * k).round(), interpolation: img.Interpolation.average);
  }
  final rgba = im.convert(numChannels: 4, format: img.Format.uint8);
  return Sheet(Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba)), rgba.width, rgba.height);
}

/// Вырезает прямоугольник листа (с запасом [pad] вокруг), при необходимости уменьшая до [maxSide].
Sheet cropSheet(({Sheet sheet, Box box, int pad, int maxSide}) a) {
  final s = a.sheet;
  final x0 = math.max(0, a.box.x0 - a.pad), y0 = math.max(0, a.box.y0 - a.pad);
  final x1 = math.min(s.w, a.box.x1 + a.pad), y1 = math.min(s.h, a.box.y1 + a.pad);
  final cw = x1 - x0, ch = y1 - y0;
  final out = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    final si = ((y0 + y) * s.w + x0) * 4;
    out.setRange(y * cw * 4, (y + 1) * cw * 4, s.rgba, si);
  }
  final big = math.max(cw, ch);
  if (big <= a.maxSide) return Sheet(out, cw, ch);
  final k = a.maxSide / big;
  final im = img.Image.fromBytes(width: cw, height: ch, bytes: out.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  final r = img.copyResize(im, width: (cw * k).round(), height: (ch * k).round(), interpolation: img.Interpolation.average);
  return Sheet(Uint8List.fromList(r.getBytes(order: img.ChannelOrder.rgba)), r.width, r.height);
}

/// Запасной способ: ровная сетка [cols]×[rows].
List<Box> gridBoxes(int w, int h, int cols, int rows) {
  final out = <Box>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      out.add(Box((c * w / cols).round(), (r * h / rows).round(), ((c + 1) * w / cols).round(), ((r + 1) * h / rows).round()));
    }
  }
  return out;
}

/// Находит предметы: убирает фон на уменьшенной копии, склеивает близкие куски (завязки, рукава)
/// и возвращает рамки в порядке чтения (по строкам, слева направо).
List<Box> findItems(({Sheet sheet, double gap, double minArea}) a) {
  final s = a.sheet;
  final k = math.max(1.0, math.max(s.w, s.h) / 640);
  final sw = math.max(1, (s.w / k).round()), sh = math.max(1, (s.h / k).round());
  final small = Uint8List(sw * sh * 4);
  for (var y = 0; y < sh; y++) {
    final sy = math.min(s.h - 1, (y * k).floor());
    for (var x = 0; x < sw; x++) {
      final sx = math.min(s.w - 1, (x * k).floor());
      final si = (sy * s.w + sx) * 4, di = (y * sw + x) * 4;
      small[di] = s.rgba[si];
      small[di + 1] = s.rgba[si + 1];
      small[di + 2] = s.rgba[si + 2];
      small[di + 3] = s.rgba[si + 3];
    }
  }
  removeBackground(small, sw, sh);
  final fg = Uint8List(sw * sh);
  for (var i = 0; i < fg.length; i++) {
    fg[i] = small[i * 4 + 3] > 128 ? 1 : 0;
  }
  final r = math.max(1, (a.gap * math.max(sw, sh)).round()); // раздувание небольшое, чтобы соседние детали не слипались
  final dil = _dilate(fg, sw, sh, r);
  final label = Int32List(sw * sh);
  final boxes = <List<int>>[]; // x0,y0,x1,y1 по настоящим (не раздутым) пикселям, площадь
  final stack = <int>[];
  var next = 0;
  for (var start = 0; start < dil.length; start++) {
    if (dil[start] == 0 || label[start] != 0) continue;
    next++;
    var bx0 = sw, by0 = sh, bx1 = -1, by1 = -1, area = 0;
    label[start] = next;
    stack.add(start);
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % sw, y = i ~/ sw;
      if (fg[i] == 1) {
        area++;
        if (x < bx0) bx0 = x;
        if (x > bx1) bx1 = x;
        if (y < by0) by0 = y;
        if (y > by1) by1 = y;
      }
      if (x > 0 && dil[i - 1] == 1 && label[i - 1] == 0) {
        label[i - 1] = next;
        stack.add(i - 1);
      }
      if (x < sw - 1 && dil[i + 1] == 1 && label[i + 1] == 0) {
        label[i + 1] = next;
        stack.add(i + 1);
      }
      if (y > 0 && dil[i - sw] == 1 && label[i - sw] == 0) {
        label[i - sw] = next;
        stack.add(i - sw);
      }
      if (y < sh - 1 && dil[i + sw] == 1 && label[i + sw] == 0) {
        label[i + sw] = next;
        stack.add(i + sw);
      }
    }
    if (bx1 >= 0 && area >= a.minArea * sw * sh) boxes.add([bx0, by0, bx1 + 1, by1 + 1, area]);
  }
  // бывает, что фон не распознан и «предметом» стал весь лист: такую рамку не берём
  boxes.removeWhere((b) => (b[2] - b[0]) * (b[3] - b[1]) > 0.6 * sw * sh);
  if (boxes.isEmpty) return [];
  // мелкие обрывки (пряди, завязки) присоединяем к ближайшей крупной детали или отбрасываем
  final biggest = boxes.map((b) => b[4]).reduce(math.max);
  final big = boxes.where((b) => b[4] >= biggest * 0.12).toList();
  final tiny = boxes.where((b) => b[4] < biggest * 0.12).toList();
  final near = math.max(sw, sh) * 0.06;
  for (final t in tiny) {
    List<int>? best;
    var bd = double.infinity;
    for (final b in big) {
      final dx = math.max(0, math.max(b[0] - t[2], t[0] - b[2])), dy = math.max(0, math.max(b[1] - t[3], t[1] - b[3]));
      final d = math.sqrt((dx * dx + dy * dy).toDouble());
      if (d < bd) {
        bd = d;
        best = b;
      }
    }
    if (best != null && bd <= near) {
      best[0] = math.min(best[0], t[0]);
      best[1] = math.min(best[1], t[1]);
      best[2] = math.max(best[2], t[2]);
      best[3] = math.max(best[3], t[3]);
    }
  }
  boxes
    ..clear()
    ..addAll(big);
  // порядок чтения: строки по центру по вертикали
  boxes.sort((p, q) => (p[1] + p[3]).compareTo(q[1] + q[3]));
  final heights = boxes.map((b) => b[3] - b[1]).toList()..sort();
  final rowGap = heights[heights.length ~/ 2] * 0.5;
  final rows = <List<List<int>>>[];
  double rowCy = -1e9;
  for (final b in boxes) {
    final cy = (b[1] + b[3]) / 2;
    if (rows.isEmpty || cy - rowCy > rowGap) {
      rows.add([b]);
      rowCy = cy;
    } else {
      rows.last.add(b);
    }
  }
  final out = <Box>[];
  final padX = (s.w * 0.004).round();
  for (final row in rows) {
    row.sort((p, q) => p[0].compareTo(q[0]));
    for (final b in row) {
      out.add(Box(
        math.max(0, (b[0] * k).floor() - padX),
        math.max(0, (b[1] * k).floor() - padX),
        math.min(s.w, (b[2] * k).ceil() + padX),
        math.min(s.h, (b[3] * k).ceil() + padX),
      ));
    }
  }
  return out;
}

Uint8List _dilate(Uint8List m, int w, int h, int r) {
  final tmp = Uint8List(w * h), out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    var cnt = 0;
    for (var x = 0; x < math.min(w, r); x++) {
      cnt += m[y * w + x];
    }
    for (var x = 0; x < w; x++) {
      if (x + r < w) cnt += m[y * w + x + r];
      if (x - r - 1 >= 0) cnt -= m[y * w + x - r - 1];
      tmp[y * w + x] = cnt > 0 ? 1 : 0;
    }
  }
  for (var x = 0; x < w; x++) {
    var cnt = 0;
    for (var y = 0; y < math.min(h, r); y++) {
      cnt += tmp[y * w + x];
    }
    for (var y = 0; y < h; y++) {
      if (y + r < h) cnt += tmp[(y + r) * w + x];
      if (y - r - 1 >= 0) cnt -= tmp[(y - r - 1) * w + x];
      out[y * w + x] = cnt > 0 ? 1 : 0;
    }
  }
  return out;
}
