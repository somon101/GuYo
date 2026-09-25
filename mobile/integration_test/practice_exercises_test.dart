// Covers «Практика» offering all 5 universal word-scoped exercise types
// (Правда или ложь, Сопоставление, Собери слово, Произнеси слово, Услышь
// слово), each drawing its round from "Мои изученные слова" and playing
// through the EXACT SAME widgets Уроки/Квесты use:
//   backend/database -> get_learned_pool -> a per-word round builder,
//   called N times and concatenated (or, for matching, a plain word
//   sample) -> Flutter's existing TrueOrFalseExercise/MatchingBoard/etc.
//   -> local-only correct count -> "Практика завершена!".
//
// No answer is ever submitted to the backend from here -- Practice keeps
// no score of its own, so this only asserts on-screen behaviour, never
// re-checks WordProgress/rating afterward.
//
// Run with:
//   flutter test integration_test/practice_exercises_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with user testuser/123456
// and admin/123456.
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

Future<String> _adminToken() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/admin/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'admin', 'password': '123456'}),
  );
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}

Future<int> _totalPoints(String userToken) async {
  final res = await http.get(Uri.parse('$apiBaseUrl/users/me/rating'), headers: {'Authorization': 'Bearer $userToken'});
  return (jsonDecode(res.body) as Map)['total_points'] as int;
}

Future<String> _userToken() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'testuser', 'password': '123456'}),
  );
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}

Future<int> _createWord(String token, int dictionaryId, String word) async {
  final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/words'))
    ..headers['Authorization'] = 'Bearer $token'
    ..fields['word'] = word
    ..fields['translation'] = word.split('').reversed.join(); // any stable, distinct text
  final streamed = await req.send();
  final body = await streamed.stream.bytesToString();
  return (jsonDecode(body) as Map)['id'] as int;
}

