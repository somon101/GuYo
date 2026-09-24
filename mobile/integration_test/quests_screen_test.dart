// Covers "Квесты сезона" end to end against the real backend: word levels ->
// quest configured for a level -> a word already at that level -> the
// the season quests screen shows it as available -> a real UI answer -> reinforcement
// points change on WordProgress + a rating reward is granted.
//
// Run with:
//   flutter test integration_test/quests_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
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

  testWidgets('Квесты shows an available quest, and a real answer changes reinforcement points and grants a reward', (
    tester,
  ) async {
    final adminToken = await _adminToken();
    final userToken = await _userToken();

    // Clean slate: no quests/levels left from a previous run -- a quest a
    // PREVIOUS run actually completed can never be deleted (same
    // "history is never silently erased" rule real admins get), so
    // disable what can't be removed instead of leaving it around to
    // overlap this run's own fresh level.
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

    // One level covering the whole 0-100 range, so any WordProgress score
    // qualifies -- this test cares about the quest flow, not the ladder.
    final levelRes = await http.post(
      Uri.parse('$apiBaseUrl/admin/word-levels'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'name': 'E2E Уровень', 'min_points': 0, 'enabled': true, 'order': 0}),
    );
    final levelId = (jsonDecode(levelRes.body) as Map)['id'] as int;

    final questRes = await http.post(
      Uri.parse('$apiBaseUrl/admin/quests'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': 'E2E Квест',
        'word_level_id': levelId,
        'exercise_key': 'true_or_false',
        'reward_points': 7,
        'enabled': true,
        'order': 0,
      }),
    );
    expect(questRes.statusCode, 201);
    final questId = (jsonDecode(questRes.body) as Map)['id'] as int;

    // A fresh word, with SOME progress already recorded (via the real
    // lessons pipeline) so it has a WordProgress row and is a real
    // candidate -- word_ids 1-10ish already exist in dictionary 1 from
    // this repo's seeded dev data; word 5 ("apple") is reused by other
    // test files too, so create a brand-new word here instead to avoid
    // cross-test interference.
    final wordReq = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/dictionaries/1/words'))
      ..headers['Authorization'] = 'Bearer $adminToken'
      ..fields['word'] = 'questword'
      ..fields['translation'] = 'x';
    final wordStreamed = await wordReq.send();
    final wordBody = await wordStreamed.stream.bytesToString();
    final wordId = (jsonDecode(wordBody) as Map)['id'] as int;

    // Give it a translation with audio-free text -- true_or_false needs
    // `translations[0]`, already present via the word creation above.

    final lessonRes = await http.post(
      Uri.parse('$apiBaseUrl/lessons'),
      headers: {'Authorization': 'Bearer $userToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'dictionary_id': 1, 'word_ids': [wordId]}),
    );
    final lesson = jsonDecode(lessonRes.body) as Map<String, dynamic>;
    final lessonId = lesson['id'] as int;
    final exerciseKey = (lesson['exercise_keys'] as List<dynamic>).first as String;
    // One real (possibly wrong) answer is enough -- this only needs a
    // WordProgress row to exist so the word is a real quest candidate,
    // not that it reach any particular level.
    await http.post(
      Uri.parse('$apiBaseUrl/lessons/$lessonId/exercises/$exerciseKey/answers'),
      headers: {'Authorization': 'Bearer $userToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'word_id': wordId, 'is_correct': true}),
    );

    final ratingBeforeRes = await http.get(
      Uri.parse('$apiBaseUrl/users/me/rating'),
      headers: {'Authorization': 'Bearer $userToken'},
    );
    final pointsBefore = (jsonDecode(ratingBeforeRes.body) as Map)['total_points'] as int;

    await _login(tester);
    // Quests now live in their own season block on Главная, not behind a
    // pill on the Уроки screen.
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('Квесты сезона'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Квесты'), findsWidgets);
    expect(find.text('Ежедневные квесты'), findsOneWidget);
    expect(find.text('E2E Квест'), findsOneWidget);

    await tester.tap(find.text('E2E Квест'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The round shows a true/false card -- tap whichever button is
    // actually correct by reading the TEXT ACTUALLY ON SCREEN (never a
    // second network call: true_or_false randomizes show-real-or-fake
    // independently on every fetch, so a second GET here would very
    // likely disagree with what the app's own single fetch already
    // rendered). The word's own real translation is "x" (see the word
    // created above); if that's what's shown, "Правда" is correct.
    final isCorrectShown = find.text('x').evaluate().isNotEmpty;

    if (isCorrectShown) {
      await tester.tap(find.widgetWithText(FilledButton, 'Правда'));
    } else {
      await tester.tap(find.widgetWithText(OutlinedButton, 'Ложь'));
    }
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Квест выполнен!'), findsOneWidget);
    expect(find.textContaining('+7 рейтинговых очков'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Готово'));
    await tester.pumpAndSettle();

    final ratingAfterRes = await http.get(
      Uri.parse('$apiBaseUrl/users/me/rating'),
      headers: {'Authorization': 'Bearer $userToken'},
    );
    final pointsAfter = (jsonDecode(ratingAfterRes.body) as Map)['total_points'] as int;
    expect(pointsAfter, pointsBefore + 7, reason: 'exactly the quest reward, granted once');

    // Cleanup. The quest was just completed, so it (and the level it
    // targets) can never be deleted (see admin_quests.py's own
    // delete-safety) -- disable both instead, so this run doesn't leave
    // the WordLevel ladder enabled and silently changing the GLOBAL
    // "word is learned" threshold for whichever test/feature runs next.
    await http.patch(
      Uri.parse('$apiBaseUrl/admin/quests/$questId'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': false}),
    );
    await http.patch(
      Uri.parse('$apiBaseUrl/admin/word-levels/$levelId'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': false}),
    );
    await http.delete(Uri.parse('$apiBaseUrl/words/$wordId'), headers: {'Authorization': 'Bearer $adminToken'});
  });
}
