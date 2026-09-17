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
//   - a Russian dictionary testuser hasn't learned any words in (to
//     exercise "not enough words" -- "Сопоставление" now draws from
//     LEARNED words only, never the raw dictionary, so this holds
//     trivially as long as no Russian word has been learned)
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

// Each feature is reached by tapping its card on the main menu, which
// pushes it as its own screen -- only one of DictionaryWordsScreen/
// MatchingScreen is ever in the tree at a time. Scoping lookups to the
// screen type is kept anyway: cheap, and still correct.
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

Future<(int dictionaryId, Map<String, int> wordIdsByText)> _fetchEnglishWordIdsByText() async {
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
  return (englishId, {for (final w in words) w['word'] as String: w['id'] as int});
}

/// "Сопоставление" now draws only from testuser's LEARNED words (see
/// matching_screen.dart) -- drives the real "Изучение слов" API (never a
/// raw DB write) until every word in [wordIds] is learned, so the drill
/// test below has the same 6-word English round it always did.
Future<void> _ensureWordsLearned(int dictionaryId, List<int> wordIds) async {
  final loginRes = await http.post(
    Uri.parse('$apiBaseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'testuser', 'password': '123456'}),
  );
  final token = (jsonDecode(loginRes.body) as Map)['access_token'] as String;
  final h = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  Future<Set<int>> learnedIds() async {
    final res = await http.get(
      Uri.parse('$apiBaseUrl/learned-words?dictionary_id=$dictionaryId'),
      headers: h,
    );
    return (jsonDecode(res.body) as List).map((w) => w['id'] as int).toSet();
  }

  // A handful of passes covers any leftover partial session from an
  // earlier test run; for this small, fixed dev dataset one pass is
  // normally enough.
  for (var attempt = 0; attempt < 3; attempt++) {
    if ((await learnedIds()).containsAll(wordIds)) return;

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

  final finalLearned = await learnedIds();
  assert(finalLearned.containsAll(wordIds), 'expected all of $wordIds to be learned, got $finalLearned');
}

Future<void> _login(WidgetTester tester) async {
  await tester.pumpWidget(const GuyoApp());
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // integration_test keeps the same app process (and its real secure
  // storage) across every testWidgets case in this file, so a session left
  // behind by a previous test would otherwise skip straight past the login
  // screen here. Start each test from a clean, logged-out state.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, language switch changes the word list, no crash', (tester) async {
    await _login(tester);

    // Lands on the main menu; default language is whichever dictionary
    // came first from the API (English in the seed data). Open "Словарь".
    await tester.tap(find.text('Словарь'));
    await tester.pumpAndSettle();
    expect(_inWordList(find.text('apple')), findsOneWidget);
    expect(_inWordList(find.text('яблочко')), findsOneWidget);

    // The language switcher lives on the menu's app bar, not inside a
    // pushed feature -- back out to it first.
    await tester.pageBack();
    await tester.pumpAndSettle();

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
    await tester.tap(find.text('Словарь'));
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsNothing);
    expect(_inWordList(find.text('В этом словаре пока нет слов')), findsOneWidget);

    // Back to the menu; logout is still reachable, just tucked into the
    // overflow menu.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Выйти'), findsOneWidget);
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.text('Вход'), findsOneWidget, reason: 'logout should return to the login screen');
  });

  testWidgets('matching drill: correct/incorrect feedback, duplicate translations, completion, replay', (tester) async {
    final (englishId, ids) = await _fetchEnglishWordIdsByText();
    final appleId = ids['apple']!;
    final bookId = ids['book']!;
    final houseId = ids['house']!;
    final catId = ids['cat']!;
    final dogId = ids['dog']!;
    final doggoId = ids['doggo']!;
    await _ensureWordsLearned(englishId, ids.values.toList());

    await _login(tester);

    // English is selected by default; open "Сопоставление" from the menu.
    await tester.tap(find.text('Сопоставление'));
    await tester.pumpAndSettle();

    // All 6 English words are learned and the admin-configured "matching"
    // count defaults to 10 (> 6) -- the round must gracefully use all 6
    // available learned words rather than error or pad with anything else.
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

  testWidgets('matching drill shows a clean message when too few words are learned', (tester) async {
    await _login(tester);

    await tester.tap(_languageSwitcher);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сопоставление'));
    await tester.pumpAndSettle();

    // testuser has learned 0 Russian words -- "Сопоставление" draws only
    // from learned words, so this is the same empty state regardless of
    // how many words the Russian dictionary itself actually has.
    expect(find.textContaining('нужно изучить'), findsOneWidget);
    // No crash, no stray "Правильно: x/y" counter for an empty round.
    expect(find.textContaining('Правильно:'), findsNothing);
  });
}
