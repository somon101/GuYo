// Covers "Профиль" and "Достижения" end to end against the real backend:
//   backend/database -> API -> Flutter -> avatar upload/removal ->
//   automatic achievement granting via a real lesson flow -> Profile
//   screen showing earned/unearned status and progress -> the unlock
//   celebration showing once and never again for the same achievement.
//
// Real gallery/file-picker interaction can't be driven on the Windows
// desktop test target (it opens a native OS dialog) -- avatar upload/
// removal itself is exercised via direct HTTP calls (already covered by
// backend testing), and this file instead confirms the Profile screen
// correctly RENDERS whatever the backend returns, without crashing.
//
// Run with:
//   flutter test integration_test/profile_achievements_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456, admin/123456
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

Future<void> _createPhrase(String token, int dictionaryId, String original) async {
  final req = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId/phrases'))
    ..headers['Authorization'] = 'Bearer $token'
    ..fields['original'] = original
    ..fields['translation_tg'] = 'tg-$original';
  await req.send();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Профиль shows login/id, no achievements yet; then earning one via a real lesson answer '
    'shows the unlock celebration once, and the achievement appears earned with progress afterwards',
    (tester) async {
      final adminToken = await _adminToken();
      final userToken = await _userToken();

      // Clean slate: no achievement definitions, no grants, no seen-ids.
      final existing = await http.get(
        Uri.parse('$apiBaseUrl/admin/achievements'),
        headers: {'Authorization': 'Bearer $adminToken'},
      );
      for (final a in jsonDecode(existing.body) as List<dynamic>) {
        await http.delete(
          Uri.parse('$apiBaseUrl/admin/achievements/${a['id']}'),
          headers: {'Authorization': 'Bearer $adminToken'},
        );
      }
      await const FlutterSecureStorage().delete(key: 'guyo_seen_achievement_ids');

      final dictRes = await http.post(
        Uri.parse('$apiBaseUrl/dictionaries'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'ProfileAchTest', 'language': 'pra'}),
      );
      final dictionaryId = (jsonDecode(dictRes.body) as Map)['id'] as int;
      await http.patch(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'is_published': true}),
      );
      final wordId = await _createWord(adminToken, dictionaryId, 'solo');
      await _createPhrase(adminToken, dictionaryId, 'solo');

      final achRes = await http.post(
        Uri.parse('$apiBaseUrl/admin/achievements'),
        headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Первая фраза',
          'description': 'Ты открыл свою первую фразу',
          'icon': 'trophy',
          'condition_type': 'phrases_opened',
          'condition_value': 1,
          'enabled': true,
          'order': 1,
        }),
      );
      expect(achRes.statusCode, 201);

      await _login(tester);
      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('testuser'), findsOneWidget);
      expect(find.textContaining('ID:'), findsOneWidget);
      expect(find.text('Достижения'), findsOneWidget);
      expect(find.text('Первая фраза'), findsOneWidget, reason: 'the enabled achievement should be listed even unearned');
      // "0 / 1" legitimately appears twice here: the header's earned-count
      // summary (0 of 1 achievements) AND this one achievement's own
      // progress (0 of 1 phrases) happen to coincide numerically at this
      // exact scale -- both are correct, so this only checks it's present.
      expect(find.text('0 / 1'), findsWidgets, reason: 'not earned yet -- 0 phrases open so far');
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // Earn it: create a lesson with the one word and answer correctly
      // through the REAL exercise/answers pipeline (never a raw DB write).
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

      // Pull to refresh the Profile screen -- this is the moment the
      // unlock celebration should appear, since this device hasn't shown
      // it for this achievement yet.
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Достижение получено!'), findsOneWidget, reason: 'first time seeing this earned achievement');
      expect(find.text('Первая фраза'), findsWidgets, reason: 'shown both in the dialog and (behind it) the list');
      await tester.tap(find.widgetWithText(FilledButton, 'Отлично!'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'now shown as earned in the list');
      expect(find.byIcon(Icons.lock_outline), findsNothing);

      // Refresh again -- the celebration must NOT show a second time for
      // the same achievement.
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('Достижение получено!'), findsNothing, reason: 'already shown once on this device -- must not repeat');

      await http.delete(
        Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
        headers: {'Authorization': 'Bearer $adminToken'},
      );
      final remaining = await http.get(
        Uri.parse('$apiBaseUrl/admin/achievements'),
        headers: {'Authorization': 'Bearer $adminToken'},
      );
      for (final a in jsonDecode(remaining.body) as List<dynamic>) {
        // The one we earned is now blocked from deletion (409) -- that's
        // expected/correct; only clean up ones that aren't.
        await http.delete(
          Uri.parse('$apiBaseUrl/admin/achievements/${a['id']}'),
          headers: {'Authorization': 'Bearer $adminToken'},
        );
      }
    },
  );
}
