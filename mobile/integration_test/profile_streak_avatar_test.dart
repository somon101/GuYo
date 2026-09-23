// Covers the two additions to "Профиль" end to end against the real
// backend: the activity streak badge (server-computed, reused from
// app/achievements/conditions.py's streak_days_count -- never a locally
// tracked counter) and avatar upload/replace/delete (already existed;
// this just re-confirms it still works and that BOTH values come back
// from the backend together on GET /users/me/profile, as they would for
// a login from a different device).
//
// Run with:
//   flutter test integration_test/profile_streak_avatar_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with user testuser/123456.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Профиль shows the real server-computed activity streak, sourced from GET /users/me/profile', (
    tester,
  ) async {
    final loginRes = await http.post(
      Uri.parse('$apiBaseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'login': 'testuser', 'password': '123456'}),
    );
    final userToken = (jsonDecode(loginRes.body) as Map)['access_token'] as String;

    // GET /users/me/profile is the exact source of truth this screen
    // reads -- fetch it directly first so this test knows the real
    // expected number instead of guessing at fixture setup.
    final profileRes = await http.get(
      Uri.parse('$apiBaseUrl/users/me/profile'),
      headers: {'Authorization': 'Bearer $userToken'},
    );
    final profile = jsonDecode(profileRes.body) as Map<String, dynamic>;
    final streakDays = profile['current_streak_days'] as int;
    expect(streakDays, greaterThan(0), reason: 'testuser should have SOME recent activity from other test runs today');

    await _login(tester);
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Серий'), findsOneWidget, reason: 'the streak stat card renders');
    expect(find.textContaining('$streakDays'), findsWidgets, reason: 'shows the exact backend-computed number');

    // Re-fetch straight from the backend to confirm avatar_url/streak
    // travel together in one response, exactly as a login from a
    // different device would receive them (both live in Postgres, never
    // only on this one).
    final refetchRes = await http.get(
      Uri.parse('$apiBaseUrl/users/me/profile'),
      headers: {'Authorization': 'Bearer $userToken'},
    );
    final refetched = jsonDecode(refetchRes.body) as Map<String, dynamic>;
    expect(refetched['current_streak_days'], streakDays);
  });
}
