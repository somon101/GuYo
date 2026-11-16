// Панели: наборы, слоты, детали, положение, кадр, аватарки, проект.
import 'package:flutter/material.dart';

import '../core/model.dart';
import '../state/studio.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class SetsPanel extends StatelessWidget {
  final Studio s;
  const SetsPanel(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return CardBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PanelTitle('Наборы'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in s.p.sets) _SetChip(label: x.name, on: x.id == s.p.cur, onTap: () => s.selectSet(x.id)),
          _SetChip(label: '+ Набор', add: true, onTap: s.addSet),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: NameField(key: ValueKey('set-${s.p.cur}'), value: s.curSet.name, onChanged: s.renameSet)),
          const SizedBox(width: 8),
          TextButton(onPressed: s.deleteSet, child: Text('Удалить', style: TextStyle(color: c.mut, fontWeight: FontWeight.w700))),
        ]),
        const Note('Набор это комплект деталей: одежда, лица, волосы, очки, фоны. Положение слотов по умолчанию общее, поэтому деталь из другого набора встаёт на то же место.'),
        const SizedBox(height: 10),
        Btn('Загрузить набор деталей', icon: Icons.folder_open_outlined, onTap: () async {
          final files = await s.files.pickImages();
          if (files.isEmpty) return;
          final n = await s.importPack(files);
          s.message('Добавлено деталей: $n');
        }),
        const Note('Выберите много файлов сразу. Если имя файла вида «слот__пол__название.png», деталь сама встанет в нужный слот и для нужного пола.'),
      ]),
    );
  }
}

class _SetChip extends StatelessWidget {
  final String label;
  final bool on, add;
  final VoidCallback onTap;
  const _SetChip({required this.label, this.on = false, this.add = false, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(color: on ? c.accent : (add ? Colors.transparent : c.panel2), borderRadius: BorderRadius.circular(10), border: add ? Border.all(color: c.line) : null),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: on ? c.onAccent : (add ? c.mut : c.ink))),
      ),
    );
  }
}

class SlotsPanel extends StatefulWidget {
  final Studio s;
  final VoidCallback? onPicked;
  const SlotsPanel(this.s, {super.key, this.onPicked});
  @override
  State<SlotsPanel> createState() => _SlotsPanelState();
}

class _SlotsPanelState extends State<SlotsPanel> {
  final ctl = TextEditingController();
  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final c = sc(context);
    return CardBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PanelTitle('Слоты, снизу вверх'),
        for (final id in s.p.order.reversed) _SlotRow(s, id, widget.onPicked),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: ctl,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(isDense: true, filled: true, fillColor: c.panel2, hintText: 'Новый слот, например «Шапка»', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11)),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          Btn('Добавить', onTap: _add),
        ]),
      ]),
    );
  }

  void _add() {
    widget.s.addSlot(ctl.text);
    ctl.clear();
  }
}

class _SlotRow extends StatelessWidget {
  final Studio s;
  final String id;
  final VoidCallback? onPicked;
  const _SlotRow(this.s, this.id, this.onPicked);
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    final sl = s.slot(id), part = s.partOf(id), g = s.slotGeo(id), on = id == s.p.sel;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        s.select(id);
        onPicked?.call();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: on ? c.accent2 : Colors.transparent, borderRadius: BorderRadius.circular(14), border: on ? Border.all(color: c.accent, width: 1.5) : null),
        child: Row(children: [
          if (id == 'bg')
            const SizedBox(width: 24)
          else
            Column(mainAxisSize: MainAxisSize.min, children: [
              _Arrow(Icons.keyboard_arrow_up, () => s.moveSlot(id, 1), c),
              _Arrow(Icons.keyboard_arrow_down, () => s.moveSlot(id, -1), c),
            ]),
          const SizedBox(width: 6),
          Container(
            width: 44,
            height: 44,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: part == null ? null : c.stage, borderRadius: BorderRadius.circular(11), border: part == null ? Border.all(color: c.line, width: 1.5) : null),
            child: part == null ? Icon(Icons.add, size: 18, color: c.mut) : Padding(padding: EdgeInsets.all(part.isImage && id != 'bg' ? 2 : 0), child: PartThumb(s, part, fit: id == 'bg' ? BoxFit.cover : BoxFit.contain)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sl.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(part == null ? 'пусто, загрузите деталь' : part.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.mut)),
            ]),
          ),
          if (sl.custom) IconButton(onPressed: () => s.removeSlot(id), icon: Icon(Icons.close, size: 18, color: c.mut), tooltip: 'Удалить слот', visualDensity: VisualDensity.compact),
          IconButton(onPressed: () => s.toggleVis(id), icon: Icon(g.vis ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: g.vis ? c.accent : c.mut), tooltip: 'Показать или скрыть'),
        ]),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final SC c;
  const _Arrow(this.icon, this.onTap, this.c);
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, child: Icon(icon, size: 16, color: c.mut));
}

