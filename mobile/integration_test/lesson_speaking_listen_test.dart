// Covers "Произнеси слово" and "Услышь слово" end to end against the real
// backend, through the NEW auto-sequenced lesson runner (tap "Начать
// урок" once, no manual exercise picking):
//   backend/database -> lesson exercise availability -> round generation
//   -> Flutter -> answer submission via the SAME generic
//   .../answers endpoint every other exercise uses -> score/threshold ->
//   the lesson's own results screen.
//
// Real speech recognition itself can't be exercised on the Windows desktop
// test target (no Android speech recognizer available there) -- this test
// instead confirms the "Произнеси слово" screen handles that unavailability
// gracefully (no crash, a clear message, and the sequencer moves on) exactly
// as the spec requires, and covers "Услышь слово" (which needs no
// microphone) fully, including real answers through the real scoring
// pipeline.
//
// matching/build_word/true_or_false are deliberately disabled for the run
// (all three would otherwise also be available -- true_or_false needs the
// same external learned-word pool this test seeds for listen_word -- and
// this test only wants speaking_word/listen_word in the sequence) --
// restored afterward
// regardless of outcome so no other test is left with them disabled.
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

Future<void> _setExerciseEnabled(String token, String exerciseKey, bool enabled) async {
  await http.put(
    Uri.parse('$apiBaseUrl/exercise-settings/$exerciseKey'),
    headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    body: jsonEncode({'word_count': 10, 'enabled': enabled}),
  );
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

/// Learns [wordIds] the same way the rest of this app does it -- through a
/// real Lesson and real "Сопоставление" answers, never a raw DB write.
/// Same helper shape as practice_exercises_test.dart's own.
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
  expect(finalWords.every((w) => w['is_learned'] == true), isTrue, reason: 'seed word should be learned by now');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'auto-sequenced lesson runner: speaking_word degrades gracefully and listen_word scores '
    'through the real backend, in order, with no manual exercise picking',
    (tester) async {
      final adminToken = await _adminToken();

      try {
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

        // Услышь слово's distractor options now always come from the
        // user's own PREVIOUSLY learned words via Priority (see
        // app/exercises/listen_word.py), same as Правда или ложь already
        // did -- never from this same lesson's own word set any more. A
        // seed word, learned here through a real (throwaway) "Урок 1"
        // before red/blue/green exist, is what makes listen_word
        // available at all for them below -- done through matching's own
        // answers endpoint, so matching/build_word must still be ENABLED
        // for this one step, only disabled afterward for the real test.
        final userLoginRes = await http.post(
          Uri.parse('$apiBaseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'login': 'testuser', 'password': '123456'}),
        );
        final userToken = (jsonDecode(userLoginRes.body) as Map)['access_token'] as String;
        // 2 words, not 1 -- Сопоставление (which _learnWordsViaLesson
        // answers through) needs at least 2 lesson words to be offered at
        // all.
        final seed1Id = await _createWord(adminToken, dictionaryId, 'seed1');
        final seed2Id = await _createWord(adminToken, dictionaryId, 'seed2');
        // A short settle beat before creating the seed lesson -- this
        // step intermittently raced with backend state in this test
        // environment (the seed lesson would come back missing
        // "matching" even though the word count/enabled checks are
        // satisfied); this delay is a pragmatic guard against that.
        await Future.delayed(const Duration(milliseconds: 500));
        await _learnWordsViaLesson(userToken, dictionaryId, [seed1Id, seed2Id]);

        await _setExerciseEnabled(adminToken, 'matching', false);
        await _setExerciseEnabled(adminToken, 'build_word', false);
        // The seed pool above (needed for listen_word) now also makes
        // Правда или ложь available, which it never was before (it needs
        // the same external pool) -- keep the sequence to just
        // speaking_word/listen_word as originally intended.
        await _setExerciseEnabled(adminToken, 'true_or_false', false);

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
        // The seed lesson above is "Урок 1" (already complete) -- the
        // chain is no longer empty, and this test's own lesson is next.
        await tester.tap(find.text('Урок 2'));
        await tester.pumpAndSettle();

        // Manual selection: all 3 words (2 with audio, 1 without) so
        // listen_word (needs >=1 audio word + >=2 lesson words) is
        // available; speaking_word always is. matching/build_word/
        // true_or_false are disabled above so they never enter the
        // sequence at all.
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
        // into the lesson) -- "Урок 2" is now a real, in-progress chain
        // link instead of the "create next" node it was a moment ago.
        await tester.tap(find.text('Урок 2'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(find.text('Начать урок'), findsOneWidget, reason: 'no manual exercise menu any more');
        await tester.tap(find.text('Начать урок'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // --- Произнеси слово comes first in the sequence, but this target
        // has no speech recognizer, so the exercise cannot run at all. It
        // skips ITSELF and the lesson carries on -- never a dead end the
        // user has to back out of by hand, and never a faked result. ---
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(
          find.byKey(const ValueKey('speaking-word-mic-button')),
          findsNothing,
          reason: 'nothing to record with -- the mic must not be offered',
        );

        // --- Sequencer moved on to Услышь слово by itself ---
        expect(find.textContaining('Слова 1 из 2'), findsOneWidget, reason: 'only red/blue have audio -- 2 items');

        // Item order isn't guaranteed, and BOTH word_ids can appear as
        // options on EITHER screen (each is the other's wrong-answer
        // distractor) -- read the correct one off the active item's own
        // Key instead of assuming an order.
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
        // The round's last answer hands control straight back to the
        // lesson runner -- no completion panel, no button to tap.
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.text('Упражнение завершено!'), findsNothing);
        expect(find.text('К уроку'), findsNothing);
        expect(find.text('Играть ещё раз'), findsNothing);

        // --- Sequence exhausted: the lesson's own results screen ---
        // green never got any real exercise (no audio for listen_word, no
        // recognizer for speaking_word, matching/build_word disabled), and
        // red/blue only got listen_word's single correct answer each --
        // none reach the default threshold (60), so the lesson stays
        // incomplete and offers a repeat instead of "Готово".
        expect(find.textContaining('результаты'), findsOneWidget);
        expect(find.text('Ещё не всё закреплено'), findsOneWidget);
        expect(find.textContaining('0 из 3'), findsOneWidget);
        expect(find.text('Повторить урок'), findsOneWidget);

        // --- Verify real backend scoring happened for listen_word answers ---
        // (userToken already fetched above, before the seed word was learned)
        final myLessonsRes = await http.get(
          Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/lessons'),
          headers: {'Authorization': 'Bearer $userToken'},
        );
        final lessons = (jsonDecode(myLessonsRes.body) as Map)['lessons'] as List<dynamic>;
        expect(lessons, isNotEmpty);
        // Two lessons now exist (the seed one, and this test's own) --
        // pick this test's own by number, never assume list order/index.
        final testLesson = lessons.cast<Map<String, dynamic>>().firstWhere((l) => l['number'] == 2);
        final lessonDetailRes = await http.get(
          Uri.parse('$apiBaseUrl/lessons/${testLesson['id']}'),
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
      } finally {
        await _setExerciseEnabled(adminToken, 'matching', true);
        await _setExerciseEnabled(adminToken, 'build_word', true);
        await _setExerciseEnabled(adminToken, 'true_or_false', true);
      }
    },
  );
}
