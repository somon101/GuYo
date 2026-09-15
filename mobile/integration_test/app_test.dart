// Integration tests: run against a REAL Flutter engine (real platform
// channels, real HTTP, real flutter_secure_storage) rather than the fake
// environment `flutter test` normally uses -- so these exercise the app
// exactly as a user would, against the local dev backend.
//
// Run with:
//   flutter test integration_test/app_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456
//   - an English dictionary with words including a duplicate translation
//     (this repo's dev data already has "doggo" and "dog" both -> "собака")
//   - a Russian dictionary with 0 words (to exercise "not enough words")
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';
import 'package:guyo_app/models/dictionary.dart';
import 'package:guyo_app/screens/dictionary_words_screen.dart';
import 'package:guyo_app/screens/matching_screen.dart';

Finder get _languageSwitcher => find.byType(PopupMenuButton<GuyoDictionary>);

// IndexedStack builds BOTH tabs eagerly (only one is painted, but both
// exist in the widget tree at all times), so a word that's short enough to
// fit a matching round -- true for every word in this dev dataset -- shows
// up under both DictionaryWordsScreen and MatchingScreen simultaneously.
// Every lookup below is scoped to the tab it actually means to check.
Finder _inMatching(Finder matching) =>
    find.descendant(of: find.byType(MatchingScreen), matching: matching);
Finder _inWordList(Finder matching) =>
    find.descendant(of: find.byType(DictionaryWordsScreen), matching: matching);

// Each match card carries a Key of 'match-<left|right>-<word_id>' (see
// matching_screen.dart) purely so tests can target an exact card
// deterministically -- including the two identical-looking "собака" cards
// -- without guessing. Looking up real word_ids straight from the API
// (rather than hardcoding them) keeps this test correct even if the dev
// data changes.
Finder _leftCard(int wordId) => find.byKey(ValueKey('match-left-$wordId'));
Finder _rightCard(int wordId) => find.byKey(ValueKey('match-right-$wordId'));

