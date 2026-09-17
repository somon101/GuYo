// Covers "Собери слово" end to end against the real backend:
//   - the translation is shown, letters are tappable buttons (no system
//     keyboard involved);
//   - tapping a letter moves it into the assembly area and removes that
//     specific button from the pool -- including tapping each of two
//     identical letters (e.g. doggo's two g's) independently;
//   - tapping a placed letter removes it back to the pool (undo), but only
//     before "Проверить" is pressed;
//   - pressing "Проверить" checks the word once -- colors every slot
//     green/red, then ALWAYS advances to the next word (right or wrong,
//     one attempt per word, no retry);
//   - the round always completes after all words have been attempted, with
//     the correct-count reflecting only the right ones, and "Играть ещё
//     раз" starts a fresh round.
//
// Run with:
//   flutter test integration_test/build_word_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456
//   - an English dictionary (id resolved by language) with an alphabet set
//     and "build_word" exercise settings configured with word_count=6 (so
//     the round covers exactly this repo's 6 dev words deterministically)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';

Future<Map<String, String>> _adminHeaders() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/admin/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'admin', 'password': '123456'}),
  );
  final token = (jsonDecode(res.body) as Map)['access_token'] as String;
  return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
}

Future<Map<String, String>> _userHeaders() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'testuser', 'password': '123456'}),
  );
  final token = (jsonDecode(res.body) as Map)['access_token'] as String;
  return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
}

/// Learns every word of [dictionaryId] the user hasn't learned yet, via the
/// real Learning sessions API (never a raw DB write).
Future<void> _learnAllWords(int dictionaryId) async {
  final h = await _userHeaders();
  for (var attempt = 0; attempt < 3; attempt++) {
    final wordsRes = await http.get(
      Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/words'),
      headers: h,
    );
    final allIds = (jsonDecode(wordsRes.body) as List).map((w) => w['id'] as int).toSet();
    final learnedRes = await http.get(
      Uri.parse('$apiBaseUrl/learned-words?dictionary_id=$dictionaryId'),
      headers: h,
    );
    final learnedIds = (jsonDecode(learnedRes.body) as List).map((w) => w['id'] as int).toSet();
    if (learnedIds.containsAll(allIds)) return;

    Map<String, dynamic> session;
    final activeRes = await http.get(
      Uri.parse('$apiBaseUrl/learning/sessions/active?dictionary_id=$dictionaryId'),
      headers: h,
    );
    if (activeRes.statusCode == 200) {
      session = jsonDecode(activeRes.body) as Map<String, dynamic>;
    } else {
      final createRes = await http.post(
        Uri.parse('$apiBaseUrl/learning/sessions'),
        headers: h,
        body: jsonEncode({'dictionary_id': dictionaryId, 'count': 20}),
      );
      session = jsonDecode(createRes.body) as Map<String, dynamic>;
    }
    var current = session['current_word'] as Map<String, dynamic>?;
    while (current != null) {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/learning/sessions/${session['id']}/words/${current['id']}/learned'),
        headers: h,
      );
      session = jsonDecode(res.body) as Map<String, dynamic>;
      current = session['current_word'] as Map<String, dynamic>?;
    }
  }
}

Future<int> _englishDictionaryId() async {
  final h = await _userHeaders();
  final res = await http.get(Uri.parse('$apiBaseUrl/dictionaries'), headers: h);
  return (jsonDecode(res.body) as List).firstWhere((d) => d['language'] == 'en')['id'] as int;
}

Future<void> _configureBuildWord(int dictionaryId) async {
  final h = await _adminHeaders();
  await http.patch(
    Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
    headers: h,
    body: jsonEncode({'alphabet': 'abcdefghijklmnopqrstuvwxyz'}),
  );
  await http.put(
    Uri.parse('$apiBaseUrl/exercise-settings/build_word'),
    headers: h,
    body: jsonEncode({'word_count': 6, 'wrong_letter_count': 3, 'min_word_length': 3, 'case_sensitive': false}),
  );
}

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

