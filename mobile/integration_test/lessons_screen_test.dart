// Covers "Уроки" end to end against the real backend, through the NEW
// auto-sequenced lesson runner (tap "Начать урок" once, no manual
// exercise picking -- the app runs every available exercise type in the
// backend's own fixed order automatically):
//   - no lessons yet -> the chain shows a single unlocked "create" link;
//   - random selection creates Lesson 1, visible in the chain as
//     in-progress; opening it shows the word list + "Начать урок", never a
//     manual exercise menu;
//   - tapping "Начать урок" auto-opens Сопоставление first (no previously-
//     learned pool exists yet, so "Правда или ложь" isn't part of the
//     sequence at all for this very first lesson -- see EXERCISE_AVAILABILITY
//     in lessons.py), then auto-advances to Собери слово the moment that
//     round's last answer lands: no completion panel, no "Играть ещё раз",
//     no "К уроку", nothing to tap in between;
//   - one pass (matching +20, build_word +30 = 50) leaves the words below
//     the learned threshold, so the single results screen reports the
//     lesson unfinished and offers "Повторить урок"; the repeat runs the
//     same sequence again over the words still short and finishes them;
//   - answering correctly raises each specific word's own score (never a
//     lesson-wide total); once every word crosses the admin threshold, the
//     sequence ends and the lesson's own RESULTS screen shows "Урок пройден"
//     -- those words show up under "Мои слова", Lesson 1 stays in the chain
//     marked "Пройден", and a new unlocked link for Lesson 2 appears --
//     Lesson 1 is NEVER removed or replaced;
//   - a new lesson cannot be created while one is still active/incomplete
//     (enforced by the chain only ever showing an unlocked "create" link
//     once the last real lesson is complete);
//   - manual selection (checkboxes, grouped by category) creates Lesson 2
//     from a hand-picked word set, and once a learned-words pool exists
//     "Правда или ложь" becomes available too -- now leading the auto
//     sequence, since it comes first in the backend's own exercise order;
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
//     apple/book/house/cat/doggo/dog), and matching +20 / build_word +30.
//     The learned threshold is read from the backend at run time, not
//     assumed. listen_word and speaking_word are switched off for the
//     duration of this file (see _exercisesOffDuringThisFile) so the
//     sequence under test does not change when a word gains audio.
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

Future<String> _adminToken() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/admin/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'admin', 'password': '123456'}),
  );
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}

Future<void> _setExerciseEnabled(String token, String exerciseKey, bool enabled) async {
  await http.put(
    Uri.parse('$apiBaseUrl/exercise-settings/$exerciseKey'),
    headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    body: jsonEncode({'word_count': 10, 'enabled': enabled}),
  );
}

/// The exercises this file drives by hand. Everything else is switched off
/// for the duration of the run, and switched back on afterwards.
///
/// Which exercises a lesson offers depends on the DATA -- listen_word, for
/// instance, appears as soon as the fixture's words have audio. This file
/// is about the lesson RUNNER (one continuous pass, nothing to tap between
/// exercises), so it pins the set rather than silently changing meaning
/// when a word gains a recording.
const List<String> _exercisesOffDuringThisFile = ['listen_word', 'speaking_word'];

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

/// Plays every word of the "Собери слово" round currently on screen.
///
/// Driven by what is actually rendered rather than by a fixed count: the
/// round only ever contains the words still short of the threshold, so its
/// length differs between the first pass and a repeat.
Future<void> _buildAllWordsCorrectly(WidgetTester tester) async {
  var played = 0;
  while (find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith('build-word-active-');
  }).evaluate().isNotEmpty) {
    await _buildWordCorrectly(tester, _readCurrentBuildWordCorrectWord(tester));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    played++;
    if (played > 15) fail('build_word round never ended -- more items than a lesson can hold');
  }
  expect(played, greaterThan(0), reason: 'the round should have had at least one word to build');
}

/// The score a word must reach to count as learned: the top word level's
/// own lower bound. Read from the backend rather than assumed, so a
/// changed level ladder fails loudly here instead of quietly breaking the
/// pass/fail assertions further down.
Future<int> _learnedThreshold(String token) async {
  final res = await http.get(
    Uri.parse('$apiBaseUrl/word-levels'),
    headers: {'Authorization': 'Bearer $token'},
  );
  final levels = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
  return (levels.last as Map<String, dynamic>)['min_points'] as int;
}

