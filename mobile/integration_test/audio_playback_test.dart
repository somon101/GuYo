// Verifies the reusable AudioButton mechanism (mobile/lib/widgets/audio_button.dart)
// actually renders wherever a Word with audio is shown, end to end:
//   Admin ZIP import -> backend storage -> Word.word_audio_key /
//   WordTranslation('tg').audio_key -> WordOut.word_audio_url /
//   translation_audio_url -> GuyoWord -> AudioButton in the real widget tree.
//
// The test word/data itself is prepared beforehand by a small Python script
// (scratchpad/prepare_audio_test_word.py) that imports a real dictionary
// ZIP through the same backend endpoint Admin Web uses -- this file only
// drives the UI, it never builds the ZIP itself.
//
// Goes through "Мои слова" -> the word's own card, which is where a Word
// with audio is shown now that the standalone "Словарь" screen is gone.
// That card is the one place BOTH recordings (the word's and its
// translation's) render together, which is exactly what this file checks.
//
// Run with:
//   python .../prepare_audio_test_word.py
//   flutter test integration_test/audio_playback_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';
import 'package:guyo_app/screens/word_detail_screen.dart';
import 'package:guyo_app/widgets/audio_button.dart';
import 'package:guyo_app/widgets/word_card.dart';

const _word = 'audiotestword';

Future<Map<String, String>> _adminHeaders() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/admin/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'admin', 'password': '123456'}),
  );
  final token = (jsonDecode(res.body) as Map)['access_token'] as String;
  return {'Authorization': 'Bearer $token'};
}

Future<String> _userToken() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'testuser', 'password': '123456'}),
  );
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}

/// Gives testuser progress on the imported word so it shows up under
/// "Мои слова" at all -- real lesson answers, the same way progress is
/// created anywhere else.
///
/// Answers CORRECTLY until the lesson completes, deliberately: a backend
/// only allows one incomplete lesson per (user, dictionary), so a lesson
/// left half-finished here would block every later test in the suite from
/// creating its own. Finishing it leaves the fixture exactly as it was
/// found.
Future<void> _giveWordProgress(int wordId) async {
  final token = await _userToken();
  final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  final lessonRes = await http.post(
    Uri.parse('$apiBaseUrl/lessons'),
    headers: headers,
    body: jsonEncode({
      'dictionary_id': 1,
      'word_ids': [wordId],
    }),
  );
  final lesson = jsonDecode(lessonRes.body) as Map<String, dynamic>;
  final lessonId = lesson['id'] as int?;
  if (lessonId == null) {
    throw StateError('could not create a lesson for the audio test word: ${lessonRes.body}');
  }
  final exerciseKey = (lesson['exercise_keys'] as List<dynamic>).first as String;

  // Capped rather than while(true): if the scoring settings ever make the
  // threshold unreachable this way, the test should fail loudly instead of
  // looping forever.
  for (var attempt = 0; attempt < 12; attempt++) {
    await http.post(
      Uri.parse('$apiBaseUrl/lessons/$lessonId/exercises/$exerciseKey/answers'),
      headers: headers,
      body: jsonEncode({'word_id': wordId, 'is_correct': true}),
    );
    final check = await http.get(
      Uri.parse('$apiBaseUrl/lessons/$lessonId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if ((jsonDecode(check.body) as Map)['is_completed'] == true) return;
  }
  throw StateError('lesson $lessonId never completed -- it would block later tests');
}

Future<int?> _testWordId() async {
  final h = await _adminHeaders();
  final wordsRes = await http.get(Uri.parse('$apiBaseUrl/dictionaries/1/words'), headers: h);
  final words = jsonDecode(wordsRes.body) as List;
  final match = words.where((w) => w['word'] == _word).cast<Map<String, dynamic>?>().firstOrNull;
  return match?['id'] as int?;
}

Future<void> _cleanupTestWord() async {
  final h = await _adminHeaders();
  final dictsRes = await http.get(Uri.parse('$apiBaseUrl/dictionaries'), headers: h);
  final dictId = (jsonDecode(dictsRes.body) as List).firstWhere((d) => d['language'] == 'en')['id'] as int;
  final wordsRes = await http.get(Uri.parse('$apiBaseUrl/dictionaries/$dictId/words'), headers: h);
  final words = jsonDecode(wordsRes.body) as List;
  final match = words.where((w) => w['word'] == _word).cast<Map<String, dynamic>?>().firstOrNull;
  if (match != null) {
    await http.delete(Uri.parse('$apiBaseUrl/words/${match['id']}'), headers: h);
  }
  // No delete-category endpoint exists; an empty leftover "Audio Playback
  // Test" category is a harmless trace, consistent with the rest of this
  // test suite's cleanup approach.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('audio buttons render for a ZIP-imported word in Мои слова', (tester) async {
    try {
      final wordId = await _testWordId();
      expect(wordId, isNotNull, reason: 'prepare_audio_test_word.py must have imported the word first');
      await _giveWordProgress(wordId!);

      await _login(tester);

      // --- Мои слова: the imported word is listed on the shared word
      // card, which plays its own recording... ---
      // "Мои слова" lives on Профиль now, not above the lesson chain.
      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await tester.tap(find.text('Мои слова'));
      await tester.pumpAndSettle();

      expect(find.text(_word), findsOneWidget, reason: 'imported word should be visible in Мои слова');
      expect(
        find.descendant(of: find.widgetWithText(WordCard, _word), matching: find.byType(AudioButton)),
        findsOneWidget,
        reason: "the word's own recording should play straight from the list",
      );

      // ...and its own card shows BOTH recordings: the word's and its
      // Tajik translation's.
      await tester.tap(find.text(_word));
      await tester.pumpAndSettle();

      final audioButtonsOnCard = find.descendant(
        of: find.byType(WordDetailScreen),
        matching: find.byType(AudioButton),
      );
      expect(
        audioButtonsOnCard,
        findsAtLeastNWidgets(2),
        reason: 'both word audio and translation audio buttons should render (this word has both)',
      );

      // Tapping is deliberately NOT exercised here: the `audioplayers`
      // Windows-desktop backend has its own platform-channel decoding bug
      // unrelated to this app's code (reproduces even with a minimal valid
      // WAV file) -- Windows desktop is only this repo's test target, never
      // the real one (Android). Real playback is verified on-device via the
      // built APK; this test's job is confirming the button itself renders
      // wherever a Word's audio exists.
    } finally {
      await _cleanupTestWord();
    }
  });
}
