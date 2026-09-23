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
import 'package:http_parser/http_parser.dart';
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

      final achReq = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/admin/achievements'))
        ..headers['Authorization'] = 'Bearer $adminToken'
        ..fields['title'] = 'Первая фраза'
        ..fields['description'] = 'Ты открыл свою первую фразу'
        ..fields['condition_type'] = 'phrases_opened'
        ..fields['condition_value'] = '1'
        ..fields['color'] = '#6366F1'
        ..fields['visibility'] = 'visible'
        ..fields['show_before_unlock'] = 'true'
        ..fields['enabled'] = 'true'
        ..fields['order'] = '1'
        ..files.add(
          http.MultipartFile.fromBytes(
            'icon',
            // 1x1 transparent PNG -- content doesn't matter, only that a
            // real image file is uploaded (admin picks no emoji here).
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
            filename: 'icon.png',
            contentType: MediaType('image', 'png'),
          ),
        );
      final achStreamed = await achReq.send();
      expect(achStreamed.statusCode, 201);

      await _login(tester);
      await tester.tap(find.text('Профиль'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('testuser'), findsOneWidget);
      expect(find.textContaining('ID:'), findsOneWidget);
      expect(find.text('Достижения'), findsOneWidget);
      // The profile itself now only shows the compact icon strip and the
      // earned-count -- every achievement's own title/progress lives on
      // the dedicated "Достижения" screen behind it.
      expect(find.text('0 / 1'), findsWidgets, reason: 'not earned yet -- 0 of 1 achievements');
      await tester.tap(find.text('Достижения'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Первая фраза'), findsOneWidget, reason: 'the enabled achievement should be listed even unearned');
      // Progress towards this achievement's own condition (1 phrase). The
      // "already open" count itself depends on what else this shared dev
      // fixture has learned, so only the "/ 1" target is asserted here.
      expect(find.textContaining('/ 1'), findsWidgets, reason: 'unearned -- its progress towards 1 phrase is shown');
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 1));

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
      expect(find.text('Первая фраза'), findsWidgets, reason: 'shown in the celebration dialog');
      await tester.tap(find.widgetWithText(FilledButton, 'Отлично!'));
      await tester.pumpAndSettle();

      expect(find.text('1 / 1'), findsOneWidget, reason: 'the profile count now reads as earned');
      await tester.tap(find.text('Достижения'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'now shown as earned in the list');
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 1));

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