class PartsPanel extends StatelessWidget {
  final Studio s;
  /// Нажали «Править положение детали»: на телефоне переключает на вкладку «Положение».
  final VoidCallback? onEdit;
  const PartsPanel(this.s, {super.key, this.onEdit});

  Future<void> _upload(BuildContext context) async {
    final files = await s.files.pickImages();
    if (files.isEmpty) return;
    var cut = false;
    if (s.p.sel != 'bg') {
      final mode = s.p.settings.removeMode;
      if (mode == 'ask') {
        if (!context.mounted) return;
        final r = await askBgMode(context, files.length);
        if (r == null) return;
        cut = r.cut;
        if (r.remember) {
          s.p.settings.removeMode = r.cut ? 'cut' : 'keep';
          s.changed();
        }
      } else {
        cut = mode == 'cut';
      }
    }
    await s.addImages(files, cut: cut);
  }

  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    final id = s.p.sel, isBg = id == 'bg';
    final arr = s.partsOf(id);
    final hidden = (s.curSet.parts[id] ?? const <Part>[]).length - arr.length;
    final cur = s.partOf(id);
    final character = s.p.gender == 'male' ? 'мужского' : 'женского';
    final upload = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _upload(context),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.accent, width: 1.5)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.file_upload_outlined, color: c.accent, size: 22), Text(isBg ? 'Фото' : 'Загрузить', style: TextStyle(color: c.accent, fontWeight: FontWeight.w700, fontSize: 11.5))]),
      ),
    );
    final tiles = <Widget>[
      for (final p in arr) _PartTile(s: s, part: p, on: cur?.id == p.id, slotId: id, cover: isBg),
      upload,
    ];
    return CardBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PanelTitle(isBg ? 'Фон профиля' : 'Детали слота «${s.slot(id).name}»'),
        GridView.count(crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, children: tiles),
        if (isBg) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Btn('Добавить готовые цвета', small: true, onTap: s.addPresetBackgrounds)),
            const SizedBox(width: 8),
            Btn('Свой цвет', small: true, icon: Icons.palette_outlined, onTap: () async {
              final col = await pickColor(context);
              if (col != null) s.addColor(col);
            }),
          ]),
          const Note('Фон виден за персонажем и внутри круга профиля. Фото можно приблизить и сдвинуть в блоке «Положение».'),
        ] else ...[
          Note(arr.isEmpty
              ? 'Для $character персонажа в слоте пока нет деталей. Загрузите картинки: они появятся здесь как варианты.'
              : 'Показаны детали $character персонажа и те, что отмечены «Оба».${hidden > 0 ? ' Скрыто деталей другого пола: $hidden.' : ''}'),
          if (cur != null && cur.isImage) ...[
            const SizedBox(height: 12),
            Text('Деталь «${cur.name}» подходит для', style: TextStyle(fontSize: 12.5, color: c.mut)),
            const SizedBox(height: 6),
            Seg<String>(items: const [('male', 'Мужского'), ('female', 'Женского'), ('both', 'Обоих')], value: cur.gender, onChanged: (v) => s.setPartGender(cur.id, v)),
            const SizedBox(height: 10),
            Btn(cur.geo != null ? 'Править положение детали (своё)' : 'Править положение детали', icon: Icons.edit_outlined, on: s.editingPart, onTap: () {
              s.setEditTarget('part');
              onEdit?.call();
            }),
          ],
          const SizedBox(height: 14),
          Text('Фон картинки при загрузке', style: TextStyle(fontSize: 12.5, color: c.mut)),
          const SizedBox(height: 6),
          Seg<String>(items: const [('ask', 'Спрашивать'), ('cut', 'Вырезать'), ('keep', 'Как есть')], value: s.p.settings.removeMode, onChanged: (v) {
            s.p.settings.removeMode = v;
            s.changed();
          }),
          if (cur != null && cur.isImage && cur.blobId != null) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Btn('Вырезать фон у выбранной', small: true, onTap: s.cutSelected),
              if (cur.origId != null) Btn('Вернуть как было', small: true, onTap: s.restoreOriginal),
            ]),
            if (cur.origId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Text('Строгость', style: TextStyle(fontSize: 12.5, color: c.mut)),
                  Expanded(child: Slider(value: s.p.settings.tol.toDouble(), min: 2, max: 40, onChanged: (v) {
                    s.p.settings.tol = v.round();
                    s.changed();
                  })),
                  Text('${s.p.settings.tol}', style: TextStyle(fontSize: 12.5, color: c.mut)),
                ]),
              ),
          ],
        ],
      ]),
    );
  }
}

