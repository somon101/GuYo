// «Вырезалка»: загрузить лист, выбрать предметы рамками, подправить вырезку кистью и положить в слот.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/mask_edit.dart';
import '../core/sheet_split.dart';
import '../state/studio.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openCutter(BuildContext context, Studio s) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CutterScreen(s)));

/// Тяжёлые шаги идут в отдельном потоке; в тестах считаются на месте.
Future<R> _run<A, R>(Studio s, R Function(A) f, A a) => s.useIsolate ? compute(f, a) : Future.value(f(a));

class _Item {
  Box box;
  bool on = true;
  MaskEditor? ed;
  bool done = false;
  _Item(this.box);
}

enum _Tool { erase, restore, pipette }

class CutterScreen extends StatefulWidget {
  final Studio s;
  const CutterScreen(this.s, {super.key});
  @override
  State<CutterScreen> createState() => _CutterScreenState();
}

class _CutterScreenState extends State<CutterScreen> {
  Studio get s => widget.s;

  // лист
  Sheet? _sheet;
  ui.Image? _sheetImg;
  String _baseName = 'Деталь';
  var _items = <_Item>[];
  bool _busy = false;
  int _cols = 4, _rows = 3;
  Offset? _dragA, _dragB; // рамка, которую рисуют вручную (в пикселях листа)

  // правка
  int _cur = -1; // -1: выбор рамок
  ui.Image? _edImg;
  Uint8List? _disp;
  int _shownVersion = -1;
  bool _uploading = false;
  _Tool _tool = _Tool.erase;
  double _size = 36, _soft = 0.35, _colorTol = 22;
  Color? _bg; // null: шахматка
  Color _customBg = const Color(0xFFFFD0E2);
  int _active = -1; // рамка с ручками на экране выбора
  int _dragMode = 0; // 0 новая рамка, иначе биты ручки (1 лево, 2 право, 4 верх, 8 низ, 16 двигать)
  Box? _dragBox;
  Offset? _dragFrom;
  double _scale = 1;
  Offset _off = Offset.zero;
  Size _view = Size.zero;
  bool _fitted = false;
  final _ptr = <int, Offset>{};
  bool _drawing = false;
  Offset? _last, _hover;
  bool _space = false;
  double _pinchDist = 0;
  Offset _pinchMid = Offset.zero;

  MaskEditor? get _ed => _cur >= 0 && _cur < _items.length ? _items[_cur].ed : null;

  @override
  void dispose() {
    _msgTimer?.cancel();
    _sheetImg?.dispose();
    _edImg?.dispose();
    super.dispose();
  }

  String? _msg;
  Timer? _msgTimer;

