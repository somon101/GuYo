// Covers the new "Все уровни" screen end to end against the real backend:
// GET /rating/ranks returns the full ladder, and the screen correctly
// splits it into passed/current/future relative to the caller's own
// current rank (never a second rank-classification of its own).
//
// Run with:
//   flutter test integration_test/all_ranks_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456, admin/123456
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

  testWidgets('Все уровни shows the full ladder with passed/current/future correctly split', (tester) async {
    final adminToken = await _adminToken();
    final userToken = await _userToken();

    // A 100% reset mode BEFORE ending whatever season is currently active
    // zeroes testuser's points as a side effect of that end -- the only
    // reliable way to reach a known point total, since this account's
    // total_points otherwise carries over from every other test file that
    // has ever run against it.
    await http.put(
      Uri.parse('$apiBaseUrl/admin/rating/settings'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'points_per_learned_word': 1, 'season_reset_mode': 'percent', 'season_reset_value': 100}),
    );
    for (final path in ['/admin/rating/ranks', '/admin/rating/seasons']) {
      final existing = await http.get(Uri.parse('$apiBaseUrl$path'), headers: {'Authorization': 'Bearer $adminToken'});
      for (final row in jsonDecode(existing.body) as List<dynamic>) {
        if (path == '/admin/rating/seasons' && (row as Map)['status'] == 'active') {
          await http.post(
            Uri.parse('$apiBaseUrl/admin/rating/seasons/${row['id']}/end'),
            headers: {'Authorization': 'Bearer $adminToken'},
          );
        } else if (path == '/admin/rating/ranks') {
          await http.delete(Uri.parse('$apiBaseUrl$path/${(row as Map)['id']}'), headers: {'Authorization': 'Bearer $adminToken'});
        }
      }
    }

    // The cleanup loop above only resets points as a SIDE EFFECT of ending
    // an already-active season -- if there happened to be none (e.g. the
    // previous test run already ended its own), testuser's total_points
    // just carries over untouched. Force a reset unconditionally: start a
    // throwaway season and immediately end it under the still-100%-reset
    // settings, so total_points is guaranteed 0 regardless of prior state.
    await http.post(
      Uri.parse('$apiBaseUrl/admin/rating/seasons'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'name': 'СезонСброса-${DateTime.now().millisecondsSinceEpoch}'}),
    );
    final resetSeasons = jsonDecode(
      (await http.get(Uri.parse('$apiBaseUrl/admin/rating/seasons'), headers: {'Authorization': 'Bearer $adminToken'})).body,
    ) as List<dynamic>;
    final activeForReset = resetSeasons.firstWhere((s) => (s as Map)['status'] == 'active') as Map;
    await http.post(
      Uri.parse('$apiBaseUrl/admin/rating/seasons/${activeForReset['id']}/end'),
      headers: {'Authorization': 'Bearer $adminToken'},
    );

    await http.put(
      Uri.parse('$apiBaseUrl/admin/rating/settings'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'points_per_learned_word': 60, 'season_reset_mode': 'fixed', 'season_reset_value': 0}),
    );
    await http.post(
      Uri.parse('$apiBaseUrl/admin/rating/seasons'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'name': 'СезонЛестницы-${DateTime.now().millisecondsSinceEpoch}'}),
    );

    Future<void> createRank(String name, int minPoints, int? maxPoints) async {
      final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/admin/rating/ranks'))
        ..headers['Authorization'] = 'Bearer $adminToken'
        ..fields['name'] = name
        ..fields['min_points'] = '$minPoints'
        ..fields['color'] = '#22C55E'
        ..fields['enabled'] = 'true';
      if (maxPoints != null) req.fields['max_points'] = '$maxPoints';
      final streamed = await req.send();
      expect(streamed.statusCode, 201, reason: 'rank $name must be created');
    }

    // 0-49 (will be PASSED), 50-149 (will be CURRENT, landed on via one
    // 60-point word below), 150+ (will be FUTURE).
    await createRank('РангНизкий', 0, 49);
    await createRank('РангСредний', 50, 149);
    await createRank('РангВысокий', 150, null);

    final beforeRating = jsonDecode(
      (await http.get(Uri.parse('$apiBaseUrl/users/me/rating'), headers: {'Authorization': 'Bearer $userToken'})).body,
    ) as Map;
    final currentPoints = beforeRating['total_points'] as int;
    expect(currentPoints, 0, reason: 'the season-end reset above must have zeroed testuser\'s points');

    final dictRes = await http.post(
      Uri.parse('$apiBaseUrl/dictionaries'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'name': 'AllRanksTest', 'language': 'art'}),
    );
    final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
    await http.patch(
      Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
      headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'is_published': true}),
    );
    final wordReq = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/words'))
      ..headers['Authorization'] = 'Bearer $adminToken'
      ..fields['word'] = 'ladderword'
      ..fields['translation'] = 'x';
    final wordStreamed = await wordReq.send();
    final wordBody = await wordStreamed.stream.bytesToString();
    final wordId = (jsonDecode(wordBody) as Map)['id'] as int;

    final createLessonRes = await http.post(
      Uri.parse('$apiBaseUrl/lessons'),
      headers: {'Authorization': 'Bearer $userToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'dictionary_id': dictionaryId, 'word_ids': [wordId]}),
    );
    final lesson = jsonDecode(createLessonRes.body) as Map<String, dynamic>;
    final lessonId = lesson['id'] as int;
    final exerciseKey = (lesson['exercise_keys'] as List<dynamic>).first as String;
    for (var i = 0; i < 8; i++) {
      await http.post(
        Uri.parse('$apiBaseUrl/lessons/$lessonId/exercises/$exerciseKey/answers'),
        headers: {'Authorization': 'Bearer $userToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'word_id': wordId, 'is_correct': true}),
      );
    }

    final finalPoints = currentPoints + 60;
    expect(finalPoints, inInclusiveRange(50, 149), reason: 'test setup must land the user in РангСредний');

    await _login(tester);
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // The rank card itself is the way in now -- its chevron stands for
    // what used to be a separate "Все уровни" button.
    await tester.tap(find.text('РангСредний'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Все уровни'), findsWidgets, reason: 'the AppBar title, at least');
    expect(find.text('РангНизкий'), findsOneWidget);
    expect(find.text('РангСредний'), findsOneWidget);
    expect(find.text('РангВысокий'), findsOneWidget);
    expect(find.text('Вы здесь'), findsOneWidget, reason: 'exactly one rank is marked as current');
    expect(find.text('Нужно ещё ${150 - finalPoints} очков'), findsOneWidget, reason: 'the future rank shows the real points gap');

    await http.delete(Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'), headers: {'Authorization': 'Bearer $adminToken'});
  });
}
