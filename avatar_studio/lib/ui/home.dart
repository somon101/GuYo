// Главный экран: три колонки на компьютере, сцена и вкладки на телефоне.
import 'package:flutter/material.dart';

import '../state/studio.dart';
import 'dialogs.dart';
import 'panels.dart';
import 'stage.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  final Studio s;
  const HomePage(this.s, {super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  Studio get s => widget.s;

  @override
  void initState() {
    super.initState();
    s.onMessage = (t) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
    };
  }

  Future<void> _exportAvatar() async {
    final b = await s.avatarPng();
    if (b == null) {
      s.message('Сначала загрузите хотя бы одну деталь');
      return;
    }
    await s.files.saveFile('avatar.png', b, 'image/png');
  }

  Widget _top(bool narrow) {
    final c = sc(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(9)), child: Icon(Icons.person, size: 18, color: c.onAccent)),
      const SizedBox(width: 10),
      Flexible(child: Text('Студия аватаров', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: narrow ? 16 : 18, fontWeight: FontWeight.w800))),
      const Spacer(),
      if (!narrow) Padding(padding: const EdgeInsets.only(right: 14), child: Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: c.ok, shape: BoxShape.circle)), const SizedBox(width: 7), Text(s.savedLabel.isEmpty ? 'Сохранено' : s.savedLabel, style: TextStyle(fontSize: 12.5, color: c.mut))])),
      IconButton(tooltip: dark ? 'Светлая тема' : 'Тёмная тема', onPressed: () {
        s.p.settings.theme = dark ? 'light' : 'dark';
        s.changed();
      }, icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: c.mut)),
      const SizedBox(width: 4),
      Btn(narrow ? '' : 'В профиле', icon: Icons.account_circle_outlined, onTap: () => showProfileDialog(context, s)),
      const SizedBox(width: 8),
      Btn(narrow ? '' : 'Скачать PNG', icon: Icons.download, primary: true, onTap: _exportAvatar),
    ]);
  }

  Widget _tools() => Positioned(
        left: 12,
        top: 12,
        child: ListenableBuilder(
          listenable: s,
          builder: (_, _) => Wrap(spacing: 7, children: [
            Btn(MediaQuery.sizeOf(context).width < 1020 ? '' : 'Указать точку кликом', icon: Icons.gps_fixed, on: s.placing, onTap: () {
              s.placing = !s.placing;
              s.frameTool = false;
              s.changed(save: false);
            }),
            Btn(MediaQuery.sizeOf(context).width < 1020 ? '' : 'Кадр профиля', icon: Icons.crop_free, on: s.frameTool, onTap: () {
              s.frameTool = !s.frameTool;
              s.placing = false;
              s.changed(save: false);
            }),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (ctx, _) => LayoutBuilder(builder: (ctx, box) {
            final narrow = box.maxWidth < 1020;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(children: [
                _top(narrow),
                const SizedBox(height: 12),
                Expanded(child: narrow ? _narrow(box) : _wide()),
              ]),
            );
          }),
        ),
      ),
    );
  }

  Widget _stage() => Stack(children: [Positioned.fill(child: StageView(s)), _tools()]);

  Widget _wide() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 300, child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [SetsPanel(s), SlotsPanel(s), ProjectPanel(s)])),
        const SizedBox(width: 14),
        Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 16), child: _stage())),
        const SizedBox(width: 14),
        SizedBox(width: 340, child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [PartsPanel(s), GeoPanel(s), FramePanel(s), LooksPanel(s)])),
      ]);

  Widget _narrow(BoxConstraints box) {
    final c = sc(context);
    const names = ['Слои', 'Детали', 'Положение', 'Кадр', 'Аватарки'];
    final panels = <Widget>[
      Column(children: [SetsPanel(s), SlotsPanel(s, onPicked: () => setState(() => tab = 1)), ProjectPanel(s)]),
      PartsPanel(s),
      GeoPanel(s),
      FramePanel(s),
      LooksPanel(s),
    ];
    return Column(children: [
      SizedBox(height: (box.maxHeight * 0.5).clamp(240, 560).toDouble(), child: _stage()),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: c.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
        child: Row(children: [
          for (var i = 0; i < names.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => tab = i),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 10), alignment: Alignment.center, decoration: BoxDecoration(color: tab == i ? c.accent : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: FittedBox(child: Text(names[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tab == i ? c.onAccent : c.mut)))),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [panels[tab]])),
    ]);
  }
}