  /// Короткое сообщение сверху (не закрывает кнопки внизу).
  void _toast(String t) {
    if (!mounted) return;
    setState(() => _msg = t);
    _msgTimer?.cancel();
    _msgTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _msg = null);
    });
  }

  Future<ui.Image> _toImage(Uint8List rgba, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  // ---------- лист ----------
  Future<void> _load() async {
    final files = await s.files.pickImages();
    if (files.isEmpty) return;
    setState(() => _busy = true);
    try {
      final sh = await _run(s, decodeSheet, (bytes: files.first.bytes, maxSide: 3200));
      final im = await _toImage(sh.rgba, sh.w, sh.h);
      _sheetImg?.dispose();
      _sheet = sh;
      _sheetImg = im;
      _baseName = files.first.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      _cur = -1;
      await _detect();
    } catch (_) {
      _toast('Не удалось открыть картинку');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _detect() async {
    final sh = _sheet;
    if (sh == null) return;
    setState(() => _busy = true);
    final boxes = await _run(s, findItems, (sheet: sh, gap: 0.002, minArea: 0.0005));
    _items = boxes.map(_Item.new).toList();
    if (boxes.isEmpty) _toast('Предметы не нашлись. Нарисуйте рамку пальцем или возьмите сетку');
    if (mounted) setState(() => _busy = false);
  }

  void _grid() {
    final sh = _sheet;
    if (sh == null) return;
    setState(() => _items = gridBoxes(sh.w, sh.h, _cols, _rows).map(_Item.new).toList());
  }

  Future<MaskEditor> _make(_Item it) async {
    if (it.ed != null) return it.ed!;
    final crop = await _run(s, cropSheet, (sheet: _sheet!, box: it.box, pad: math.max(4, (math.max(it.box.w, it.box.h) * 0.02).round()), maxSide: 1600));
    final ed = MaskEditor(crop.w, crop.h, crop.rgba);
    final r = await _run(s, autoAlpha, (rgba: crop.rgba, w: crop.w, h: crop.h, tol: s.p.settings.tol));
    ed.apply(r.alpha);
    ed.clearHistory();
    it.ed = ed;
    return ed;
  }

  Future<void> _openQueue() async {
    final first = (_active >= 0 && _active < _items.length && _items[_active].on && !_items[_active].done) ? _active : _items.indexWhere((e) => e.on && !e.done);
    if (first < 0) {
      _toast('Отметьте хотя бы одну рамку');
      return;
    }
    await _show(first);
  }

  Future<void> _show(int i) async {
    setState(() => _busy = true);
    final ed = await _make(_items[i]);
    final disp = Uint8List.fromList(ed.rgba);
    ed.paintAlphaInto(disp);
    final im = await _toImage(disp, ed.w, ed.h);
    _edImg?.dispose();
    if (!mounted) return;
    setState(() {
      _cur = i;
      _disp = disp;
      _edImg = im;
      _shownVersion = ed.version;
      _fitted = false;
      _busy = false;
    });
  }

  // ---------- показ правки ----------
  void _fit() {
    final ed = _ed;
    if (ed == null || _view.isEmpty) return;
    _scale = math.min(_view.width / ed.w, _view.height / ed.h) * 0.94;
    _off = Offset((_view.width - ed.w * _scale) / 2, (_view.height - ed.h * _scale) / 2);
    _fitted = true;
  }

  Future<void> _refresh() async {
    final ed = _ed;
    if (ed == null || _uploading || _disp == null || ed.version == _shownVersion) return;
    _uploading = true;
    final v = ed.version;
    ed.paintAlphaInto(_disp!);
    final im = await _toImage(Uint8List.fromList(_disp!), ed.w, ed.h);
    _uploading = false;
    if (!mounted || _ed != ed) {
      im.dispose();
      return;
    }
    final old = _edImg;
    setState(() {
      _edImg = im;
      _shownVersion = v;
    });
    old?.dispose();
    if (ed.version != v) unawaited(_refresh());
  }

  Offset _toImg(Offset p) => Offset((p.dx - _off.dx) / _scale, (p.dy - _off.dy) / _scale);
  double get _radius => (_size / 2) / _scale; // размер кисти задан в пикселях экрана

  void _zoomAt(Offset focus, double k) {
    final ns = (_scale * k).clamp(0.05, 40.0).toDouble();
    final f = ns / _scale;
    _off = focus - (focus - _off) * f;
    _scale = ns;
  }

  // ---------- жесты ----------
  void _down(PointerDownEvent e) {
    final ed = _ed;
    if (ed == null) return;
    _ptr[e.pointer] = e.localPosition;
    if (_ptr.length >= 2) {
      // второй палец: мазок отменяется, дальше масштаб и сдвиг
      if (_drawing) {
        ed.cancelStroke();
        _drawing = false;
      }
      _initPinch();
      setState(() {});
      return;
    }
    final pan = e.kind == PointerDeviceKind.mouse && (e.buttons & kMiddleMouseButton != 0 || _space);
    if (pan) {
      _last = e.localPosition;
      return;
    }
    if (_tool == _Tool.pipette) {
      final p = _toImg(e.localPosition);
      final c = ed.colorAt(p.dx.floor(), p.dy.floor());
      if (c != null) {
        ed.removeColor(c.$1, c.$2, c.$3, _colorTol);
        _refresh();
      }
      return;
    }
    _drawing = true;
    final p = _toImg(e.localPosition);
    ed.beginStroke();
    ed.stamp(p.dx, p.dy, _radius, _soft, erase: _tool == _Tool.erase);
    _last = e.localPosition;
    _hover = e.localPosition;
    _refresh();
    setState(() {});
  }

  void _initPinch() {
    final pts = _ptr.values.toList();
    _pinchDist = (pts[0] - pts[1]).distance;
    _pinchMid = (pts[0] + pts[1]) / 2;
  }

  void _move(PointerMoveEvent e) {
    final ed = _ed;
    if (ed == null || !_ptr.containsKey(e.pointer)) return;
    _ptr[e.pointer] = e.localPosition;
    if (_ptr.length >= 2) {
      final pts = _ptr.values.toList();
      final dist = (pts[0] - pts[1]).distance, mid = (pts[0] + pts[1]) / 2;
      if (_pinchDist > 0) _zoomAt(mid, dist / _pinchDist);
      _off += mid - _pinchMid;
      _pinchDist = dist;
      _pinchMid = mid;
      setState(() {});
      return;
    }
    if (_drawing) {
      final a = _toImg(_last!), b = _toImg(e.localPosition);
      ed.line(a.dx, a.dy, b.dx, b.dy, _radius, _soft, erase: _tool == _Tool.erase);
      _last = e.localPosition;
      _hover = e.localPosition;
      _refresh();
      setState(() {});
    } else if (_last != null && e.kind == PointerDeviceKind.mouse) {
      _off += e.localPosition - _last!;
      _last = e.localPosition;
      setState(() {});
    }
  }

  void _up(PointerEvent e) {
    final ed = _ed;
    _ptr.remove(e.pointer);
    if (_ptr.isEmpty) {
      if (_drawing && ed != null) {
        _drawing = false;
        ed.endStroke();
        _refresh();
      }
      _last = null;
    } else if (_ptr.length == 1) {
      _last = null;
    } else {
      _initPinch();
    }
    setState(() {});
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent && _ed != null) {
      _zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15);
      setState(() {});
    }
  }

  // ---------- действия над деталью ----------
  void _undo() {
    _ed?.undo();
    _refresh();
    setState(() {});
  }

  void _redo() {
    _ed?.redo();
    _refresh();
    setState(() {});
  }

  Future<void> _auto() async {
    final ed = _ed;
    if (ed == null) return;
    setState(() => _busy = true);
    final r = await _run(s, autoAlpha, (rgba: ed.rgba, w: ed.w, h: ed.h, tol: s.p.settings.tol));
    if (r.mode == 'alpha') {
      _toast('У картинки уже есть прозрачный фон');
    } else {
      ed.apply(r.alpha);
    }
    if (mounted) setState(() => _busy = false);
    _refresh();
  }

  void _smooth() {
    _ed?.smoothEdge();
    _refresh();
    setState(() {});
  }

  void _restoreAll() {
    final ed = _ed;
    if (ed == null) return;
    ed.apply(Uint8List.fromList(ed.orig));
    _refresh();
    setState(() {});
  }

  Future<bool> _put(int i) async {
    final it = _items[i];
    final ed = await _make(it);
    final res = ed.result();
    if (res == null) return false;
    final png = await _run(s, encodePngRgba, (rgba: res.rgba, w: res.w, h: res.h));
    // исходник детали: вырезанный кусок листа без прозрачности, чтобы можно было вернуть как было
    final orig = await _run(s, encodePngRgba, (rgba: ed.rgba, w: ed.w, h: ed.h));
    final n = _items.where((e) => e.done).length + 1;
    await s.addCutPart(name: '$_baseName $n', png: png, w: res.w, h: res.h, origPng: orig, origW: ed.w, origH: ed.h);
    it.done = true;
    return true;
  }

  Future<void> _toSlot({required bool all}) async {
    setState(() => _busy = true);
    var added = 0;
    try {
      if (all) {
        for (var i = 0; i < _items.length; i++) {
          if (_items[i].on && !_items[i].done && await _put(i)) added++;
        }
      } else if (_cur >= 0 && await _put(_cur)) {
        added = 1;
      } else {
        _toast('Ничего не осталось: деталь стёрта целиком');
      }
    } catch (_) {
      _toast('Не удалось добавить деталь');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (added == 0) return;
    final next = _items.indexWhere((e) => e.on && !e.done);
    if (!all && next >= 0) {
      _toast('Деталь добавлена');
      await _show(next);
    } else {
      _toast(added == 1 ? 'Деталь добавлена' : 'Добавлено деталей: $added');
      setState(() => _cur = -1);
    }
  }

  Future<void> _savePng() async {
    final ed = _ed;
    final res = ed?.result();
    if (ed == null || res == null) return;
    final png = await _run(s, encodePngRgba, (rgba: res.rgba, w: res.w, h: res.h));
    await s.files.saveFile('$_baseName-${_cur + 1}.png', png, 'image/png');
  }

  // ---------- вид ----------
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    final slot = s.p.sel == 'bg' ? 'Фон' : s.slot(s.p.sel).name;
    final who = s.p.sel == 'bg' ? '' : (s.p.gender == 'male' ? ', мужской персонаж' : ', женский персонаж');
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e.logicalKey == LogicalKeyboardKey.space) {
            final down = e is! KeyUpEvent;
            if (down != _space) setState(() => _space = down);
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: c.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              tooltip: 'Назад',
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (_cur >= 0) {
                  setState(() => _cur = -1);
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
            title: Text(_cur >= 0 ? 'Правка детали ${_cur + 1} из ${_items.length}' : 'Вырезалка', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            actions: [
              if (_cur >= 0) ...[
                IconButton(tooltip: 'Назад (Ctrl+Z)', onPressed: (_ed?.canUndo ?? false) ? _undo : null, icon: const Icon(Icons.undo)),
                IconButton(tooltip: 'Вперёд (Ctrl+Y)', onPressed: (_ed?.canRedo ?? false) ? _redo : null, icon: const Icon(Icons.redo)),
              ],
            ],
          ),
          body: SafeArea(
            child: Stack(children: [
              Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Align(alignment: Alignment.centerLeft, child: Text('Деталь пойдёт в слот «$slot»$who', style: TextStyle(fontSize: 12.5, color: c.mut))),
                ),
                Expanded(child: _cur >= 0 ? _editor(c) : _picker(c)),
              ]),
              if (_msg != null)
                Positioned(
                  top: 30,
                  left: 14,
                  right: 14,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(color: c.ink.withValues(alpha: .9), borderRadius: BorderRadius.circular(12)),
                        child: Text(_msg!, style: TextStyle(color: c.bg, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
              if (_busy) Positioned.fill(child: ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator(color: c.accent)))),
            ]),
          ),
        ),
      ),
    );
  }

  // ----- выбор рамок -----
  Widget _picker(SC c) {
    final sh = _sheet;
    if (sh == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.content_cut, size: 42, color: c.accent),
            const SizedBox(height: 12),
            const Text('Загрузите фото или лист с несколькими деталями', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Программа найдёт предметы рамками. Выберите нужные и подправьте вырезку кистью.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: c.mut)),
            const SizedBox(height: 16),
            Btn('Загрузить фото', icon: Icons.file_upload_outlined, primary: true, onTap: _load),
          ]),
        ),
      );
    }
    final n = _items.where((e) => e.on && !e.done).length;
    return Column(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final k = math.min(box.maxWidth / sh.w, box.maxHeight / sh.h);
          final iw = sh.w * k, ih = sh.h * k;
          final ox = (box.maxWidth - iw) / 2, oy = (box.maxHeight - ih) / 2;
          Offset toSheet(Offset p) => Offset((p.dx - ox) / k, (p.dy - oy) / k);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final p = toSheet(d.localPosition);
              // верхняя из рамок под пальцем: меньшая по площади
              int? hit;
              for (var i = 0; i < _items.length; i++) {
                final b = _items[i].box;
                if (p.dx >= b.x0 && p.dx <= b.x1 && p.dy >= b.y0 && p.dy <= b.y1) {
                  if (hit == null || b.w * b.h < _items[hit].box.w * _items[hit].box.h) hit = i;
                }
              }
              setState(() {
                if (hit != null) {
                  _items[hit].on = !_items[hit].on;
                  _active = hit;
                } else {
                  _active = -1;
                }
              });
            },
            onPanStart: (d) {
              final p = toSheet(d.localPosition);
              _dragFrom = p;
              _dragMode = 0;
              if (_active >= 0 && _active < _items.length) {
                final b = _items[_active].box;
                final tol = 22 / k;
                final inX = p.dx >= b.x0 - tol && p.dx <= b.x1 + tol, inY = p.dy >= b.y0 - tol && p.dy <= b.y1 + tol;
                if (inX && inY) {
                  var m = 0;
                  if ((p.dx - b.x0).abs() <= tol) m |= 1;
                  if ((p.dx - b.x1).abs() <= tol) m |= 2;
                  if ((p.dy - b.y0).abs() <= tol) m |= 4;
                  if ((p.dy - b.y1).abs() <= tol) m |= 8;
                  if (m == 0 && p.dx > b.x0 && p.dx < b.x1 && p.dy > b.y0 && p.dy < b.y1) m = 16;
                  if (m != 0) {
                    _dragMode = m;
                    _dragBox = b;
                  }
                }
              }
              setState(() {
                if (_dragMode == 0) _dragA = _dragB = p;
              });
            },
            onPanUpdate: (d) {
              final p = toSheet(d.localPosition);
              setState(() {
                if (_dragMode == 0) {
                  _dragB = p;
                  return;
                }
                final it = _items[_active], b0 = _dragBox!;
                final dx = (p.dx - _dragFrom!.dx).round(), dy = (p.dy - _dragFrom!.dy).round();
                int x0 = b0.x0, x1 = b0.x1, y0 = b0.y0, y1 = b0.y1;
                if (_dragMode == 16) {
                  final mx = dx.clamp(-b0.x0, sh.w - b0.x1), my = dy.clamp(-b0.y0, sh.h - b0.y1);
                  x0 += mx;
                  x1 += mx;
                  y0 += my;
                  y1 += my;
                } else {
                  if (_dragMode & 1 != 0) x0 = (b0.x0 + dx).clamp(0, b0.x1 - 16);
                  if (_dragMode & 2 != 0) x1 = (b0.x1 + dx).clamp(b0.x0 + 16, sh.w);
                  if (_dragMode & 4 != 0) y0 = (b0.y0 + dy).clamp(0, b0.y1 - 16);
                  if (_dragMode & 8 != 0) y1 = (b0.y1 + dy).clamp(b0.y0 + 16, sh.h);
                }
                it.box = Box(x0, y0, x1, y1);
                it.ed = null; // деталь будет вырезана заново по новой рамке
                it.done = false;
              });
            },
            onPanEnd: (_) {
              final a = _dragA, b = _dragB;
              setState(() {
                _dragA = _dragB = null;
                _dragMode = 0;
                _dragBox = null;
                if (a != null && b != null && (a - b).dx.abs() > 12 && (a - b).dy.abs() > 12) {
                  final x0 = math.max(0, math.min(a.dx, b.dx).round()), x1 = math.min(sh.w, math.max(a.dx, b.dx).round());
                  final y0 = math.max(0, math.min(a.dy, b.dy).round()), y1 = math.min(sh.h, math.max(a.dy, b.dy).round());
                  if (x1 - x0 > 8 && y1 - y0 > 8) {
                    _items.add(_Item(Box(x0, y0, x1, y1)));
                    _active = _items.length - 1;
                  }
                }
              });
            },
            child: CustomPaint(
              size: Size(box.maxWidth, box.maxHeight),
              painter: _SheetPainter(sh, _sheetImg, _items, _dragA, _dragB, c.accent, ox, oy, k, _active),
            ),
          );
        }),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        decoration: BoxDecoration(color: c.panel, border: Border(top: BorderSide(color: c.line))),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Btn('Другое фото', small: true, icon: Icons.file_upload_outlined, onTap: _load),
          Btn('Найти заново', small: true, icon: Icons.auto_fix_high, onTap: _detect),
          _stepper('Столбцы', _cols, (v) => setState(() => _cols = v)),
          _stepper('Строки', _rows, (v) => setState(() => _rows = v)),
          Btn('Сетка', small: true, icon: Icons.grid_on, onTap: _grid),
          if (_active >= 0 && _active < _items.length)
            Btn('Удалить рамку ${_active + 1}', small: true, icon: Icons.delete_outline, onTap: () => setState(() {
                  _items.removeAt(_active);
                  _active = -1;
                })),
          Btn('Выбрать все', small: true, onTap: () => setState(() {
                for (final it in _items) {
                  it.on = true;
                }
              })),
          Btn('Все в слот ($n)', small: true, onTap: n == 0 ? null : () => _toSlot(all: true)),
          Btn('Править выбранные ($n)', primary: true, onTap: n == 0 ? null : _openQueue),
        ]),
      ),
      if (_items.isEmpty) const SizedBox.shrink(),
    ]);
  }

  Widget _stepper(String label, int v, ValueChanged<int> on) {
    final c = sc(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 12, color: c.mut)),
      IconButton(visualDensity: VisualDensity.compact, onPressed: v > 1 ? () => on(v - 1) : null, icon: const Icon(Icons.remove, size: 16)),
      Text('$v', style: const TextStyle(fontWeight: FontWeight.w700)),
      IconButton(visualDensity: VisualDensity.compact, onPressed: v < 12 ? () => on(v + 1) : null, icon: const Icon(Icons.add, size: 16)),
    ]);
  }

  // ----- правка -----
  Widget _editor(SC c) {
    final cursorOn = _tool != _Tool.pipette;
    return Column(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          _view = Size(box.maxWidth, box.maxHeight);
          if (!_fitted) _fit();
          return ClipRect(
            child: MouseRegion(
              cursor: cursorOn ? SystemMouseCursors.none : SystemMouseCursors.precise,
              onHover: (e) => setState(() => _hover = e.localPosition),
              onExit: (_) => setState(() => _hover = null),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                onPointerSignal: _signal,
                child: CustomPaint(
                  size: Size(box.maxWidth, box.maxHeight),
                  painter: _EditPainter(_edImg, _scale, _off, _bg, cursorOn && (_hover != null || _drawing) ? _hover : null, _size / 2, c.accent),
                ),
              ),
            ),
          );
        }),
      ),
      _toolbar(c),
    ]);
  }

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> on) => Row(children: [
        SizedBox(width: 74, child: Text(label, style: TextStyle(fontSize: 12, color: sc(context).mut))),
        Expanded(child: Slider(value: v.clamp(min, max).toDouble(), min: min, max: max, onChanged: on)),
        SizedBox(width: 34, child: Text(v.round().toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
      ]);

  void _editFrame() {
    setState(() {
      _active = _cur;
      _cur = -1;
    });
    _toast('Поправьте рамку (ручки по краям) и нажмите «Править выбранные»');
  }

  Future<void> _customColor() async {
    final hex = await pickColor(context);
    if (hex == null) return;
    try {
      final v = int.parse(hex.replaceFirst('#', ''), radix: 16);
      setState(() => _bg = _customBg = Color(0xFF000000 | v));
    } catch (_) {}
  }

  /// Ряд кружков: каким фоном показывать деталь, чтобы увидеть огрехи вырезки.
  Widget _bgRow(SC c) {
    Widget dot(Color? col, String tip, {VoidCallback? onTap, Widget? child, bool sel = false}) => Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: onTap ?? () => setState(() => _bg = col),
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: col ?? const Color(0xFFC4C8D8),
                shape: BoxShape.circle,
                border: Border.all(color: sel ? c.accent : c.line, width: sel ? 3 : 1.5),
              ),
              child: child,
            ),
          ),
        );
    const colors = [
      (Color(0xFFFFFFFF), 'Белый'),
      (Color(0xFF000000), 'Чёрный'),
      (Color(0xFFE53935), 'Красный'),
      (Color(0xFF43A047), 'Зелёный'),
      (Color(0xFF1E88E5), 'Синий'),
      (Color(0xFF9E9E9E), 'Серый'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Text('Фон просмотра', style: TextStyle(fontSize: 12, color: c.mut)),
          const SizedBox(width: 10),
          dot(null, 'Шахматка (прозрачность)', sel: _bg == null, child: const Icon(Icons.grid_4x4, size: 16, color: Colors.white)),
          for (final cl in colors) dot(cl.$1, cl.$2, sel: _bg == cl.$1),
          dot(_customBg, 'Свой цвет', sel: _bg == _customBg && !colors.any((x) => x.$1 == _bg), onTap: _customColor, child: const Icon(Icons.palette_outlined, size: 16, color: Colors.black54)),
        ]),
      ),
    );
  }

  Widget _toolbar(SC c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(color: c.panel, border: Border(top: BorderSide(color: c.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Btn('Стереть', small: true, icon: Icons.auto_fix_normal, on: _tool == _Tool.erase, onTap: () => setState(() => _tool = _Tool.erase)),
          Btn('Вернуть', small: true, icon: Icons.brush, on: _tool == _Tool.restore, onTap: () => setState(() => _tool = _Tool.restore)),
          Btn('Убрать цвет', small: true, icon: Icons.colorize, on: _tool == _Tool.pipette, onTap: () => setState(() => _tool = _Tool.pipette)),
          Btn('Авто фон', small: true, icon: Icons.auto_awesome, onTap: _auto),
          Btn('Сгладить край', small: true, onTap: _smooth),
          Btn('Вернуть всё', small: true, onTap: _restoreAll),
          Btn('Рамка', small: true, icon: Icons.crop_free, onTap: _editFrame),
          Btn('', small: true, icon: Icons.fit_screen, onTap: () => setState(_fit)),
        ]),
        _bgRow(c),
        _slider('Размер', _size, 4, 140, (v) => setState(() => _size = v)),
        _slider('Мягкость', _soft * 100, 0, 100, (v) => setState(() => _soft = v / 100)),
        if (_tool == _Tool.pipette) _slider('Допуск цвета', _colorTol, 2, 80, (v) => setState(() => _colorTol = v)),
        Text(
          _tool == _Tool.pipette
              ? 'Нажмите на цвет, который нужно убрать: он исчезнет по всей детали.'
              : 'Один палец рисует, два пальца двигают и приближают (на компьютере: колесо мыши, пробел или средняя кнопка для сдвига).',
          style: TextStyle(fontSize: 11.5, color: c.mut),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Btn('Сохранить PNG', small: true, icon: Icons.download, onTap: _savePng),
          Btn('Все в слот', small: true, onTap: () => _toSlot(all: true)),
          Btn('В слот', primary: true, small: true, icon: Icons.check, onTap: () => _toSlot(all: false)),
        ]),
      ]),
    );
  }
}

