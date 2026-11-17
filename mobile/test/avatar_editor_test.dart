// The avatar is built from the Studio's parts: each part sits at ITS OWN saved place, picking a gender puts
// together a random SET of that gender, the grid shows many parts at once, white squares stand in until
// pictures arrive.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/avatar/avatar_logic.dart';
import 'package:guyo_app/avatar/avatar_models.dart';
import 'package:guyo_app/avatar/avatar_painter.dart';
import 'package:guyo_app/avatar/avatar_store.dart';
import 'package:guyo_app/demo/demo_avatar.dart';
import 'package:guyo_app/models/user_profile.dart';
import 'package:guyo_app/screens/avatar_editor_screen.dart';

Map<String, dynamic> part(String id, String slot, String gender, String set, {double x = 600, double y = 500, double w = 400, double r = 0}) => {
      'id': id, 'slot': slot, 'gender': gender, 'set_id': set, 'name': id, 'url': '/media/$id.png', 'w': 100, 'h': 100, 'v': 1,
      'place': {
        if (gender != 'female') 'male': {'x': x, 'y': y, 'w': w, 'r': r, 'pivot': 'center'},
        if (gender != 'male') 'female': {'x': x, 'y': y, 'w': w, 'r': r, 'pivot': 'center'},
      },
    };

AvatarCatalog catalog() => AvatarCatalog.fromJson({
      'version': 3,
      'canvas': {'w': 1200, 'h': 1600},
      'frame': {'x': 600, 'y': 560, 'size': 760, 'shape': 'circle'},
      'slots': [{'id': 'cloth', 'name': 'Одежда'}, {'id': 'hair', 'name': 'Волосы'}],
      'items': [
        part('c-f1', 'cloth', 'female', 's1'), part('h-f1', 'hair', 'female', 's1'),
        part('c-f2', 'cloth', 'female', 's2'), part('h-f2', 'hair', 'female', 's2', x: 640),
        part('c-m1', 'cloth', 'male', 's3'), part('h-m1', 'hair', 'male', 's3'), part('h-m2', 'hair', 'male', 's3'),
        part('h-m3', 'hair', 'male', 's3'), part('h-m4', 'hair', 'male', 's3'), part('h-m5', 'hair', 'male', 's3'),
      ],
      'backgrounds': [{'id': 'bg1', 'name': 'Розовый', 'kind': 'solid', 'c1': '#FFD0E2', 'v': 1}, {'id': 'bg2', 'name': 'Синий', 'kind': 'solid', 'c1': '#4060F0', 'v': 1}],
    });

Future<ui.Image> square(int color) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 20, 20), Paint()..color = Color(color));
  return rec.endRecording().toImage(20, 20);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);

  test('a part sits at its own place: width from the place, height by proportion, pivot and rotation kept', () {
    final c = catalog();
    final p = c.part('h-f2')!;
    final r = partRect(p, p.places['female']!);
    expect(r.center.dx, 640);
    expect(r.width, 400);
    expect(r.height, 400, reason: '100×100 picture keeps its proportions');
    final top = partRect(p, const AvatarPlace(x: 100, y: 200, w: 300, pivot: 'top'));
    expect(top.top, 200);
    expect(partRect(p, const AvatarPlace(x: 100, y: 200, w: 300, pivot: 'bottom')).bottom, 200);
  });

  test('picking a gender puts together a random SET of that gender, with a random background', () {
    final c = catalog();
    for (var seed = 0; seed < 30; seed++) {
      final choice = randomChoice(c, 'female', math.Random(seed));
      expect(choice.slots.keys.toSet(), {'cloth', 'hair'});
      final sets = {for (final id in choice.slots.values) c.part(id)!.setId};
      expect(sets.length, 1, reason: 'clothes and hair come from the same set');
      expect(sets.single, anyOf('s1', 's2'));
      expect(choice.slots.values.every((id) => c.part(id)!.fits('female')), isTrue);
      expect(c.background(choice.bg), isNotNull);
    }
    final boy = randomChoice(c, 'male', math.Random(1));
    expect(boy.slots.values.every((id) => c.part(id)!.gender == 'male'), isTrue, reason: 'a boy never gets a girl\'s part');
  });

  test('the picture is drawn from the frame and comes out as a square PNG', () async {
    final c = catalog();
    final choice = AvatarChoice(gender: 'female', slots: {'hair': 'h-f1', 'cloth': 'c-f1'}, bg: 'bg1');
    final png = await renderAvatarPng(c, choice, {'/media/h-f1.png': await square(0xFF804020), '/media/c-f1.png': await square(0xFF3366CC)}, px: 64);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    final im = await decodeImageFromList(png);
    expect((im.width, im.height), (64, 64));
  });

  testWidgets('the editor: gender → a random set is already there → grid of parts → change one → dice', (t) async {
    t.view.physicalSize = const Size(1080, 2200);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final store = AvatarStore.instance;
    store.debugCatalog = () async => catalog();
    final loaded = <String>[];
    store.debugImage = (url) async {
      loaded.add(url);
      return square(0xFF5566AA);
    };
    addTearDown(() {
      store.debugCatalog = null;
      store.debugImage = null;
      store.images.clear();
    });
    final profile = UserProfile(id: 1, publicId: 123456789, login: 'Aisha', firstName: null, lastName: null, email: null, avatarUrl: null, currentStreakDays: 0, lessonsCompleted: 0, wordsLearned: 0);
    await t.pumpWidget(MaterialApp(home: AvatarEditorScreen(profile: profile, random: math.Random(5))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Кто вы?'), findsOneWidget);
    expect(find.text('Парень'), findsOneWidget);
    expect(find.text('Девушка'), findsOneWidget);

    await t.tap(find.text('Девушка'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    // the first step after the gender is the clothes (slot order from the server): a grid with the girl's parts
    expect(find.text('Одежда · 2'), findsOneWidget);
    expect(find.text('Дальше'), findsOneWidget);
    expect(loaded.any((u) => u.contains('c-f')), isTrue, reason: 'the pictures of the random set were fetched');
    expect(loaded.any((u) => u.contains('c-m')), isFalse, reason: 'a boy\'s clothes are never fetched for a girl');
    await t.tap(find.text('Дальше'));
    await t.pump();
    expect(find.text('Волосы · 2'), findsOneWidget);
    // jump back through the chips and use the dice
    await t.tap(find.byIcon(Icons.casino_rounded));
    await t.pump();
    await t.tap(find.text('Фон'));
    await t.pump();
    expect(find.text('Готово'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('demo: the boys\' set from the Studio is the demo catalog, every part has its picture', () async {
    final c = AvatarCatalog.fromJson(jsonDecode(await demoAvatarCatalogJson()) as Map<String, dynamic>);
    expect(c.parts, isNotEmpty);
    expect(c.parts.every((p) => p.gender == 'male'), isTrue, reason: 'a boys\' set; nothing is made up in code any more');
    expect(c.backgrounds, isEmpty);
    expect(c.slotsFor('female'), isEmpty);
    expect(c.slotsFor('male').map((s) => s.id), containsAll(['cloth', 'face', 'hair']));
    for (final p in c.parts.take(5)) {
      final png = await demoPartPng(p.url.split('/').last);
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    }
    final choice = randomChoice(c, 'male', math.Random(2));
    expect(choice.slots.keys.toSet(), c.slotsFor('male').map((s) => s.id).toSet());
  });
}
