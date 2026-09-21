// Covers "Практика" / "Собери фразу" end to end against the real backend:
//   backend/database -> API -> Flutter -> получение изученных слов ->
//   получение доступных фраз -> генерация задания -> удаление одного
//   слова -> генерация вариантов -> перемешивание -> выбор ответа ->
//   переход к следующему заданию.
//
// Run with:
//   flutter test integration_test/build_phrase_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456
//   - default exercise/threshold settings (threshold 60, matching +20)
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
    ..fields['translation'] = 'x';
  final streamed = await req.send();
  final body = await streamed.stream.bytesToString();
  return (jsonDecode(body) as Map)['id'] as int;
}

Future<void> _createPhrase(String token, int dictionaryId, String original, String translationTg) async {
  final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/phrases'))
    ..headers['Authorization'] = 'Bearer $token'
    ..fields['original'] = original
    ..fields['translation_tg'] = translationTg;
  await req.send();
}

Future<void> _addForm(String token, int wordId, String language, String text) async {
  final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/words/$wordId/forms'))
    ..headers['Authorization'] = 'Bearer $token'
    ..fields['language'] = language
    ..fields['text'] = text;
  await req.send();
}

/// Learns [wordIds] the same way the rest of this app does it -- through a
/// real Lesson (POST /lessons, then correct answers via whichever exercise
/// the backend decided is available), never a raw DB write. Loops
/// submitting correct "matching" answers until every word's WordProgress
/// crosses the threshold (checked via the lesson's own `is_learned` field),
/// so this stays correct even if the admin-configured points/threshold
/// change later.
Future<void> _learnWordsViaLesson(String userToken, int dictionaryId, List<int> wordIds) async {
  final createRes = await http.post(
    Uri.parse('$apiBaseUrl/lessons'),
    headers: {'Authorization': 'Bearer $userToken', 'Content-Type': 'application/json'},
    body: jsonEncode({'dictionary_id': dictionaryId, 'word_ids': wordIds}),
  );
  final lesson = jsonDecode(createRes.body) as Map<String, dynamic>;
  final lessonId = lesson['id'] as int;
  final exerciseKeys = (lesson['exercise_keys'] as List<dynamic>).cast<String>();
  expect(exerciseKeys, contains('matching'), reason: '>=2 words should always make "Сопоставление" available');

  for (var attempt = 0; attempt < 6; attempt++) {
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

String _readCurrentCorrectAnswer(WidgetTester tester) {
  final matches = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith('build-phrase-task-');
  });
  expect(matches, findsOneWidget, reason: 'exactly one active build-phrase task should be shown');
  final key = (tester.widget(matches).key! as ValueKey<String>).value;
  // Format: build-phrase-task-<phraseId>-<correctAnswerText>
  final withoutPrefix = key.substring('build-phrase-task-'.length);
  final firstDash = withoutPrefix.indexOf('-');
  return withoutPrefix.substring(firstDash + 1);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('English dictionary with no learned words yet -> clean empty state, no crash', (tester) async {
    await _login(tester);
    await tester.tap(find.text('Практика'));
    await tester.pumpAndSettle();

    expect(find.text('Собери фразу'), findsOneWidget);
    await tester.tap(find.text('Собери фразу'));
    await tester.pumpAndSettle();

    // This repo's dev "English" dictionary (id 1) has no phrases at all,
    // so this is also exercising "phrases exist nowhere for this
    // dictionary" as a form of "insufficient data", not just "no learned
    // words" specifically.
    expect(find.textContaining('недостаточно данных'), findsOneWidget);
  });

  testWidgets(
    'a fresh language with learned words and an available phrase: the task shows the blank + '
    'translation, options are offered, tapping the correct one advances, and the round completes',
    (tester) async {
      final adminToken = await _adminToken();
      final userToken = await _userToken();

      // A brand new, distinct language code -- never collides with this
      // repo's existing "en"/"ru"/"zh" dev dictionaries, so the app's
      // language switcher offers it as its own separate option.
      final dictRes = await http.post(
        Uri.parse('$apiBaseUrl/dictionaries'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'BuildPhraseTest', 'language': 'bp'}),
      );
      final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
      await http.patch(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_published': true}),
      );

      final goId = await _createWord(adminToken, dictionaryId, 'go');
      final homeId = await _createWord(adminToken, dictionaryId, 'home');
      final fastId = await _createWord(adminToken, dictionaryId, 'fast');
      await _createPhrase(adminToken, dictionaryId, 'go home fast', 'test-translation-phrase');

      await _learnWordsViaLesson(userToken, dictionaryId, [goId, homeId, fastId]);

      await _login(tester);

      // Switch the language switcher to the new "bp" dictionary.
      await tester.tap(find.byTooltip('Выбрать язык'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('bp').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Практика'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Собери фразу'));
      await tester.pumpAndSettle();

      expect(find.text('Фраза 1 из 1'), findsOneWidget, reason: 'exactly one phrase exists for this language');
      expect(find.text('test-translation-phrase'), findsOneWidget, reason: 'the translation hint should be shown');

      final correctAnswer = _readCurrentCorrectAnswer(tester);
      expect(['go', 'home', 'fast'], contains(correctAnswer), reason: 'the blanked word must be one of the 3 seeded words');

      // The exact blanked-out word must not still be visible as plain text
      // in the sentence itself (it was replaced by a blank) -- scoped to
      // the sentence area specifically, since a wrong-answer OPTION below
      // may legitimately repeat the same word text (it's drawn from the
      // same 3-word vocabulary).
      final sentence = find.byKey(const ValueKey('build-phrase-sentence'));
      final remainingWords = ['go', 'home', 'fast'].where((w) => w != correctAnswer);
      for (final w in remainingWords) {
        expect(
          find.descendant(of: sentence, matching: find.text(w)),
          findsOneWidget,
          reason: 'the two NOT blanked words should still show in the sentence',
        );
      }
      expect(
        find.descendant(of: sentence, matching: find.text(correctAnswer)),
        findsNothing,
        reason: 'the blanked word must not still appear as plain text in the sentence',
      );

      // Tap the correct option and confirm it's visually marked correct,
      // then confirm the round completes (only 1 phrase was available).
      await tester.tap(find.text(correctAnswer));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.check_circle), findsWidgets, reason: 'the correct option should show a check mark');

      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Практика завершена!'), findsOneWidget);
      expect(find.textContaining('Правильно: 1 из 1'), findsOneWidget);

      // Replay draws a fresh (here: the same single) task -- must not
      // crash and must show the same phrase again since it's still the
      // only one available.
      await tester.tap(find.widgetWithText(FilledButton, 'Играть ещё раз'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Фраза 1 из 1'), findsOneWidget);

      // Cleanup: remove the temporary dictionary (cascades its words/
      // phrases/lessons/word_progress).
      await http.delete(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken'},
      );
    },
  );

  testWidgets(
    'the correct answer is the phrase\'s own grammatical FORM ("могу"), never the learned '
    'word\'s base dictionary form ("мочь")',
    (tester) async {
      final adminToken = await _adminToken();
      final userToken = await _userToken();

      // Uses "zh" as this dictionary's own language: WordForm.language is
      // validated against the fixed translation-language allow-list
      // (en/ru/zh/tg -- see app/core/languages.py), NOT against whatever
      // free-text language a Dictionary itself carries, so a form can only
      // ever be added in one of those four codes regardless of the
      // dictionary's own language string. This repo's dev "中文" (zh)
      // dictionary is currently an unpublished draft, so it stays
      // invisible to testuser and never collides with this test's own
      // freshly-published "zh" dictionary in the language switcher.
      final dictRes = await http.post(
        Uri.parse('$apiBaseUrl/dictionaries'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'BuildPhraseFormTest', 'language': 'zh'}),
      );
      final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
      await http.patch(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_published': true}),
      );

      final canId = await _createWord(adminToken, dictionaryId, 'мочь');
      await _addForm(adminToken, canId, 'zh', 'могу');
      // A second learned word purely to supply a wrong-answer candidate --
      // never appears in the phrase itself.
      final homeId = await _createWord(adminToken, dictionaryId, 'дом');

      // A single-token phrase: the ENTIRE phrase is the grammatical form
      // "могу" (never the word "мочь" itself), so the one word that gets
      // blanked is deterministic -- no race with the random blank-position
      // choice needed to exercise this exact case.
      await _createPhrase(adminToken, dictionaryId, 'могу', 'test-form-translation');

      await _learnWordsViaLesson(userToken, dictionaryId, [canId, homeId]);

      await _login(tester);
      await tester.tap(find.byTooltip('Выбрать язык'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('中文').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Практика'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Собери фразу'));
      await tester.pumpAndSettle();

      expect(find.text('Фраза 1 из 1'), findsOneWidget);

      final correctAnswer = _readCurrentCorrectAnswer(tester);
      expect(
        correctAnswer,
        'могу',
        reason: 'the correct answer must be the phrase\'s own form, not the base word "мочь"',
      );
      expect(find.text('мочь'), findsNothing, reason: 'the base dictionary form should never be shown as an option');
      expect(find.text('могу'), findsOneWidget, reason: 'the actual phrase form should be offered as an option');

      await tester.tap(find.text('могу'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.check_circle), findsWidgets, reason: '"могу" must be accepted as correct');

      await http.delete(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken'},
      );
    },
  );
}
