import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avatar_studio/core/geometry.dart';
import 'package:avatar_studio/state/services.dart';
import 'package:avatar_studio/state/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<ui.Color?> corner(dynamic s, String blobId) async {
  final im = s.images[blobId] as ui.Image;
  final d = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
  return ui.Color.fromARGB(d!.getUint8(3), d.getUint8(0), d.getUint8(1), d.getUint8(2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('режим «вырезать»: фон убирается, исходник сохраняется для «Вернуть как было»', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      s.p.sel = 'face';
      await s.addImages([PickedFile('face.jpg', faceOnBlack())], cut: true);
      final part = s.partOf('face')!;
      expect(part.origId, isNotNull);
      expect(part.blobId, isNot(part.origId));
      expect((await corner(s, part.blobId!))!.a, 0, reason: 'левый верхний угол прозрачный');
      expect(s.rectFor('face')!.width, closeTo(canvasW * 0.56, 1), reason: 'новая деталь встаёт по стандартной ширине слота');
      await s.restoreOriginal();
      final back = s.partOf('face')!;
      expect(back.origId, isNull);
      expect((await corner(s, back.blobId!))!.a, 1.0, reason: 'исходник вернулся с чёрным фоном');
    });
  });

  testWidgets('режим «оставить как есть»: байты картинки не меняются', (t) async {
    await t.runAsync(() async {
      final st = MemoryStorage();
      final s = newStudio(storage: st);
      s.p.sel = 'cloth';
      final bytes = squareOnChecker();
      await s.addImages([PickedFile('cloth.png', bytes)], cut: false);
      final part = s.partOf('cloth')!;
      expect(part.origId, isNull);
      expect(st.blobs[part.blobId], bytes);
      // потом вручную: вырезать у выбранной
      await s.cutSelected();
      expect(s.partOf('cloth')!.origId, isNotNull);
    });
  });

  testWidgets('у каждой детали своё положение, у не правленых стандарт слота', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      s.p.sel = 'face';
      await s.addImages([PickedFile('a.jpg', faceOnBlack()), PickedFile('b.jpg', faceOnBlack(w: 300, h: 260))], cut: false);
      final a = s.curSet.parts['face']![0], b = s.curSet.parts['face']![1];
      // обе встали по стандарту, одной ширины
      expect(s.rectFor('face')!.width, closeTo(canvasW * 0.56, 1e-6));
      s.pickPart('face', a.id);
      expect(s.rectFor('face')!.width, closeTo(canvasW * 0.56, 1e-6));
      // правим деталь b: сохраняется именно для неё
      s.pickPart('face', b.id);
      s.setEditTarget('part');
      s.setGeo(x: 500, y: 520, w: 700);
      expect(b.geo, isNotNull);
      expect(a.geo, isNull);
      s.pickPart('face', a.id);
      expect(s.rectFor('face')!.width, closeTo(canvasW * 0.56, 1e-6), reason: 'другая деталь осталась по стандарту');
      s.pickPart('face', b.id);
      expect(s.rectFor('face')!.width, closeTo(700, 1e-6), reason: 'вернулись и своё положение на месте');
      expect(s.geoOf('face').x, 500);
      // стандарт слота меняют: не правленая деталь следует, правленая нет
      s.setEditTarget('slot');
      s.setGeo(x: 100);
      expect(s.geoOf('face').x, 500, reason: 'у детали своё положение');
      s.pickPart('face', a.id);
      s.setEditTarget('slot');
      expect(s.geoOf('face').x, 100, reason: 'деталь по стандарту следует за ним');
      // сброс у детали убирает своё положение
      s.pickPart('face', b.id);
      s.setEditTarget('part');
      s.resetGeo();
      expect(b.geo, isNull);
      expect(s.geoOf('face').x, 100);
    });
  });

  testWidgets('поворот: свой у детали и у стандарта слота, откатывается, попадает в картинку', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      s.p.sel = 'face';
      await s.addImages([PickedFile('a.jpg', faceOnBlack()), PickedFile('b.jpg', faceOnBlack())], cut: false);
      final a = s.curSet.parts['face']![0], b = s.curSet.parts['face']![1];
      s.pickPart('face', b.id);
      s.setEditTarget('part');
      s.setGeo(r: 12);
      expect(b.geo!.r, 12);
      s.pickPart('face', a.id);
      expect(s.geoOf('face').r, 0, reason: 'другая деталь не повёрнута');
      s.setEditTarget('slot');
      s.setGeo(r: -5);
      expect(s.geoOf('face').r, -5);
      s.pickPart('face', b.id);
      expect(s.geoOf('face').r, 12, reason: 'своя деталь держит свой угол');
      final w0 = s.boundsFor('face')!.width;
      expect(w0, greaterThan(s.rectFor('face')!.width), reason: 'описанный прямоугольник шире из-за поворота');
      s.undo();
      s.undo();
      expect((await s.avatarPng())!.length, greaterThan(500));
      expect(s.curSet.parts['face']![1].geo, isNull, reason: 'откат вернул деталь без своего положения');
      expect(s.slotGeo('face').r, 0);
    });
  });

  testWidgets('пол: у персонажа видны детали его пола и «оба»; стандарты слотов раздельные', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      s.p.sel = 'hair';
      await s.addImages([PickedFile('m.jpg', faceOnBlack())], cut: false); // мужской персонаж: деталь мужская
      final male = s.curSet.parts['hair']!.single;
      expect(male.gender, 'male');
      s.setGender('female');
      expect(s.partOf('hair'), isNull, reason: 'мужская деталь скрыта у женского персонажа');
      await s.addImages([PickedFile('f.jpg', faceOnBlack())], cut: false);
      final fem = s.partOf('hair')!;
      expect(fem.gender, 'female');
      s.setPartGender(fem.id, 'both');
      s.setGender('male');
      expect(s.partsOf('hair').length, 2, reason: '«оба» показывается и мужскому');
      expect(s.curSet.parts['hair']!.length, 2);
      // стандарты слотов раздельные
      s.p.sel = 'face';
      s.setGeo(x: 777);
      expect(s.slotGeo('face').x, 777);
      s.setGender('female');
      expect(s.slotGeo('face').x, isNot(777));
    });
  });

  testWidgets('история: назад и вперёд, быстрые правки склеиваются, удаление детали откатывается', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      s.p.sel = 'face';
      await s.addImages([PickedFile('a.jpg', faceOnBlack())], cut: true);
      final id = s.partOf('face')!.id;
      expect(s.canUndo, isTrue);
      // перетаскивание: много мелких правок = один шаг
      for (var i = 0; i < 20; i++) {
        s.setGeo(x: 600.0 + i);
      }
      expect(s.slotGeo('face').x, 619);
      s.undo();
      expect(s.slotGeo('face').x, 600, reason: 'вся правка откатилась одним шагом');
      s.redo();
      expect(s.slotGeo('face').x, 619);
      // удаление детали и откат: картинка и деталь возвращаются
      await s.deletePart('face', id);
      expect(s.partOf('face'), isNull);
      s.undo();
      final back = s.partOf('face')!;
      expect(back.id, id);
      expect(s.imageOf(back), isNotNull);
      // вырезание фона у выбранной и откат
      await s.cutSelected();
      s.undo();
      s.redo();
      expect(s.partOf('face'), isNotNull);
      // новое действие обнуляет «вперёд»
      s.undo();
      s.setGeo(x: 1);
      expect(s.canRedo, isFalse);
      // настройки и выбор слота в историю не входят
      final steps = s.canUndo;
      s.p.settings.theme = 'dark';
      s.changed();
      s.select('hair');
      expect(s.canUndo, steps);
    });
  });

  testWidgets('аватарки: сохранить, изменить, открыть; кадр «Голова» следует за деталями', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      s.p.sel = 'face';
      await s.addImages([PickedFile('a.jpg', faceOnBlack())], cut: true);
      s.setFrame(mode: 'head');
      final f1 = s.p.frame.size;
      s.saveLook('Школьник');
      expect(s.p.looks.single.name, 'Школьник');
      s.toggleVis('face');
      s.setFrame(mode: 'custom', size: 123);
      s.applyLook(s.p.looks.single);
      expect(s.geoOf('face').vis, isTrue);
      expect(s.p.frame.size, closeTo(f1, 1e-6));
      s.p.sel = 'face';
      s.setGeo(w: s.geoOf('face').w * 2);
      s.setFrame(mode: 'head');
      expect(s.p.frame.size, greaterThan(f1));
    });
  });

  testWidgets('проект: сохранение в файл и открытие даёт те же детали и картинки', (t) async {
    await t.runAsync(() async {
      final a = newStudio();
      a.p.sel = 'face';
      await a.addImages([PickedFile('a.jpg', faceOnBlack())], cut: true);
      a.addPresetBackgrounds();
      a.saveLook('Один');
      final bytes = await a.projectBytes();
      final st = MemoryStorage();
      final b = newStudio(storage: st);
      await b.loadProject(bytes);
      final part = b.partOf('face')!;
      expect(part.origId, isNotNull);
      expect(b.images.containsKey(part.blobId), isTrue);
      expect(st.blobs.length, 2);
      expect(b.p.looks.single.name, 'Один');
      expect(b.curSet.parts['bg']!.length, 6);
      expect(() => b.loadProject(utf8Bytes('{"format":"x"}')), throwsFormatException);
    });
  });

  testWidgets('автосохранение и перезапуск: всё на месте', (t) async {
    await t.runAsync(() async {
      final st = MemoryStorage();
      final a = newStudio(storage: st);
      a.p.sel = 'hair';
      await a.addImages([PickedFile('h.png', squareOnChecker())], cut: true);
      a.setGeo(x: 321);
      await a.flush();
      final b = newStudio(storage: st);
      await b.load();
      expect(b.geoOf('hair').x, 321);
      expect(b.partOf('hair'), isNotNull);
      expect(b.imageOf(b.partOf('hair')), isNotNull);
    });
  });

  testWidgets('набор деталей: имя файла раскладывает по слотам и полу, рука попадает в оба слота', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      await s.importPack([
        PickedFile('hair__female__Косы.png', squareOnChecker()),
        PickedFile('hand__both__Рука 01.png', squareOnChecker()),
        PickedFile('face__male__Лицо М.png', faceOnBlack()),
        PickedFile('без_имени.png', faceOnBlack()),
      ]);
      final hair = s.curSet.parts['hair']!.single;
      expect(hair.name, 'Косы');
      expect(hair.gender, 'female');
      expect(s.curSet.parts['handL']!.single.name, 'Рука 01');
      expect(s.curSet.parts['handR']!.single.gender, 'both');
      expect(s.curSet.parts['handL']!.single.blobId, s.curSet.parts['handR']!.single.blobId, reason: 'одна картинка на оба слота');
      expect(s.curSet.parts['face']!.first.gender, 'male');
      // без «слот__» файл идёт в выбранный слот с полом текущего персонажа
      expect(s.curSet.parts[s.p.sel]!.any((x) => x.name == 'без_имени' && x.gender == 'male'), isTrue);
      // мужской персонаж не видит женскую причёску
      expect(s.partOf('hair'), isNull);
      s.setGender('female');
      expect(s.partOf('hair')!.name, 'Косы');
      expect(s.partOf('handL'), isNotNull);
    });
  });

  testWidgets('PNG аватара и профиля не пустые', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      expect(await s.avatarPng(), isNull);
      s.p.sel = 'face';
      await s.addImages([PickedFile('a.jpg', faceOnBlack())], cut: true);
      s.addPresetBackgrounds();
      expect((await s.avatarPng())!.length, greaterThan(500));
      expect((await s.profilePng()).length, greaterThan(500));
    });
  });
}

List<int> _u(String s) => s.codeUnits;
dynamic utf8Bytes(String s) => Uint8List.fromList(_u(s));
