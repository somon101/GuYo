import 'package:avatar_studio/state/studio.dart';
import 'package:avatar_studio/state/services.dart';
import 'package:avatar_studio/ui/home.dart';
import 'package:avatar_studio/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Widget app(Studio s) => MaterialApp(theme: buildTheme(Brightness.light).copyWith(textTheme: buildTheme(Brightness.light).textTheme.apply(fontFamily: 'Roboto')), home: HomePage(s));

Future<void> settle(WidgetTester t, Studio s) async {
  for (var i = 0; i < 50; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 50));
    if (!s.busy && i > 1) break;
  }
}

void main() {
  setUpAll(loadRoboto);
  testWidgets('загрузка с окном выбора: вырезать автоматически и оставить как есть', (t) async {
    t.view.physicalSize = const Size(1500, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final files = FakeServices();
    final s = newStudio(files: files);
    await t.pumpWidget(app(s));
    files.next = [PickedFile('face.jpg', faceOnBlack())];

    await t.tap(find.text('Голова с лицом').first);
    await t.pump();
    await t.tap(find.text('Загрузить'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Что сделать с фоном картинки?'), findsOneWidget);
    expect(find.text('Вырезать фон автоматически'), findsOneWidget);
    expect(find.text('Оставить как есть'), findsOneWidget);
    await t.tap(find.text('Вырезать фон автоматически'));
    await t.pump();
    await settle(t, s);
    expect(s.partOf('face')!.origId, isNotNull, reason: 'фон вырезан, исходник сохранён');

    // второй раз: «как есть» и «запомнить выбор»
    files.next = [PickedFile('face2.jpg', faceOnBlack())];
    await t.tap(find.text('Загрузить'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Запомнить мой выбор'));
    await t.pump();
    await t.tap(find.text('Оставить как есть'));
    await t.pump();
    await settle(t, s);
    expect(s.curSet.parts['face']!.length, 2);
    expect(s.partOf('face')!.origId, isNull);
    expect(s.p.settings.removeMode, 'keep');

    // дальше окно не спрашивает
    files.next = [PickedFile('face3.jpg', faceOnBlack())];
    await t.tap(find.text('Загрузить'));
    await t.pump();
    await settle(t, s);
    expect(find.text('Что сделать с фоном картинки?'), findsNothing);
    expect(s.curSet.parts['face']!.length, 3);
    expect(t.takeException(), isNull);
    await t.runAsync(s.flush);
  });

  testWidgets('окно «В профиле» открывается и сравнение показывает сохранённые аватарки', (t) async {
    t.view.physicalSize = const Size(1500, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = newStudio();
    await t.pumpWidget(app(s));
    s.saveLook('Один');
    s.saveLook('Два');
    await t.tap(find.text('В профиле'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Как это выглядит в профиле'), findsOneWidget);
    expect(find.text('Шапка профиля'.toUpperCase()), findsOneWidget);
    await t.tap(find.text('Закрыть'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Как это выглядит в профиле'), findsNothing);
    await t.scrollUntilVisible(find.text('Сравнить рядом'), 300, scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first);
    await t.drag(find.byType(ListView).last, const Offset(0, -400));
    await t.pump();
    await t.tap(find.text('Сравнить рядом'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Сравнение аватарок'), findsOneWidget);
    expect(find.text('Один'), findsWidgets);
    expect(t.takeException(), isNull);
    await t.runAsync(s.flush);
  });

  testWidgets('пол персонажа и кнопка «Назад»: детали другого пола скрываются, откат возвращает', (t) async {
    t.view.physicalSize = const Size(1500, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = newStudio();
    await t.pumpWidget(app(s));
    s.p.sel = 'face';
    await t.runAsync(() => s.addImages([PickedFile('m.jpg', faceOnBlack())], cut: false));
    await t.pump();
    expect(s.partOf('face'), isNotNull);
    expect(find.textContaining('Показаны детали мужского'), findsOneWidget);
    await t.tap(find.text('Женский'));
    await t.pump();
    expect(s.partOf('face'), isNull);
    expect(find.textContaining('Для женского персонажа в слоте пока нет деталей'), findsOneWidget);
    await t.tap(find.byTooltip('Назад (Ctrl+Z)'));
    await t.pump();
    expect(s.p.gender, 'male');
    expect(s.partOf('face'), isNotNull);
    await t.tap(find.byTooltip('Вперёд (Ctrl+Y)'));
    await t.pump();
    expect(s.p.gender, 'female');
    expect(t.takeException(), isNull);
    await t.runAsync(s.flush);
  });

  testWidgets('телефон: вкладки переключаются без переполнения', (t) async {
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = newStudio();
    await t.pumpWidget(app(s));
    for (final name in ['Детали', 'Положение', 'Кадр', 'Аватарки', 'Слои']) {
      await t.tap(find.text(name).first);
      await t.pump();
    }
    expect(find.text('НАБОРЫ'), findsWidgets);
    await t.tap(find.text('Кадр').first);
    await t.pump();
    expect(find.text('Какую часть показать'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(s.flush);
  });
}