class _SheetPainter extends CustomPainter {
  final Sheet sh;
  final ui.Image? im;
  final List<_Item> items;
  final Offset? da, db;
  final Color accent;
  final double ox, oy, k;
  final int active;
  _SheetPainter(this.sh, this.im, this.items, this.da, this.db, this.accent, this.ox, this.oy, this.k, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    if (im != null) {
      canvas.drawImageRect(im!, Rect.fromLTWH(0, 0, sh.w.toDouble(), sh.h.toDouble()), Rect.fromLTWH(ox, oy, sh.w * k, sh.h * k), Paint()..filterQuality = FilterQuality.medium);
    }
    Rect r(Box b) => Rect.fromLTRB(ox + b.x0 * k, oy + b.y0 * k, ox + b.x1 * k, oy + b.y1 * k);
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final rect = r(it.box);
      final col = it.done ? const Color(0xFF1E9E6A) : (it.on ? accent : Colors.grey);
      canvas.drawRect(rect, Paint()..color = col.withValues(alpha: it.on || it.done ? .14 : .05));
      canvas.drawRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = i == active ? 3.5 : (it.on ? 2.5 : 1.2)..color = col);
      if (i == active) {
        // ручки: углы и середины сторон
        final cx = rect.center.dx, cy = rect.center.dy;
        for (final pt in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight, Offset(cx, rect.top), Offset(cx, rect.bottom), Offset(rect.left, cy), Offset(rect.right, cy)]) {
          canvas.drawRect(Rect.fromCenter(center: pt, width: 12, height: 12), Paint()..color = Colors.white);
          canvas.drawRect(Rect.fromCenter(center: pt, width: 12, height: 12), Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = col);
        }
      }
      final tp = TextPainter(text: TextSpan(text: '${i + 1}', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)), textDirection: TextDirection.ltr)..layout();
      final tag = Rect.fromLTWH(rect.left, rect.top, tp.width + 10, tp.height + 4);
      canvas.drawRRect(RRect.fromRectAndRadius(tag, const Radius.circular(5)), Paint()..color = col);
      tp.paint(canvas, tag.topLeft + const Offset(5, 2));
    }
    if (da != null && db != null) {
      final rect = Rect.fromPoints(Offset(ox + da!.dx * k, oy + da!.dy * k), Offset(ox + db!.dx * k, oy + db!.dy * k));
      canvas.drawRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = accent);
    }
  }

  @override
  bool shouldRepaint(_SheetPainter o) => true;
}

