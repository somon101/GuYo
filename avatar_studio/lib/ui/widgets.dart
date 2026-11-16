// Общие элементы интерфейса: карточка, кнопки, переключатели, поле числа.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model.dart';
import '../state/render.dart';
import '../state/studio.dart';
import 'theme.dart';

class CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const CardBox({super.key, required this.child, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding,
      decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
      child: child,
    );
  }
}

class PanelTitle extends StatelessWidget {
  final String text;
  const PanelTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: .9, fontWeight: FontWeight.w700, color: sc(context).mut)),
      );
}

class Note extends StatelessWidget {
  final String text;
  const Note(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 10), child: Text(text, style: TextStyle(fontSize: 12.5, color: sc(context).mut, height: 1.4)));
}

class Btn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary, small, on;
  const Btn(this.label, {super.key, this.icon, this.onTap, this.primary = false, this.small = false, this.on = false});
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    final bg = primary ? c.accent : (on ? c.accent2 : c.panel);
    final fg = primary ? c.onAccent : (on ? c.accent : c.ink);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(small ? 10 : 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(small ? 10 : 12),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14, vertical: small ? 7 : 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(small ? 10 : 12), border: primary ? null : Border.all(color: on ? c.accent : c.line, width: on ? 1.5 : 1)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: small ? 15 : 17, color: fg), if (label.isNotEmpty) const SizedBox(width: 7)],
            if (label.isNotEmpty) Flexible(child: Text(label, style: TextStyle(fontSize: small ? 12.5 : 14, fontWeight: FontWeight.w700, color: fg))),
          ]),
        ),
      ),
    );
  }
}

/// Переключатель из нескольких вариантов. В узком месте подписи сжимаются, а не вылезают.
class Seg<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  const Seg({super.key, required this.items, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return LayoutBuilder(builder: (context, box) {
      final bounded = box.maxWidth.isFinite;
      Widget cell((T, String) it) {
        final on = it.$1 == value;
        final label = Text(it.$2, maxLines: 1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? c.onAccent : c.mut));
        final inner = Container(
          padding: EdgeInsets.symmetric(horizontal: bounded ? 6 : 12, vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? c.accent : Colors.transparent, borderRadius: BorderRadius.circular(99)),
          child: bounded ? FittedBox(fit: BoxFit.scaleDown, child: label) : label,
        );
        final tap = GestureDetector(onTap: () => onChanged(it.$1), behavior: HitTestBehavior.opaque, child: inner);
        return bounded ? Expanded(flex: it.$2.length + 4, child: tap) : tap;
      }

      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(99), border: Border.all(color: c.line)),
        child: Row(mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min, children: [for (final it in items) cell(it)]),
      );
    });
  }
}

/// Числовое поле, которое обновляется снаружи, пока в нём не печатают.
class NumBox extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const NumBox({super.key, required this.value, required this.onChanged});
  @override
  State<NumBox> createState() => _NumBoxState();
}

class _NumBoxState extends State<NumBox> {
  late final TextEditingController ctl = TextEditingController(text: widget.value.round().toString());
  final FocusNode focus = FocusNode();
  @override
  void didUpdateWidget(NumBox old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus) ctl.text = widget.value.round().toString();
  }

  @override
  void dispose() {
    ctl.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return SizedBox(
      width: 74,
      child: TextField(
        controller: ctl,
        focusNode: focus,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9]'))],
        style: const TextStyle(fontSize: 14, fontFeatures: [ui.FontFeature.tabularFigures()]),
        decoration: InputDecoration(isDense: true, filled: true, fillColor: c.panel2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9)),
        onChanged: (t) {
          final v = double.tryParse(t);
          if (v != null) widget.onChanged(v);
        },
      ),
    );
  }
}

class SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const SliderRow({super.key, required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        SizedBox(width: 76, child: Text(label, style: TextStyle(fontSize: 12.5, color: c.mut))),
        Expanded(child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged)),
        NumBox(value: value, onChanged: onChanged),
      ]),
    );
  }
}

/// Поле с названием: сохраняет по ходу ввода.
class NameField extends StatefulWidget {
  final String value, hint;
  final ValueChanged<String> onChanged;
  final bool center;
  const NameField({super.key, required this.value, required this.onChanged, this.hint = '', this.center = false});
  @override
  State<NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<NameField> {
  late final TextEditingController ctl = TextEditingController(text: widget.value);
  final FocusNode focus = FocusNode();
  @override
  void didUpdateWidget(NameField old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && ctl.text != widget.value) ctl.text = widget.value;
  }

  @override
  void dispose() {
    ctl.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return TextField(
      controller: ctl,
      focusNode: focus,
      textAlign: widget.center ? TextAlign.center : TextAlign.start,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(isDense: true, filled: true, fillColor: c.panel2, hintText: widget.hint, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
      onChanged: widget.onChanged,
    );
  }
}

/// Картинка детали или образец цвета.
class PartThumb extends StatelessWidget {
  final Studio s;
  final Part? part;
  final BoxFit fit;
  const PartThumb(this.s, this.part, {super.key, this.fit = BoxFit.contain});
  @override
  Widget build(BuildContext context) {
    final p = part;
    if (p == null) return const SizedBox.shrink();
    if (p.kind == 'solid') return ColoredBox(color: parseHex(p.c1));
    if (p.kind == 'grad') return DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [parseHex(p.c1), parseHex(p.c2)])));
    final im = s.imageOf(p);
    if (im == null) return const SizedBox.shrink();
    return RawImage(image: im, fit: fit, filterQuality: FilterQuality.medium);
  }
}

/// Круг (или скруглённый квадрат) профиля: фон, персонаж и кадр.
class ProfileView extends StatelessWidget {
  final Studio s;
  final ViewSpec? spec;
  final double px;
  final String? shape;
  const ProfileView(this.s, {super.key, this.spec, required this.px, this.shape});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (_, _) {
          final v0 = spec ?? s.view;
          final v = shape == null ? v0 : ViewSpec(v0.setId, v0.gender, v0.pick, v0.hide, v0.frame.copy()..shape = shape!);
          return CustomPaint(size: Size(px, px), painter: _ProfilePainter(s, v, px));
        },
      );
}

class _ProfilePainter extends CustomPainter {
  final Studio s;
  final ViewSpec v;
  final double px;
  _ProfilePainter(this.s, this.v, this.px);
  @override
  void paint(Canvas canvas, Size size) => paintProfile(canvas, s, v, px);
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
