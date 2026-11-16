/* Студия аватаров: чистая логика без DOM (геометрия, кадр профиля, вырезание фона, формат проекта).
   Работает и в браузере (глобальный AS), и в Node (require) для тестов. */
(function (root) {
  'use strict';
  const AS = root.AS || (root.AS = {});

  /* Холст аватара в условных пикселях: 0..1200 по X, 0..1600 по Y. */
  AS.CANVAS = { w: 1200, h: 1600 };
  AS.FORMAT = 'avatar-studio/1';

  /* Слоты по умолчанию снизу вверх. pivot: точка детали, которая ставится на координаты слота.
     fit: во сколько раз от ширины холста первый раз вписывается новая деталь. */
  AS.BASE_SLOTS = [
    { id: 'bg', name: 'Фон', pivot: 'center', x: 600, y: 800, s: 1, fit: 1 },
    { id: 'handL', name: 'Рука левая', pivot: 'top', x: 250, y: 1030, s: 1, fit: 0.16 },
    { id: 'handR', name: 'Рука правая', pivot: 'top', x: 950, y: 1030, s: 1, fit: 0.16 },
    { id: 'cloth', name: 'Одежда', pivot: 'center', x: 600, y: 1180, s: 1, fit: 0.82 },
    { id: 'neck', name: 'Шея', pivot: 'center', x: 600, y: 760, s: 1, fit: 0.42 },
    { id: 'face', name: 'Голова с лицом', pivot: 'center', x: 600, y: 560, s: 1, fit: 0.56 },
    { id: 'glasses', name: 'Очки', pivot: 'center', x: 600, y: 580, s: 1, fit: 0.42 },
    { id: 'hair', name: 'Волосы', pivot: 'center', x: 600, y: 470, s: 1, fit: 0.66 },
  ];

  AS.uid = () => Math.random().toString(36).slice(2, 9);

  AS.newState = function () {
    return {
      format: AS.FORMAT,
      slots: AS.BASE_SLOTS.map(b => ({ id: b.id, name: b.name, custom: false })),
      order: AS.BASE_SLOTS.map(b => b.id),
      geo: Object.fromEntries(AS.BASE_SLOTS.map(b => [b.id, { x: b.x, y: b.y, s: b.s, pivot: b.pivot, vis: 1, placed: 0 }])),
      sets: [{ id: 's1', name: 'Набор 1', parts: {}, pick: {}, geo: {} }],
      cur: 's1', sel: 'face',
      frame: { mode: 'head', x: 600, y: 560, size: 760, shape: 'circle' },
      looks: [],
    };
  };

  /* Прямоугольник детали на холсте: размер картинки * масштаб, привязка по pivot. */
  AS.rectOf = function (part, g) {
    if (!part || part.kind && part.kind !== 'img') return null;
    const w = part.w * g.s, h = part.h * g.s;
    const y = g.pivot === 'top' ? g.y : g.pivot === 'bottom' ? g.y - h : g.y - h / 2;
    return { x: g.x - w / 2, y, w, h };
  };

  /* Масштаб, при котором новая деталь занимает долю fit от ширины холста. */
  AS.fitScale = function (part, slotId) {
    const b = AS.BASE_SLOTS.find(x => x.id === slotId);
    const fit = b ? b.fit : 0.5;
    return Math.max(0.02, Math.min(4, (AS.CANVAS.w * fit) / part.w));
  };

  const union = rs => {
    rs = rs.filter(Boolean);
    if (!rs.length) return null;
    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    for (const r of rs) { x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y); x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h); }
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  };
  AS.union = union;

  /* Готовые кадры профиля по видимым деталям. rects: {slotId: rect|null}. */
  AS.framePreset = function (mode, rects) {
    const head = union([rects.face, rects.hair, rects.neck]) || { x: 300, y: 200, w: 600, h: 620 };
    const all = union(Object.entries(rects).filter(([k]) => k !== 'bg').map(([, r]) => r)) || head;
    if (mode === 'head') {
      const top = head.y, bottom = rects.face ? rects.face.y + rects.face.h : head.y + head.h;
      const size = Math.max(head.w, bottom - top) * 1.12;
      return { x: head.x + head.w / 2, y: top + (bottom - top) / 2, size };
    }
    if (mode === 'bust') {
      const cl = rects.cloth;
      const bottom = cl ? cl.y + cl.h * 0.55 : head.y + head.h * 1.7;
      const top = head.y;
      const size = Math.max(head.w * 1.25, bottom - top) * 1.08;
      return { x: head.x + head.w / 2, y: top + (bottom - top) / 2, size };
    }
    return { x: all.x + all.w / 2, y: all.y + all.h / 2, size: Math.max(all.w, all.h) * 1.06 };
  };

  /* ---------- вырезание фона ----------
     data: RGBA (Uint8ClampedArray), меняется на месте. Возвращает {mode, removed}. */
  AS.removeBackground = function (data, w, h, opt) {
    opt = Object.assign({ tol: 16, erode: 1, blur: 1, open: -1, minIsland: 0.004 }, opt || {});
    const N = w * h;
    const A = i => data[i * 4 + 3];
    const corners = [0, w - 1, (h - 1) * w, N - 1];
    // уже есть прозрачность по углам: ничего не делаем
    if (corners.every(i => A(i) < 200)) return { mode: 'alpha', removed: 0 };
    let cr = 0, cg = 0, cb = 0;
    for (const i of corners) { cr += data[i * 4]; cg += data[i * 4 + 1]; cb += data[i * 4 + 2]; }
    cr /= 4; cg /= 4; cb /= 4;
    const mx = Math.max(cr, cg, cb), mn = Math.min(cr, cg, cb);
    let mode;
    if (mx <= 70) mode = 'black';
    else if (mx - mn <= 28 && mn >= 110) mode = 'neutral'; // белый фон или «шахматка»
    else mode = 'color';
    // на чёрном фоне тёмная одежда: складки соединяются с фоном тонкими щелями, поэтому раскрытие сильнее
    if (opt.open < 0) opt.open = mode === 'black' ? 5 : 2;
    let T = opt.tol;
    if (mode === 'black') { // порог по шуму самой картинки: у JPEG чёрный фон обычно 0..6, а складки одежды темнее порога не должны быть
      const hist = new Uint32Array(256); let cnt = 0;
      const sample = i => { hist[Math.max(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])]++; cnt++; };
      for (let x = 0; x < w; x++) { sample(x); sample((h - 1) * w + x); } for (let y = 0; y < h; y++) { sample(y * w); sample(y * w + w - 1); }
      let acc = 0, p90 = 0; for (let v = 0; v < 256; v++) { acc += hist[v]; if (acc >= cnt * 0.9) { p90 = v; break; } }
      T = Math.min(opt.tol, Math.max(3, p90 + 3));
    }
    const isBg = new Uint8Array(N);
    for (let i = 0; i < N; i++) {
      const r = data[i * 4], g = data[i * 4 + 1], b = data[i * 4 + 2];
      if (mode === 'black') isBg[i] = Math.max(r, g, b) <= T ? 1 : 0;
      else if (mode === 'neutral') isBg[i] = (Math.max(r, g, b) - Math.min(r, g, b) <= T + 6 && Math.min(r, g, b) >= 120) ? 1 : 0;
      else isBg[i] = (Math.abs(r - cr) + Math.abs(g - cg) + Math.abs(b - cb)) <= T * 4 ? 1 : 0;
    }
    // заливка от границы
    const bg = new Uint8Array(N), q = new Int32Array(N);
    let qh = 0, qt = 0;
    const push = i => { if (isBg[i] && !bg[i]) { bg[i] = 1; q[qt++] = i; } };
    for (let x = 0; x < w; x++) { push(x); push((h - 1) * w + x); }
    for (let y = 0; y < h; y++) { push(y * w); push(y * w + w - 1); }
    while (qh < qt) {
      const i = q[qh++], x = i % w, y = (i / w) | 0;
      if (x > 0) push(i - 1); if (x < w - 1) push(i + 1); if (y > 0) push(i - w); if (y < h - 1) push(i + w);
    }
    // тонкие «коридоры» фона внутри предмета не считаются фоном: раскрытие маски фона
    if (opt.open > 0) {
      const e = AS._box(bg, w, h, opt.open, true), o = AS._box(e, w, h, opt.open, false);
      for (let i = 0; i < N; i++) bg[i] = (bg[i] && o[i]) ? 1 : 0;
    }
    let fg = new Uint8Array(N);
    for (let i = 0; i < N; i++) fg[i] = bg[i] ? 0 : 1;
    // мелкие островки (кусочки «шахматки») убираем
    fg = AS._dropIslands(fg, w, h, opt.minIsland);
    // тёмная кайма (след старого фона у светлых предметов): снимаем по слою, пока крайние пиксели тёмные
    if (mode === 'black') for (let p = 0; p < 6; p++) {
      const del = [];
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = y * w + x; if (!fg[i]) continue;
        if (!((x > 0 && !fg[i - 1]) || (x < w - 1 && !fg[i + 1]) || (y > 0 && !fg[i - w]) || (y < h - 1 && !fg[i + w]))) continue;
        if (Math.max(data[i * 4], data[i * 4 + 1], data[i * 4 + 2]) < 100) del.push(i);
      }
      if (!del.length) break; for (const i of del) fg[i] = 0;
    }
    // сжатие кромки на erode пикселей
    for (let p = 0; p < opt.erode; p++) {
      const nx = new Uint8Array(N);
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = y * w + x; if (!fg[i]) continue;
        if (x > 0 && !fg[i - 1] || x < w - 1 && !fg[i + 1] || y > 0 && !fg[i - w] || y < h - 1 && !fg[i + w]) continue;
        nx[i] = 1;
      }
      fg = nx;
    }
    // мягкий край
    let al = Float32Array.from(fg);
    const bl = opt.blur;
    if (bl > 0) for (let pass = 0; pass < 2; pass++) {
      const tmp = new Float32Array(N), dst = new Float32Array(N);
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { let s = 0, k = 0; for (let d = -bl; d <= bl; d++) { const xx = x + d; if (xx < 0 || xx >= w) continue; s += al[y * w + xx]; k++; } tmp[y * w + x] = s / k; }
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { let s = 0, k = 0; for (let d = -bl; d <= bl; d++) { const yy = y + d; if (yy < 0 || yy >= h) continue; s += tmp[yy * w + x]; k++; } dst[y * w + x] = s / k; }
      al = dst;
    }
    // цвет мягкого края: берём среднее соседей из плотной части, чтобы фон не просвечивал
    const R = 3, src = new Uint8ClampedArray(data);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = y * w + x; if (al[i] >= 0.999 || al[i] <= 0.001) continue;
      let r = 0, g = 0, b = 0, k = 0;
      for (let dy = -R; dy <= R; dy++) { const yy = y + dy; if (yy < 0 || yy >= h) continue; for (let dx = -R; dx <= R; dx++) { const xx = x + dx; if (xx < 0 || xx >= w) continue; const j = yy * w + xx; if (al[j] >= 0.999) { r += src[j * 4]; g += src[j * 4 + 1]; b += src[j * 4 + 2]; k++; } } }
      if (k) { data[i * 4] = r / k; data[i * 4 + 1] = g / k; data[i * 4 + 2] = b / k; }
    }
    let removed = 0;
    for (let i = 0; i < N; i++) { const a = Math.round(al[i] * 255); data[i * 4 + 3] = Math.min(a, A(i)); if (a === 0) removed++; }
    return { mode, removed };
  };

  /* min/max по квадрату радиуса r (раскрытие/закрытие маски) */
  AS._box = function (src, w, h, r, isMin) {
    const tmp = new Uint8Array(w * h), dst = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      let v = isMin ? 1 : 0;
      for (let d = -r; d <= r; d++) { const xx = x + d; const val = (xx < 0 || xx >= w) ? (isMin ? 1 : 0) : src[y * w + xx]; if (isMin ? !val : val) { v = isMin ? 0 : 1; break; } }
      tmp[y * w + x] = v;
    }
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      let v = isMin ? 1 : 0;
      for (let d = -r; d <= r; d++) { const yy = y + d; const val = (yy < 0 || yy >= h) ? (isMin ? 1 : 0) : tmp[yy * w + x]; if (isMin ? !val : val) { v = isMin ? 0 : 1; break; } }
      dst[y * w + x] = v;
    }
    return dst;
  };

  /* оставляем связные области не меньше доли minFrac от самой большой */
  AS._dropIslands = function (fg, w, h, minFrac) {
    const N = w * h, lab = new Int32Array(N), sizes = [0], q = new Int32Array(N);
    let n = 0;
    for (let s = 0; s < N; s++) {
      if (!fg[s] || lab[s]) continue;
      n++; let qh = 0, qt = 0; q[qt++] = s; lab[s] = n; let c = 0;
      while (qh < qt) {
        const i = q[qh++]; c++; const x = i % w, y = (i / w) | 0;
        const nb = [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1];
        for (const j of nb) if (j >= 0 && fg[j] && !lab[j]) { lab[j] = n; q[qt++] = j; }
      }
      sizes[n] = c;
    }
    const big = Math.max(0, ...sizes), out = new Uint8Array(N);
    for (let i = 0; i < N; i++) if (lab[i] && sizes[lab[i]] >= big * minFrac) out[i] = 1;
    return out;
  };

  /* Проект в файл и обратно: версия формата нужна для будущей отправки на сервер. */
  AS.migrate = function (raw) {
    if (!raw || typeof raw !== 'object') throw new Error('Это не проект студии аватаров');
    if (raw.format !== AS.FORMAT) throw new Error('Неизвестный формат файла');
    const base = AS.newState();
    const st = Object.assign(base, raw);
    st.slots = (raw.slots || base.slots).map(s => ({ id: s.id, name: s.name, custom: !!s.custom }));
    st.order = (raw.order || []).filter(id => st.slots.some(s => s.id === id));
    for (const s of st.slots) if (!st.order.includes(s.id)) st.order.push(s.id);
    for (const s of st.slots) if (!st.geo[s.id]) st.geo[s.id] = { x: 600, y: 700, s: 1, pivot: 'center', vis: 1, placed: 0 };
    if (!st.sets || !st.sets.length) st.sets = base.sets;
    if (!st.sets.some(s => s.id === st.cur)) st.cur = st.sets[0].id;
    if (!st.slots.some(s => s.id === st.sel)) st.sel = st.slots[0].id;
    st.looks = raw.looks || [];
    return st;
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = AS;
})(typeof globalThis !== 'undefined' ? globalThis : this);