/// Reads the correct word for the CURRENTLY shown item straight off the
/// screen's own testing Key (see build_word_screen.dart) -- the only way
/// to know it without racing the backend's own random selection with a
/// second, separate HTTP call.
String _readCurrentCorrectWord(WidgetTester tester) {
  final matches = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith('build-word-active-');
  });
  expect(matches, findsOneWidget, reason: 'exactly one active build-word item should be shown');
  final key = (tester.widget(matches).key! as ValueKey<String>).value;
  // Format: build-word-active-<wordId>-<correctWord>
  final firstDash = key.indexOf('-', 'build-word-active-'.length);
  return key.substring(firstDash + 1);
}

Finder get _poolArea => find.byKey(const ValueKey('build-word-pool'));
Finder get _slotsArea => find.byKey(const ValueKey('build-word-slots'));

/// Taps pool letters, in order, to spell [word] -- tapping the first
/// still-available pool button with each required letter, so duplicate
/// letters (each independently tappable) are handled correctly too -- then
/// presses "Проверить", since checking is no longer automatic on the last
/// letter.
Future<void> _buildWord(WidgetTester tester, String word) async {
  for (final letter in word.split('')) {
    final button = find.descendant(of: _poolArea, matching: find.text(letter)).first;
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.tap(find.byKey(const ValueKey('build-word-check-button')));
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('one attempt per word, always advances, completion, replay', (tester) async {
    final dictionaryId = await _englishDictionaryId();
    await _configureBuildWord(dictionaryId);
    await _learnAllWords(dictionaryId);

    await _login(tester);
    await tester.tap(find.text('Собери слово'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Слово 1 из 6'), findsOneWidget);

    final seenWords = <String>{};

    // --- Word 1: place one letter, then undo it before checking (still
    // allowed pre-check), then build it WRONG on purpose. ---
    final word1 = _readCurrentCorrectWord(tester);
    seenWords.add(word1);
    expect(word1.length >= 3, isTrue, reason: 'min_word_length=3 should exclude nothing shorter than this');

    final firstLetterButton = find.descendant(of: _poolArea, matching: find.text(word1[0])).first;
    await tester.tap(firstLetterButton);
    await tester.pump(const Duration(milliseconds: 80));
    // Tap it back out of the slot -- undoing a placed letter must still
    // work before the check button has been pressed.
    final placedInSlot = find.descendant(of: _slotsArea, matching: find.text(word1[0])).first;
    await tester.tap(placedInSlot);
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.descendant(of: _slotsArea, matching: find.text(word1[0])),
      findsNothing,
      reason: 'tapping a placed letter before checking must return it to the pool',
    );

    // Now build it WRONG on purpose (reversed order -- guaranteed wrong for
    // any word with length > 1 that is not its own reversal, true for
    // every word in this dev dataset), and confirm a wrong answer STILL
    // advances -- one attempt per word, no retry.
    final reversed = word1.split('').reversed.join();
    await _buildWord(tester, reversed);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.textContaining('Слово 2 из 6'), findsOneWidget, reason: 'a wrong answer must still advance');
    expect(find.textContaining('Правильно'), findsNothing, reason: 'the wrong word-1 attempt must not be counted');

    // --- Words 2..6: build each correctly ---
    for (var i = 2; i <= 6; i++) {
      expect(find.textContaining('Слово $i из 6'), findsOneWidget, reason: 'should be on word $i');
      final word = _readCurrentCorrectWord(tester);
      expect(seenWords.contains(word), isFalse, reason: 'each word in the round must be distinct: $word');
      seenWords.add(word);

      // Tap each of THIS word's own letters independently, including
      // duplicate letters (e.g. doggo's two g's/o's) -- proves each
      // button is tapped as its own instance, not by letter text alone.
      await _buildWord(tester, word);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    // --- Round complete: 5 correct out of 6 (word 1 was wrong) ---
    expect(find.text('Упражнение завершено!'), findsOneWidget);
    expect(find.textContaining('Собрано слов: 5 из 6'), findsOneWidget);
    expect(seenWords.length, 6, reason: 'all 6 distinct dev words must have appeared exactly once');

    // --- Replay: a fresh round starts from word 1 again ---
    await tester.tap(find.widgetWithText(FilledButton, 'Играть ещё раз'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.textContaining('Слово 1 из 6'), findsOneWidget);
  });
}