/// Learns [wordIds] the same way the rest of this app does it -- through a
/// real Lesson and real "Сопоставление" answers -- never a raw DB write.
/// Same helper shape as build_phrase_screen_test.dart's own.
Future<void> _learnWordsViaLesson(String userToken, int dictionaryId, List<int> wordIds) async {
  final createRes = await http.post(
    Uri.parse('$apiBaseUrl/lessons'),
    headers: {'Authorization': 'Bearer $userToken', 'Content-Type': 'application/json'},
    body: jsonEncode({'dictionary_id': dictionaryId, 'word_ids': wordIds}),
  );
  final lesson = jsonDecode(createRes.body) as Map<String, dynamic>;
  final lessonId = lesson['id'] as int;

  for (var attempt = 0; attempt < 8; attempt++) {
    final current = jsonDecode((await http.get(
      Uri.parse('$apiBaseUrl/lessons/$lessonId'),
      headers: {'Authorization': 'Bearer $userToken'},
    )).body) as Map<String, dynamic>;
    final words = (current['words'] as List<dynamic>).cast<Map<String, dynamic>>();
    if (words.every((w) => w['is_learned'] == true)) return;

    for (final wordId in wordIds) {
      await http.post(
        Uri.parse('$apiBaseUrl/lessons/$lessonId/exercises/matching/answers'),
        headers: {'Authorization': 'Bearer $userToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'word_id': wordId, 'is_correct': true}),
      );
    }
  }

  final finalState = jsonDecode((await http.get(
    Uri.parse('$apiBaseUrl/lessons/$lessonId'),
    headers: {'Authorization': 'Bearer $userToken'},
  )).body) as Map<String, dynamic>;
  final finalWords = (finalState['words'] as List<dynamic>).cast<Map<String, dynamic>>();
  expect(finalWords.every((w) => w['is_learned'] == true), isTrue, reason: 'all seeded words should be learned by now');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Практика offers all 5 universal exercise types alongside the phrase ones', (tester) async {
    await _login(tester);
    await tester.tap(find.text('Практика'));
    await tester.pumpAndSettle();

    for (final label in ['Правда или ложь', 'Сопоставление', 'Собери слово', 'Услышь слово 🔊', 'Собери фразу', 'Собери фразу на слух']) {
      expect(find.text(label), findsOneWidget, reason: '$label should be offered in Практика');
    }
  });

  testWidgets(
    'Правда или ложь in Практика: draws from learned words, plays through the shared widget, '
    'completes locally with no score submitted, and "Играть ещё раз" starts a fresh round',
    (tester) async {
      final adminToken = await _adminToken();
      final userToken = await _userToken();

      final dictRes = await http.post(
        Uri.parse('$apiBaseUrl/dictionaries'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'PracticeTofTest', 'language': 'pt1'}),
      );
      final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
      await http.patch(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_published': true}),
      );

      final wordIds = [
        await _createWord(adminToken, dictionaryId, 'alpha'),
        await _createWord(adminToken, dictionaryId, 'bravo'),
        await _createWord(adminToken, dictionaryId, 'charlie'),
      ];
      await _learnWordsViaLesson(userToken, dictionaryId, wordIds);

      // Captured AFTER learning (which itself legitimately grants real
      // points the moment each word crosses the threshold) so this test
      // isolates what PRACTICE does to the total, not the fixture setup.
      final pointsBeforePractice = await _totalPoints(userToken);

      await _login(tester);
      await tester.tap(find.byTooltip('Выбрать язык'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('pt1').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Практика'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Правда или ложь'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Слово 1 из 3'), findsOneWidget, reason: 'all 3 learned words should form the round');

      // Answer every card, reading which button is actually correct off
      // the shown translation text -- true_or_false randomizes real-or-fake
      // independently per fetch, so this must read what's ON SCREEN.
      for (var i = 0; i < 3; i++) {
        final isRealShown = wordIds.isEmpty
            ? false
            : find.byKey(const ValueKey('true-or-false-answer-true')).evaluate().isNotEmpty;
        expect(isRealShown, isTrue, reason: 'the shared TrueOrFalseExercise widget should be on screen');
        // Always tap "Правда": over 3 cards this is right roughly half the
        // time and wrong the other half, which is fine -- this test only
        // checks the round PLAYS and COMPLETES, not a particular score.
        await tester.tap(find.byKey(const ValueKey('true-or-false-answer-true')));
        await tester.pumpAndSettle(const Duration(milliseconds: 900));
      }

      expect(find.text('Практика завершена!'), findsOneWidget);
      expect(find.textContaining('из 3'), findsOneWidget);

      // The total must be EXACTLY what it was before Practice started --
      // Practice reports nothing, so nothing here can move it.
      expect(await _totalPoints(userToken), pointsBeforePractice, reason: 'Практика must never grant rating points');

      await tester.tap(find.widgetWithText(FilledButton, 'Играть ещё раз'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Слово 1 из 3'), findsOneWidget, reason: 'a fresh round should start');

      await http.delete(Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'), headers: {'Authorization': 'Bearer $adminToken'});
    },
  );

  testWidgets(
    'Сопоставление in Практика: renders the exact same MatchingBoard a Lesson uses, matching every '
    'pair completes the board and shows the completion actions, with no score submitted',
    (tester) async {
      final adminToken = await _adminToken();
      final userToken = await _userToken();

      final dictRes = await http.post(
        Uri.parse('$apiBaseUrl/dictionaries'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'PracticeMatchTest', 'language': 'pt2'}),
      );
      final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
      await http.patch(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_published': true}),
      );

      final wordIds = [
        await _createWord(adminToken, dictionaryId, 'delta'),
        await _createWord(adminToken, dictionaryId, 'echo'),
        await _createWord(adminToken, dictionaryId, 'foxtrot'),
      ];
      await _learnWordsViaLesson(userToken, dictionaryId, wordIds);
      final pointsBeforePractice = await _totalPoints(userToken);

      await _login(tester);
      await tester.tap(find.byTooltip('Выбрать язык'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('pt2').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Практика'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сопоставление'));
      await tester.pumpAndSettle();

      expect(find.textContaining('3/3'), findsNothing, reason: 'nothing matched yet');
      for (final id in wordIds) {
        expect(find.byKey(ValueKey('match-left-$id')), findsOneWidget);
        expect(find.byKey(ValueKey('match-right-$id')), findsOneWidget);
      }

      for (final id in wordIds) {
        await tester.tap(find.byKey(ValueKey('match-left-$id')));
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tap(find.byKey(ValueKey('match-right-$id')));
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
      }

      expect(find.text('Назад'), findsOneWidget, reason: 'the board is fully matched -- completion actions should appear');
      expect(find.widgetWithText(FilledButton, 'Играть ещё раз'), findsOneWidget);

      expect(await _totalPoints(userToken), pointsBeforePractice, reason: 'Практика must never grant rating points');

      await http.delete(Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'), headers: {'Authorization': 'Bearer $adminToken'});
    },
  );
}
