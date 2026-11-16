/* Студия аватаров: интерфейс. Всё работает локально и офлайн. */
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const esc = t => String(t).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const { uid, CANVAS } = AS;
  const VB = [0, 0, CANVAS.w, CANVAS.h];
  const BGS = [
    { name: 'Розовый', kind: 'solid', c1: '#FFD0E2' }, { name: 'Мята', kind: 'solid', c1: '#CDEFDD' }, { name: 'Солнце', kind: 'solid', c1: '#FFE7A8' },
    { name: 'Закат', kind: 'grad', c1: '#FFB36B', c2: '#FF6FA1' }, { name: 'Небо', kind: 'grad', c1: '#8BDCFF', c2: '#5560E0' }, { name: 'Ночь', kind: 'grad', c1: '#343B7A', c2: '#12152A' }];

  /* ---------- состояние ---------- */
  let S = AS.newState();
  S.settings = { removeBg: true, tol: 16 };
  const urls = {};          // blobId -> адрес картинки
  const datas = {};         // blobId -> data: адрес (нужен только для экспорта)
  let OV = null;            // временный «взгляд» на сохранённую аватарку (для миниатюр)
  let placing = false, drag = null, saveTimer = 0;

  const curSet = () => S.sets.find(s => s.id === (OV ? OV.cur : S.cur)) || S.sets[0];
  const slot = id => S.slots.find(s => s.id === id);
  const G = id => curSet().geo[id] || S.geo[id];
  const visOf = id => OV ? (OV.hide.includes(id) ? 0 : 1) : G(id).vis;
  const FR = () => OV ? OV.frame : S.frame;
  const partOf = id => { const a = curSet().parts[id] || []; const k = (OV ? OV.pick : curSet().pick)[id]; return a.find(p => p.id === k) || a[0] || null; };
  const rectOf = id => id === 'bg' ? null : AS.rectOf(partOf(id), G(id));
  const srcOf = p => p && p.blobId ? urls[p.blobId] : '';

  function toast(t) { const el = document.createElement('div'); el.textContent = t; el.style.cssText = 'position:fixed;left:50%;bottom:calc(24px + env(safe-area-inset-bottom,0px));transform:translateX(-50%);background:var(--ink);color:var(--bg);padding:10px 16px;border-radius:12px;font-weight:600;z-index:60;max-width:90vw;text-align:center'; document.body.appendChild(el); setTimeout(() => el.remove(), 2600); }
  const busy = on => $('busy').classList.toggle('show', on);

  /* ---------- хранение ---------- */
  function save() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(async () => {
      try { await AS.db.put('kv', 'state', S); const d = new Date(); $('savedTxt').textContent = 'Сохранено в ' + String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); $('saved').classList.remove('bad'); }
      catch (e) { $('savedTxt').textContent = 'Не удалось сохранить'; $('saved').classList.add('bad'); }
    }, 200);
  }
  const putBlob = async (blob) => { const id = uid(); await AS.db.put('blobs', id, blob); urls[id] = URL.createObjectURL(blob); return id; };
  const getBlob = async id => (await AS.db.get('blobs', id)) || null;
  const blobToDataURL = b => new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(b); });
  const dataURLToBlob = u => { const [h, d] = u.split(','); const mime = /:(.*?);/.exec(h)[1]; const bin = atob(d); const a = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i); return new Blob([a], { type: mime }); };
  async function loadAll() {
    const st = await AS.db.get('kv', 'state').catch(() => null);
    if (st) { try { S = AS.migrate(st); S.settings = Object.assign({ removeBg: true, tol: 16 }, st.settings); } catch (e) { S = AS.newState(); S.settings = { removeBg: true, tol: 16 }; } }
    for (const s of S.sets) for (const k in s.parts) for (const p of s.parts[k]) {
      for (const id of [p.blobId, p.origId]) if (id && !urls[id]) { const b = await getBlob(id); if (b) urls[id] = URL.createObjectURL(b); }
    }
  }

  /* ---------- картинки на сцене ---------- */
  const lib = $('lib'), known = new Set();
  function sym(p) { const k = p.blobId; if (known.has(k)) return; known.add(k); lib.insertAdjacentHTML('beforeend', `<symbol id="p${k}" viewBox="0 0 ${p.w} ${p.h}" preserveAspectRatio="none"><image href="${urls[k]}" width="${p.w}" height="${p.h}"/></symbol>`); }
  function imgEl(p, x, y, w, h, inline) {
    if (!p || !p.blobId) return '';
    if (inline) return `<image href="${datas[p.blobId] || ''}" x="${x}" y="${y}" width="${w}" height="${h}"/>`;
    sym(p); return `<use href="#p${p.blobId}" x="${x}" y="${y}" width="${w}" height="${h}"/>`;
  }
  const bgCss = p => p.kind === 'solid' ? p.c1 : p.kind === 'grad' ? `linear-gradient(135deg,${p.c1},${p.c2})` : '';
  function bgHTML(f, tag, inline) {
    const p = partOf('bg'), g = G('bg'); if (!p || !visOf('bg')) return '';
    if (p.kind === 'solid') return `<rect x="${f.x}" y="${f.y}" width="${f.w}" height="${f.h}" fill="${p.c1}"/>`;
    if (p.kind === 'grad') return `<defs><linearGradient id="bg${tag}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${p.c1}"/><stop offset="1" stop-color="${p.c2}"/></linearGradient></defs><rect x="${f.x}" y="${f.y}" width="${f.w}" height="${f.h}" fill="url(#bg${tag})"/>`;
    const k = Math.max(f.w / p.w, f.h / p.h) * g.s, w = p.w * k, h = p.h * k, x = f.x + (f.w - w) / 2 + g.x / 100 * f.w, y = f.y + (f.h - h) / 2 + g.y / 100 * f.h;
    return `<svg x="${f.x}" y="${f.y}" width="${f.w}" height="${f.h}" viewBox="${f.x} ${f.y} ${f.w} ${f.h}" overflow="hidden">${imgEl(p, x, y, w, h, inline)}</svg>`;
  }
  function layersHTML(inline) {
    let o = '';
    for (const id of S.order) { if (id === 'bg' || !visOf(id)) continue; const p = partOf(id), r = rectOf(id); if (p && r) o += imgEl(p, r.x, r.y, r.w, r.h, inline); }
    return o;
  }
  const frameRect = () => { const f = FR(); return { x: f.x - f.size / 2, y: f.y - f.size / 2, w: f.size, h: f.size }; };
  const shapeEl = (f, shape) => shape === 'circle' ? `<circle cx="${f.x + f.w / 2}" cy="${f.y + f.h / 2}" r="${f.w / 2}"/>` : `<rect x="${f.x}" y="${f.y}" width="${f.w}" height="${f.h}" rx="${f.w * .24}"/>`;
  function profileSVG(px, tag, inline) {
    const f = frameRect();
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${f.x} ${f.y} ${f.w} ${f.h}" width="${px}" height="${px}" style="display:block;flex:none"><defs><clipPath id="pc${tag}">${shapeEl(f, FR().shape)}</clipPath></defs><g clip-path="url(#pc${tag})">${bgHTML(f, tag, inline)}${layersHTML(inline)}</g></svg>`;
  }
  const svg = $('st'); svg.setAttribute('viewBox', VB.join(' '));
  function stageHTML() {
    const cv = { x: VB[0], y: VB[1], w: VB[2], h: VB[3] }; const pb = partOf('bg');
    const wide = pb && pb.kind !== 'img' ? { x: -4000, y: -4000, w: 9000, h: 9000 } : cv;
    let o = bgHTML(wide, 'st') + layersHTML(false);
    for (const id of S.order) {
      if (id === 'bg' || !visOf(id) || partOf(id)) continue; const g = G(id);
      o += `<g opacity="${id === S.sel ? 1 : .5}"><circle cx="${g.x}" cy="${g.y}" r="36" fill="none" stroke="var(--mut)" stroke-width="4" stroke-dasharray="8 8"/><text x="${g.x}" y="${g.y + 74}" text-anchor="middle" font-size="30" fill="var(--mut)" font-family="system-ui,sans-serif">${esc(slot(id).name)}</text></g>`;
    }
    if (S.frameTool) {
      const f = frameRect();
      o += `<defs><mask id="fm"><rect x="-4000" y="-4000" width="9000" height="9000" fill="#fff"/><g fill="#000">${shapeEl(f, S.frame.shape)}</g></mask></defs><rect x="-4000" y="-4000" width="9000" height="9000" fill="rgba(8,10,34,.5)" mask="url(#fm)"/><g fill="none" stroke="#fff" stroke-width="6" stroke-dasharray="16 12">${shapeEl(f, S.frame.shape)}</g>`;
    } else if (S.sel !== 'bg') {
      const id = S.sel, g = G(id), r = rectOf(id);
      if (r) o += `<rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" fill="none" stroke="var(--accent)" stroke-width="4" stroke-dasharray="14 10" rx="8"/>`;
      o += `<g stroke="var(--accent)" stroke-width="5" stroke-linecap="round"><circle cx="${g.x}" cy="${g.y}" r="18" fill="var(--panel)"/><path d="M${g.x - 36} ${g.y}H${g.x + 36}M${g.x} ${g.y - 36}V${g.y + 36}"/></g>`;
    }
    return o;
  }
  function currentRects() { const r = {}; for (const id of S.order) if (id !== 'bg' && visOf(id)) r[id] = rectOf(id); return r; }
  function refreshFrame() { if (S.frame.mode === 'custom') return; Object.assign(S.frame, AS.framePreset(S.frame.mode, currentRects())); }
  function draw() {
    refreshFrame();
    svg.innerHTML = stageHTML();
    const g = G(S.sel);
    $('selInfo').textContent = S.frameTool ? `Кадр профиля · x ${Math.round(S.frame.x)} · y ${Math.round(S.frame.y)} · ${Math.round(S.frame.size)}` : S.sel === 'bg' ? 'Фон' : `${slot(S.sel).name} · x ${Math.round(g.x)} · y ${Math.round(g.y)} · ${Math.round(g.s * 100)}%`;
    $('emptyNote').classList.toggle('show', !S.order.some(id => partOf(id)));
    const pv = $('pvLive'); if (pv) pv.innerHTML = profileSVG(120, 'lv');
    if ($('modal').classList.contains('show')) renderModal();
  }

  /* ---------- списки ---------- */
  const IC = d => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
  const ICEYE = IC('<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'), ICOFF = IC('<path d="M3 3l18 18M10.6 5.1A9.9 9.9 0 0 1 12 5c6 0 10 7 10 7a17 17 0 0 1-3.2 3.9M6.6 6.6C3.7 8.4 2 12 2 12s4 7 10 7a9.6 9.6 0 0 0 4.2-1"/>'), ICPLUS = IC('<path d="M12 5v14M5 12h14"/>'), ICUP = IC('<path d="M12 16V4m0 0l-4 4m4-4l4 4M4 20h16"/>');
  function thumbHTML(p) {
    if (!p) return ICPLUS;
    if (p.kind === 'img') return `<img src="${srcOf(p)}" alt="" style="width:100%;height:100%;object-fit:cover">`;
    if (p.kind) return `<span style="display:block;width:100%;height:100%;background:${bgCss(p)}"></span>`;
    return `<img src="${srcOf(p)}" alt="">`;
  }
  function renderSets() {
    $('sets').innerHTML = S.sets.map(s => `<button class="set ${s.id === S.cur ? 'on' : ''}" data-set="${s.id}">${esc(s.name)}</button>`).join('') + '<button class="set add" id="setAdd">+ Набор</button>';
    $('setName').value = curSet().name;
  }
  function renderSlots() {
    $('slots').innerHTML = [...S.order].reverse().map(id => {
      const sl = slot(id), p = partOf(id), g = G(id);
      const ord = id === 'bg' ? '<div class="ord" style="width:20px"></div>' : `<div class="ord"><button data-up="${id}" aria-label="Выше">▲</button><button data-dn="${id}" aria-label="Ниже">▼</button></div>`;
      const del = sl.custom ? `<button class="ic" data-rmslot="${id}" aria-label="Удалить слот" title="Удалить слот">×</button>` : '';
      return `<div class="slot ${id === S.sel ? 'on' : ''}" data-slot="${id}" role="button" tabindex="0">${ord}<div class="th ${p ? '' : 'empty'}">${thumbHTML(p)}</div><div class="sn"><b>${esc(sl.name)}</b><small>${p ? esc(p.name) : 'пусто, загрузите деталь'}</small></div>${del}<button class="ic ${g.vis ? '' : 'off'}" data-vis="${id}" aria-label="Показать или скрыть">${g.vis ? ICEYE : ICOFF}</button></div>`;
    }).join('');
  }
  function renderParts() {
    const id = S.sel, s = curSet(), arr = s.parts[id] || [], cur = partOf(id), isbg = id === 'bg';
    const tools = `<label class="note" style="display:flex;gap:8px;align-items:center"><input type="checkbox" id="rmbg" ${S.settings.removeBg ? 'checked' : ''} style="accent-color:var(--accent)"> Убирать фон при загрузке</label>
      <div class="range"><span>Строгость</span><input type="range" id="tol" min="4" max="60" value="${S.settings.tol}"><span id="tolv">${S.settings.tol}</span></div>
      ${cur && cur.blobId && cur.kind === 'img' ? `<div class="row2"><button class="btn sm" id="doRm">Убрать фон у выбранной</button>${cur.origId ? '<button class="btn sm" id="doOrig">Вернуть исходную</button>' : ''}</div>` : ''}`;
    if (isbg) {
      $('parts').innerHTML = `<h2>Фон профиля</h2>
      <div class="sw">${arr.map(p => `<button class="bgt ${cur && cur.id === p.id ? 'on' : ''}" data-pick="${p.id}" title="${esc(p.name)}" style="${p.kind === 'img' ? '' : 'background:' + bgCss(p)}">${p.kind === 'img' ? `<img src="${srcOf(p)}" alt="">` : ''}<span class="x" data-del="${p.id}" role="button" aria-label="Удалить фон">×</span></button>`).join('')}<label class="vt up" for="file" style="aspect-ratio:1">${ICUP}Фото</label></div>
      <input type="file" id="file" accept="image/png,image/webp,image/jpeg" multiple hidden>
      <div class="colpick"><input type="color" id="colAdd" value="#FFD0E2" aria-label="Свой цвет"><span>Свой цвет: выберите, он добавится в набор</span></div>
      <div class="row2"><button class="btn sm" id="bgPresets">Добавить готовые цвета</button></div>
      <p class="note">Фон виден за персонажем и внутри круга профиля. Фото можно приблизить и сдвинуть в блоке «Положение».</p>`;
      return;
    }
    $('parts').innerHTML = `<h2>Детали слота «${esc(slot(id).name)}»</h2>
    <div class="vgrid">${arr.map(p => `<button class="vt ${cur && cur.id === p.id ? 'on' : ''}" data-pick="${p.id}" title="${esc(p.name)}"><img src="${srcOf(p)}" alt="${esc(p.name)}"><span class="x" data-del="${p.id}" role="button" aria-label="Удалить деталь">×</span></button>`).join('')}<label class="vt up" for="file">${ICUP}Загрузить</label></div>
    <input type="file" id="file" accept="image/png,image/webp,image/jpeg" multiple hidden>
    <p class="note">${arr.length ? 'Выбранная деталь встаёт на точку слота. Любая другая деталь этого слота займёт то же место.' : 'В слоте пока нет деталей. Загрузите одну или несколько картинок: они появятся здесь как варианты.'}</p>${tools}`;
  }
  const fld = (i, label, min, max, v, step = 1) => `<div class="fld"><label for="${i}">${label}</label><input type="range" id="${i}r" min="${min}" max="${max}" step="${step}" value="${Math.round(v)}"><input class="num" id="${i}" type="number" value="${Math.round(v)}"></div>`;
  function renderGeo() {
    const id = S.sel, g = G(id), own = !!curSet().geo[id];
    const scope = `<div style="margin-top:14px;color:var(--mut);font-size:12.5px">Положение действует</div><div class="seg s" id="scope"><button data-sc="all" class="${own ? '' : 'on'}">Для всех наборов</button><button data-sc="own" class="${own ? 'on' : ''}">Только в этом наборе</button></div>`;
    if (id === 'bg') {
      const p = partOf('bg'), img = p && p.kind === 'img';
      $('geo').innerHTML = `<h2>Положение фона</h2>${img ? fld('gs', 'Приближение, %', 100, 300, g.s * 100) + fld('gx', 'Сдвиг по X, %', -50, 50, g.x) + fld('gy', 'Сдвиг по Y, %', -50, 50, g.y) : '<p class="note" style="margin-top:0">Для цвета и градиента положение не нужно. Загрузите фото, чтобы двигать его.</p>'}${scope}<div class="row2"><button class="btn" id="reset">Вернуть исходное</button></div>`;
      return;
    }
    $('geo').innerHTML = `<h2>Положение слота</h2>${fld('gx', 'По X', -300, 1500, g.x)}${fld('gy', 'По Y', -300, 1900, g.y)}${fld('gs', 'Размер, %', 5, 300, g.s * 100)}
    <div class="pv"><div class="nudge"><span></span><button data-n="0,-1" aria-label="Вверх">↑</button><span></span><button data-n="-1,0" aria-label="Влево">←</button><button data-n="0,0" aria-label="К исходному" title="К исходному">•</button><button data-n="1,0" aria-label="Вправо">→</button><span></span><button data-n="0,1" aria-label="Вниз">↓</button><span></span></div>
    <div><div style="color:var(--mut);font-size:12.5px">Точка привязки детали</div><div class="seg s" id="pivot">${[['top', 'Верх'], ['center', 'Центр'], ['bottom', 'Низ']].map(([v, t]) => `<button data-pv="${v}" class="${g.pivot === v ? 'on' : ''}">${t}</button>`).join('')}</div></div></div>
    ${scope}<p class="note">Для руки поставьте привязку «Верх»: точка слота будет у запястья. Можно потянуть макет пальцем или мышью, либо нажать «Указать точку».</p><div class="row2"><button class="btn" id="reset">Вернуть исходное</button></div>`;
  }
  function renderFrame() {
    const f = S.frame;
    $('frame').innerHTML = `<h2>Кадр для профиля</h2>
    <div class="pvrow"><div class="pvbig" id="pvLive"></div><div style="min-width:0"><div style="color:var(--mut);font-size:12.5px">Какую часть показать</div><div class="seg s" id="modes">${[['head', 'Голова'], ['bust', 'По пояс'], ['full', 'Весь']].map(([v, t]) => `<button data-mode="${v}" class="${f.mode === v ? 'on' : ''}">${t}</button>`).join('')}</div>
    <div style="color:var(--mut);font-size:12.5px;margin-top:10px">Форма</div><div class="seg s" id="shapes">${[['circle', 'Круг'], ['round', 'Скруглённый']].map(([v, t]) => `<button data-shape="${v}" class="${f.shape === v ? 'on' : ''}">${t}</button>`).join('')}</div></div></div>
    ${fld('fx', 'Центр по X', -300, 1500, f.x)}${fld('fy', 'Центр по Y', -300, 1900, f.y)}${fld('fs', 'Размер кадра', 150, 2400, f.size)}
    <div class="row2"><button class="btn ${S.frameTool ? 'on' : ''}" id="frameTool2">${S.frameTool ? 'Скрыть кадр на макете' : 'Показать кадр на макете'}</button><button class="btn pri" id="openPv2">Посмотреть в профиле</button></div>
    <p class="note">Кадр сохраняется. «Голова», «По пояс» и «Весь» подстраиваются под детали сами. Если подвинуть кадр вручную, он остаётся там.</p>`;
    $('pvLive').innerHTML = profileSVG(120, 'lv');
  }
  function lookSVG(look, px, tag) { OV = { cur: look.set, pick: look.pick, hide: look.hide, frame: look.frame }; try { return profileSVG(px, tag); } finally { OV = null; } }
  function renderLooks() {
    $('looks').innerHTML = `<h2>Мои аватарки</h2>
    <p class="sub" style="font-size:13px">Сохраняйте разные сборки: детали, фон и кадр запоминаются вместе. Потом их можно сравнить рядом.</p>
    <div class="savebar"><input id="lookName" placeholder="Название, например «Школьник»" aria-label="Название аватарки"><button class="btn pri" id="lookSave">Сохранить текущую</button></div>
    ${S.looks.length ? `<div class="lgrid">${S.looks.map(l => `<div class="lk"><button class="pic" data-look="${l.id}" aria-label="Открыть ${esc(l.name)}">${lookSVG(l, 84, 'k' + l.id)}</button><input data-lname="${l.id}" value="${esc(l.name)}" aria-label="Название"><div class="acts"><button data-lpng="${l.id}">PNG</button><button data-lupd="${l.id}" title="Записать текущую сборку">Обновить</button><button data-ldel="${l.id}">Удалить</button></div></div>`).join('')}</div>
    <div class="row2"><button class="btn" id="cmpOpen">Сравнить рядом</button><button class="btn" id="allPng">Скачать все PNG</button></div>` : '<p class="note">Пока ничего не сохранено.</p>'}`;
  }
  function renderProject() {
    $('project').innerHTML = `<h2>Проект</h2>
    <p class="note" style="margin-top:0">Всё хранится на этом устройстве и работает без интернета. Проект можно сохранить в файл и открыть на другом устройстве.</p>
    <div class="row2"><button class="btn" id="saveProject">Сохранить проект в файл</button><button class="btn" id="loadProject">Открыть проект из файла</button></div>
    <div class="row2"><button class="btn sm" id="wipe">Очистить всё</button></div>`;
  }
  function renderAll() { renderSets(); renderSlots(); renderParts(); renderGeo(); renderFrame(); renderLooks(); renderProject(); draw(); $('frameTool').classList.toggle('on', S.frameTool); }

  /* ---------- детали: загрузка, вырезание фона ---------- */
  async function decode(blob) {
    const url = URL.createObjectURL(blob);
    try { const im = new Image(); im.src = url; await im.decode(); return im; } finally { setTimeout(() => URL.revokeObjectURL(url), 5000); }
  }
  const MAXSIDE = 2400;
  async function processImage(blob, doRemove) {
    const im = await decode(blob);
    let w = im.naturalWidth, h = im.naturalHeight; const k = Math.min(1, MAXSIDE / Math.max(w, h));
    w = Math.round(w * k); h = Math.round(h * k);
    const c = document.createElement('canvas'); c.width = w; c.height = h; const x = c.getContext('2d', { willReadFrequently: true }); x.drawImage(im, 0, 0, w, h);
    let info = { mode: 'none' };
    if (doRemove) { const d = x.getImageData(0, 0, w, h); await new Promise(r => setTimeout(r, 30)); info = AS.removeBackground(d.data, w, h, { tol: S.settings.tol }); x.putImageData(d, 0, 0); }
    const out = await new Promise(r => c.toBlob(r, 'image/png'));
    return { blob: out, w, h, ow: im.naturalWidth, oh: im.naturalHeight, info };
  }
  async function addFiles(files) {
    const id = S.sel, arr = curSet().parts[id] || (curSet().parts[id] = []);
    busy(true);
    try {
      for (const f of files) {
        const isBg = id === 'bg';
        const doRm = S.settings.removeBg && !isBg;
        const r = await processImage(f, doRm);
        const p = { id: uid(), name: f.name.replace(/\.[^.]+$/, ''), kind: 'img', w: r.w, h: r.h };
        if (doRm && r.info.mode !== 'alpha') { p.origId = await putBlob(f); p.origW = r.ow; p.origH = r.oh; p.blobId = await putBlob(r.blob); }
        else p.blobId = await putBlob(r.w === r.ow && r.h === r.oh ? f : r.blob);
        arr.push(p); curSet().pick[id] = p.id;
        const g = G(id); if (!isBg && !g.placed) { g.s = AS.fitScale(p, id); g.placed = 1; }
      }
    } catch (e) { toast('Не удалось открыть картинку'); }
    busy(false); renderAll(); save();
  }
  async function redoBg() {
    const p = partOf(S.sel); if (!p) return; busy(true);
    try {
      const src = p.origId ? await getBlob(p.origId) : await getBlob(p.blobId);
      const r = await processImage(src, true);
      if (r.info.mode === 'alpha') toast('У картинки уже есть прозрачный фон');
      if (!p.origId) { p.origId = p.blobId; p.origW = p.w; p.origH = p.h; } else await AS.db.del('blobs', p.blobId);
      p.blobId = await putBlob(r.blob); p.w = r.w; p.h = r.h;
    } catch (e) { toast('Не удалось убрать фон'); }
    busy(false); renderAll(); save();
  }
  async function restoreOrig() {
    const p = partOf(S.sel); if (!p || !p.origId) return;
    await AS.db.del('blobs', p.blobId); p.blobId = p.origId; p.w = p.origW; p.h = p.origH; p.origId = null; renderAll(); save();
  }
  async function delPart(pid) {
    const arr = curSet().parts[S.sel]; const i = arr.findIndex(p => p.id === pid); if (i < 0) return;
    const p = arr[i]; arr.splice(i, 1); for (const b of [p.blobId, p.origId]) if (b) { AS.db.del('blobs', b).catch(() => { }); }
    if (curSet().pick[S.sel] === pid) delete curSet().pick[S.sel]; renderAll(); save();
  }

  /* ---------- сохранение файлов (компьютер, браузер, Android) ---------- */
  async function saveBlob(name, blob) {
    const C = window.Capacitor;
    if (C && C.isNativePlatform && C.isNativePlatform() && C.Plugins && C.Plugins.Filesystem) {
      try {
        const b64 = (await blobToDataURL(blob)).split(',')[1];
        const r = await C.Plugins.Filesystem.writeFile({ path: name, data: b64, directory: 'CACHE' });
        if (C.Plugins.Share) await C.Plugins.Share.share({ title: name, url: r.uri, dialogTitle: 'Сохранить или отправить' });
        return;
      } catch (e) { toast('Не удалось сохранить файл'); return; }
    }
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { a.remove(); URL.revokeObjectURL(a.href); }, 1500);
  }
  async function prepData() { for (const id of S.order) { const p = partOf(id); if (p && p.blobId && !datas[p.blobId]) datas[p.blobId] = await blobToDataURL(await getBlob(p.blobId)); } }
  async function svgToPNG(s, W, H) {
    const url = URL.createObjectURL(new Blob([s], { type: 'image/svg+xml' })); const im = new Image(); im.src = url; await im.decode();
    const c = document.createElement('canvas'); c.width = W; c.height = H; c.getContext('2d').drawImage(im, 0, 0, W, H); URL.revokeObjectURL(url);
    return new Promise(r => c.toBlob(r, 'image/png'));
  }
  async function avatarPNG() {
    await prepData(); const rs = Object.entries(currentRects()).filter(([k, r]) => r); if (!rs.length) return null;
    const u = AS.union(rs.map(([, r]) => r)), pad = 30, x0 = u.x - pad, y0 = u.y - pad, w = u.w + 2 * pad, h = u.h + 2 * pad, W = 1400, k = W / w, H = Math.round(h * k);
    return svgToPNG(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${x0} ${y0} ${w} ${h}" width="${W}" height="${H}">${layersHTML(true)}</svg>`, W, H);
  }
  async function profilePNG(look) {
    if (look) OV = { cur: look.set, pick: look.pick, hide: look.hide, frame: look.frame };
    try { await prepData(); return await svgToPNG(profileSVG(768, 'ex', true), 768, 768); } finally { OV = null; }
  }

  /* ---------- сохранённые аватарки ---------- */
  const snapshot = name => ({ id: uid(), name, set: S.cur, pick: Object.assign({}, curSet().pick), hide: S.order.filter(id => !G(id).vis), frame: Object.assign({}, S.frame) });
  function applyLook(l) {
    if (!S.sets.some(s => s.id === l.set)) { toast('Набор этой аватарки удалён'); return; }
    S.cur = l.set; const s = curSet(); s.pick = Object.assign({}, l.pick); for (const id of S.order) G(id).vis = l.hide.includes(id) ? 0 : 1; S.frame = Object.assign({}, l.frame); renderAll(); save(); toast('Открыта: ' + l.name);
  }

  /* ---------- окно «в профиле» и сравнение ---------- */
  function renderModal() {
    const mode = $('modal').dataset.view, cs = n => profileSVG(n, 'm' + n);
    const shapeSeg = `<div class="seg" id="mshape">${[['circle', 'Круг'], ['round', 'Скруглённый']].map(([v, t]) => `<button data-mshape="${v}" class="${S.frame.shape === v ? 'on' : ''}">${t}</button>`).join('')}</div>`;
    if (mode === 'cmp') {
      $('sheet').innerHTML = `<div style="display:flex;align-items:center;gap:10px"><h3 style="flex:1">Сравнение аватарок</h3>${shapeSeg}<button class="ic" data-close aria-label="Закрыть" style="font-size:22px">×</button></div>
      <div class="cmp">${S.looks.map(l => { const lk = Object.assign({}, l, { frame: Object.assign({}, l.frame, { shape: S.frame.shape }) }); return `<div class="lk"><button class="pic" data-look="${l.id}">${lookSVG(lk, 128, 'c' + l.id)}</button><b style="text-align:center">${esc(l.name)}</b></div>`; }).join('')}</div>
      <p class="note">Нажмите на аватарку, чтобы открыть её в редакторе.</p>`;
      return;
    }
    $('sheet').innerHTML = `<div style="display:flex;align-items:center;gap:10px"><h3 style="flex:1">Как это выглядит в профиле</h3>${shapeSeg}<button class="ic" data-close aria-label="Закрыть" style="font-size:22px">×</button></div>
    <div class="ctx">
     <div class="ctxc full"><small>Шапка профиля</small><div class="big">${cs(200)}<div class="who"><div><b style="font-size:18px">Алишер</b><span>Уровень 12 · Серия 34 дня</span></div></div></div></div>
     <div class="ctxc"><small>Рейтинг</small><div class="who">${cs(48)}<div style="flex:1"><b>Алишер</b><span>1 240 XP</span></div><b>3</b></div></div>
     <div class="ctxc"><small>Дуэль и чат</small><div class="who" style="align-items:flex-end">${cs(36)}<span class="bubble" style="color:var(--ink)">Готов к дуэли?</span></div></div>
    </div>
    <div class="row2" style="margin-top:16px"><button class="btn pri" id="pvPng">Скачать картинку профиля</button><button class="btn" data-close>Закрыть</button></div>
    <p class="note">Показано то, что сохранено: фон, персонаж и выбранный кадр. Меняйте кадр и слоты, окно обновляется сразу.</p>`;
  }
  const openModal = mode => { $('modal').dataset.view = mode; $('modal').classList.add('show'); renderModal(); };

  /* ---------- события ---------- */
  const narrow = () => matchMedia('(max-width:1020px)').matches;
  function tab(t) { document.body.dataset.tab = t; document.querySelectorAll('#tabs button').forEach(b => b.classList.toggle('on', b.dataset.tab === t)); }
  tab('layers');
  $('tabs').addEventListener('click', e => { const b = e.target.closest('[data-tab]'); if (b) tab(b.dataset.tab); });
  function sync() { renderGeo(); draw(); renderSlots(); save(); }
  function resetGeo() { const b = AS.BASE_SLOTS.find(x => x.id === S.sel), g = G(S.sel); const p = partOf(S.sel); if (b) Object.assign(g, { x: b.x, y: b.y, s: b.id === 'bg' ? 1 : (p && p.w ? AS.fitScale(p, b.id) : 1), pivot: b.pivot }); else Object.assign(g, { x: 600, y: 700, s: p ? AS.fitScale(p, '') : 1, pivot: 'center' }); sync(); }
  function addSlot() { const v = $('newSlot').value.trim(); if (!v) return; const id = 'c' + uid(); S.slots.push({ id, name: v, custom: true }); S.geo[id] = { x: 600, y: 700, s: 1, pivot: 'center', vis: 1, placed: 0 }; S.order.push(id); S.sel = id; $('newSlot').value = ''; renderAll(); save(); }
  let wipeArm = 0;
  document.addEventListener('click', async e => {
    const t = e.target;
    const st = t.closest('[data-set]'); if (st) { S.cur = st.dataset.set; renderAll(); save(); return; }
    if (t.closest('#setAdd')) { const n = { id: uid(), name: 'Набор ' + (S.sets.length + 1), parts: {}, pick: {}, geo: {} }; S.sets.push(n); S.cur = n.id; renderAll(); save(); return; }
    if (t.closest('#setDel')) { if (S.sets.length > 1) { S.sets = S.sets.filter(s => s.id !== S.cur); S.looks = S.looks.filter(l => l.set !== S.cur); S.cur = S.sets[0].id; renderAll(); save(); } else toast('Должен остаться хотя бы один набор'); return; }
    const up = t.closest('[data-up]'), dn = t.closest('[data-dn]');
    if (up || dn) { const id = (up || dn).dataset.up || dn.dataset.dn; const i = S.order.indexOf(id), j = up ? i + 1 : i - 1; if (j >= 1 && j < S.order.length) { [S.order[i], S.order[j]] = [S.order[j], S.order[i]]; renderSlots(); draw(); save(); } return; }
    const rs = t.closest('[data-rmslot]'); if (rs) { const id = rs.dataset.rmslot; S.slots = S.slots.filter(s => s.id !== id); S.order = S.order.filter(x => x !== id); if (S.sel === id) S.sel = 'face'; renderAll(); save(); e.stopPropagation(); return; }
    const vis = t.closest('[data-vis]'); if (vis) { const g = G(vis.dataset.vis); g.vis = g.vis ? 0 : 1; renderSlots(); draw(); save(); return; }
    const sl = t.closest('[data-slot]'); if (sl) { S.sel = sl.dataset.slot; S.frameTool = false; renderAll(); save(); if (narrow()) tab('parts'); return; }
    const del = t.closest('[data-del]'); if (del) { e.preventDefault(); delPart(del.dataset.del); return; }
    const pk = t.closest('[data-pick]'); if (pk) { curSet().pick[S.sel] = pk.dataset.pick; renderSlots(); renderParts(); renderGeo(); draw(); renderLooks(); save(); return; }
    const n = t.closest('[data-n]'); if (n) { const [dx, dy] = n.dataset.n.split(',').map(Number); if (!dx && !dy) resetGeo(); else { const g = G(S.sel), k = e.shiftKey ? 10 : 1; g.x += dx * k; g.y += dy * k; g.placed = 1; sync(); } return; }
    const pv = t.closest('[data-pv]'); if (pv) { G(S.sel).pivot = pv.dataset.pv; sync(); return; }
    const sc = t.closest('[data-sc]'); if (sc) { const s = curSet(); if (sc.dataset.sc === 'own') s.geo[S.sel] = Object.assign({}, S.geo[S.sel]); else delete s.geo[S.sel]; renderGeo(); draw(); save(); return; }
    const md = t.closest('[data-mode]'); if (md) { S.frame.mode = md.dataset.mode; renderFrame(); draw(); save(); return; }
    const sh = t.closest('[data-shape]'); if (sh) { S.frame.shape = sh.dataset.shape; renderFrame(); draw(); save(); return; }
    const ms = t.closest('[data-mshape]'); if (ms) { S.frame.shape = ms.dataset.mshape; renderFrame(); draw(); save(); return; }
    if (t.closest('#reset')) { resetGeo(); return; }
    if (t.closest('#addSlot')) { addSlot(); return; }
    if (t.closest('#place')) { placing = !placing; S.frameTool = false; svg.classList.toggle('place', placing); $('place').classList.toggle('on', placing); return; }
    if (t.closest('#frameTool') || t.closest('#frameTool2')) { S.frameTool = !S.frameTool; placing = false; svg.classList.remove('place'); $('frameTool').classList.toggle('on', S.frameTool); renderFrame(); draw(); return; }
    if (t.closest('#openPv') || t.closest('#openPv2')) { openModal('pv'); return; }
    if (t.closest('[data-close]') || t.id === 'modal') { $('modal').classList.remove('show'); return; }
    if (t.closest('#pvPng')) { const b = await profilePNG(); saveBlob('profile.png', b); return; }
    if (t.closest('#doRm')) { redoBg(); return; }
    if (t.closest('#doOrig')) { restoreOrig(); return; }
    if (t.closest('#bgPresets')) { const a = curSet().parts.bg || (curSet().parts.bg = []); for (const b of BGS) if (!a.some(x => x.name === b.name)) a.push(Object.assign({ id: uid() }, b)); if (!curSet().pick.bg) curSet().pick.bg = a[0].id; renderAll(); save(); return; }
    if (t.closest('#lookSave')) { const nm = $('lookName').value.trim() || 'Аватарка ' + (S.looks.length + 1); S.looks.push(snapshot(nm)); renderLooks(); save(); toast('Сохранено: ' + nm); return; }
    const lk = t.closest('[data-look]'); if (lk) { const l = S.looks.find(x => x.id === lk.dataset.look); if (l) { $('modal').classList.remove('show'); applyLook(l); } return; }
    const lu = t.closest('[data-lupd]'); if (lu) { const i = S.looks.findIndex(x => x.id === lu.dataset.lupd); const old = S.looks[i]; S.looks[i] = Object.assign(snapshot(old.name), { id: old.id }); renderLooks(); save(); toast('Аватарка обновлена'); return; }
    const ld = t.closest('[data-ldel]'); if (ld) { S.looks = S.looks.filter(x => x.id !== ld.dataset.ldel); renderLooks(); save(); return; }
    const lp = t.closest('[data-lpng]'); if (lp) { const l = S.looks.find(x => x.id === lp.dataset.lpng); busy(true); const b = await profilePNG(l); busy(false); saveBlob((l.name || 'avatar') + '.png', b); return; }
    if (t.closest('#cmpOpen')) { openModal('cmp'); return; }
    if (t.closest('#allPng')) { busy(true); for (const l of S.looks) { const b = await profilePNG(l); await saveBlob((l.name || 'avatar') + '.png', b); } busy(false); return; }
    if (t.closest('#saveProject')) { busy(true); try { await saveProject(); } finally { busy(false); } return; }
    if (t.closest('#loadProject')) { $('openFile').click(); return; }
    if (t.closest('#wipe')) { const b = t.closest('#wipe'); if (!wipeArm) { wipeArm = 1; b.textContent = 'Точно очистить? Нажмите ещё раз'; setTimeout(() => { wipeArm = 0; const x = $('wipe'); if (x) x.textContent = 'Очистить всё'; }, 4000); } else { wipeArm = 0; await wipeAll(); } return; }
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') $('modal').classList.remove('show');
    if (e.key === 'Enter' && e.target.closest && e.target.closest('[data-slot]') && !e.target.closest('button')) e.target.click();
    const a = document.activeElement; if (a && /INPUT|TEXTAREA|SELECT/.test(a.tagName)) return;
    const d = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
    if (d && S.sel !== 'bg' && !S.frameTool) { e.preventDefault(); const g = G(S.sel), k = e.shiftKey ? 10 : 1; g.x += d[0] * k; g.y += d[1] * k; g.placed = 1; sync(); }
  });
  $('setName').addEventListener('input', e => { curSet().name = e.target.value || 'Без названия'; renderSets(); $('setName').focus(); save(); });
  document.addEventListener('input', e => {
    const t = e.target;
    if (t.id === 'tol') { S.settings.tol = +t.value; $('tolv').textContent = t.value; save(); return; }
    if (t.dataset && t.dataset.lname) { const l = S.looks.find(x => x.id === t.dataset.lname); if (l) { l.name = t.value || 'Без названия'; save(); } return; }
    const base = t.id.replace(/r$/, '');
    if (['fx', 'fy', 'fs'].includes(base)) { const v = parseFloat(t.value); if (isNaN(v)) return; S.frame[{ fx: 'x', fy: 'y', fs: 'size' }[base]] = v; S.frame.mode = 'custom'; const a = $(base), b = $(base + 'r'); if (a && a !== t) a.value = Math.round(v); if (b && b !== t) b.value = Math.round(v); document.querySelectorAll('#modes button').forEach(x => x.classList.remove('on')); draw(); save(); return; }
    const m = { gx: 'x', gy: 'y', gs: 's' }[base]; if (!m) return;
    const v = parseFloat(t.value); if (isNaN(v)) return; const g = G(S.sel); g[m] = m === 's' ? v / 100 : v; g.placed = 1;
    const a = $(base), b = $(base + 'r'); if (a && a !== t) a.value = Math.round(v); if (b && b !== t) b.value = Math.round(v); draw(); save();
  });
  document.addEventListener('change', e => {
    const t = e.target;
    if (t.id === 'file') { addFiles(t.files); t.value = ''; }
    if (t.id === 'rmbg') { S.settings.removeBg = t.checked; save(); }
    if (t.id === 'colAdd') { const c = t.value, a = curSet().parts.bg || (curSet().parts.bg = []); const p = { id: uid(), name: 'Цвет ' + c, kind: 'solid', c1: c }; a.push(p); curSet().pick.bg = p.id; renderAll(); save(); }
    if (t.id === 'openFile' && t.files[0]) { loadProject(t.files[0]); t.value = ''; }
  });
  /* перетаскивание, точка кликом, кадр */
  function pt(e) { const p = svg.createSVGPoint(); p.x = e.clientX; p.y = e.clientY; return p.matrixTransform(svg.getScreenCTM().inverse()); }
  svg.addEventListener('pointerdown', e => {
    const p = pt(e);
    if (S.frameTool) { drag = { frame: 1, dx: S.frame.x - p.x, dy: S.frame.y - p.y }; S.frame.mode = 'custom'; svg.setPointerCapture(e.pointerId); svg.classList.add('drag'); return; }
    if (S.sel === 'bg') return;
    const g = G(S.sel);
    if (placing) { g.x = p.x; g.y = p.y; g.placed = 1; placing = false; svg.classList.remove('place'); $('place').classList.remove('on'); sync(); return; }
    drag = { dx: g.x - p.x, dy: g.y - p.y }; svg.setPointerCapture(e.pointerId); svg.classList.add('drag');
  });
  svg.addEventListener('pointermove', e => {
    const p = pt(e); $('cur').textContent = `x ${Math.round(p.x)}  y ${Math.round(p.y)}`; if (!drag) return;
    if (drag.frame) { S.frame.x = p.x + drag.dx; S.frame.y = p.y + drag.dy; draw(); return; }
    const g = G(S.sel); g.x = p.x + drag.dx; g.y = p.y + drag.dy; g.placed = 1; draw();
    if ($('gx')) { $('gx').value = Math.round(g.x); $('gxr').value = Math.round(g.x); $('gy').value = Math.round(g.y); $('gyr').value = Math.round(g.y); }
  });
  const endDrag = () => { if (drag) { const f = drag.frame; drag = null; svg.classList.remove('drag'); if (f) renderFrame(); else { renderGeo(); renderSlots(); } renderLooks(); save(); } };
  svg.addEventListener('pointerup', endDrag); svg.addEventListener('pointercancel', endDrag);

  /* ---------- проект в файл и обратно ---------- */
  async function saveProject() {
    const copy = JSON.parse(JSON.stringify(S));
    for (const s of copy.sets) for (const k in s.parts) for (const p of s.parts[k]) {
      if (p.blobId) { p.data = await blobToDataURL(await getBlob(p.blobId)); delete p.blobId; }
      if (p.origId) { p.origData = await blobToDataURL(await getBlob(p.origId)); delete p.origId; }
    }
    await saveBlob('avatar-studio-project.json', new Blob([JSON.stringify(copy)], { type: 'application/json' }));
  }
  async function loadProject(file) {
    busy(true);
    try {
      const raw = JSON.parse(await file.text()); const st = AS.migrate(raw); st.settings = Object.assign({ removeBg: true, tol: 16 }, raw.settings);
      await AS.db.clear('blobs'); for (const k in urls) { URL.revokeObjectURL(urls[k]); delete urls[k]; } for (const k in datas) delete datas[k]; known.clear(); lib.innerHTML = '';
      for (const s of st.sets) for (const k in s.parts) for (const p of s.parts[k]) {
        if (p.data) { p.blobId = await putBlob(dataURLToBlob(p.data)); delete p.data; }
        if (p.origData) { p.origId = await putBlob(dataURLToBlob(p.origData)); delete p.origData; }
      }
      S = st; S.frameTool = false; renderAll(); save(); toast('Проект открыт');
    } catch (e) { toast('Не получилось открыть файл: ' + (e.message || 'ошибка')); }
    busy(false);
  }
  async function wipeAll() { await AS.db.clear('blobs'); await AS.db.clear('kv'); for (const k in urls) delete urls[k]; for (const k in datas) delete datas[k]; known.clear(); lib.innerHTML = ''; S = AS.newState(); S.settings = { removeBg: true, tol: 16 }; renderAll(); save(); toast('Всё очищено'); }

  /* ---------- вывод в файл ---------- */
  $('exPng').onclick = async () => { busy(true); const b = await avatarPNG(); busy(false); if (b) saveBlob('avatar.png', b); else toast('Сначала загрузите хотя бы одну деталь'); };
  const root = document.documentElement;
  function theme(t) { root.dataset.theme = t; document.querySelectorAll('#th button').forEach(b => b.classList.toggle('on', b.dataset.t === t)); try { localStorage.setItem('as-theme', t); } catch (e) { } }
  document.querySelectorAll('#th button').forEach(b => b.onclick = () => theme(b.dataset.t));
  let th = null; try { th = localStorage.getItem('as-theme'); } catch (e) { }
  theme(th || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));

  /* ---------- запуск ---------- */
  (async function start() {
    busy(true);
    try { await loadAll(); } catch (e) { toast('Хранилище недоступно: изменения не сохранятся'); }
    busy(false); renderAll();
    if ('serviceWorker' in navigator && /^https?:/.test(location.protocol)) navigator.serviceWorker.register('sw.js').catch(() => { });
    window.__AS = { get S() { return S; }, addFiles, avatarPNG, profilePNG, saveBlob }; // для автотестов
  })();
})();
