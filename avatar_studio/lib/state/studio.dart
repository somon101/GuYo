// Состояние студии: проект, картинки, сохранение, операции над слоями, наборами и аватарками.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/bg_removal.dart';
import '../core/geometry.dart';
import '../core/model.dart';
import 'render.dart';
import 'services.dart';
import 'storage.dart';

/// Взгляд на проект: какой набор, какие детали выбраны, что скрыто и какой кадр. Нужен для миниатюр аватарок.
class ViewSpec {
  final String setId;
  final Map<String, String> pick;
  final Set<String> hide;
  final FrameState frame;
  const ViewSpec(this.setId, this.pick, this.hide, this.frame);
}

const int maxSide = 2400;

class _CutIn {
  final Uint8List bytes;
  final int tol;
  _CutIn(this.bytes, this.tol);
}

class CutResult {
  final Uint8List png;
  final int w, h, ow, oh;
  final String mode;
  CutResult(this.png, this.w, this.h, this.ow, this.oh, this.mode);
}

/// Вырезание фона в отдельном потоке: картинка уменьшается до maxSide, обрабатывается и кодируется в PNG.
CutResult cutBackground(Uint8List bytes, int tol) {
  var im = img.decodeImage(bytes);
  if (im == null) throw const FormatException('Не удалось открыть картинку');
  im = img.bakeOrientation(im);
  final ow = im.width, oh = im.height;
  final k = maxSide / (ow > oh ? ow : oh);
  if (k < 1) im = img.copyResize(im, width: (ow * k).round(), height: (oh * k).round(), interpolation: img.Interpolation.average);
  final rgba = im.convert(numChannels: 4, format: img.Format.uint8);
  final data = Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba));
  final mode = removeBackground(data, rgba.width, rgba.height, tol: tol);
  final out = img.Image.fromBytes(width: rgba.width, height: rgba.height, bytes: data.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  return CutResult(Uint8List.fromList(img.encodePng(out, level: 3)), rgba.width, rgba.height, ow, oh, mode);
}

CutResult _cutTask(_CutIn i) => cutBackground(i.bytes, i.tol);

class Studio extends ChangeNotifier {
  Studio(this.storage, this.files, {this.useIsolate = true});
  final StudioStorage storage;
  final FileServices files;
  final bool useIsolate;

  ProjectState p = ProjectState.fresh();
  final Map<String, ui.Image> images = {};
  bool busy = false, frameTool = false, placing = false, loaded = false;
  String savedLabel = '';
  void Function(String)? onMessage;
  Timer? _timer;

  // ---------- доступ к данным ----------
  StudioSet get curSet => p.sets.firstWhere((s) => s.id == p.cur, orElse: () => p.sets.first);
  SlotDef slot(String id) => p.slots.firstWhere((s) => s.id == id);
  Geo geoOf(String id, [ViewSpec? v]) {
    final set = v == null ? curSet : p.sets.firstWhere((s) => s.id == v.setId, orElse: () => p.sets.first);
    return set.geo[id] ?? p.geo[id]!;
  }

  bool visOf(String id, [ViewSpec? v]) => v == null ? geoOf(id).vis : !v.hide.contains(id);
  Part? partOf(String slotId, [ViewSpec? v]) {
    final set = v == null ? curSet : p.sets.firstWhere((s) => s.id == v.setId, orElse: () => p.sets.first);
    final list = set.parts[slotId] ?? const <Part>[];
    final key = (v?.pick ?? set.pick)[slotId];
    for (final x in list) {
      if (x.id == key) return x;
    }
    return list.isEmpty ? null : list.first;
  }

  ui.Image? imageOf(Part? part) => part?.blobId == null ? null : images[part!.blobId];
  Rect? rectFor(String slotId, [ViewSpec? v]) {
    if (slotId == 'bg') return null;
    final part = partOf(slotId, v);
    if (part == null || !part.isImage || part.blobId == null) return null;
    return rectOf(part.w, part.h, geoOf(slotId, v));
  }

  ViewSpec get view => ViewSpec(p.cur, Map.of(curSet.pick), {for (final id in p.order) if (!geoOf(id).vis) id}, p.frame);
  ViewSpec viewOfLook(Look l) => ViewSpec(l.set, l.pick, l.hide.toSet(), l.frame);
  bool get hasAnyPart => p.order.any((id) => partOf(id) != null);

  Map<String, Rect?> visibleRects() => {for (final id in p.order) if (id != 'bg' && geoOf(id).vis) id: rectFor(id)};
  void refreshFrame() {
    if (p.frame.mode == 'custom') return;
    final f = framePreset(p.frame.mode, visibleRects());
    p.frame..x = f.x..y = f.y..size = f.size;
  }

  void message(String t) => onMessage?.call(t);

