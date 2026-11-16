// Окна: выбор режима фона при загрузке, цвет, просмотр в профиле, сравнение аватарок.
import 'package:flutter/material.dart';

import '../state/render.dart';
import '../state/studio.dart';
import 'theme.dart';
import 'widgets.dart';

class BgChoice {
  final bool cut, remember;
  const BgChoice(this.cut, this.remember);
}

/// Спрашивает, что сделать с фоном загружаемых картинок: вырезать автоматически или оставить как есть.
Future<BgChoice?> askBgMode(BuildContext context, int count) {
  return showDialog<BgChoice>(
    context: context,
    builder: (ctx) {
      var remember = false;
      return StatefulBuilder(builder: (ctx, setS) {
        final c = sc(ctx);
        Widget option(IconData icon, String title, String sub, bool cut, {bool primary = false}) => InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.pop(ctx, BgChoice(cut, remember)),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: primary ? c.accent2 : c.panel2, borderRadius: BorderRadius.circular(16), border: Border.all(color: primary ? c.accent : c.line, width: primary ? 1.5 : 1)),
                child: Row(children: [
                  Icon(icon, color: primary ? c.accent : c.mut, size: 26),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(height: 2), Text(sub, style: TextStyle(fontSize: 12.5, color: c.mut, height: 1.35))])),
                ]),
              ),
            );
        return Dialog(
          backgroundColor: c.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(count == 1 ? 'Что сделать с фоном картинки?' : 'Что сделать с фоном картинок ($count)?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                option(Icons.auto_fix_high, 'Вырезать фон автоматически', 'Подходит для чёрного, белого, «шахматного» и однотонного фона. Исходник сохраняется, потом можно вернуть.', true, primary: true),
                const SizedBox(height: 10),
                option(Icons.image_outlined, 'Оставить как есть', 'Картинка не меняется. Выбирайте, если вы уже вырезали фон сами.', false),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: remember,
                  onChanged: (v) => setS(() => remember = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text('Запомнить мой выбор', style: TextStyle(fontSize: 13, color: c.mut)),
                ),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена', style: TextStyle(color: c.mut, fontWeight: FontWeight.w700)))),
              ]),
            ),
          ),
        );
      });
    },
  );
}

const _swatches = [
  '#FFD0E2', '#FFB36B', '#FFE7A8', '#CDEFDD', '#8BDCFF', '#C9C6FF', '#FF6FA1', '#F2C94C', '#6FCF97', '#56CCF2', '#5560E0', '#BB6BD9',
  '#FFFFFF', '#E0E0E0', '#9AA3C0', '#4F4F4F', '#343B7A', '#12152A',
];

Future<String?> pickColor(BuildContext context) {
  final hex = TextEditingController(text: '#FFD0E2');
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = sc(ctx);
      return Dialog(
        backgroundColor: c.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Свой цвет фона', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final h in _swatches)
                  InkWell(onTap: () => Navigator.pop(ctx, h), customBorder: const CircleBorder(), child: Container(width: 40, height: 40, decoration: BoxDecoration(color: parseHex(h), shape: BoxShape.circle, border: Border.all(color: c.line, width: 1.5)))),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(controller: hex, decoration: InputDecoration(isDense: true, filled: true, fillColor: c.panel2, labelText: 'Код цвета, например #FFD0E2', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
                const SizedBox(width: 8),
                Btn('Добавить', primary: true, onTap: () {
                  final t = hex.text.trim();
                  if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(t)) Navigator.pop(ctx, t.toUpperCase());
                }),
              ]),
            ]),
          ),
        ),
      );
    },
  );
}

Future<void> showProfileDialog(BuildContext context, Studio s) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: sc(ctx).panel,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: _ProfileBody(s))),
    ),
  );
}

class _ProfileBody extends StatelessWidget {
  final Studio s;
  const _ProfileBody(this.s);
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        Widget card(String title, Widget child) => Container(
              padding: const EdgeInsets.all(14),
              width: double.infinity,
              decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: .8, fontWeight: FontWeight.w700, color: c.mut)), const SizedBox(height: 10), child]),
            );
        Widget who(String name, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.w700)), Text(sub, style: TextStyle(fontSize: 12.5, color: c.mut))]);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Как это выглядит в профиле', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            Seg<String>(items: const [('circle', 'Круг'), ('round', 'Скруглённый')], value: s.p.frame.shape, onChanged: (v) => s.setFrame(shape: v)),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 12),
          card('Шапка профиля', Wrap(spacing: 18, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [ProfileView(s, px: 200), who('Алишер', 'Уровень 12 · Серия 34 дня')])),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 300, child: card('Рейтинг', Row(children: [ProfileView(s, px: 48), const SizedBox(width: 12), Expanded(child: who('Алишер', '1 240 XP')), const Text('3', style: TextStyle(fontWeight: FontWeight.w800))]))),
            SizedBox(width: 300, child: card('Дуэль и чат', Row(crossAxisAlignment: CrossAxisAlignment.end, children: [ProfileView(s, px: 36), const SizedBox(width: 10), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: c.accent2, borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14), bottomRight: Radius.circular(14), bottomLeft: Radius.circular(4))), child: const Text('Готов к дуэли?'))]))),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Btn('Скачать картинку профиля', primary: true, onTap: () async => s.files.saveFile('profile.png', await s.profilePng(), 'image/png')),
            const SizedBox(width: 8),
            Btn('Закрыть', onTap: () => Navigator.pop(context)),
          ]),
          const Note('Показано то, что сохранено: фон, персонаж и выбранный кадр. Меняйте кадр и слоты, окно обновляется сразу.'),
        ]);
      },
    );
  }
}

Future<void> showCompareDialog(BuildContext context, Studio s) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final c = sc(ctx);
      return Dialog(
        backgroundColor: c.panel,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ListenableBuilder(
              listenable: s,
              builder: (_, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Expanded(child: Text('Сравнение аватарок', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  Seg<String>(items: const [('circle', 'Круг'), ('round', 'Скруглённый')], value: s.p.frame.shape, onChanged: (v) => s.setFrame(shape: v)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 14),
                Wrap(spacing: 14, runSpacing: 14, children: [
                  for (final l in s.p.looks)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.pop(ctx);
                        s.applyLook(l);
                      },
                      child: Container(
                        width: 160,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
                        child: Column(children: [ProfileView(s, spec: s.viewOfLook(l), px: 128, shape: s.p.frame.shape), const SizedBox(height: 10), Text(l.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))]),
                      ),
                    ),
                ]),
                const Note('Нажмите на аватарку, чтобы открыть её в редакторе.'),
              ]),
            ),
          ),
        ),
      );
    },
  );
}
