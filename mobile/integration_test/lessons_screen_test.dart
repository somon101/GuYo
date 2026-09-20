// Covers "Уроки" end to end against the real backend:
//   - no lessons yet -> the chain shows a single unlocked "create" link;
//   - random selection creates Lesson 1, visible in the chain as
//     in-progress; opening it shows only "Сопоставление"/"Собери слово"
//     (no previously-learned pool exists yet, so "Правда или ложь" isn't
//     available for this very first lesson -- see EXERCISE_AVAILABILITY in
//     lessons.py);
//   - answering correctly in those exercises raises each specific word's
//     own score (never a lesson-wide total); once every word crosses the
//     admin threshold, the lesson-complete screen appears, those words show
//     up under "Мои слова", Lesson 1 stays in the chain marked "Пройден",
//     and a new unlocked link for Lesson 2 appears -- Lesson 1 is NEVER
//     removed or replaced;
//   - a new lesson cannot be created while one is still active/incomplete
//     (enforced by the chain only ever showing an unlocked "create" link
//     once the last real lesson is complete);
//   - manual selection (checkboxes, grouped by category) creates Lesson 2
//     from a hand-picked word set, and once a learned-words pool exists
//     "Правда или ложь" becomes available too;
//   - after re-loading the chain, BOTH lessons remain, in the right order,
//     with the right statuses -- lessons are permanent, not swapped out.
//
// Run with:
//   flutter test integration_test/lessons_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456
//   - an English dictionary with exactly 6 words, none of them already
//     learned/in a lesson (this repo's dev data already has exactly 6:
//     apple/book/house/cat/doggo/dog), and default exercise/threshold
//     settings (threshold 60, matching +20, build_word +30)
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

  expect(find.text('Главная'), findsOneWidget, reason: 'should reach the home screen');
}

Future<void> _openLessonsTab(WidgetTester tester) async {
  await tester.tap(find.text('Уроки'));
  await tester.pumpAndSettle();
}

Future<String> _userToken() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'testuser', 'password': '123456'}),
  );
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}

Future<int> _englishDictionaryId(String token) async {
  final res = await http.get(
    Uri.parse('$apiBaseUrl/dictionaries'),
    headers: {'Authorization': 'Bearer $token'},
  );
  return (jsonDecode(res.body) as List).firstWhere((d) => d['language'] == 'en')['id'] as int;
}

Future<Map<String, dynamic>> _activeLesson(String token, int dictionaryId) async {
  final res = await http.get(
    Uri.parse('$apiBaseUrl/lessons/active?dictionary_id=$dictionaryId'),
    headers: {'Authorization': 'Bearer $token'},
  );
  expect(res.statusCode, 200, reason: 'expected an active lesson to exist by now');
  return jsonDecode(res.body) as Map<String, dynamic>;
}

/// Taps pool letters, in order, to spell [word] correctly, then presses
/// "Проверить" -- same helper shape as the old build_word integration test.
Finder get _poolArea => find.byKey(const ValueKey('build-word-pool'));

Future<void> _buildWordCorrectly(WidgetTester tester, String word) async {
  for (final letter in word.split('')) {
    final button = find.descendant(of: _poolArea, matching: find.text(letter)).first;
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.tap(find.byKey(const ValueKey('build-word-check-button')));
  await tester.pump(const Duration(milliseconds: 80));
}

String _readCurrentBuildWordCorrectWord(WidgetTester tester) {
  final matches = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith('build-word-active-');
  });
  expect(matches, findsOneWidget, reason: 'exactly one active build-word item should be shown');
  final key = (tester.widget(matches).key! as ValueKey<String>).value;
  final firstDash = key.indexOf('-', 'build-word-active-'.length);
  return key.substring(firstDash + 1);
}

