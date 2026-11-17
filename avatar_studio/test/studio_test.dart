import 'dart:convert';
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
      expect((await s.avatarPng())!.length, greaterThan(500));
      while (s.canUndo) {
        s.undo();
      }
      expect(s.curSet.parts['face'] ?? const [], isEmpty, reason: 'откатили до пустого проекта');
      expect(s.slotGeo('face').r, 0);
      while (s.canRedo) {
        s.redo();
      }
      expect(s.curSet.parts['face']!.length, 2);
      expect(s.curSet.parts['face']![1].geo!.r, 12, reason: 'вперёд вернул свой угол детали');
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

  testWidgets('резервная копия: после «стереть всё» и восстановления всё то же до байта', (t) async {
    await t.runAsync(() async {
      final st = MemoryStorage();
      final a = newStudio(storage: st);
      a.setGender('female');
      a.p.sel = 'hair';
      await a.addImages([PickedFile('h.jpg', faceOnBlack())], cut: true);
      final hair = a.partOf('hair')!;
      a.setPartGender(hair.id, 'female');
      a.setEditTarget('part');
      a.setGeo(x: 321, y: 123, w: 456, r: 7);
      a.setEditTarget('slot');
      a.setGeo(x: 111, y: 222);
      a.p.settings.theme = 'dark';
      a.p.settings.removeMode = 'keep';
      a.addPresetBackgrounds();
      a.saveLook('Образ');
      final hairBytes = await st.readBlob(hair.blobId!);
      final origBytes = await st.readBlob(hair.origId!);
      final backup = await a.projectBytes();
      final before = a.p.toJson();

      await a.wipe();
      expect(a.p.looks, isEmpty);
      expect(a.partOf('hair'), isNull);

      await a.loadProject(backup);
      final back = a.p.toJson();
      expect(back['settings'], before['settings'], reason: 'настройки восстановились');
      expect(back['looks'], before['looks']);
      expect(back['gender'], before['gender']);
      expect(back['geos'], before['geos'], reason: 'стандарты слотов у обоих персонажей');
      final h2 = a.curSet.parts['hair']!.single;
      expect(h2.name, hair.name);
      expect(h2.gender, 'female');
      expect(h2.geo!.toJson(), hair.geo!.toJson(), reason: 'своё положение детали');
      expect(await st.readBlob(h2.blobId!), hairBytes, reason: 'картинка детали та же');
      expect(await st.readBlob(h2.origId!), origBytes, reason: 'исходник тот же');
      expect(a.curSet.parts['bg']!.length, 6);
    });
  });

  testWidgets('выгрузка для GuYo: у каждой детали свой ID и своё положение для каждого пола', (t) async {
    await t.runAsync(() async {
      final a = newStudio();
      a.setGender('female');
      a.p.sel = 'hair';
      await a.addImages([PickedFile('h1.jpg', faceOnBlack()), PickedFile('h2.jpg', faceOnBlack())], cut: true);
      final h = a.curSet.parts['hair']!;
      a.setPartGender(h[0].id, 'both');
      a.p.sel = 'hair';
      a.curSet.pick['hair'] = h[1].id;
      a.setEditTarget('part');
      a.setGeo(x: 400, y: 300, w: 450, r: 5); // своё положение только у второй причёски
      a.setEditTarget('slot');
      final j = jsonDecode(utf8.decode(await a.guyoBytes())) as Map;
      expect(j['format'], 'avatar-items/1');
      final items = (j['items'] as List).cast<Map>();
      expect(items.length, 2);
      expect(items[0]['id'], isNot(items[1]['id']));
      expect(items[0]['id'], h[0].id, reason: 'ID те же, что в Студии');
      expect(items[0]['ownPlace'], isFalse);
      expect(items[1]['ownPlace'], isTrue);
      expect((items[1]['place'] as Map)['female']['x'], 400);
      expect((items[1]['place'] as Map).containsKey('male'), isFalse, reason: 'вторая причёска только женская');
      expect((items[0]['place'] as Map).keys.toSet(), {'male', 'female'});
      expect(items[0]['png'], isA<String>());
      expect(items[0].containsKey('origData'), isFalse);
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

  testWidgets('кисть на сцене: стирает кусок слоя, «Готово» сохраняет, Назад возвращает', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      s.p.sel = 'hair';
      await s.addImages([PickedFile('face.jpg', faceOnBlack())], cut: true);
      final part = s.partOf('hair')!;
      final before = part.blobId!;
      expect(await s.beginPartEdit(), isTrue);
      final ed = s.partEdit!;
      final cx = ed.w ~/ 2, cy = ed.h ~/ 2;
      expect(ed.alpha[cy * ed.w + cx], greaterThan(200));
      ed.beginStroke();
      ed.stamp(cx.toDouble(), cy.toDouble(), 20, 0, erase: true);
      ed.endStroke();
      s.touchPartEdit();
      expect(s.canUndo, isTrue, reason: 'пока идёт правка, Назад работает по мазкам');
      await s.commitPartEdit();
      expect(s.painting, isFalse);
      final after = s.partOf('hair')!;
      expect(after.blobId, isNot(before));
      expect(after.origId, isNotNull, reason: 'прежняя картинка сохранена для «Вернуть как было»');
      final d = await (s.images[after.blobId!]!).toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(d!.getUint8((cy * ed.w + cx) * 4 + 3), 0, reason: 'на месте мазка прозрачно');
      s.undo();
      expect(s.partOf('hair')!.blobId, before, reason: 'общая кнопка «Назад» возвращает прежнюю картинку');
      await t.pump();
    });
  });

  testWidgets('кисть на сцене: отмена и смена слоя не портят деталь', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      s.p.sel = 'hair';
      await s.addImages([PickedFile('face.jpg', faceOnBlack())], cut: true);
      final before = s.partOf('hair')!.blobId;
      await s.beginPartEdit();
      s.partEdit!.beginStroke();
      s.partEdit!.stamp(30, 30, 25, 0, erase: true);
      s.partEdit!.endStroke();
      s.cancelPartEdit();
      expect(s.partOf('hair')!.blobId, before);
      expect(s.painting, isFalse);
      s.p.sel = 'bg';
      expect(await s.beginPartEdit(), isFalse, reason: 'у фона кисти нет');
    });
  });
}

List<int> _u(String s) => s.codeUnits;
dynamic utf8Bytes(String s) => Uint8List.fromList(_u(s));
