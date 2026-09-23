// Covers "Мои слова" end to end against the real backend/UI wiring: a word
// with SOME progress (not yet past the "learned" threshold) now shows up in
// the list at all, tagged with its current word-reinforcement level's own
// name -- the compact, color-coded status badge this task added.
//
// Run with:
//   flutter test integration_test/learned_words_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456, admin/123456
//   - the English dictionary (id 1 in this repo's dev data)
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Мои слова shows an in-progress (not yet fully learned) word tagged with its current level', (
    tester,
  ) async {
    final adminToken = await _adminToken();
    final userToken = await _userToken();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final levelName = 'E2E-Уровень-$stamp';
    final wordText = 'e2eword$stamp';

    // Clean slate: no quests/levels left enabled from a previous run would
    // overlap this run's whole-range level (assert_level_range_free
    // rejects any overlap) -- same cleanup quests_screen_test.dart does.
    for (final path in ['/admin/quests', '/admin/word-levels']) {
      final existing = await http.get(Uri.parse('$apiBaseUrl$path'), headers: {'Authorization': 'Bearer $adminToken'});
      for (final row in jsonDecode(existing.body) as List<dynamic>) {
        final id = (row as Map)['id'];
        final deleteRes = await http.delete(
          Uri.parse('$apiBaseUrl$path/$id'),
          headers: {'Authorization': 'Bearer $adminToken'},
        );
        if (deleteRes.statusCode == 409) {
          await http.patch(
            Uri.parse('$apiBaseUrl$path/$id'),
            headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
            body: jsonEncode({'enabled': false}),
          );
        }
      }
    }

    // One level covering the whole 0-100 range -- any WordProgress score
    // qualifies, this test only cares that the badge shows the level a
    // score actually lands in, not the ladder's boundaries.
    final levelRes = await http.post(
      Uri.parse('$apiBaseUrl/admin/word-levels'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'name': levelName, 'min_points': 0, 'enabled': true, 'order': 0}),
    );
    final levelId = (jsonDecode(levelRes.body) as Map)['id'] as int;

    final wordReq = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/dictionaries/1/words'))
      ..headers['Authorization'] = 'Bearer $adminToken'
      ..fields['word'] = wordText
      ..fields['translation'] = 'x';
    final wordStreamed = await wordReq.send();
    final wordBody = await wordStreamed.stream.bytesToString();
    final wordId = (jsonDecode(wordBody) as Map)['id'] as int;

    // A single real lesson answer is enough to create a WordProgress row --
    // deliberately NOT pushed to the "learned" threshold, so this word
    // would be invisible under the OLD (threshold-only) behavior and only
    // shows up now because of include_in_progress.
    final lessonRes = await http.post(
      Uri.parse('$apiBaseUrl/lessons'),
      headers: {'Authorization': 'Bearer $userToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'dictionary_id': 1, 'word_ids': [wordId]}),
    );
    final lesson = jsonDecode(lessonRes.body) as Map<String, dynamic>;
    final lessonId = lesson['id'] as int;
    final exerciseKey = (lesson['exercise_keys'] as List<dynamic>).first as String;
    await http.post(
      Uri.parse('$apiBaseUrl/lessons/$lessonId/exercises/$exerciseKey/answers'),
      headers: {'Authorization': 'Bearer $userToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'word_id': wordId, 'is_correct': false}),
    );

    await _login(tester);
    await tester.tap(find.text('Уроки'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Мои слова'));
    await tester.pumpAndSettle();
    expect(find.text('Мои изученные слова'), findsOneWidget);

    // The new word has no category -- reach it via "Без категории".
    await tester.tap(find.text('Без категории'));
    await tester.pumpAndSettle();

    expect(find.text(wordText), findsOneWidget, reason: 'an in-progress word must now be listed at all');
    expect(find.text(levelName), findsOneWidget, reason: 'tagged with the level its score actually falls in');

    // Cleanup: this level was never used by any quest, so (unlike
    // quests_screen_test.dart's own level) it can be deleted outright
    // rather than just disabled.
    await http.delete(Uri.parse('$apiBaseUrl/words/$wordId'), headers: {'Authorization': 'Bearer $adminToken'});
    await http.delete(Uri.parse('$apiBaseUrl/admin/word-levels/$levelId'), headers: {'Authorization': 'Bearer $adminToken'});
  });
}