Future<void> _matchAllCorrectly(WidgetTester tester, List<int> wordIds) async {
  for (final id in wordIds) {
    await tester.tap(find.byKey(ValueKey('match-left-$id')));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byKey(ValueKey('match-right-$id')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'random lesson: chain shows the unlocked create-link first, Lesson 1 stays in the chain as '
    '"Пройден" after completion (never removed), and Lesson 2 unlocks next to it',
    (tester) async {
      final token = await _userToken();
      final dictionaryId = await _englishDictionaryId(token);

      await _login(tester);
      await _openLessonsTab(tester);

      // No lessons yet -- the chain is just one unlocked "create" link.
      expect(find.text('Создайте первый урок, чтобы начать'), findsOneWidget);
      expect(find.text('Урок 1'), findsOneWidget);
      await tester.tap(find.text('Создать урок'));
      await tester.pumpAndSettle();

      // Random mode is the default; drive the stepper down to 3 (default
      // starts at min(available, 15) = 6 for this fixture).
      final countFinder = find.byKey(const ValueKey('lesson-random-count'));
      var current = int.parse(tester.widget<Text>(countFinder).data!);
      while (current > 3) {
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pump();
        current--;
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Создать урок'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Back on the chain -- Lesson 1 now shows as its own (in-progress)
      // link, not a full-screen replacement of the chain itself.
      expect(find.text('Урок 1'), findsOneWidget);
      expect(find.textContaining('Изучено 0 из 3'), findsOneWidget);

      final lessonWords = (await _activeLesson(token, dictionaryId))['words'] as List<dynamic>;
      final wordIds = lessonWords.map((w) => w['word_id'] as int).toList();
      expect(wordIds.length, 3);

      // Open Lesson 1's own screen to see its exercises.
      await tester.tap(find.text('Урок 1'));
      await tester.pumpAndSettle();
      expect(find.text('Сопоставление'), findsOneWidget);
      expect(find.text('Собери слово'), findsOneWidget);
      expect(
        find.text('Правда или ложь'),
        findsNothing,
        reason: 'first-ever lesson has no previously-learned pool, so True/False cannot be offered',
      );

      // --- Matching, played twice (each correct match is +20): total +40 ---
      await tester.tap(find.text('Сопоставление'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Правильно: 0/3'), findsOneWidget);

      await _matchAllCorrectly(tester, wordIds);
      expect(find.text('Раунд завершён!'), findsOneWidget);
      expect(find.text('Урок пройден!'), findsNothing, reason: '+20 alone must stay below the threshold (60)');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Играть ещё раз'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await _matchAllCorrectly(tester, wordIds);
      expect(find.text('Раунд завершён!'), findsOneWidget);
      expect(find.text('Урок пройден!'), findsNothing, reason: '+40 total must still stay below the threshold (60)');
      await tester.tap(find.widgetWithText(FilledButton, 'К уроку'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Back on Lesson 1's own screen (its AppBar reads "Урок 1"), not yet
      // complete.
      expect(find.text('Урок 1'), findsOneWidget, reason: 'back on lesson 1\'s own screen, not yet complete');
      expect(find.textContaining('Изучено 0 из 3'), findsOneWidget);

      // --- Build word, once (+30): total 40+30 = 70 >= threshold (60) ---
      await tester.tap(find.text('Собери слово'));
      await tester.pumpAndSettle();

      for (var i = 0; i < wordIds.length; i++) {
        final word = _readCurrentBuildWordCorrectWord(tester);
        await _buildWordCorrectly(tester, word);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      expect(find.text('Упражнение завершено!'), findsOneWidget);
      expect(find.textContaining('Собрано слов: 3 из 3'), findsOneWidget);
      expect(
        find.text('Урок пройден!'),
        findsOneWidget,
        reason: 'every word should now be at 70 >= the 60 threshold',
      );

      // The round-complete button now leads to a dedicated completion
      // screen instead of popping straight back.
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('УРОК 1'), findsOneWidget);
      expect(find.text('Пройден!'), findsOneWidget);

      // Continuing from there returns all the way to the "Уроки" chain --
      // never to Lesson 1's own (now-history) screen.
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Lesson 1 stays in the chain, now marked "Пройден" -- it is NOT
      // removed or replaced by a fresh lesson-creation prompt.
      expect(find.text('Урок 1'), findsOneWidget);
      expect(find.text('Пройден'), findsOneWidget);
      // A new unlocked link for Lesson 2 appears right after it.
      expect(find.text('Урок 2'), findsOneWidget);
      expect(find.text('Доступен для создания'), findsOneWidget);

      // --- Мои слова: all 3 lesson words now show up there ---
      await tester.tap(find.widgetWithIcon(TextButton, Icons.bookmark_outline));
      await tester.pumpAndSettle();
      expect(find.text('Мои изученные слова'), findsOneWidget);
      expect(find.text('Без категории'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Re-open Lesson 1 directly: it must still be there, read-only (no
      // exercise buttons -- a completed lesson is history, not replayable).
      await tester.tap(find.text('Урок 1'));
      await tester.pumpAndSettle();
      expect(find.text('Урок пройден'), findsOneWidget);
      expect(find.text('Сопоставление'), findsNothing, reason: 'a completed lesson shows no exercise buttons');
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'manual lesson: checkbox selection creates Lesson 2 from the hand-picked words, it joins the '
    'chain alongside the still-present Lesson 1, and Правда или ложь is now available',
    (tester) async {
      final token = await _userToken();
      final dictionaryId = await _englishDictionaryId(token);

      await _login(tester);
      await _openLessonsTab(tester);

      // Both lessons from the previous test must still be present.
      expect(find.text('Урок 1'), findsOneWidget);
      expect(find.text('Пройден'), findsOneWidget);
      expect(find.text('Урок 2'), findsOneWidget);

      // The 3 remaining never-learned words from the fixture (the other 3
      // were learned by the previous test in this same run).
      final res = await http.get(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/lesson-candidate-words'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final candidateWords = (jsonDecode(res.body) as Map)['words'] as List<dynamic>;
      expect(candidateWords.length, 3, reason: 'exactly the 3 words not consumed by the previous test');
      final targetIds = candidateWords.map((w) => w['id'] as int).toList();

      await tester.tap(find.text('Доступен для создания'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Вручную'));
      await tester.pumpAndSettle();

      // Expand the (single, "Без категории") group and check every word.
      await tester.tap(find.text('Без категории'));
      await tester.pumpAndSettle();
      for (final id in targetIds) {
        await tester.tap(find.byKey(ValueKey('lesson-word-checkbox-$id')));
        await tester.pump();
      }
      expect(find.textContaining('Выбрано: 3/15'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Создать урок (3)'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Back on the chain: both lessons present, in order, right statuses.
      expect(find.text('Урок 1'), findsOneWidget);
      expect(find.text('Пройден'), findsOneWidget);
      expect(find.text('Урок 2'), findsOneWidget);
      expect(find.textContaining('Изучено 0 из 3'), findsOneWidget);

      await tester.tap(find.text('Урок 2'));
      await tester.pumpAndSettle();
      expect(
        find.text('Правда или ложь'),
        findsOneWidget,
        reason: 'the 3 words learned in Lesson 1 are now a usable pool for True/False',
      );
      expect(find.text('Сопоставление'), findsOneWidget);
      expect(find.text('Собери слово'), findsOneWidget);

      // Smoke-test True/False actually loads a playable round.
      await tester.tap(find.text('Правда или ложь'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Правда'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Ложь'), findsOneWidget);
      expect(find.textContaining('Правильно: 0/3'), findsOneWidget);
    },
  );
}