class _PartTile extends StatelessWidget {
  final Studio s;
  final Part part;
  final bool on, cover;
  final String slotId;
  const _PartTile({required this.s, required this.part, required this.on, required this.slotId, required this.cover});
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => s.pickPart(slotId, part.id),
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            clipBehavior: Clip.antiAlias,
            padding: EdgeInsets.all(cover ? 0 : 5),
            decoration: BoxDecoration(color: c.stage, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? c.accent : c.line, width: on ? 2 : 1)),
            child: PartThumb(s, part, fit: cover ? BoxFit.cover : BoxFit.contain),
          ),
        ),
        // точка: у детали сохранено своё положение
        if (part.geo != null) Positioned(left: 6, bottom: 6, child: Container(width: 9, height: 9, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle, border: Border.all(color: c.panel, width: 1.5)))),
        if (part.gender != 'both' && !cover) Positioned(left: 4, top: 3, child: Text(part.gender == 'male' ? 'М' : 'Ж', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c.mut))),
        Positioned(
          right: 3,
          top: 3,
          child: InkWell(
            onTap: () => s.deletePart(slotId, part.id),
            child: Container(width: 22, height: 22, decoration: BoxDecoration(color: c.panel, shape: BoxShape.circle, border: Border.all(color: c.line)), child: Icon(Icons.close, size: 13, color: c.mut)),
          ),
        ),
      ]),
    );
  }
}

