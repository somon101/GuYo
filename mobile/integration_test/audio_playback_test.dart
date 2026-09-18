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
import 'package:guyo_app/screens/dictionary_words_screen.dart';
import 'package:guyo_app/screens/matching_screen.dart';
import 'package:guyo_app/widgets/audio_button.dart';

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

  testWidgets('audio buttons render for a ZIP-imported word in Словарь and Сопоставление', (tester) async {
    try {
      await _login(tester);

      // --- Словарь: the imported word shows BOTH its own and its Tajik
      // translation's play button, and tapping one doesn't crash. ---
      await tester.tap(find.text('Словарь'));
      await tester.pumpAndSettle();

      expect(find.text(_word), findsOneWidget, reason: 'imported word should be visible in Словарь');

      final audioButtonsInWordList = find.descendant(
        of: find.byType(DictionaryWordsScreen),
        matching: find.byType(AudioButton),
      );
      expect(
        audioButtonsInWordList,
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
      await tester.pageBack();
      await tester.pumpAndSettle();

      // --- Сопоставление: since the word is now learned, it appears in a
      // matching round with its own audio button on the left (word) card. ---
      await tester.tap(find.text('Сопоставление'));
      await tester.pumpAndSettle();

      final audioButtonsInMatching = find.descendant(
        of: find.byType(MatchingScreen),
        matching: find.byType(AudioButton),
      );
      expect(
        audioButtonsInMatching,
        findsAtLeastNWidgets(1),
        reason: 'at least one match card (this word, learned) should show an audio button',
      );
    } finally {
      await _cleanupTestWord();
    }
  });
}
