// Сцена: собранный аватар, перетаскивание слота, указание точки и кадр профиля.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/geometry.dart';
import '../state/render.dart';
import '../state/studio.dart';
import 'theme.dart';

class StageXf {
  final Size size;
  late final double k, ox, oy;
  StageXf(this.size) {
    k = (size.width / canvasW < size.height / canvasH ? size.width / canvasW : size.height / canvasH) * 0.96;
    ox = (size.width - canvasW * k) / 2;
    oy = (size.height - canvasH * k) / 2;
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
  Offset? hover;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final c = sc(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(color: c.stage, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(22)),
        child: LayoutBuilder(builder: (ctx, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          final xf = StageXf(size);
          return MouseRegion(
            cursor: s.frameTool || s.placing ? SystemMouseCursors.precise : SystemMouseCursors.grab,
            onHover: (e) => setState(() => hover = xf.toCanvas(e.localPosition)),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                if (s.placing && s.p.sel != 'bg') {
                  final p = xf.toCanvas(d.localPosition);
                  s.placing = false;
                  s.setGeo(x: p.dx, y: p.dy);
                }
              },
              onPanStart: (d) {
                final p = xf.toCanvas(d.localPosition);
                if (s.frameTool) {
                  _frameDrag = true;
                  _grab = Offset(s.p.frame.x - p.dx, s.p.frame.y - p.dy);
                } else if (s.p.sel != 'bg') {
                  final g = s.geoOf(s.p.sel);
                  _frameDrag = false;
                  _grab = Offset(g.x - p.dx, g.y - p.dy);
                }
              },
              onPanUpdate: (d) {
                final grab = _grab;
                if (grab == null) return;
                final p = xf.toCanvas(d.localPosition);
                if (_frameDrag) {
                  s.setFrame(x: p.dx + grab.dx, y: p.dy + grab.dy);
                } else {
                  s.setGeo(x: p.dx + grab.dx, y: p.dy + grab.dy);
                }
              },
              onPanEnd: (_) => _grab = null,
              child: ListenableBuilder(
                listenable: s,
                builder: (_, _) => Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _StagePainter(s, xf, c))),
                  if (!s.hasAnyPart)
                    Center(child: Padding(padding: const EdgeInsets.all(30), child: Text('Макет пустой\nВыберите слот и загрузите первую деталь.', textAlign: TextAlign.center, style: TextStyle(color: c.mut, fontSize: 15, height: 1.5)))),
                  Positioned(left: 12, right: 12, bottom: 10, child: IgnorePointer(child: Row(children: [_chip(c, _info(s)), const Spacer(), _chip(c, hover == null ? 'x —  y —' : 'x ${hover!.dx.round()}  y ${hover!.dy.round()}')]))),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  String _info(Studio s) {
    if (s.frameTool) return 'Кадр профиля · x ${s.p.frame.x.round()} · y ${s.p.frame.y.round()} · ${s.p.frame.size.round()}';
    if (s.p.sel == 'bg') return 'Фон';
    final g = s.geoOf(s.p.sel);
    return '${s.slot(s.p.sel).name} · x ${g.x.round()} · y ${g.y.round()} · ${(g.s * 100).round()}%';
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
      final g = s.geoOf(s.p.sel);
      final r = s.rectFor(s.p.sel);
      if (r != null) canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = c.accent);
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