class GeoPanel extends StatelessWidget {
  final Studio s;
  const GeoPanel(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    final id = s.p.sel;
    final cur = s.partOf(id);
    if (id == 'bg') {
      final g = s.slotGeo('bg');
      final img = cur?.kind == 'img';
      return CardBox(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PanelTitle('Положение фона'),
          if (img) ...[
            SliderRow(label: 'Приближение', value: g.s * 100, min: 100, max: 300, onChanged: (v) => s.setGeo(s: v / 100)),
            SliderRow(label: 'Сдвиг по X', value: g.x, min: -50, max: 50, onChanged: (v) => s.setGeo(x: v)),
            SliderRow(label: 'Сдвиг по Y', value: g.y, min: -50, max: 50, onChanged: (v) => s.setGeo(y: v)),
          ] else
            Text('Для цвета и градиента положение не нужно. Загрузите фото, чтобы двигать его.', style: TextStyle(fontSize: 12.5, color: c.mut)),
          const SizedBox(height: 12),
          Btn('Вернуть исходное', onTap: s.resetGeo),
        ]),
      );
    }
    final canPart = cur != null && cur.isImage;
    final part = s.editingPart;
    final g = s.editGeoRead;
    final who = s.p.gender == 'male' ? 'мужского' : 'женского';
    void nudge(double dx, double dy) => s.setGeo(x: g.x + dx, y: g.y + dy);
    Widget arrow(IconData i, double dx, double dy) => SizedBox(width: 38, height: 38, child: Material(color: c.panel2, borderRadius: BorderRadius.circular(10), child: InkWell(borderRadius: BorderRadius.circular(10), onTap: () => nudge(dx, dy), child: Icon(i, size: 18))));
    return CardBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PanelTitle('Положение'),
        if (canPart) ...[
          Seg<String>(items: const [('slot', 'Слот по умолчанию'), ('part', 'Эта деталь')], value: part ? 'part' : 'slot', onChanged: s.setEditTarget),
          const SizedBox(height: 8),
        ],
        Text(
          part
              ? (cur!.geo != null ? 'У детали «${cur.name}» своё положение, оно сохранено. Другие детали слота его не меняют.' : 'Деталь «${cur.name}» пока стоит по стандарту слота. Измените что-нибудь, и положение сохранится именно для неё.')
              : 'Стандарт слота для $who персонажа. По нему встают все детали, у которых нет своего положения.',
          style: TextStyle(fontSize: 12.5, color: c.mut, height: 1.4),
        ),
        if (!part && cur != null && cur.geo != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('У выбранной детали своё положение: стандарт слота её не двигает.', style: TextStyle(fontSize: 12.5, color: c.warn, height: 1.4))),
        const SizedBox(height: 8),
        SliderRow(label: 'По X', value: g.x, min: -300, max: 1500, onChanged: (v) => s.setGeo(x: v)),
        SliderRow(label: 'По Y', value: g.y, min: -300, max: 1900, onChanged: (v) => s.setGeo(y: v)),
        SliderRow(label: 'Ширина', value: g.w, min: 20, max: 2400, onChanged: (v) => s.setGeo(w: v)),
        const SizedBox(height: 12),
        Wrap(spacing: 18, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 38 * 3 + 8,
            child: Column(children: [
              arrow(Icons.arrow_upward, 0, -1),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [arrow(Icons.arrow_back, -1, 0), SizedBox(width: 38, height: 38, child: Material(color: c.panel2, borderRadius: BorderRadius.circular(10), child: InkWell(borderRadius: BorderRadius.circular(10), onTap: s.resetGeo, child: const Icon(Icons.circle, size: 7)))), arrow(Icons.arrow_forward, 1, 0)]),
              const SizedBox(height: 4),
              arrow(Icons.arrow_downward, 0, 1),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Точка привязки детали', style: TextStyle(fontSize: 12.5, color: c.mut)),
            const SizedBox(height: 6),
            Seg<String>(items: const [('top', 'Верх'), ('center', 'Центр'), ('bottom', 'Низ')], value: g.pivot, onChanged: (v) => s.setGeo(pivot: v)),
          ]),
        ]),
        const Note('Для руки поставьте привязку «Верх»: точка слота будет у запястья. Можно потянуть макет пальцем или мышью, либо нажать «Указать точку».'),
        const SizedBox(height: 12),
        Btn(part ? 'Вернуть к стандартному' : 'Вернуть исходное', onTap: s.resetGeo),
      ]),
    );
  }
}

class FramePanel extends StatelessWidget {
  final Studio s;
  const FramePanel(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final f = s.p.frame;
    final c = sc(context);
    return CardBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PanelTitle('Кадр для профиля'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProfileView(s, px: 120),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Какую часть показать', style: TextStyle(fontSize: 12.5, color: c.mut)),
              const SizedBox(height: 6),
              Seg<String>(items: const [('head', 'Голова'), ('bust', 'По пояс'), ('full', 'Весь')], value: f.mode, onChanged: (v) => s.setFrame(mode: v)),
              const SizedBox(height: 10),
              Text('Форма', style: TextStyle(fontSize: 12.5, color: c.mut)),
              const SizedBox(height: 6),
              Seg<String>(items: const [('circle', 'Круг'), ('round', 'Скруглённый')], value: f.shape, onChanged: (v) => s.setFrame(shape: v)),
            ]),
          ),
        ]),
        SliderRow(label: 'Центр по X', value: f.x, min: -300, max: 1500, onChanged: (v) => s.setFrame(x: v)),
        SliderRow(label: 'Центр по Y', value: f.y, min: -300, max: 1900, onChanged: (v) => s.setFrame(y: v)),
        SliderRow(label: 'Размер', value: f.size, min: 150, max: 2400, onChanged: (v) => s.setFrame(size: v)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Btn(s.frameTool ? 'Скрыть кадр на макете' : 'Показать кадр на макете', on: s.frameTool, onTap: () {
            s.frameTool = !s.frameTool;
            s.placing = false;
            s.changed(save: false);
          }),
          Btn('Посмотреть в профиле', primary: true, onTap: () => showProfileDialog(context, s)),
        ]),
        const Note('Кадр сохраняется. «Голова», «По пояс» и «Весь» подстраиваются под детали сами. Если подвинуть кадр вручную, он остаётся там.'),
      ]),
    );
  }
}

