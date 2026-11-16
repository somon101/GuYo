/* Сквозная проверка в браузере: node test/smoke.js (нужен playwright). Запускает локальный сервер для www. */
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path'), assert = require('assert');
const root = path.join(__dirname, '..', 'www'), tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'as-'));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.webmanifest': 'application/manifest+json' };
const srv = http.createServer((q, r) => { const f = path.join(root, q.url === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); r.end(); } else { r.writeHead(200, { 'content-type': types[path.extname(f)] || 'text/plain' }); r.end(d); } }); });
(async () => {
  await new Promise(r => srv.listen(0, r)); const url = 'http://127.0.0.1:' + srv.address().port + '/';
  const b = await chromium.launch(); const ctx = await b.newContext({ viewport: { width: 1360, height: 1000 }, acceptDownloads: true }); const p = await ctx.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  // тестовые картинки: лицо на чёрном фоне (jpeg), одежда на «шахматке» (png)
  const mk = async (kind) => p.evaluate(kind => {
    const c = document.createElement('canvas'); c.width = 600; c.height = 500; const x = c.getContext('2d');
    if (kind === 'face') { x.fillStyle = '#000'; x.fillRect(0, 0, 600, 500); x.fillStyle = '#F2BC9C'; x.beginPath(); x.arc(300, 250, 200, 0, 7); x.fill(); x.fillStyle = '#3a2418'; x.beginPath(); x.arc(230, 230, 26, 0, 7); x.arc(370, 230, 26, 0, 7); x.fill(); return c.toDataURL('image/jpeg', .95); }
    for (let i = 0; i < 600; i += 20) for (let j = 0; j < 500; j += 20) { x.fillStyle = ((i + j) / 20) % 2 ? '#fff' : '#ddd'; x.fillRect(i, j, 20, 20); }
    x.fillStyle = '#2b3a8f'; x.fillRect(80, 60, 440, 400); return c.toDataURL('image/png');
  }, kind);
  const save = async (kind, name) => { const d = await mk(kind); const f = path.join(tmp, name); fs.writeFileSync(f, Buffer.from(d.split(',')[1], 'base64')); return f; };
  await p.goto(url); await p.waitForSelector('#slots .slot');
  assert.equal(await p.locator('#emptyNote.show').count(), 1, 'пустой макет показывает подсказку');
  // 1. лицо: загрузка, вырезание чёрного фона, авторазмер
  await p.click('[data-slot=face]'); await p.setInputFiles('#file', await save('face', 'face.jpg')); await p.waitForSelector('#parts .vt[data-pick]');
  let st = await p.evaluate(() => window.__AS.S); let face = st.sets[0].parts.face[0];
  assert.ok(face.origId, 'исходник сохранён для «вернуть»'); assert.equal(st.geo.face.placed, 1);
  const alpha = await p.evaluate(async () => { const S = window.__AS.S, f = S.sets[0].parts.face[0]; const u = document.querySelector('#parts img').src; const im = new Image(); im.src = u; await im.decode(); const c = document.createElement('canvas'); c.width = im.naturalWidth; c.height = im.naturalHeight; const x = c.getContext('2d'); x.drawImage(im, 0, 0); return [x.getImageData(2, 2, 1, 1).data[3], x.getImageData(300, 250, 1, 1).data[3]]; });
  assert.equal(alpha[0], 0, 'фон вырезан'); assert.equal(alpha[1], 255, 'лицо осталось');
  // 2. одежда на «шахматке»
  await p.click('[data-slot=cloth]'); await p.setInputFiles('#file', await save('check', 'cloth.png')); await p.waitForSelector('#parts .vt[data-pick]');
  st = await p.evaluate(() => window.__AS.S); assert.ok(st.sets[0].parts.cloth[0].origId, 'шахматка вырезана');
  // 3. фон и кадр
  await p.click('[data-slot=bg]'); await p.click('#bgPresets'); await p.click('.bgt >> nth=3');
  await p.click('[data-mode=bust]'); const fr = await p.evaluate(() => window.__AS.S.frame); assert.ok(fr.size > 100 && fr.mode === 'bust');
  // 4. смена варианта: вторая деталь встаёт на то же место
  await p.click('[data-slot=face]'); await p.setInputFiles('#file', await save('face', 'face2.jpg')); await p.waitForFunction(() => window.__AS.S.sets[0].parts.face.length === 2);
  st = await p.evaluate(() => window.__AS.S); const g0 = JSON.stringify(st.geo.face);
  await p.click('#parts .vt[data-pick] >> nth=0'); assert.equal(JSON.stringify(await p.evaluate(() => window.__AS.S.geo.face)), g0, 'положение слота не меняется при смене детали');
  // 5. своя координата
  await p.fill('#gx', '500'); assert.equal(await p.evaluate(() => window.__AS.S.geo.face.x), 500);
  // 6. сохранённые аватарки
  await p.click('[data-tab=looks]').catch(() => { }); await p.fill('#lookName', 'Первая'); await p.click('#lookSave'); await p.waitForSelector('.lk');
  await p.click('#parts .vt[data-pick] >> nth=1').catch(() => { });
  assert.equal(await p.locator('.lk').count(), 1);
  // 7. перезапуск: всё на месте (IndexedDB)
  await p.waitForTimeout(500); await p.reload(); await p.waitForSelector('#slots .slot');
  st = await p.evaluate(() => window.__AS.S); assert.equal(st.sets[0].parts.face.length, 2, 'детали сохранились после перезапуска'); assert.equal(st.looks.length, 1);
  assert.ok(await p.evaluate(() => document.querySelector('#stage image, #stage use') !== null), 'сцена нарисована из сохранённого');
  // 8. PNG аватара и профиля
  const png = await p.evaluate(async () => { const b = await window.__AS.avatarPNG(); return b.size; }); assert.ok(png > 1000, 'png аватара не пустой');
  const [dl] = await Promise.all([p.waitForEvent('download'), p.click('#openPv').then(() => p.click('#pvPng'))]); assert.equal(dl.suggestedFilename(), 'profile.png');
  const pf = path.join(tmp, 'p.png'); await dl.saveAs(pf); assert.ok(fs.statSync(pf).size > 1000);
  await p.keyboard.press('Escape');
  // 9. проект в файл и обратно
  const [dl2] = await Promise.all([p.waitForEvent('download'), p.click('#saveProject')]); const pj = path.join(tmp, 'proj.json'); await dl2.saveAs(pj);
  const j = JSON.parse(fs.readFileSync(pj, 'utf8')); assert.equal(j.format, 'avatar-studio/1'); assert.ok(j.sets[0].parts.face[0].data.startsWith('data:image/png'));
  await p.click('#wipe'); await p.click('#wipe'); await p.waitForFunction(() => window.__AS.S.looks.length === 0 && !(window.__AS.S.sets[0].parts.face || []).length);
  await p.setInputFiles('#openFile', pj); await p.waitForFunction(() => (window.__AS.S.sets[0].parts.face || []).length === 2 && window.__AS.S.looks.length === 1);
  await p.waitForSelector('#parts .vt[data-pick] img'); const ok = await p.evaluate(async () => { const im = document.querySelector('#parts .vt img'); await im.decode().catch(() => { }); return im.naturalWidth > 0; }); assert.ok(ok, 'картинки открылись из файла');
  // 10. телефон: вкладки и без горизонтальной прокрутки
  const m = await ctx.newPage({ viewport: { width: 400, height: 860 } }); await m.setViewportSize({ width: 400, height: 860 }); await m.goto(url); await m.waitForSelector('#slots .slot');
  assert.ok(await m.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'нет горизонтальной прокрутки на телефоне');
  await m.click('[data-tab=profile]'); assert.ok(await m.locator('#frame').isVisible()); assert.ok(!(await m.locator('#parts').isVisible()));
  assert.deepEqual(errs, [], 'ошибок в консоли нет: ' + errs.join(' | '));
  await b.close(); srv.close(); console.log('smoke: всё прошло');
})().catch(e => { console.error('smoke: ОШИБКА', e); process.exit(1); });
