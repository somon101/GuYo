// Снимок экрана с набором деталей: AS_SHOTS=папка AS_PACK=папка_с_деталями flutter test test/pack_screenshot_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:avatar_studio/state/services.dart';
import 'package:avatar_studio/ui/home.dart';
import 'package:avatar_studio/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final out = Platform.environment['AS_SHOTS'], pack = Platform.environment['AS_PACK'];
  setUpAll(loadRoboto);
  testWidgets('набор: снимки', (t) async {
    final key = GlobalKey();
    final s = newStudio();
    t.view.physicalSize = const Size(1500, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light).copyWith(textTheme: buildTheme(Brightness.light).textTheme.apply(fontFamily: 'Roboto')), home: HomePage(s))));
    final files = [for (final f in Directory(pack!).listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) PickedFile(f.uri.pathSegments.last, f.readAsBytesSync())];
    await t.runAsync(() => s.importPack(files));
    s.addPresetBackgrounds();
    s.curSet.pick['bg'] = s.curSet.parts['bg']![0].id;
    Future<void> pick(String slot, String name) async {
      final p = s.curSet.parts[slot]!.firstWhere((x) => x.name.contains(name));
      s.curSet.pick[slot] = p.id;
    }
    s.setGender('female');
    await pick('face', 'Ж2 Смех');
    await pick('hair', 'Косы');
    await pick('cloth', 'Свитер');
    await pick('glasses', 'Сердечки розовые');
    await pick('handL', 'Рука розовый рукав 01');
    await pick('handR', 'Рука розовый рукав 02');
    s.p.sel = 'face';
    s.setFrame(mode: 'bust');
    s.changed(save: false);
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final im = await b.toImage(pixelRatio: 1);
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/pack_female.png').writeAsBytes(d!.buffer.asUint8List());
    });
    await t.runAsync(s.flush);
  }, skip: out == null || pack == null);
}