class LooksPanel extends StatefulWidget {
  final Studio s;
  const LooksPanel(this.s, {super.key});
  @override
  State<LooksPanel> createState() => _LooksPanelState();
}

class _LooksPanelState extends State<LooksPanel> {
  final ctl = TextEditingController();
  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final c = sc(context);
    return CardBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PanelTitle('Мои аватарки'),
        Text('Сохраняйте разные сборки: детали, фон и кадр запоминаются вместе. Потом их можно сравнить рядом.', style: TextStyle(fontSize: 13, color: c.mut)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: ctl,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(isDense: true, filled: true, fillColor: c.panel2, hintText: 'Название, например «Школьник»', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11)),
            ),
          ),
          const SizedBox(width: 8),
          Btn('Сохранить текущую', primary: true, onTap: () {
            s.saveLook(ctl.text);
            ctl.clear();
          }),
        ]),
        if (s.p.looks.isEmpty)
          const Note('Пока ничего не сохранено.')
        else ...[
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [for (final l in s.p.looks) _LookCard(s, l)]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn('Сравнить рядом', onTap: () => showCompareDialog(context, s)),
            Btn('Скачать все PNG', onTap: () async {
              for (final l in s.p.looks) {
                final b = await s.profilePng(look: l);
                await s.files.saveFile('${l.name}.png', b, 'image/png');
              }
            }),
          ]),
        ],
      ]),
    );
  }
}

class _LookCard extends StatelessWidget {
  final Studio s;
  final Look l;
  const _LookCard(this.s, this.l);
  @override
  Widget build(BuildContext context) {
    final c = sc(context);
    Widget act(String t, VoidCallback f) => InkWell(onTap: f, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: c.panel2, borderRadius: BorderRadius.circular(8)), child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.mut))));
    return Container(
      width: 148,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(children: [
        InkWell(customBorder: const CircleBorder(), onTap: () => s.applyLook(l), child: ProfileView(s, spec: s.viewOfLook(l), px: 84)),
        const SizedBox(height: 8),
        NameField(key: ValueKey('look-${l.id}'), value: l.name, center: true, onChanged: (v) => s.renameLook(l.id, v)),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.gender == 'male' ? 'Мужской' : 'Женский', style: TextStyle(fontSize: 11.5, color: c.mut))),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
          act('PNG', () async => s.files.saveFile('${l.name}.png', await s.profilePng(look: l), 'image/png')),
          act('Обновить', () => s.updateLook(l.id)),
          act('Удалить', () => s.deleteLook(l.id)),
        ]),
      ]),
    );
  }
}

class ProjectPanel extends StatefulWidget {
  final Studio s;
  const ProjectPanel(this.s, {super.key});
  @override
  State<ProjectPanel> createState() => _ProjectPanelState();
}

class _ProjectPanelState extends State<ProjectPanel> {
  bool armed = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return CardBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const PanelTitle('Проект'),
        Text('Всё хранится на этом устройстве и работает без интернета. Проект можно сохранить в файл и открыть на другом устройстве.', style: TextStyle(fontSize: 12.5, color: sc(context).mut, height: 1.4)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Btn('Сохранить проект в файл', onTap: () async {
            final b = await s.projectBytes();
            await s.files.saveFile('avatar-studio-project.json', b, 'application/json');
          }),
          Btn('Открыть проект из файла', onTap: () async {
            final f = await s.files.pickProject();
            if (f == null) return;
            try {
              await s.loadProject(f.bytes);
              s.message('Проект открыт');
            } catch (e) {
              s.message('Не получилось открыть файл');
            }
          }),
        ]),
        const SizedBox(height: 8),
        Btn(armed ? 'Точно очистить? Нажмите ещё раз' : 'Очистить всё', small: true, onTap: () async {
          if (!armed) {
            setState(() => armed = true);
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted) setState(() => armed = false);
            });
          } else {
            setState(() => armed = false);
            await s.wipe();
            s.message('Всё очищено');
          }
        }),
      ]),
    );
  }
}
