// Сцена: собранный аватар, перетаскивание слота, указание точки и кадр профиля.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/geometry.dart';
import '../state/render.dart';
import '../state/studio.dart';
import 'theme.dart';
import 'widgets.dart';

class StageXf {
  final Size size;
  final double zoom;
  final Offset pan;
  late final double k0, k, ox, oy;
  StageXf(this.size, {this.zoom = 1, this.pan = Offset.zero}) {
    k0 = (size.width / canvasW < size.height / canvasH ? size.width / canvasW : size.height / canvasH) * 0.96;
    k = k0 * zoom;
    ox = (size.width - canvasW * k) / 2 + pan.dx;
    oy = (size.height - canvasH * k) / 2 + pan.dy;
  }
  Offset toCanvas(Offset o) => Offset((o.dx - ox) / k, (o.dy - oy) / k);
}

class StageView extends StatefulWidget {
  final Studio s;
  const StageView(this.s, {super.key});
  @override
  State<StageView> createState() => _StageViewState();
}

class _StageViewState extends State<StageView> {
  Offset? _grab;
  bool _frameDrag = false;
  Offset? hover; // точка холста под мышью
  Offset? _hoverPx; // она же в пикселях экрана (для круга кисти)
  final _ptr = <int, Offset>{};
  bool _stroke = false, _panning = false, _moved = false;
  Offset? _down, _lastPx;
  double _pinchDist = 0;
  Offset _pinchMid = Offset.zero;
  bool _space = false;
  Size _size = Size.zero;

  Studio get s => widget.s;
  StageXf get _xf => StageXf(_size, zoom: s.stageZoom, pan: s.stagePan);

  /// Приближение к точке экрана f: точка холста под ней остаётся на месте.
  void _zoomAt(Offset f, double factor) {
    final xf = _xf;
    final p = xf.toCanvas(f);
    final z = (s.stageZoom * factor).clamp(0.6, 16.0).toDouble();
    final k = xf.k0 * z;
    s.stageZoom = z;
    s.stagePan = Offset(f.dx - p.dx * k - (_size.width - canvasW * k) / 2, f.dy - p.dy * k - (_size.height - canvasH * k) / 2);
  }

  /// Точка экрана → пиксель картинки выбранной детали.
  Offset? _toPart(Offset screen) {
    final ed = s.partEdit;
    final r = s.rectFor(s.p.sel);
    if (ed == null || r == null) return null;
    return canvasToPart(_xf.toCanvas(screen), r, s.geoOf(s.p.sel), ed.w, ed.h);
  }

  /// Радиус кисти в пикселях картинки: размер задан в пикселях экрана, поэтому при приближении кисть тоньше.
  double get _brushR {
    final ed = s.partEdit, r = s.rectFor(s.p.sel);
    if (ed == null || r == null) return 1;
    return (s.brushSize / 2) / _xf.k * (ed.w / r.width);
  }

  void _initPinch() {
    final pts = _ptr.values.toList();
    _pinchDist = (pts[0] - pts[1]).distance;
    _pinchMid = (pts[0] + pts[1]) / 2;
  }

  void _down0(PointerDownEvent e) {
    _ptr[e.pointer] = e.localPosition;
    _moved = false;
    if (_ptr.length >= 2) {
      if (_stroke) {
        s.partEdit?.cancelStroke();
        s.touchPartEdit();
        _stroke = false;
      }
      _grab = null;
      _panning = false;
      _initPinch();
      return;
    }
    _down = e.localPosition;
    _lastPx = e.localPosition;
    final mousePan = e.kind == PointerDeviceKind.mouse && (e.buttons & kMiddleMouseButton != 0 || _space);
    if (mousePan) {
      _panning = true;
      return;
    }
    if (s.painting) {
      final ed = s.partEdit!, pt = _toPart(e.localPosition);
      if (pt != null) {
        _stroke = true;
        ed.beginStroke();
        ed.stamp(pt.dx, pt.dy, _brushR, s.brushSoft, erase: s.brushErase);
        s.touchPartEdit();
      }
      return;
    }
    final p = _xf.toCanvas(e.localPosition);
    if (s.frameTool) {
      _frameDrag = true;
      _grab = Offset(s.p.frame.x - p.dx, s.p.frame.y - p.dy);
    } else if (s.p.sel != 'bg') {
      final g = s.editGeoRead;
      _frameDrag = false;
      _grab = Offset(g.x - p.dx, g.y - p.dy);
    }
  }

