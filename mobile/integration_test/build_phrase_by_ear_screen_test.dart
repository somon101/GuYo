// Covers "Практика" / "Собери фразу на слух" end to end against the real
// backend: доступные пользователю фразы (тот же /available-phrases, что и
// "Мои фразы"/"Собери фразу") -> фраза с озвучкой -> original text ->
// токенизация -> перемешивание -> сборка -> сравнение с исходным порядком
// -> переход к следующей.
//
// Run with:
//   flutter test integration_test/build_phrase_by_ear_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456
//   - default exercise/threshold settings (threshold 60, matching +20)
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

/// A minimal, structurally-valid silent WAV -- only needs to be non-empty
/// bytes the backend will store and hand back a URL for; playback itself is
/// never asserted on (see the note by `_tapReplay` below).
Uint8List _silentWavBytes() {
  const sampleRate = 8000;
  const numSamples = sampleRate; // 1 second
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

Future<void> _createPhrase(
  String token,
  int dictionaryId,
  String original,
  String translationTg, {
  bool withAudio = false,
}) async {
  final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/phrases'))
    ..headers['Authorization'] = 'Bearer $token'
    ..fields['original'] = original
    ..fields['translation_tg'] = translationTg;
  if (withAudio) {
    req.files.add(http.MultipartFile.fromBytes('original_audio', _silentWavBytes(), filename: 'p.wav'));
  }
  await req.send();
}

/// Same real-Lesson learning helper as build_phrase_screen_test.dart --
/// never a raw DB write.
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

Finder get _pool => find.byKey(const ValueKey('build-phrase-by-ear-pool'));
Finder get _assembled => find.byKey(const ValueKey('build-phrase-by-ear-assembled'));

/// Taps pool tiles, in order, to assemble [tokens] -- always the FIRST
/// matching-text tile still in the pool, so a token that repeats (e.g. "to"
/// twice) is handled correctly: after the first "to" moves to the
/// assembled area, only one "to" tile remains in the pool, so `.first`
/// resolves unambiguously the second time too. Correctness is about the
/// resulting TEXT sequence, never which physical duplicate instance was
/// tapped -- same principle as BuildWordScreen's own letter tiles.
Future<void> _assembleInOrder(WidgetTester tester, List<String> tokens) async {
  for (final token in tokens) {
    final button = find.descendant(of: _pool, matching: find.text(token)).first;
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('English dictionary with no phrases at all -> clean empty state, no crash', (tester) async {
    await _login(tester);
    await tester.tap(find.text('Практика'));
    await tester.pumpAndSettle();

    expect(find.text('Собери фразу на слух'), findsOneWidget);
    await tester.tap(find.text('Собери фразу на слух'));
    await tester.pumpAndSettle();

    expect(find.textContaining('недостаточно данных'), findsOneWidget);
  });

  testWidgets(
    'available phrase with audio and a repeated token ("to" twice): correct assembly in order '
    'advances and completes the round; a sibling phrase with NO audio is excluded from the pool',
    (tester) async {
      final adminToken = await _adminToken();
      final userToken = await _userToken();

      final dictRes = await http.post(
        Uri.parse('$apiBaseUrl/dictionaries'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'ByEarTest', 'language': 'bpe'}),
      );
      final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
      await http.patch(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_published': true}),
      );

      final iId = await _createWord(adminToken, dictionaryId, 'i');
      final wantId = await _createWord(adminToken, dictionaryId, 'want');
      final toId = await _createWord(adminToken, dictionaryId, 'to');
      final goId = await _createWord(adminToken, dictionaryId, 'go');
      final schoolId = await _createWord(adminToken, dictionaryId, 'school');

      // The phrase actually used by the exercise: 6 tokens, "to" twice.
      await _createPhrase(
        adminToken,
        dictionaryId,
        'i want to go to school',
        'test-by-ear-translation',
        withAudio: true,
      );
      // A second, otherwise-equally-available phrase but with NO audio --
      // must never appear in this exercise's pool (nothing to listen to).
      await _createPhrase(adminToken, dictionaryId, 'i want to go', 'no-audio-translation', withAudio: false);

      await _learnWordsViaLesson(userToken, dictionaryId, [iId, wantId, toId, goId, schoolId]);

      await _login(tester);
      await tester.tap(find.byTooltip('Выбрать язык'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('bpe').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Практика'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Собери фразу на слух'));
      await tester.pumpAndSettle();

      expect(
        find.text('Фраза 1 из 1'),
        findsOneWidget,
        reason: 'only the phrase WITH audio should be in the pool, never the one without',
      );

      // Both "to" tiles must exist as independent, tappable pool elements.
      expect(find.descendant(of: _pool, matching: find.text('to')), findsNWidgets(2));
      expect(find.descendant(of: _pool, matching: find.text('school')), findsOneWidget);

      // The replay button itself is present and enabled -- actually tapping
      // it is deliberately NOT exercised here: the `audioplayers` Windows-
      // desktop backend has its own platform-channel error unrelated to
      // this app's code (same caveat noted in audio_playback_test.dart),
      // and it fires asynchronously late enough to bleed into whichever
      // test runs next. Real playback is verified on-device via the built
      // APK; this test's job is the assembly mechanic, not audio playback.
      expect(find.text('Прослушать ещё раз'), findsOneWidget);

      await _assembleInOrder(tester, ['i', 'want', 'to', 'go', 'to', 'school']);
      await tester.pump(const Duration(milliseconds: 150));

      // Assembled order must match exactly, including both "to" placements.
      expect(find.descendant(of: _assembled, matching: find.text('i')), findsOneWidget);
      expect(find.descendant(of: _assembled, matching: find.text('to')), findsNWidgets(2));
      expect(find.descendant(of: _pool, matching: find.text('to')), findsNothing, reason: 'pool should now be empty');

      expect(find.text('Правильно'), findsOneWidget);
      expect(find.text('test-by-ear-translation'), findsOneWidget, reason: 'translation shown as feedback after answering');

      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('Практика завершена!'), findsOneWidget);
      expect(find.textContaining('Правильно: 1 из 1'), findsOneWidget);

      await http.delete(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken'},
      );
    },
  );

  testWidgets('assembling in the WRONG order is marked incorrect but still advances (no auto-fix, no crash)', (tester) async {
    final adminToken = await _adminToken();
    final userToken = await _userToken();

    final dictRes = await http.post(
      Uri.parse('$apiBaseUrl/dictionaries'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'name': 'ByEarWrongOrderTest', 'language': 'bpw'}),
    );
    final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
    await http.patch(
      Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'is_published': true}),
    );

    final redId = await _createWord(adminToken, dictionaryId, 'red');
    final carId = await _createWord(adminToken, dictionaryId, 'car');
    await _createPhrase(adminToken, dictionaryId, 'red car', 'wrong-order-translation', withAudio: true);
    await _learnWordsViaLesson(userToken, dictionaryId, [redId, carId]);

    await _login(tester);
    await tester.tap(find.byTooltip('Выбрать язык'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bpw').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Практика'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Собери фразу на слух'));
    await tester.pumpAndSettle();

    expect(find.text('Фраза 1 из 1'), findsOneWidget);

    // Deliberately reversed order.
    await _assembleInOrder(tester, ['car', 'red']);
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Неправильный порядок'), findsOneWidget);
    // Nothing here silently reorders the tiles back to "red car" -- the
    // user's own (wrong) order must still be what's shown.
    final assembledTexts = tester
        .widgetList<Text>(find.descendant(of: _assembled, matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    expect(assembledTexts, ['car', 'red'], reason: 'the wrong order must be shown as-is, never auto-corrected');

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Практика завершена!'), findsOneWidget);
    expect(find.textContaining('Правильно: 0 из 1'), findsOneWidget);

    await http.delete(
      Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
      headers: {'Authorization': 'Bearer $adminToken'},
    );
  });
}