Future<Map<String, int>> _fetchEnglishWordIdsByText() async {
  final loginRes = await http.post(
    Uri.parse('$apiBaseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'testuser', 'password': '123456'}),
  );
  final token = (jsonDecode(loginRes.body) as Map)['access_token'] as String;
  final authHeader = {'Authorization': 'Bearer $token'};

  final dictsRes = await http.get(Uri.parse('$apiBaseUrl/dictionaries'), headers: authHeader);
  final dicts = jsonDecode(dictsRes.body) as List;
  final englishId = dicts.firstWhere((d) => d['language'] == 'en')['id'] as int;

  final wordsRes =
      await http.get(Uri.parse('$apiBaseUrl/dictionaries/$englishId/words'), headers: authHeader);
  final words = jsonDecode(wordsRes.body) as List;
  return {for (final w in words) w['word'] as String: w['id'] as int};
}

Future<void> _login(WidgetTester tester) async {
  await tester.pumpWidget(const GuyoApp());
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // integration_test keeps the same app process (and its real secure
  // storage) across every testWidgets case in this file, so a session left
  // behind by a previous test would otherwise skip straight past the login
  // screen here. Start each test from a clean, logged-out state.
  if (find.byType(NavigationBar).evaluate().isNotEmpty) {
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

  expect(find.byType(NavigationBar), findsOneWidget, reason: 'should reach the home screen with tabs');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, language switch changes the word list, no crash', (tester) async {
    await _login(tester);

    // Default tab is "Словарь"; default language is whichever dictionary
    // came first from the API (English in the seed data) -- its words
    // should be visible without any extra taps.
    expect(_inWordList(find.text('apple')), findsOneWidget);
    expect(_inWordList(find.text('яблочко')), findsOneWidget);

    // Switch language to Русский via the switcher that replaced "Выйти".
    expect(find.byIcon(Icons.logout), findsNothing, reason: '"Выйти" must not sit in the main bar anymore');
    await tester.tap(_languageSwitcher);
    await tester.pumpAndSettle();
    expect(find.text('Русский'), findsWidgets);
    await tester.tap(find.text('Русский').last);
    await tester.pumpAndSettle();

    // The Russian dictionary has 0 words in this dev environment -- the
    // word list must say so cleanly, not crash and not still show English
    // words.
    expect(find.text('apple'), findsNothing);
    expect(_inWordList(find.text('В этом словаре пока нет слов')), findsOneWidget);

    // Logout is still reachable, just tucked into the overflow menu.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Выйти'), findsOneWidget);
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.text('Вход'), findsOneWidget, reason: 'logout should return to the login screen');
  });

  testWidgets('matching drill: correct/incorrect feedback, duplicate translations, completion, replay', (tester) async {
    final ids = await _fetchEnglishWordIdsByText();
    final appleId = ids['apple']!;
    final bookId = ids['book']!;
    final houseId = ids['house']!;
    final catId = ids['cat']!;
    final dogId = ids['dog']!;
    final doggoId = ids['doggo']!;

    await _login(tester);

    // English is selected by default; open the Сопоставление tab.
    await tester.tap(find.text('Сопоставление'));
    await tester.pumpAndSettle();

    // English dictionary here has 6 words (fewer than the round size of
    // 10) -- the round must gracefully use all 6 rather than error.
    expect(_inMatching(find.textContaining('Правильно: 0/6')), findsOneWidget);
    expect(_leftCard(appleId), findsOneWidget);
    expect(_rightCard(appleId), findsOneWidget);

    // Taps a left card then a right card and waits for the round's state
    // to settle. The transient "Правильно"/"Неправильно" SnackBar is real
    // UI (checked once below as a smoke test), but asserting on it after
    // every single tap is racy against real wall-clock animation timing
    // on this machine -- the durable, race-free signal for "did this
    // count as correct" is the "Правильно: N/6" counter, which is what
    // every check below relies on instead.
    Future<void> tapPair(int leftId, int rightId) async {
      await tester.tap(_leftCard(leftId));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(_rightCard(rightId));
      await tester.pumpAndSettle(const Duration(milliseconds: 150));
    }

    // --- Wrong match: apple must NOT match book's translation ---
    // (kept as a one-off smoke test that the feedback SnackBar itself
    // actually appears, with a generous window to catch it.)
    await tester.tap(_leftCard(appleId));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(_rightCard(bookId));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Неправильно'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
    expect(_inMatching(find.textContaining('Правильно: 0/6')), findsOneWidget);

    // --- Correct match: apple -> its own translation ---
    await tapPair(appleId, appleId);
    expect(_inMatching(find.textContaining('Правильно: 1/6')), findsOneWidget);

    // --- Duplicate translations: "doggo" and "dog" both translate to
    // "собака", i.e. two cards on the right show identical text. Prove
    // matching is decided by word_id, not by that text:
    //   1) doggo's identically-labelled card, tried against dog, must be
    //      REJECTED even though the text is the same "собака" -- the
    //      counter must NOT move.
    //   2) dog's own card must then be ACCEPTED -- the counter must move
    //      by exactly one.
    await tapPair(dogId, doggoId); // wrong word_id, same displayed text
    expect(_inMatching(find.textContaining('Правильно: 1/6')), findsOneWidget,
        reason: 'dog must not match doggo\'s card just because both say "собака"');

    await tapPair(dogId, dogId); // dog's own card -- correct word_id
    expect(_inMatching(find.textContaining('Правильно: 2/6')), findsOneWidget);
    // doggo's card is untouched by dog's match -- still there, still live.
    expect(_rightCard(doggoId), findsOneWidget);
    expect(_leftCard(doggoId), findsOneWidget);

    // --- Finish the round: match everything still remaining ---
    for (final id in [bookId, houseId, catId, doggoId]) {
      await tapPair(id, id);
    }

    // --- Round complete screen ---
    expect(_inMatching(find.text('Раунд завершён!')), findsOneWidget);
    expect(_inMatching(find.widgetWithText(FilledButton, 'Играть ещё раз')), findsOneWidget);

    // --- Replay starts a fresh round: counter resets, cards return ---
    await tester.tap(_inMatching(find.widgetWithText(FilledButton, 'Играть ещё раз')));
    await tester.pumpAndSettle();
    expect(_inMatching(find.textContaining('Правильно: 0/6')), findsOneWidget);
    expect(_leftCard(appleId), findsOneWidget);
  });

  testWidgets('matching drill shows a clean message when a dictionary has too few words', (tester) async {
    await _login(tester);

    await tester.tap(_languageSwitcher);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сопоставление'));
    await tester.pumpAndSettle();

    expect(find.textContaining('недостаточно слов'), findsOneWidget);
    // No crash, no stray "Правильно: x/y" counter for an empty round.
    expect(find.textContaining('Правильно:'), findsNothing);
  });
}