class _EditPainter extends CustomPainter {
  final ui.Image? im;
  final double scale;
  final Offset off;
  final Color? bg;
  final Offset? cursor;
  final double radius;
  final Color accent;
  _EditPainter(this.im, this.scale, this.off, this.bg, this.cursor, this.radius, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    if (bg != null) {
      canvas.drawRect(full, Paint()..color = bg!);
    } else {
      canvas.drawRect(full, Paint()..color = const Color(0xFFFFFFFF));
      final p = Paint()..color = const Color(0xFFC4C8D8);
      const cell = 14.0;
      for (var y = 0; y * cell < size.height; y++) {
        for (var x = 0; x * cell < size.width; x++) {
          if ((x + y).isOdd) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), p);
        }
      }
    }
    if (im != null) {
      final dst = Rect.fromLTWH(off.dx, off.dy, im!.width * scale, im!.height * scale);
      canvas.drawImageRect(im!, Rect.fromLTWH(0, 0, im!.width.toDouble(), im!.height.toDouble()), dst, Paint()..filterQuality = scale < 1 ? FilterQuality.medium : FilterQuality.none);
    }
    if (cursor != null) {
      canvas.drawCircle(cursor!, radius, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.black54);
      canvas.drawCircle(cursor!, radius, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_EditPainter o) => true;
}
