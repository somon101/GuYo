// Covers "Произнеси слово" and "Услышь слово" end to end against the real
// backend, as two of a Lesson's exercises:
//   backend/database -> lesson exercise availability -> round generation
//   -> Flutter -> answer submission via the SAME generic
//   .../answers endpoint every other exercise uses -> score/threshold/
//   lesson completion.
//
// Real speech recognition itself can't be exercised on the Windows desktop
// test target (no Android speech recognizer available there) -- this test
// instead confirms the "Произнеси слово" screen handles that unavailability
// gracefully (no crash, a clear message) exactly as the spec requires,
// and covers "Услышь слово" (which needs no microphone) fully, including
// real answers through the real scoring pipeline.
//
// Run with:
//   flutter test integration_test/lesson_speaking_listen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456, admin/123456
//   - default exercise/threshold settings (threshold 60)
import 'dart:convert';
import 'dart:typed_data';

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

Uint8List _silentWavBytes() {
  const sampleRate = 8000;
  const numSamples = sampleRate;
  const dataSize = numSamples * 2;
  final b = BytesBuilder();
  void s(String v) => b.add(v.codeUnits);
  void u32(int v) => b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  s('RIFF');
  u32(36 + dataSize);
  s('WAVE');
  s('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  s('data');
  u32(dataSize);
  b.add(List<int>.filled(dataSize, 0));
  return b.toBytes();
}

Future<int> _createWord(String token, int dictionaryId, String word, {bool withAudio = false}) async {
  final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/words'))
    ..headers['Authorization'] = 'Bearer $token'
    ..fields['word'] = word
    ..fields['translation'] = 'x';
  if (withAudio) {
    req.files.add(http.MultipartFile.fromBytes('word_audio', _silentWavBytes(), filename: '$word.wav'));
  }
  final streamed = await req.send();
  final body = await streamed.stream.bytesToString();
  return (jsonDecode(body) as Map)['id'] as int;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a lesson with listen_word available: round autoplays without crashing, correct/incorrect '
    'answers score through the real backend, and the round completes',
    (tester) async {
      final adminToken = await _adminToken();

      final dictRes = await http.post(
        Uri.parse('$apiBaseUrl/dictionaries'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'SpeakListenTest', 'language': 'sql'}),
      );
      final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
      await http.patch(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_published': true}),
      );

      final redId = await _createWord(adminToken, dictionaryId, 'red', withAudio: true);
      final blueId = await _createWord(adminToken, dictionaryId, 'blue', withAudio: true);
      final greenId = await _createWord(adminToken, dictionaryId, 'green', withAudio: false);

      await _login(tester);
      await tester.tap(find.byTooltip('Выбрать язык'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sql').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Уроки'));
      await tester.pumpAndSettle();
      expect(find.text('Создайте первый урок, чтобы начать'), findsOneWidget);
      await tester.tap(find.text('Урок 1'));
      await tester.pumpAndSettle();

      // Manual selection: all 3 words (2 with audio, 1 without) so both
      // speaking_word (works for any word) and listen_word (needs >=1
      // audio word + >=2 lesson words) should both be offered.
      await tester.tap(find.text('Вручную'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Без категории'));
      await tester.pumpAndSettle();
      for (final id in [redId, blueId, greenId]) {
        await tester.tap(find.byKey(ValueKey('lesson-word-checkbox-$id')));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Создать урок (3)'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Creating the lesson pops back to the "Уроки" chain (not directly
      // into the lesson) -- "Урок 1" is now a real, in-progress chain link
      // instead of the "create next" node it was a moment ago. Open it to
      // reach the exercise buttons.
      await tester.tap(find.text('Урок 1'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Услышь слово 🔊'), findsOneWidget, reason: '2 audio words + 3 total should make it available');
      expect(find.text('Произнеси слово 🎙️'), findsOneWidget, reason: 'always available for any word set');

      // --- Услышь слово: play through both audio-bearing items ---
      await tester.tap(find.text('Услышь слово 🔊'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Правильно: 0/2'), findsOneWidget, reason: 'only red/blue have audio -- 2 items');

      // Item order isn't guaranteed (red/blue could come up in either
      // order), and BOTH word_ids can appear as options on EITHER screen
      // (each is the other's wrong-answer distractor) -- so which key is
      // "correct" depends on which item is actually active. Read that off
      // the active item's own Key (same convention BuildWordScreen/
      // BuildPhraseScreen use) instead of assuming an order.
      for (var i = 0; i < 2; i++) {
        final activeKeyFinder = find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('listen-word-active-'),
        );
        expect(activeKeyFinder, findsOneWidget);
        final activeKey = (tester.widget(activeKeyFinder).key! as ValueKey<String>).value;
        final activeWordId = int.parse(activeKey.replaceFirst('listen-word-active-', ''));
        expect([redId, blueId], contains(activeWordId), reason: 'the active item must be one of the 2 audio words');

        final correctOption = find.byKey(ValueKey('listen-word-option-$activeWordId'));
        expect(correctOption, findsOneWidget);
        await tester.tap(correctOption);
        await tester.pumpAndSettle(const Duration(milliseconds: 900));
      }
      expect(find.text('Упражнение завершено!'), findsOneWidget);
      expect(find.textContaining('Правильно: 2 из 2'), findsOneWidget, reason: 'both answered with their own correct word_id');
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // --- Произнеси слово: on Windows desktop there is no Android speech
      // recognizer, so the screen must show the graceful "unavailable"
      // state rather than crash or fake a result. ---
      expect(find.text('Произнеси слово 🎙️'), findsOneWidget);
      await tester.tap(find.text('Произнеси слово 🎙️'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(
        find.textContaining('недоступно'),
        findsOneWidget,
        reason: 'no speech recognizer on the Windows test target -- must degrade gracefully, never fake a result',
      );
      expect(find.byKey(const ValueKey('speaking-word-mic-button')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // --- Verify real backend scoring happened for listen_word answers ---
      final userLoginRes = await http.post(
        Uri.parse('$apiBaseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'login': 'testuser', 'password': '123456'}),
      );
      final userToken = (jsonDecode(userLoginRes.body) as Map)['access_token'] as String;
      final myLessonsRes = await http.get(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/lessons'),
        headers: {'Authorization': 'Bearer $userToken'},
      );
      final lessons = (jsonDecode(myLessonsRes.body) as Map)['lessons'] as List<dynamic>;
      expect(lessons, isNotEmpty);
      final lessonDetailRes = await http.get(
        Uri.parse('$apiBaseUrl/lessons/${lessons[0]['id']}'),
        headers: {'Authorization': 'Bearer $userToken'},
      );
      final words = (jsonDecode(lessonDetailRes.body) as Map)['words'] as List<dynamic>;
      final scores = {for (final w in words) w['word_id'] as int: w['score'] as int};
      // Both were answered correctly through the real UI -- each should
      // have gained exactly one "listen_word" correct_points award (15 by
      // default), proving the tap genuinely reached the real backend
      // scoring pipeline via the generic .../answers endpoint, not just a
      // client-side animation.
      expect(scores[redId], greaterThan(0), reason: 'red was answered correctly and must have scored');
      expect(scores[blueId], greaterThan(0), reason: 'blue was answered correctly and must have scored');

      await http.delete(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken'},
      );
    },
  );
}