  void _move0(PointerMoveEvent e) {
    if (!_ptr.containsKey(e.pointer)) return;
    _ptr[e.pointer] = e.localPosition;
    if (_ptr.length >= 2) {
      final pts = _ptr.values.toList();
      final dist = (pts[0] - pts[1]).distance, mid = (pts[0] + pts[1]) / 2;
      if (_pinchDist > 0) _zoomAt(mid, dist / _pinchDist);
      s.stagePan += mid - _pinchMid;
      _pinchDist = dist;
      _pinchMid = mid;
      s.resetNotify();
      return;
    }
    if (_down != null && (e.localPosition - _down!).distance > 6) _moved = true;
    _hoverPx = e.localPosition;
    if (_panning) {
      s.stagePan += e.localPosition - _lastPx!;
      _lastPx = e.localPosition;
      s.resetNotify();
      return;
    }
    if (_stroke) {
      final a = _toPart(_lastPx!), b = _toPart(e.localPosition);
      if (a != null && b != null) {
        s.partEdit!.line(a.dx, a.dy, b.dx, b.dy, _brushR, s.brushSoft, erase: s.brushErase);
        s.touchPartEdit();
      }
      _lastPx = e.localPosition;
      return;
    }
    final grab = _grab;
    if (grab == null || !_moved) return;
    final p = _xf.toCanvas(e.localPosition);
    if (_frameDrag) {
      s.setFrame(x: p.dx + grab.dx, y: p.dy + grab.dy);
    } else {
      s.setGeo(x: p.dx + grab.dx, y: p.dy + grab.dy);
    }
  }

