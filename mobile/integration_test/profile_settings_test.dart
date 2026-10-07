// Covers "Настройки" end to end against the real backend:
//   - the gear opens a SCREEN, not the old photo-only sheet;
//   - the profile shows the 9-digit account number;
//   - name, surname and email are editable there and are saved through
//     the backend, not only on the device;
//   - the profile then shows what the server holds.
//
// Deliberately does NOT change the login: other tests sign in as
// "testuser", and renaming it here would break them.
//
// Run with:
//   flutter test integration_test/profile_settings_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL with user testuser/123456.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';
import 'package:guyo_app/screens/profile_settings_screen.dart';

Future<String> _userToken() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'testuser', 'password': '123456'}),
  );
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}

Future<Map<String, dynamic>> _profile(String token) async {
  final res = await http.get(
    Uri.parse('$apiBaseUrl/users/me/profile'),
    headers: {'Authorization': 'Bearer $token'},
  );
  return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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

  testWidgets('Настройки is its own screen, and name/surname/email save through the backend', (tester) async {
    final token = await _userToken();
    final before = await _profile(token);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final newFirst = 'Имя$stamp';
    final newLast = 'Фамилия$stamp';
    final newEmail = 'settings.$stamp@mail.ru';

    await _login(tester);
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The account number shown is the 9-digit one, never the internal key.
    final publicId = before['public_id'] as int;
    expect(publicId, greaterThanOrEqualTo(100000000));
    expect(publicId, lessThanOrEqualTo(999999999));
    expect(find.text('ID: $publicId'), findsOneWidget, reason: 'the profile shows the account number');

    // --- The gear opens a screen, not a sheet ---
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    for (final label in ['Логин', 'Имя и фамилия', 'Почта', 'Мои темы', 'Язык интерфейса']) {
      expect(find.text(label), findsOneWidget, reason: '$label is a row in Настройки');
    }

    // --- Each row opens its own small editor and saves on its own ---
    await tester.tap(find.text('Имя и фамилия'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Имя'), newFirst);
    await tester.enterText(find.widgetWithText(TextField, 'Фамилия'), newLast);
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('$newFirst $newLast'), findsOneWidget, reason: 'the row shows the saved name');

    await tester.tap(find.text('Почта'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Электронная почта'), newEmail);
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text(newEmail), findsOneWidget, reason: 'the row shows the saved email');

    final after = await _profile(token);
    expect(after['first_name'], newFirst);
    expect(after['last_name'], newLast);
    expect(after['email'], newEmail);
    expect(after['public_id'], publicId, reason: 'the account number never changes');
    expect(after['login'], before['login'], reason: 'nothing else was touched');

    // Restore whatever this account had before, so repeated runs and the
    // other tests see the fixture they expect.
    await http.patch(
      Uri.parse('$apiBaseUrl/users/me/profile'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'first_name': before['first_name'] ?? '',
        'last_name': before['last_name'] ?? '',
        'email': before['email'],
      }),
    );
  });
}
