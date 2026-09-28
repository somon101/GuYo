// The iOS-style "Новый урок" picker: segmented modes, search, "Выбрать
// все" per category and the 15-word cap.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:guyo_app/models/dictionary.dart';
import 'package:guyo_app/screens/lesson_create_screen.dart';

Map<String, dynamic> _word(int id, String category) => {
      'id': id,
      'dictionary_id': 1,
      'word': 'word$id',
      'translation': 'перевод$id',
      'category_name': category,
    };

final _client = MockClient((request) async {
  final words = [
    for (var i = 1; i <= 12; i++) _word(i, 'Еда'),
    for (var i = 13; i <= 20; i++) _word(i, 'Дом'),
  ];
  return http.Response.bytes(
    utf8.encode(jsonEncode({'dictionary_id': 1, 'available_count': words.length, 'words': words})),
    200,
    headers: {'content-type': 'application/json'},
  );
});

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: LessonCreateScreen(
      dictionary: GuyoDictionary.fromJson({'id': 1, 'name': 'English', 'language': 'en'}),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('random mode: stepper and quick picks', (tester) async {
    await http.runWithClient(() async {
      await _open(tester);
      final count = find.byKey(const ValueKey('lesson-random-count'));
      expect(tester.widget<Text>(count).data, '15');
      expect(find.textContaining('доступно 20'), findsOneWidget);

      await tester.tap(find.text('5'));
      await tester.pump();
      expect(tester.widget<Text>(count).data, '5');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(tester.widget<Text>(count).data, '6');
      expect(find.text('Начать урок'), findsOneWidget);
    }, () => _client);
  });

  testWidgets('manual mode: search, select all, cap at 15', (tester) async {
    await http.runWithClient(() async {
      await _open(tester);
      await tester.tap(find.text('Вручную'));
      await tester.pumpAndSettle();
      expect(find.text('Выбрано 0 из 15'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lesson-word-checkbox-3')));
      await tester.pump();
      expect(find.text('Начать урок (1)'), findsOneWidget);

      // "Выбрать все" on Еда (12 words), then on Дом: only 3 more fit.
      await tester.tap(find.text('Выбрать все').first);
      await tester.pump();
      expect(find.text('Выбрано 12 из 15'), findsOneWidget);
      expect(find.text('Снять'), findsOneWidget);
      await tester.tap(find.text('Выбрать все'));
      await tester.pump();
      expect(find.text('Выбрано 15 из 15'), findsOneWidget);

      // Full: an unselected row doesn't react.
      await tester.tap(find.byKey(const ValueKey('lesson-word-checkbox-20')));
      await tester.pump();
      expect(find.text('Выбрано 15 из 15'), findsOneWidget);

      await tester.tap(find.text('Снять'));
      await tester.pump();
      expect(find.text('Выбрано 3 из 15'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'перевод14');
      await tester.pump();
      expect(find.byKey(const ValueKey('lesson-word-checkbox-14')), findsOneWidget);
      expect(find.byKey(const ValueKey('lesson-word-checkbox-1')), findsNothing);
    }, () => _client);
  });
}
