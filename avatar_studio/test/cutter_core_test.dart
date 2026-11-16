import 'dart:typed_data';

import 'package:avatar_studio/core/mask_edit.dart';
import 'package:avatar_studio/core/sheet_split.dart';
import 'package:flutter_test/flutter_test.dart';

/// Картинка w×h: цвет bg, поверх прямоугольники (x0,y0,x1,y1,[r,g,b]).
Uint8List sheet(int w, int h, List<int> bg, List<List<int>> rects) {
  final d = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var c = bg;
      for (final r in rects) {
        if (x >= r[0] && x < r[2] && y >= r[1] && y < r[3]) c = r.sublist(4, 7);
      }
      final i = (y * w + x) * 4;
      d[i] = c[0];
      d[i + 1] = c[1];
      d[i + 2] = c[2];
      d[i + 3] = 255;
    }
  }
  return d;
}

void main() {
  test('кисть стирает и возвращает, мазок отменяется одним шагом', () {
    final ed = MaskEditor(40, 40, sheet(40, 40, [200, 50, 50], []));
    expect(ed.alpha[20 * 40 + 20], 255);
    ed.beginStroke();
    ed.line(5, 20, 35, 20, 6, 0, erase: true);
    ed.endStroke();
    expect(ed.alpha[20 * 40 + 20], 0);
    expect(ed.alpha[2 * 40 + 20], 255, reason: 'далеко от мазка не тронуто');
    ed.beginStroke();
    ed.stamp(20, 20, 4, 0, erase: false);
    ed.endStroke();
    expect(ed.alpha[20 * 40 + 20], 255, reason: '«вернуть» берёт пиксели из оригинала');
    expect(ed.alpha[20 * 40 + 30], 0);
    ed.undo();
    expect(ed.alpha[20 * 40 + 20], 0);
    ed.undo();
    expect(ed.alpha[20 * 40 + 20], 255);
    expect(ed.canUndo, isFalse);
    ed.redo();
    expect(ed.alpha[20 * 40 + 20], 0);
  });

  test('мягкий край даёт плавную прозрачность, отмена мазка возвращает как было', () {
    final ed = MaskEditor(60, 60, sheet(60, 60, [10, 10, 10], []));
    ed.beginStroke();
    ed.stamp(30, 30, 20, 1, erase: true);
    final mid = ed.alpha[30 * 60 + 45]; // на краю отпечатка
    expect(ed.alpha[30 * 60 + 30], lessThan(5));
    expect(mid, inInclusiveRange(1, 254));
    ed.cancelStroke();
    expect(ed.alpha.every((v) => v == 255), isTrue);
    expect(ed.canUndo, isFalse, reason: 'отменённый мазок не попадает в историю');
  });

  test('убрать цвет: допуск и мягкий край', () {
    final px = sheet(50, 20, [255, 0, 0], [
      [25, 0, 50, 20, 0, 0, 255],
    ]);
    final ed = MaskEditor(50, 20, px);
    expect(ed.removeColor(255, 0, 0, 10), isTrue);
    expect(ed.alpha[5 * 50 + 5], 0, reason: 'красный ушёл');
    expect(ed.alpha[5 * 50 + 40], 255, reason: 'синий остался');
    ed.undo();
    expect(ed.alpha[5 * 50 + 5], 255);
  });

  test('сгладить край подтягивает ступеньку внутрь', () {
    final ed = MaskEditor(30, 30, sheet(30, 30, [90, 90, 90], []));
    ed.beginStroke();
    ed.stamp(15, 15, 30, 0, erase: true);
    ed.endStroke();
    ed.beginStroke();
    ed.stamp(15, 15, 6, 0, erase: false);
    ed.endStroke();
    final before = ed.alpha.where((v) => v > 0).length;
    ed.smoothEdge();
    expect(ed.alpha.where((v) => v > 128).length, lessThan(before));
  });

  test('результат обрезается по видимому', () {
    final ed = MaskEditor(30, 30, sheet(30, 30, [90, 90, 90], []));
    ed.beginStroke();
    ed.stamp(15, 15, 30, 0, erase: true);
    ed.endStroke();
    expect(ed.result(), isNull, reason: 'всё стёрто');
    ed.beginStroke();
    ed.stamp(15, 15, 5, 0, erase: false);
    ed.endStroke();
    final r = ed.result(pad: 0)!;
    expect(r.w, inInclusiveRange(8, 11));
    expect(r.rgba[3], isNonNegative);
  });

  test('поиск предметов: четыре детали на белом листе в порядке чтения', () {
    const w = 600, h = 400;
    final px = sheet(w, h, [255, 255, 255], [
      [40, 30, 180, 170, 30, 30, 160],
      [260, 40, 400, 180, 180, 30, 30],
      [60, 230, 200, 370, 20, 120, 40],
      [300, 220, 460, 380, 120, 60, 10],
    ]);
    final boxes = findItems((sheet: Sheet(px, w, h), gap: 0.002, minArea: 0.0005));
    expect(boxes.length, 4);
    expect(boxes[0].x0, lessThan(60));
    expect(boxes[1].x0, greaterThan(200));
    expect(boxes[2].y0, greaterThan(200));
    expect(boxes[3].x0, greaterThan(boxes[2].x0));
  });

  test('сетка и вырезание куска листа', () {
    expect(gridBoxes(400, 300, 4, 3).length, 12);
    final px = sheet(100, 80, [255, 255, 255], []);
    final c = cropSheet((sheet: Sheet(px, 100, 80), box: const Box(10, 10, 50, 40), pad: 5, maxSide: 1600));
    expect(c.w, 50);
    expect(c.h, 40);
  });

  test('заливка по шагу убирает градиент и не заходит в тёмную деталь', () {
    const w = 80, h = 60;
    final d = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final inside = x >= 25 && x < 55 && y >= 15 && y < 45;
        // фон: голубой градиент слева направо; деталь: почти чёрная
        d[i] = inside ? 15 : 30 + x ~/ 2;
        d[i + 1] = inside ? 15 : 120 + x ~/ 2;
        d[i + 2] = inside ? 20 : 200 + x ~/ 4;
        d[i + 3] = 255;
      }
    }
    final ed = MaskEditor(w, h, d);
    expect(ed.removeColor(30, 120, 200, 10), isTrue);
    expect(ed.alpha[5 * w + 75], 255, reason: 'далёкий оттенок градиента этим способом не убирается');
    ed.undo();
    expect(ed.floodRemove(2, 2, 10), isTrue);
    expect(ed.alpha[5 * w + 75], 0, reason: 'правый край градиента ушёл');
    expect(ed.alpha[2 * w + 2], 0);
    expect(ed.alpha[30 * w + 40], 255, reason: 'деталь цела');
    ed.undo();
    expect(ed.alpha[5 * w + 75], 255);
  });
}
