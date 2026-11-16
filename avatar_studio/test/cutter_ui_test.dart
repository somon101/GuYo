import 'dart:typed_data';

import 'package:avatar_studio/state/services.dart';
import 'package:avatar_studio/ui/cutter.dart';
import 'package:avatar_studio/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers.dart';

Uint8List whiteSheet() {
  final im = img.Image(width: 600, height: 400, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(im, x1: 40, y1: 30, x2: 180, y2: 170, color: img.ColorRgba8(30, 30, 160, 255));
  img.fillRect(im, x1: 260, y1: 40, x2: 400, y2: 180, color: img.ColorRgba8(180, 30, 30, 255));
  img.fillRect(im, x1: 60, y1: 230, x2: 200, y2: 370, color: img.ColorRgba8(20, 120, 40, 255));
  return Uint8List.fromList(img.encodePng(im));
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  setUpAll(loadRoboto);
  testWidgets('вырезалка: лист, рамки, мазок кистью, двухпальцевый жест, в слот', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final files = FakeServices();
    final s = newStudio(files: files);
    s.p.sel = 'cloth';
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light).copyWith(textTheme: buildTheme(Brightness.light).textTheme.apply(fontFamily: 'Roboto')), home: CutterScreen(s)));
    expect(find.text('Загрузить фото'), findsOneWidget);
    files.next = [PickedFile('sheet.png', whiteSheet())];
    await t.tap(find.text('Загрузить фото'));
    await settle(t);
    expect(find.text('Править выбранные (3)'), findsOneWidget, reason: 'нашлось три предмета');

    await t.tap(find.text('Править выбранные (3)'));
    await settle(t);
    expect(find.text('Правка детали 1 из 3'), findsOneWidget);

    // мазок «Стереть» по центру детали
    final c = t.getCenter(find.byType(CustomPaint).last);
    final g = await t.startGesture(c);
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(const Offset(0, 30));
    await g.up();
    await settle(t);
    // два пальца: двигают и приближают, мазка не оставляют
    final g1 = await t.startGesture(c + const Offset(-30, 0), pointer: 1);
    final g2 = await t.startGesture(c + const Offset(30, 0), pointer: 2);
    await g1.moveBy(const Offset(-40, 0));
    await g2.moveBy(const Offset(40, 0));
    await g1.up();
    await g2.up();
    await settle(t);

    await t.tap(find.text('В слот'));
    await settle(t);
    final list = s.curSet.parts['cloth']!;
    expect(list.length, 1);
    expect(list.first.origId, isNotNull, reason: 'исходник кусочка сохранён, можно «вернуть как было»');
    expect(find.text('Правка детали 2 из 3'), findsOneWidget, reason: 'открылась следующая деталь');

    // остальные двое одной кнопкой
    await t.tap(find.text('Все в слот'));
    await settle(t);
    expect(s.curSet.parts['cloth']!.length, 3);
    expect(t.takeException(), isNull);
    await t.runAsync(s.flush);
  });
}
