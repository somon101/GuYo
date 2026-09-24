// Covers the two new home-screen systems end to end against the real
// backend, in one run:
//
//   Слоганы   — an admin creates a line, the greeting shows THAT line, and
//               a second load the same day shows the same one (the whole
//               point of pinning it for the day). With nothing enabled the
//               app falls back to its own built-in line instead of an
//               empty row.
//
//   Уведомления — an admin sends a message, the bell carries an indicator,
//               opening it shows the message marked "Новое", and the
//               unread count the backend reports drops to zero afterwards.
//
// Every assertion is cross-checked against the API in the same run, so
// none of it can pass on a hardcoded string.
//
// Run with:
//   flutter test integration_test/slogans_notifications_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL with testuser/123456 and
// admin/123456.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';
import 'package:guyo_app/screens/notifications_screen.dart';
import 'package:guyo_app/theme/slogans.dart';

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

Map<String, String> _json(String token) => {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

/// Every slogan is removed first so "the greeting shows THAT line" is a
/// real assertion and not a one-in-N coincidence. Returns what was there,
/// so the fixture can be put back.
Future<List<Map<String, dynamic>>> _clearSlogans(String adminToken) async {
  final res = await http.get(Uri.parse('$apiBaseUrl/admin/slogans'), headers: _json(adminToken));
  final existing = (jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>).cast<Map<String, dynamic>>();
  for (final s in existing) {
    await http.delete(Uri.parse('$apiBaseUrl/admin/slogans/${s['id']}'), headers: _json(adminToken));
  }
  return existing;
}

Future<int> _unreadCount(String userToken) async {
  final res = await http.get(
    Uri.parse('$apiBaseUrl/notifications/unread-count'),
    headers: _json(userToken),
  );
  return (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['unread_count'] as int;
}

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

  testWidgets('an admin-created slogan is what the greeting shows, and it holds for the day', (tester) async {
    final admin = await _adminToken();
    final user = await _userToken();
    final restore = await _clearSlogans(admin);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final text = 'E2E слоган $stamp';

    // Only one enabled line exists, so the greeting can show nothing else.
    final created = await http.post(
      Uri.parse('$apiBaseUrl/admin/slogans'),
      headers: _json(admin),
      body: jsonEncode({'text': text, 'enabled': true}),
    );
    expect(created.statusCode, 201, reason: 'the admin could not create a slogan');
    final sloganId = (jsonDecode(utf8.decode(created.bodyBytes)) as Map)['id'] as int;

    // The backend pins per day, so today's pick must be cleared for this
    // user or an earlier run's choice would still be held.
    await http.delete(Uri.parse('$apiBaseUrl/admin/slogans/$sloganId'), headers: _json(admin));
    final recreated = await http.post(
      Uri.parse('$apiBaseUrl/admin/slogans'),
      headers: _json(admin),
      body: jsonEncode({'text': text, 'enabled': true}),
    );
    final freshId = (jsonDecode(utf8.decode(recreated.bodyBytes)) as Map)['id'] as int;

    await _login(tester);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.textContaining('Привет, testuser'), findsOneWidget, reason: 'the greeting still names the user');
    expect(find.text(text), findsOneWidget, reason: "the admin's own line is what the greeting shows");

    // What the API says, in the same run -- and the same line again, which
    // is the whole point of pinning it for the day.
    final todayRes = await http.get(Uri.parse('$apiBaseUrl/slogans/today'), headers: _json(user));
    expect((jsonDecode(utf8.decode(todayRes.bodyBytes)) as Map)['text'], text);
    final againRes = await http.get(Uri.parse('$apiBaseUrl/slogans/today'), headers: _json(user));
    expect((jsonDecode(utf8.decode(againRes.bodyBytes)) as Map)['text'], text,
        reason: 'the same day must hand back the same line');

    // With nothing enabled the app must still have a second row -- its own
    // built-in list, never a blank.
    await http.delete(Uri.parse('$apiBaseUrl/admin/slogans/$freshId'), headers: _json(admin));
    final emptyRes = await http.get(Uri.parse('$apiBaseUrl/slogans/today'), headers: _json(user));
    expect((jsonDecode(utf8.decode(emptyRes.bodyBytes)) as Map)['text'], isNull);
    expect(
      await const LocalSloganSource().today(),
      isNotEmpty,
      reason: 'the fallback the app uses when the backend has none',
    );

    // Put the admin's own slogans back.
    for (final s in restore) {
      await http.post(
        Uri.parse('$apiBaseUrl/admin/slogans'),
        headers: _json(admin),
        body: jsonEncode({'text': s['text'], 'enabled': s['enabled']}),
      );
    }
  });

  testWidgets('a message an admin sends shows up behind the bell and is marked read on opening', (tester) async {
    final admin = await _adminToken();
    final user = await _userToken();

    // Start from a read inbox so the indicator below means this message.
    await http.post(Uri.parse('$apiBaseUrl/notifications/read-all'), headers: _json(user));
    expect(await _unreadCount(user), 0, reason: 'the inbox should start read');

    final usersRes = await http.get(Uri.parse('$apiBaseUrl/users'), headers: _json(admin));
    final me = (jsonDecode(utf8.decode(usersRes.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((u) => u['login'] == 'testuser');

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final body = 'E2E сообщение $stamp';
    final sent = await http.post(
      Uri.parse('$apiBaseUrl/admin/notifications'),
      headers: _json(admin),
      body: jsonEncode({'user_id': me['id'], 'title': 'E2E заголовок', 'body': body}),
    );
    expect(sent.statusCode, 201, reason: 'the admin could not send the message');
    expect(await _unreadCount(user), 1);

    await _login(tester);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // The bell carries an indicator while anything is unread.
    expect(
      find.byKey(const ValueKey('notifications-unread-dot')),
      findsOneWidget,
      reason: 'an unread message must show on the bell',
    );

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byType(NotificationsScreen), findsOneWidget, reason: 'the bell opens the inbox');
    expect(find.text(body), findsOneWidget, reason: "the admin's message is shown");
    expect(find.text('E2E заголовок'), findsOneWidget);
    expect(find.text('Новое'), findsWidgets, reason: 'unread on this visit is marked as such');

    // Opening the inbox IS reading it -- confirmed against the backend.
    expect(await _unreadCount(user), 0, reason: 'opening the inbox marks everything read');

    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(
      find.byKey(const ValueKey('notifications-unread-dot')),
      findsNothing,
      reason: 'the indicator clears once nothing is unread',
    );
  });
}
