// Covers "Правда или ложь" end to end against the real backend:
//   - with zero learned words, a clean empty state (no crash, no round);
//   - after learning some words via "Изучение слов", the round only ever
//     draws from those learned words (proven by checking every card's
//     word against the real learned-words list from the API);
//   - answering "Правда"/"Ложь" advances through the round and the score
//     line updates;
//   - the round completes after every card is answered, and "Играть ещё
//     раз" starts a fresh one.
//
// Run with:
//   flutter test integration_test/true_or_false_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456
//   - an English dictionary with at least 3 words, none of them already
//     learned by testuser (this repo's dev data has exactly 6:
//     apple/book/house/cat/doggo/dog)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.pumpWidget(const GuyoApp());
  await tester.pumpAndSettle(const Duration(seconds: 2));

  if (find.text('Главная').evaluate().isNotEmpty) {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
  }

  expect(find.text('Вход'), findsOneWidget, reason: 'should start at the login screen');

  await tester.enterText(find.byType(TextField).at(0), 'testuser');
  await tester.enterText(find.byType(TextField).at(1), '123456');
  await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
  await tester.pumpAndSettle(const Duration(seconds: 3));

  expect(find.text('Главная'), findsOneWidget, reason: 'should reach the home screen (main menu)');
}

Future<Set<int>> _fetchLearnedWordIds() async {
  final loginRes = await http.post(
    Uri.parse('$apiBaseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'testuser', 'password': '123456'}),
  );
  final token = (jsonDecode(loginRes.body) as Map)['access_token'] as String;
  final dictsRes = await http.get(
    Uri.parse('$apiBaseUrl/dictionaries'),
    headers: {'Authorization': 'Bearer $token'},
  );
  final englishId = (jsonDecode(dictsRes.body) as List).firstWhere((d) => d['language'] == 'en')['id'] as int;
  final res = await http.get(
    Uri.parse('$apiBaseUrl/learned-words?dictionary_id=$englishId'),
    headers: {'Authorization': 'Bearer $token'},
  );
  return (jsonDecode(res.body) as List).map((w) => w['id'] as int).toSet();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty state with zero learned words, no crash', (tester) async {
    await _login(tester);

    await tester.tap(find.text('Правда или ложь'));
    await tester.pumpAndSettle();

    expect(find.textContaining('не изучили ни одного слова'), findsOneWidget);
    expect(find.text('Правда'), findsNothing);
    expect(find.text('Ложь'), findsNothing);
  });

  testWidgets('learn some words, then the round only ever uses learned words and completes correctly', (tester) async {
    await _login(tester);

    // Learn 3 words via the existing "Изучение слов" flow -- reused
    // as-is, not reimplemented here.
    await tester.tap(find.text('Изучение слов'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Начать изучение'));
    await tester.pumpAndSettle();
    // Default count is 10 but only 6 dev words exist; step it down to 3.
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Начать'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.widgetWithText(FilledButton, 'Изучил'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    expect(find.text('Изучение завершено'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final learnedIds = await _fetchLearnedWordIds();
    expect(learnedIds.length, 3, reason: 'fixture should have learned exactly 3 words');

    // Now run "Правда или ложь" and confirm every card is one of those 3.
    await tester.tap(find.text('Правда или ложь'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Правильно: 0/3'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Правда'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Ложь'), findsOneWidget);

    for (var round = 0; round < 3; round++) {
      // The card's Key carries the real word_id -- assert it's one of the
      // words we actually learned, never anything else.
      final cardFinder = find.byWidgetPredicate(
        (w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('true-or-false-card-'),
      );
      expect(cardFinder, findsOneWidget);
      final key = (tester.widget(cardFinder).key as ValueKey).value as String;
      final shownWordId = int.parse(key.replaceFirst('true-or-false-card-', ''));
      expect(learnedIds.contains(shownWordId), isTrue,
          reason: 'card word_id $shownWordId must be one of the learned words $learnedIds');

      // Alternate answers; correctness doesn't matter for this test, only
      // that the round advances and the score line updates sensibly.
      await tester.tap(round.isEven
          ? find.widgetWithText(FilledButton, 'Правда')
          : find.widgetWithText(OutlinedButton, 'Ложь'));
      await tester.pumpAndSettle(const Duration(milliseconds: 700));
    }

    expect(find.text('Упражнение завершено!'), findsOneWidget);
    expect(find.textContaining('Правильно:'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Играть ещё раз'), findsOneWidget);

    // Replay starts a fresh round (score resets, a card shows again).
    await tester.tap(find.widgetWithText(FilledButton, 'Играть ещё раз'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Правильно: 0/3'), findsOneWidget);
  });
}
