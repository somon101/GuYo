import 'dart:typed_data';
import 'dart:ui';

import 'package:avatar_studio/core/bg_removal.dart';
import 'package:avatar_studio/core/geometry.dart';
import 'package:avatar_studio/core/model.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Px = List<int>;

Uint8List img(int w, int h, Px Function(int, int) bg, Px? Function(int, int) fg) {
  final d = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = fg(x, y) ?? bg(x, y);
      final i = (y * w + x) * 4;
      d[i] = c[0];
      d[i + 1] = c[1];
      d[i + 2] = c[2];
      d[i + 3] = 255;
    }
  }
  return d;
}

Px? Function(int, int) disc(int cx, int cy, int r, Px col) => (x, y) => ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) ? col : null;
int alphaAt(Uint8List d, int w, int x, int y) => d[(y * w + x) * 4 + 3];

void main() {
  test('чёрный фон вырезается, тёмная деталь внутри остаётся', () {
    const w = 80, h = 80;
    final d = img(w, h, (x, y) => [0, 0, 0], (x, y) => disc(40, 40, 30, [230, 170, 140])(x, y) ?? ((x - 40).abs() < 6 && (y - 40).abs() < 6 ? [2, 2, 2] : null));
    expect(removeBackground(d, w, h), 'black');
    expect(alphaAt(d, w, 2, 2), 0);
    expect(alphaAt(d, w, 40, 40), 255, reason: 'тёмный глаз внутри не становится дырой');
    expect(alphaAt(d, w, 40, 20), 255);
  });

  test('тёмная кайма у светлого предмета снимается, тёмный предмет не съедается', () {
    const w = 90, h = 90;
    // светлый диск с тёмным ободком из смеси цвета и фона
    final d = img(w, h, (x, y) => [0, 0, 0], (x, y) {
      final r2 = (x - 45) * (x - 45) + (y - 45) * (y - 45);
      if (r2 <= 30 * 30) return [235, 190, 160];
      if (r2 <= 33 * 33) return [95, 75, 65];
      return null;
    });
    removeBackground(d, w, h);
    expect(alphaAt(d, w, 45, 45), 255);
    expect(alphaAt(d, w, 45, 45 - 31), lessThan(40), reason: 'ободок снят');
    expect(alphaAt(d, w, 45, 45 - 33), 0);
  });

  test('«шахматка» вырезается, мелкий мусор убирается', () {
    const w = 100, h = 100;
    Px chk(int x, int y) => (((x >> 3) + (y >> 3)) & 1) == 1 ? [255, 255, 255] : [221, 221, 221];
    final d = img(w, h, chk, disc(50, 50, 32, [200, 120, 90]));
    d[(5 * w + 5) * 4] = 120;
    d[(5 * w + 5) * 4 + 1] = 60;
    d[(5 * w + 5) * 4 + 2] = 40;
    expect(removeBackground(d, w, h), 'neutral');
    expect(alphaAt(d, w, 1, 1), 0);
    expect(alphaAt(d, w, 50, 50), 255);
    expect(alphaAt(d, w, 5, 5), 0, reason: 'одиночное пятно убрано');
  });

  test('картинка с готовой прозрачностью не трогается', () {
    const w = 20, h = 20;
    final d = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      d[i * 4] = 10;
      d[i * 4 + 3] = i == 210 ? 255 : 0;
    }
    expect(removeBackground(d, w, h), 'alpha');
    expect(d[210 * 4 + 3], 255);
  });

  test('прямоугольник детали зависит от точки привязки', () {
    expect(rectOf(200, 100, Geo(x: 100, y: 100, w: 200, pivot: 'center')), const Rect.fromLTWH(0, 50, 200, 100));
    expect(rectOf(200, 100, Geo(x: 100, y: 100, w: 200, pivot: 'top')), const Rect.fromLTWH(0, 100, 200, 100));
    // ширина задаётся в пикселях холста, высота по пропорциям картинки
    expect(rectOf(200, 100, Geo(x: 100, y: 100, w: 400, pivot: 'bottom')), const Rect.fromLTWH(-100, -100, 400, 200));
    expect(rectOf(null, null, Geo(x: 0, y: 0)), isNull);
  });

  test('поворот: описанный прямоугольник вокруг точки привязки, JSON хранит угол', () {
    const r = Rect.fromLTWH(0, 0, 200, 100);
    expect(rotatedBounds(r, 100, 50, 0), r);
    final b = rotatedBounds(r, 100, 50, 90);
    expect(b.width, closeTo(100, 1e-6));
    expect(b.height, closeTo(200, 1e-6));
    expect(b.center.dx, closeTo(100, 1e-6));
    final g = Geo.fromJson(Geo(x: 1, y: 2, r: 12.5).toJson());
    expect(g.r, 12.5);
    expect(Geo.fromJson({'x': 1, 'y': 2}).r, 0, reason: 'в старых файлах угла нет');
  });

  test('стандартная ширина слота: доля ширины холста, одинаково для любого размера картинки', () {
    expect(baseSlot('face')!.width, closeTo(canvasW * 0.56, 1e-6));
    final g = Geo.fromBase(baseSlot('face')!);
    expect(rectOf(2000, 1000, g)!.width, closeTo(canvasW * 0.56, 1e-6));
    expect(rectOf(300, 300, g)!.width, closeTo(canvasW * 0.56, 1e-6));
  });

  test('кадр «Голова» охватывает лицо и волосы, «Весь» всё', () {
    final rects = <String, Rect?>{
      'face': const Rect.fromLTWH(300, 300, 600, 600),
      'hair': const Rect.fromLTWH(280, 150, 640, 500),
      'cloth': const Rect.fromLTWH(100, 800, 1000, 800),
      'neck': null,
    };
    final hd = framePreset('head', rects), all = framePreset('full', rects), bust = framePreset('bust', rects);
    expect(hd.size, inInclusiveRange(640, 900));
    expect(hd.y, inInclusiveRange(150, 900));
    expect(all.size, greaterThanOrEqualTo(1450));
    expect(bust.size, greaterThan(hd.size));
    expect(bust.size, lessThan(all.size));
  });

  test('проект: проверка формата, круговой JSON и починка порядка слотов', () {
    expect(() => ProjectState.migrate({'format': 'x'}), throwsFormatException);
    final st = ProjectState.fresh()..order = ['face'];
    st.sets.first.parts['face'] = [Part(id: 'p1', name: 'Лицо', w: 100, h: 100, blobId: 'b1')];
    st.sets.first.pick['face'] = 'p1';
    final m = ProjectState.migrate(st.toJson());
    expect(m.order.length, m.slots.length);
    expect(m.sets.first.parts['face']!.first.blobId, 'b1');
    expect(m.sets.first.pick['face'], 'p1');
    expect(m.geo['hair']!.pivot, 'center');
  });

  test('проект: у детали свой пол и своё положение, старые файлы читаются', () {
    final st = ProjectState.fresh();
    st.sets.first.parts['hair'] = [Part(id: 'h1', name: 'Косы', gender: 'female', w: 100, h: 100, blobId: 'b', geo: Geo(x: 10, y: 20, w: 300))];
    final m = ProjectState.migrate(st.toJson());
    final p = m.sets.first.parts['hair']!.first;
    expect(p.gender, 'female');
    expect(p.geo!.w, 300);
    expect(p.fits('female'), isTrue);
    expect(p.fits('male'), isFalse);
    expect(Part(id: 'x', name: 'x').fits('male'), isTrue, reason: 'по умолчанию «оба»');
    // старый формат: одно положение на всех, масштаб вместо ширины
    final old = {
      'format': projectFormat,
      'geo': {'face': {'x': 500, 'y': 400, 's': 0.8, 'pivot': 'center', 'vis': 1}},
      'sets': [{'id': 's1', 'name': 'Старый', 'parts': {}, 'pick': {}}],
    };
    final o = ProjectState.migrate(old);
    expect(o.geos['male']!['face']!.x, 500);
    expect(o.geos['female']!['face']!.x, 500);
    expect(o.geos['male']!['face']!.w, closeTo(canvasW * 0.56, 1e-6));
  });
}