  void _up0(PointerEvent e) {
    _ptr.remove(e.pointer);
    if (_ptr.isEmpty) {
      if (_stroke) {
        s.partEdit?.endStroke();
        s.touchPartEdit();
      } else if (!_moved && s.placing && s.p.sel != 'bg' && _down != null) {
        final p = _xf.toCanvas(_down!);
        s.placing = false;
        s.setGeo(x: p.dx, y: p.dy);
      }
      _stroke = false;
      _panning = false;
      _grab = null;
    } else if (_ptr.length == 1) {
      _grab = null;
      _lastPx = _ptr.values.first;
    } else {
      _initPinch();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(color: c.stage, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(22)),
        child: LayoutBuilder(builder: (ctx, box) {
          _size = Size(box.maxWidth, box.maxHeight);
          return ListenableBuilder(
            listenable: s,
            builder: (_, _) {
              final xf = StageXf(_size, zoom: s.stageZoom, pan: s.stagePan);
              // выбрали другой слой или деталь во время правки кистью: правка сохраняется
              if (s.painting && (s.p.sel != s.editSlot || s.partOf(s.p.sel)?.id != s.editPartId)) {
                WidgetsBinding.instance.addPostFrameCallback((_) => s.commitPartEdit());
              }
              return Focus(
                onKeyEvent: (_, e) {
                  if (e.logicalKey == LogicalKeyboardKey.space) _space = e is! KeyUpEvent;
                  return KeyEventResult.ignored;
                },
                child: MouseRegion(
                  cursor: s.painting ? SystemMouseCursors.none : (s.frameTool || s.placing ? SystemMouseCursors.precise : SystemMouseCursors.grab),
                  onHover: (e) => setState(() {
                    hover = xf.toCanvas(e.localPosition);
                    _hoverPx = e.localPosition;
                  }),
                  onExit: (_) => setState(() => _hoverPx = null),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _down0,
                    onPointerMove: _move0,
                    onPointerUp: _up0,
                    onPointerCancel: _up0,
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) {
                        _zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15);
                        s.resetNotify();
                      }
                    },
                    child: Stack(children: [
                      Positioned.fill(child: CustomPaint(painter: _StagePainter(s, xf, c))),
                      if (s.painting && _hoverPx != null)
                        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _BrushCursor(_hoverPx!, s.brushSize / 2)))),
                      if (!s.hasAnyPart)
                        Center(child: Padding(padding: const EdgeInsets.all(30), child: Text('Макет пустой\nВыберите слот и загрузите первую деталь.', textAlign: TextAlign.center, style: TextStyle(color: c.mut, fontSize: 15, height: 1.5)))),
                      if (s.painting)
                        Positioned(left: 10, right: 10, bottom: 10, child: _BrushPanel(s))
                      else
                        Positioned(left: 12, right: 12, bottom: 10, child: IgnorePointer(child: Row(children: [_chip(c, _info(s)), const Spacer(), _chip(c, '${s.stageZoom == 1 ? '' : '×${s.stageZoom.toStringAsFixed(1)}  '}${hover == null ? 'x —  y —' : 'x ${hover!.dx.round()}  y ${hover!.dy.round()}'}')]))),
                    ]),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }

  String _info(Studio s) {
    if (s.frameTool) return 'Кадр профиля · x ${s.p.frame.x.round()} · y ${s.p.frame.y.round()} · ${s.p.frame.size.round()}';
    if (s.p.sel == 'bg') return 'Фон';
    final g = s.editGeoRead;
    return '${s.slot(s.p.sel).name}${s.editingPart ? ' (деталь)' : ''} · x ${g.x.round()} · y ${g.y.round()} · ширина ${g.w.round()}${g.r == 0 ? '' : ' · поворот ${g.r.round()}°'}';
  }

  Widget _chip(SC c, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(99), border: Border.all(color: c.line)),
        child: Text(t, style: TextStyle(fontSize: 12, color: c.mut, fontFeatures: const [ui.FontFeature.tabularFigures()])),
      );
}

ui.Image? _checker;
ui.Image _checkerImage(SC c) {
  if (_checker != null) return _checker!;
  final rec = ui.PictureRecorder();
  final cv = Canvas(rec);
  cv.drawRect(const Rect.fromLTWH(0, 0, 28, 28), Paint()..color = c.stage);
  final p = Paint()..color = c.grid;
  cv.drawRect(const Rect.fromLTWH(0, 0, 14, 14), p);
  cv.drawRect(const Rect.fromLTWH(14, 14, 14, 14), p);
  _checker = rec.endRecording().toImageSync(28, 28);
  return _checker!;
}