Future<void> _matchAllCorrectly(WidgetTester tester, List<int> wordIds) async {
  for (final id in wordIds) {
    await tester.tap(find.byKey(ValueKey('match-left-$id')));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byKey(ValueKey('match-right-$id')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }
}

/// A lesson is one continuous run: between two exercises, and between the
/// last exercise and the results, the user must never be shown a
/// completion panel or asked to tap anything to continue.
void _expectNoBetweenExerciseScreen() {
  expect(find.text('Упражнение завершено!'), findsNothing);
  expect(find.text('Раунд завершён!'), findsNothing);
  expect(find.text('Играть ещё раз'), findsNothing);
  expect(find.text('К уроку'), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final admin = await _adminToken();
    for (final key in _exercisesOffDuringThisFile) {
      await _setExerciseEnabled(admin, key, false);
    }
  });

  tearDownAll(() async {
    final admin = await _adminToken();
    for (final key in _exercisesOffDuringThisFile) {
      await _setExerciseEnabled(admin, key, true);
    }
  });

  testWidgets(
    'random lesson: "Начать урок" auto-runs Сопоставление then Собери слово with no manual picking, '
    'Lesson 1 stays in the chain as "Пройден" after completion (never removed), and Lesson 2 unlocks next to it',
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

      // Open Lesson 1's own screen: word list + one "Начать урок" button,
      // never a manual exercise menu.
      await tester.tap(find.text('Урок 1'));
      await tester.pumpAndSettle();
      expect(find.text('Начать урок'), findsOneWidget);
      expect(find.text('Сопоставление'), findsNothing, reason: 'no manual exercise buttons any more');

      await tester.tap(find.text('Начать урок'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // --- First in the auto sequence: Сопоставление (AppBar confirms it,
      // "Правда или ложь" never appears at all -- no learned pool yet) ---
      expect(find.text('Сопоставление'), findsOneWidget);
      expect(find.textContaining('Правильно: 0/3'), findsOneWidget);

      // One pass over this fixture is worth matching (+20) + build_word
      // (+30) = 50 per word, so it takes two passes to clear the bar.
      // Both facts are checked against the backend's own ladder rather
      // than assumed, so a changed fixture fails here with a clear reason.
      final threshold = await _learnedThreshold(token);
      expect(50, lessThan(threshold), reason: 'one pass must leave the lesson unfinished');
      expect(100, greaterThanOrEqualTo(threshold), reason: 'two passes must finish it');

      // --- Pass 1: Сопоставление, then Собери слово, with NOTHING between ---
      await _matchAllCorrectly(tester, wordIds);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      _expectNoBetweenExerciseScreen();
      expect(find.text('Собери слово'), findsOneWidget, reason: 'the next exercise started on its own');

      await _buildAllWordsCorrectly(tester);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Every available exercise has now seen every word, so the ONE
      // results screen appears by itself -- again with nothing in between.
      _expectNoBetweenExerciseScreen();
      expect(find.textContaining('результаты'), findsOneWidget);

      // Still short of the threshold, so the lesson is NOT passed and the
      // repeat is offered instead of "Готово".
      expect(find.text('Урок пройден'), findsNothing);
      expect(find.textContaining('Достигли нужного уровня: 0 из 3'), findsOneWidget);
      expect(find.text('Повторить урок'), findsOneWidget);

      // --- Pass 2: the repeat runs the same sequence over the words that
      // are still short, and finishes them ---
      await tester.tap(find.text('Повторить урок'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('Сопоставление'), findsOneWidget, reason: 'the repeat restarts the sequence by itself');

      await _matchAllCorrectly(tester, wordIds);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      _expectNoBetweenExerciseScreen();
      expect(find.text('Собери слово'), findsOneWidget);

      await _buildAllWordsCorrectly(tester);
      await tester.pumpAndSettle(const Duration(seconds: 4));

      _expectNoBetweenExerciseScreen();
      expect(find.textContaining('результаты'), findsOneWidget);
      expect(find.text('Урок пройден'), findsOneWidget, reason: 'every word is now at 100 >= the threshold');
      expect(find.text('Готово'), findsOneWidget);
      expect(find.text('Повторить урок'), findsNothing);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Back on Lesson 1's own (now-history) screen -- "Пройден" banner,
      // no "Начать урок" button any more (a completed lesson is read-only).
      expect(find.text('Урок пройден'), findsOneWidget);
      expect(find.text('Начать урок'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Lesson 1 stays in the chain, now marked "Пройден" -- it is NOT
      // removed or replaced by a fresh lesson-creation prompt.
      expect(find.text('Урок 1'), findsOneWidget);
      expect(find.text('Пройден'), findsOneWidget);
      // A new unlocked link for Lesson 2 appears right after it.
      expect(find.text('Урок 2'), findsOneWidget);
      expect(find.text('Доступен для создания'), findsOneWidget);

      // --- Мои слова: all 3 lesson words now show up there ---
      await tester.tap(find.text('Мои слова'));
      await tester.pumpAndSettle();
      expect(find.text('Мои слова'), findsOneWidget);
      expect(find.text('Без категории'), findsOneWidget);
      expect(find.text('3 слова'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'manual lesson: checkbox selection creates Lesson 2 from the hand-picked words, it joins the '
    'chain alongside the still-present Lesson 1, and Начать урок now leads with Правда или ложь',
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
      expect(find.text('Начать урок'), findsOneWidget);

      await tester.tap(find.text('Начать урок'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Правда или ложь now comes FIRST in the auto sequence -- it's first
      // in the backend's own exercise order and is available for the first
      // time now that Lesson 1's 3 words form a real learned pool.
      expect(
        find.text('Правда или ложь'),
        findsOneWidget,
        reason: 'the 3 words learned in Lesson 1 are now a usable pool for True/False',
      );
      expect(find.widgetWithText(FilledButton, 'Правда'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Ложь'), findsOneWidget);
      expect(find.textContaining('Правильно: 0/3'), findsOneWidget);
    },
  );
}
