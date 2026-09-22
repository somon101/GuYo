// Covers the Profile screen's "Рейтинг" block end to end against the real
// backend: settings -> ranks -> a real lesson answer crossing the learned
// threshold -> points awarded once -> Profile screen showing the current
// rank/points/progress, entirely separate from achievements.
//
// Run with:
//   flutter test integration_test/profile_rating_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
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

  testWidgets(
    'Профиль shows the current rank/points, and learning a new word raises points by exactly the configured amount',
    (tester) async {
      final adminToken = await _adminToken();
      final userToken = await _userToken();

      // Clean slate: no ranks/seasons left from a previous run.
      for (final path in ['/admin/rating/ranks', '/admin/rating/seasons']) {
        final existing = await http.get(
          Uri.parse('$apiBaseUrl$path'),
          headers: {'Authorization': 'Bearer $adminToken'},
        );
        for (final row in jsonDecode(existing.body) as List<dynamic>) {
          if (path == '/admin/rating/seasons' && (row as Map)['status'] == 'active') {
            await http.post(
              Uri.parse('$apiBaseUrl/admin/rating/seasons/${row['id']}/end'),
              headers: {'Authorization': 'Bearer $adminToken'},
            );
          } else if (path == '/admin/rating/ranks') {
            await http.delete(
              Uri.parse('$apiBaseUrl$path/${(row as Map)['id']}'),
              headers: {'Authorization': 'Bearer $adminToken'},
            );
          }
        }
      }

      await http.put(
        Uri.parse('$apiBaseUrl/admin/rating/settings'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'points_per_learned_word': 10, 'season_reset_mode': 'fixed', 'season_reset_value': 0}),
      );

      final rankReq = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/admin/rating/ranks'))
        ..headers['Authorization'] = 'Bearer $adminToken'
        ..fields['name'] = 'ТестРанг'
        ..fields['min_points'] = '0'
        ..fields['color'] = '#22C55E'
        ..fields['enabled'] = 'true';
      final rankStreamed = await rankReq.send();
      expect(rankStreamed.statusCode, 201);

      // A unique name per run -- ending a PAST run's own season (the
      // cleanup loop above) permanently freezes a SeasonHistory row under
      // that name (by design: history is never deletable via the public
      // API), so reusing the same literal name every run would make it
      // ambiguous which "ТестСезон" text on screen is this run's current
      // season vs. an old frozen result.
      final seasonName = 'ТестСезон-${DateTime.now().millisecondsSinceEpoch}';
      await http.post(
        Uri.parse('$apiBaseUrl/admin/rating/seasons'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': seasonName}),
      );

      // Create a fresh dictionary/word so this run's points are predictable
      // regardless of what testuser already learned in other test files.
      final dictRes = await http.post(
        Uri.parse('$apiBaseUrl/dictionaries'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'RatingProfileTest', 'language': 'rpt'}),
      );
      final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
      await http.patch(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_published': true}),
      );
      final wordReq = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/words'))
        ..headers['Authorization'] = 'Bearer $adminToken'
        ..fields['word'] = 'solo'
        ..fields['translation'] = 'x';
      final wordStreamed = await wordReq.send();
      final wordBody = await wordStreamed.stream.bytesToString();
      final wordId = (jsonDecode(wordBody) as Map)['id'] as int;

      final pointsBeforeRes = await http.get(
        Uri.parse('$apiBaseUrl/users/me/rating'),
        headers: {'Authorization': 'Bearer $userToken'},
      );
      final pointsBefore = (jsonDecode(pointsBeforeRes.body) as Map)['total_points'] as int;

      await _login(tester);
      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // "Рейтинг" legitimately appears twice now: the bottom nav's own tab
      // label (always in the tree once IndexedStack has built it, even
      // while a different tab is on top) AND this section's own header --
      // both correct, so this only checks the section is present at all.
      expect(find.text('Рейтинг'), findsWidgets);
      expect(find.text('ТестРанг'), findsOneWidget, reason: 'the only enabled rank should show as current');
      expect(find.text(seasonName), findsOneWidget);
      expect(find.text('$pointsBefore очков'), findsOneWidget);

      // Learn the word through the REAL exercise/answers pipeline.
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

      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(
        find.text('${pointsBefore + 10} очков'),
        findsOneWidget,
        reason: 'exactly +10 points for the one newly learned word',
      );

      await http.delete(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken'},
      );
    },
  );
}