class _StagePainter extends CustomPainter {
  final Studio s;
  final StageXf xf;
  final SC c;
  _StagePainter(this.s, this.xf, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    // клетчатая подложка показывает прозрачность
    canvas.drawRect(Offset.zero & size, Paint()..shader = ImageShader(_checkerImage(c), TileMode.repeated, TileMode.repeated, Matrix4.identity().storage));
    final v = s.view;
    final bg = s.partOf('bg', v);
    if (bg != null && s.visOf('bg', v) && bg.kind != 'img') {
      // сплошной фон закрывает всю сцену, без полос по краям
      final inv = Rect.fromLTWH(-xf.ox / xf.k, -xf.oy / xf.k, size.width / xf.k, size.height / xf.k);
      canvas.save();
      canvas.translate(xf.ox, xf.oy);
      canvas.scale(xf.k);
      paintBg(canvas, s, v, inv);
      canvas.restore();
    }
    canvas.save();
    canvas.translate(xf.ox, xf.oy);
    canvas.scale(xf.k);
    if (bg != null && s.visOf('bg', v) && bg.kind == 'img') paintBg(canvas, s, v, const Rect.fromLTWH(0, 0, canvasW, canvasH));
    paintLayers(canvas, s, v);
    // пустые слоты: пунктирный кружок и название
    for (final id in s.p.order) {
      if (id == 'bg' || !s.visOf(id) || s.partOf(id) != null) continue;
      final g = s.geoOf(id);
      final col = c.mut.withValues(alpha: id == s.p.sel ? 1 : .5);
      canvas.drawCircle(Offset(g.x, g.y), 36, Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = col);
      final tp = TextPainter(text: TextSpan(text: s.slot(id).name, style: TextStyle(fontSize: 30, color: col)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(g.x - tp.width / 2, g.y + 50));
    }
    if (s.frameTool) {
      final f = frameRect(s.p.frame);
      final big = Rect.fromLTWH(-4000, -4000, 9000, 9000);
      final hole = shapePath(f, s.p.frame.shape);
      canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(big), hole), Paint()..color = const Color(0x800A0E28));
      canvas.drawPath(hole, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = Colors.white);
    } else if (s.p.sel != 'bg') {
      final g = s.editGeoRead;
      final r = s.rectFor(s.p.sel);
      if (r != null) {
        canvas.save();
        canvas.translate(g.x, g.y);
        canvas.rotate(g.r * math.pi / 180);
        canvas.translate(-g.x, -g.y);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = c.accent);
        canvas.restore();
      }
      canvas.drawCircle(Offset(g.x, g.y), 18, Paint()..color = c.panel);
      final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round..color = c.accent;
      canvas.drawCircle(Offset(g.x, g.y), 18, line);
      canvas.drawLine(Offset(g.x - 36, g.y), Offset(g.x + 36, g.y), line);
      canvas.drawLine(Offset(g.x, g.y - 36), Offset(g.x, g.y + 36), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}


class _BrushCursor extends CustomPainter {
  final Offset at;
  final double r;
  _BrushCursor(this.at, this.r);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(at, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.black54);
    canvas.drawCircle(at, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white);
  }

  @override
  bool shouldRepaint(_BrushCursor o) => o.at != at || o.r != r;
}

/// Панель кисти на сцене: что делаем, размер, мягкость, готово.
class _BrushPanel extends StatelessWidget {
  final Studio s;
  const _BrushPanel(this.s);

  Widget _slider(BuildContext context, String label, double v, double min, double max, ValueChanged<double> on) => Row(children: [
        SizedBox(width: 66, child: Text(label, style: TextStyle(fontSize: 12, color: sc(context).mut))),
        Expanded(child: SizedBox(height: 28, child: Slider(value: v.clamp(min, max).toDouble(), min: min, max: max, onChanged: on))),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: c.panel.withValues(alpha: .96), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Btn('Стереть', small: true, icon: Icons.auto_fix_normal, on: s.brushErase, onTap: () {
            s.brushErase = true;
            s.resetNotify();
          }),
          Btn('Вернуть', small: true, icon: Icons.brush, on: !s.brushErase, onTap: () {
            s.brushErase = false;
            s.resetNotify();
          }),
          Btn('Отмена', small: true, onTap: s.cancelPartEdit),
          Btn('Готово', small: true, primary: true, icon: Icons.check, onTap: s.commitPartEdit),
        ]),
        _slider(context, 'Размер', s.brushSize, 4, 140, (v) {
          s.brushSize = v;
          s.resetNotify();
        }),
        _slider(context, 'Мягкость', s.brushSoft * 100, 0, 100, (v) {
          s.brushSoft = v / 100;
          s.resetNotify();
        }),
        Text('Кисть правит слой «${s.slot(s.p.sel).name}». Приближайте двумя пальцами для точной правки.', style: TextStyle(fontSize: 11, color: c.mut)),
      ]),
    );
  }
}