  // ---------- сохранение ----------
  /// Что-то изменилось: пересчитать кадр, перерисовать и сохранить с небольшой задержкой.
  void changed({bool save = true}) {
    refreshFrame();
    notifyListeners();
    if (save) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 250), flush);
    }
  }

  Future<void> flush() async {
    _timer?.cancel();
    try {
      await storage.saveState(p.toJson());
      final d = DateTime.now();
      savedLabel = 'Сохранено в ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      savedLabel = 'Не удалось сохранить';
    }
    notifyListeners();
  }

  Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<void> load() async {
    final st = await storage.loadState();
    if (st != null) {
      try {
        p = ProjectState.migrate(st);
      } catch (_) {
        p = ProjectState.fresh();
      }
    }
    for (final set in p.sets) {
      for (final list in set.parts.values) {
        for (final part in list) {
          for (final id in [part.blobId, part.origId]) {
            if (id == null || images.containsKey(id)) continue;
            final b = await storage.readBlob(id);
            if (b != null) {
              try {
                images[id] = await decode(b);
              } catch (_) {}
            }
          }
        }
      }
    }
    loaded = true;
    refreshFrame();
    notifyListeners();
  }

  // ---------- детали ----------
  Future<CutResult> _cut(Uint8List bytes) => useIsolate ? compute(_cutTask, _CutIn(bytes, p.settings.tol)) : Future.value(cutBackground(bytes, p.settings.tol));

  Future<String> _putBlob(Uint8List bytes, {ui.Image? image}) async {
    final id = uid();
    await storage.writeBlob(id, bytes);
    images[id] = image ?? await decode(bytes);
    return id;
  }

  /// Добавляет картинки в выбранный слот. cut: вырезать фон автоматически, иначе оставить как есть.
  Future<void> addImages(List<PickedFile> picked, {required bool cut}) async {
    final slotId = p.sel;
    final isBg = slotId == 'bg';
    busy = true;
    notifyListeners();
    final list = curSet.parts.putIfAbsent(slotId, () => []);
    var failed = 0;
    for (final f in picked) {
      try {
        final name = f.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
        Part part;
        if (cut && !isBg) {
          final r = await _cut(f.bytes);
          if (r.mode == 'alpha') {
            final im = await decode(f.bytes);
            part = Part(id: uid(), name: name, w: im.width.toDouble(), h: im.height.toDouble());
            part.blobId = await _putBlob(f.bytes, image: im);
          } else {
            part = Part(id: uid(), name: name, w: r.w.toDouble(), h: r.h.toDouble(), origW: r.ow.toDouble(), origH: r.oh.toDouble());
            part.origId = await _putBlob(f.bytes);
            part.blobId = await _putBlob(r.png);
          }
        } else {
          final im = await decode(f.bytes);
          part = Part(id: uid(), name: name, w: im.width.toDouble(), h: im.height.toDouble());
          part.blobId = await _putBlob(f.bytes, image: im);
        }
        list.add(part);
        curSet.pick[slotId] = part.id;
        final g = geoOf(slotId);
        if (!isBg && !g.placed) {
          g.s = fitScale(part.w, slotId);
          g.placed = true;
        }
      } catch (_) {
        failed++;
      }
    }
    busy = false;
    if (failed > 0) message(failed == picked.length ? 'Не удалось открыть картинку' : 'Часть картинок не открылась');
    changed();
  }

  /// Вырезает фон у выбранной детали (из исходника, если он есть).
  Future<void> cutSelected() async {
    final part = partOf(p.sel);
    if (part == null || part.blobId == null || !part.isImage) return;
    busy = true;
    notifyListeners();
    try {
      final src = await storage.readBlob(part.origId ?? part.blobId!);
      if (src == null) throw const FormatException('нет файла');
      final r = await _cut(src);
      if (r.mode == 'alpha') {
        message('У картинки уже есть прозрачный фон');
      } else {
        if (part.origId == null) {
          part.origId = part.blobId;
          part.origW = part.w;
          part.origH = part.h;
        } else {
          await _dropBlob(part.blobId!);
        }
        part.blobId = await _putBlob(r.png);
        part.w = r.w.toDouble();
        part.h = r.h.toDouble();
      }
    } catch (_) {
      message('Не удалось вырезать фон');
    }
    busy = false;
    changed();
  }

  Future<void> restoreOriginal() async {
    final part = partOf(p.sel);
    if (part == null || part.origId == null) return;
    await _dropBlob(part.blobId!);
    part.blobId = part.origId;
    part.w = part.origW ?? part.w;
    part.h = part.origH ?? part.h;
    part.origId = null;
    changed();
  }

  Future<void> _dropBlob(String id) async {
    images.remove(id)?.dispose();
    await storage.deleteBlob(id);
  }

  Future<void> deletePart(String slotId, String partId) async {
    final list = curSet.parts[slotId];
    if (list == null) return;
    final i = list.indexWhere((x) => x.id == partId);
    if (i < 0) return;
    final part = list.removeAt(i);
    for (final id in [part.blobId, part.origId]) {
      if (id != null) await _dropBlob(id);
    }
    if (curSet.pick[slotId] == partId) curSet.pick.remove(slotId);
    changed();
  }

  void pickPart(String slotId, String partId) {
    curSet.pick[slotId] = partId;
    changed();
  }

  void addColor(String c) {
    final part = Part(id: uid(), name: 'Цвет $c', kind: 'solid', c1: c);
    curSet.parts.putIfAbsent('bg', () => []).add(part);
    curSet.pick['bg'] = part.id;
    changed();
  }

  void addPresetBackgrounds() {
    const presets = [
      ['Розовый', 'solid', '#FFD0E2', ''], ['Мята', 'solid', '#CDEFDD', ''], ['Солнце', 'solid', '#FFE7A8', ''],
      ['Закат', 'grad', '#FFB36B', '#FF6FA1'], ['Небо', 'grad', '#8BDCFF', '#5560E0'], ['Ночь', 'grad', '#343B7A', '#12152A'],
    ];
    final list = curSet.parts.putIfAbsent('bg', () => []);
    for (final x in presets) {
      if (list.any((q) => q.name == x[0])) continue;
      list.add(Part(id: uid(), name: x[0], kind: x[1], c1: x[2], c2: x[3].isEmpty ? null : x[3]));
    }
    curSet.pick.putIfAbsent('bg', () => list.first.id);
    changed();
  }

  // ---------- слоты и наборы ----------
  void select(String id) {
    p.sel = id;
    frameTool = false;
    changed();
  }

  void toggleVis(String id) {
    final g = geoOf(id);
    g.vis = !g.vis;
    changed();
  }

  void moveSlot(String id, int dir) {
    final i = p.order.indexOf(id), j = i + dir;
    if (j < 1 || j >= p.order.length) return;
    final t = p.order[i];
    p.order[i] = p.order[j];
    p.order[j] = t;
    changed();
  }

  void addSlot(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    final id = 'c${uid()}';
    p.slots.add(SlotDef(id, n, custom: true));
    p.geo[id] = Geo(x: 600, y: 700);
    p.order.add(id);
    p.sel = id;
    changed();
  }

  void removeSlot(String id) {
    p.slots.removeWhere((s) => s.id == id);
    p.order.remove(id);
    p.geo.remove(id);
    if (p.sel == id) p.sel = 'face';
    changed();
  }

  void addSet() {
    final s = StudioSet(id: uid(), name: 'Набор ${p.sets.length + 1}');
    p.sets.add(s);
    p.cur = s.id;
    changed();
  }

  void renameSet(String name) {
    curSet.name = name.isEmpty ? 'Без названия' : name;
    changed();
  }

  void selectSet(String id) {
    p.cur = id;
    changed();
  }

  void deleteSet() {
    if (p.sets.length < 2) {
      message('Должен остаться хотя бы один набор');
      return;
    }
    final id = p.cur;
    p.sets.removeWhere((s) => s.id == id);
    p.looks.removeWhere((l) => l.set == id);
    p.cur = p.sets.first.id;
    changed();
  }

  void setScopeOwn(bool own) {
    if (own) {
      curSet.geo[p.sel] = p.geo[p.sel]!.copy();
    } else {
      curSet.geo.remove(p.sel);
    }
    changed();
  }

  void resetGeo() {
    final b = baseSlot(p.sel);
    final g = geoOf(p.sel);
    final part = partOf(p.sel);
    if (b != null) {
      g..x = b.x..y = b.y..pivot = b.pivot..s = b.id == 'bg' ? 1 : (part != null && part.w > 0 ? fitScale(part.w, b.id) : 1);
    } else {
      g..x = 600..y = 700..pivot = 'center'..s = part != null && part.w > 0 ? fitScale(part.w, '') : 1;
    }
    changed();
  }

  void setGeo({double? x, double? y, double? s, String? pivot}) {
    final g = geoOf(p.sel);
    if (x != null) g.x = x;
    if (y != null) g.y = y;
    if (s != null) g.s = s;
    if (pivot != null) g.pivot = pivot;
    g.placed = true;
    changed();
  }

  void setFrame({String? mode, String? shape, double? x, double? y, double? size}) {
    final f = p.frame;
    if (mode != null) f.mode = mode;
    if (shape != null) f.shape = shape;
    if (x != null || y != null || size != null) {
      f.mode = 'custom';
      if (x != null) f.x = x;
      if (y != null) f.y = y;
      if (size != null) f.size = size;
    }
    changed();
  }

  // ---------- аватарки ----------
  Look snapshot(String name, {String? id}) => Look(
        id: id ?? uid(),
        name: name.trim().isEmpty ? 'Аватарка ${p.looks.length + 1}' : name.trim(),
        set: p.cur,
        pick: Map.of(curSet.pick),
        hide: [for (final i in p.order) if (!geoOf(i).vis) i],
        frame: p.frame.copy(),
      );

  void saveLook(String name) {
    p.looks.add(snapshot(name));
    changed();
    message('Сохранено');
  }

  void updateLook(String id) {
    final i = p.looks.indexWhere((l) => l.id == id);
    if (i < 0) return;
    p.looks[i] = snapshot(p.looks[i].name, id: id);
    changed();
  }

  void renameLook(String id, String name) {
    final l = p.looks.firstWhere((x) => x.id == id);
    l.name = name.isEmpty ? 'Без названия' : name;
    changed();
  }

  void deleteLook(String id) {
    p.looks.removeWhere((l) => l.id == id);
    changed();
  }

  void applyLook(Look l) {
    if (!p.sets.any((s) => s.id == l.set)) {
      message('Набор этой аватарки удалён');
      return;
    }
    p.cur = l.set;
    curSet.pick = Map.of(l.pick);
    for (final id in p.order) {
      geoOf(id).vis = !l.hide.contains(id);
    }
    p.frame = l.frame.copy();
    changed();
  }

  // ---------- картинки на выход ----------
  Future<Uint8List> _toPng(ui.Picture pic, int w, int h) async {
    final im = await pic.toImage(w, h);
    final data = await im.toByteData(format: ui.ImageByteFormat.png);
    im.dispose();
    return data!.buffer.asUint8List();
  }

  /// PNG аватара без фона, обрезанный по видимым деталям.
  Future<Uint8List?> avatarPng() async {
    final u = unionRects(visibleRects().values);
    if (u == null) return null;
    const pad = 30.0;
    final r = u.inflate(pad);
    const outW = 1400.0;
    final k = outW / r.width;
    final w = outW.round(), h = (r.height * k).round();
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.scale(k);
    c.translate(-r.left, -r.top);
    paintLayers(c, this, view);
    return _toPng(rec.endRecording(), w, h);
  }

  /// PNG профиля: фон, персонаж и кадр, с учётом формы (круг или скруглённый квадрат).
  Future<Uint8List> profilePng({Look? look, int px = 768}) async {
    final v = look == null ? view : viewOfLook(look);
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    paintProfile(c, this, v, px.toDouble());
    return _toPng(rec.endRecording(), px, px);
  }

  // ---------- проект в файл ----------
  Future<Uint8List> projectBytes() async {
    final j = p.toJson();
    final sets = j['sets'] as List;
    for (final s in sets) {
      for (final list in (s['parts'] as Map).values) {
        for (final part in list as List) {
          final m = part as Map<String, dynamic>;
          final b = m.remove('blobId') as String?;
          final o = m.remove('origId') as String?;
          if (b != null) {
            final bytes = await storage.readBlob(b);
            if (bytes != null) m['data'] = base64Encode(bytes);
          }
          if (o != null) {
            final bytes = await storage.readBlob(o);
            if (bytes != null) m['origData'] = base64Encode(bytes);
          }
        }
      }
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(j)));
  }

  Uint8List _b64(String s) => base64Decode(s.contains(',') ? s.split(',').last : s);

  Future<void> loadProject(Uint8List bytes) async {
    final raw = jsonDecode(utf8.decode(bytes));
    final st = ProjectState.migrate(raw);
    // картинки из файла: пишем заново и выдаём новые идентификаторы
    await storage.clearBlobs();
    for (final im in images.values) {
      im.dispose();
    }
    images.clear();
    final rawSets = (raw as Map)['sets'] as List;
    for (var si = 0; si < st.sets.length; si++) {
      final rawParts = ((rawSets[si] as Map)['parts'] as Map?) ?? {};
      for (final e in st.sets[si].parts.entries) {
        final rawList = (rawParts[e.key] as List?) ?? const [];
        for (var pi = 0; pi < e.value.length; pi++) {
          final part = e.value[pi];
          final rp = pi < rawList.length ? rawList[pi] as Map : const {};
          part.blobId = null;
          part.origId = null;
          if (rp['data'] is String) part.blobId = await _putBlob(_b64(rp['data'] as String));
          if (rp['origData'] is String) part.origId = await _putBlob(_b64(rp['origData'] as String));
        }
      }
    }
    p = st;
    frameTool = false;
    changed();
  }

  Future<void> wipe() async {
    await storage.clearBlobs();
    for (final im in images.values) {
      im.dispose();
    }
    images.clear();
    p = ProjectState.fresh();
    frameTool = false;
    changed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
