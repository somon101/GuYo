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
      expect(s.geoOf('face').placed, isTrue);
      expect(part.w * s.geoOf('face').s, closeTo(canvasW * 0.56, 1));
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

  testWidgets('смена детали слота не меняет его положение; наборы делят положение', (t) async {
    await t.runAsync(() async {
      final s = newStudio();
      s.p.sel = 'face';
      await s.addImages([PickedFile('a.jpg', faceOnBlack()), PickedFile('b.jpg', faceOnBlack(w: 300, h: 260))], cut: false);
      s.setGeo(x: 500, y: 520);
      final before = s.geoOf('face').toJson().toString();
      s.pickPart('face', s.curSet.parts['face']!.first.id);
      expect(s.geoOf('face').toJson().toString(), before);
      s.addSet();
      expect(s.geoOf('face').x, 500, reason: 'положение слота общее для наборов');
      s.setScopeOwn(true);
      s.setGeo(x: 100);
      s.selectSet('s1');
      expect(s.geoOf('face').x, 500);
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
      s.setGeo(s: s.geoOf('face').s * 2);
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
