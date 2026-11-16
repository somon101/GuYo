const test = require('node:test');
const assert = require('node:assert');
const AS = require('../www/core.js');

function img(w, h, bgFn, fgFn) {
  const d = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const c = fgFn(x, y) || bgFn(x, y); const i = (y * w + x) * 4;
    d[i] = c[0]; d[i + 1] = c[1]; d[i + 2] = c[2]; d[i + 3] = 255;
  }
  return d;
}
const disc = (cx, cy, r, col) => (x, y) => ((x - cx) ** 2 + (y - cy) ** 2 <= r * r ? col : null);
const alphaAt = (d, w, x, y) => d[(y * w + x) * 4 + 3];

test('чёрный фон вырезается, тёмная деталь внутри остаётся', () => {
  const w = 80, h = 80;
  const d = img(w, h, () => [0, 0, 0], (x, y) => disc(40, 40, 30, [230, 170, 140])(x, y) || (Math.abs(x - 40) < 6 && Math.abs(y - 40) < 6 ? [2, 2, 2] : null));
  const r = AS.removeBackground(d, w, h);
  assert.equal(r.mode, 'black');
  assert.equal(alphaAt(d, w, 2, 2), 0);
  assert.equal(alphaAt(d, w, 40, 40), 255, 'тёмный глаз внутри не должен стать дырой');
  assert.equal(alphaAt(d, w, 40, 20), 255);
});

test('«шахматка» вырезается, мелкий мусор убирается', () => {
  const w = 100, h = 100;
  const chk = (x, y) => (((x >> 3) + (y >> 3)) & 1 ? [255, 255, 255] : [221, 221, 221]);
  const d = img(w, h, chk, disc(50, 50, 32, [200, 120, 90]));
  d[(5 * w + 5) * 4] = 120; d[(5 * w + 5) * 4 + 1] = 60; d[(5 * w + 5) * 4 + 2] = 40; // пятнышко
  const r = AS.removeBackground(d, w, h);
  assert.equal(r.mode, 'neutral');
  assert.equal(alphaAt(d, w, 1, 1), 0);
  assert.equal(alphaAt(d, w, 50, 50), 255);
  assert.equal(alphaAt(d, w, 5, 5), 0, 'одиночное пятно убрано');
});

test('картинка с готовой прозрачностью не трогается', () => {
  const w = 20, h = 20, d = new Uint8ClampedArray(w * h * 4);
  for (let i = 0; i < w * h; i++) { d[i * 4] = 10; d[i * 4 + 3] = i === 210 ? 255 : 0; }
  assert.equal(AS.removeBackground(d, w, h).mode, 'alpha');
  assert.equal(d[210 * 4 + 3], 255);
});

test('прямоугольник детали зависит от точки привязки', () => {
  const p = { w: 200, h: 100 };
  assert.deepEqual(AS.rectOf(p, { x: 100, y: 100, s: 1, pivot: 'center' }), { x: 0, y: 50, w: 200, h: 100 });
  assert.deepEqual(AS.rectOf(p, { x: 100, y: 100, s: 1, pivot: 'top' }), { x: 0, y: 100, w: 200, h: 100 });
  assert.deepEqual(AS.rectOf(p, { x: 100, y: 100, s: 2, pivot: 'bottom' }), { x: -100, y: -100, w: 400, h: 200 });
  assert.equal(AS.rectOf({ kind: 'solid' }, { x: 0, y: 0, s: 1, pivot: 'center' }), null);
});

test('первая деталь вписывается по доле ширины холста', () => {
  const s = AS.fitScale({ w: 2000 }, 'face');
  assert.ok(Math.abs(2000 * s - AS.CANVAS.w * 0.56) < 1e-6);
});

test('кадр «Голова» охватывает лицо и волосы, «Весь» всё', () => {
  const rects = { face: { x: 300, y: 300, w: 600, h: 600 }, hair: { x: 280, y: 150, w: 640, h: 500 }, cloth: { x: 100, y: 800, w: 1000, h: 800 }, neck: null };
  const hd = AS.framePreset('head', rects), all = AS.framePreset('full', rects), bust = AS.framePreset('bust', rects);
  assert.ok(hd.size >= 640 && hd.size < 900);
  assert.ok(hd.y > 150 && hd.y < 900);
  assert.ok(all.size >= 1450);
  assert.ok(bust.size > hd.size && bust.size < all.size);
});

test('проект: проверка формата и починка порядка слотов', () => {
  assert.throws(() => AS.migrate({ format: 'x' }));
  const st = AS.newState(); st.order = ['face'];
  const m = AS.migrate(JSON.parse(JSON.stringify(st)));
  assert.equal(m.order.length, m.slots.length);
  assert.ok(m.sets.length >= 1 && m.sets.some(s => s.id === m.cur));
});
