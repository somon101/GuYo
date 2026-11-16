// Снимки экранов для ручной проверки. Запуск: AS_SHOTS=/путь/для/png AS_PARTS=/папка/с/jpg flutter test test/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:avatar_studio/state/services.dart';
import 'package:avatar_studio/ui/home.dart';
import 'package:avatar_studio/ui/dialogs.dart';
import 'package:avatar_studio/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final out = Platform.environment['AS_SHOTS'], parts = Platform.environment['AS_PARTS'];
  setUpAll(loadRoboto);

  Future<void> shot(WidgetTester t, GlobalKey k, String name) async {
    await t.runAsync(() async {
      final b = k.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final im = await b.toImage(pixelRatio: 1);
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(d!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    testWidgets('снимки ${dark ? 'тёмная' : 'светлая'}', (t) async {
      final key = GlobalKey();
      final s = newStudio(files: FakeServices());
      Future<void> settle() async {
        for (var i = 0; i < 40; i++) {
          await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 50));
          if (!s.busy && i > 1) break;
        }
      }

      Widget app() => RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(dark ? Brightness.dark : Brightness.light).copyWith(textTheme: buildTheme(dark ? Brightness.dark : Brightness.light).textTheme.apply(fontFamily: 'Roboto')),
            home: HomePage(s),
          ));
      t.view.physicalSize = const Size(1500, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app());
      for (final e in {'cloth': 'hoodie.jpg', 'neck': 'head.jpg', 'face': 'face.jpg', 'hair': 'hair.jpg'}.entries) {
        s.p.sel = e.key;
        await t.runAsync(() async => s.addImages([PickedFile(e.value, File('$parts/${e.value}').readAsBytesSync())], cut: true));
        await settle();
      }
      s.p.sel = 'bg';
      s.addPresetBackgrounds();
      s.curSet.pick['bg'] = s.curSet.parts['bg']![4].id;
      s.p.sel = 'face';
      s.setFrame(mode: 'head');
      s.saveLook('Школьник');
      s.p.sel = 'cloth';
      s.setFrame(mode: 'bust');
      s.saveLook('По пояс');
      s.p.sel = 'face';
      s.changed(save: false);
      await t.pump(const Duration(milliseconds: 200));
      await shot(t, key, 'desktop${dark ? '_dark' : ''}');
      if (!dark) {
        s.frameTool = true;
        s.changed(save: false);
        await t.pump(const Duration(milliseconds: 200));
        await shot(t, key, 'desktop_frame');
        s.frameTool = false;
        showProfileDialog(t.element(find.byType(HomePage)), s);
        await t.pump(const Duration(milliseconds: 300));
        await shot(t, key, 'profile_dialog');
        await t.tapAt(const Offset(20, 20));
        await t.pump(const Duration(milliseconds: 300));
        t.view.physicalSize = const Size(420, 880);
        await t.pump(const Duration(milliseconds: 300));
        await shot(t, key, 'phone');
        await t.tap(find.text('Кадр').first);
        await t.pump(const Duration(milliseconds: 300));
        await shot(t, key, 'phone_frame');
        await t.tap(find.text('Аватарки').first);
        await t.pump(const Duration(milliseconds: 300));
        await shot(t, key, 'phone_looks');
      }
      await t.runAsync(s.flush);
    }, skip: out == null || parts == null);
  }
}
