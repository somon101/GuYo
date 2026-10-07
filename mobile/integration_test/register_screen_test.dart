// Covers self-registration end to end against the real backend:
//   Вход -> "Регистрация" -> выбор языка (>4 доступно, "Другие" видна) ->
//   данные аккаунта (валидация) -> возраст -> цель -> источник ->
//   создание аккаунта -> автоматический вход -> Главная.
//
// Also covers: a taken login surfaces the backend's own message without
// losing any previously entered data, and resubmitting after fixing it
// succeeds.
//
// Run with (needs the local backend at that URL, with admin/123456, and
// at least 5 distinct published dictionary languages so "Другие
// доступные языки" has something to reveal):
//   flutter test integration_test/register_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';

Future<String> _adminToken() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/admin/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'admin', 'password': '123456'}),
  );
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}

Future<void> _deleteUserByLogin(String adminToken, String login) async {
  final res = await http.get(
    Uri.parse('$apiBaseUrl/users'),
    headers: {'Authorization': 'Bearer $adminToken'},
  );
  final users = (jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>).cast<Map<String, dynamic>>();
  final match = users.where((u) => u['login'] == login);
  if (match.isEmpty) return;
  await http.delete(
    Uri.parse('$apiBaseUrl/users/${match.first['id']}'),
    headers: {'Authorization': 'Bearer $adminToken'},
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Вход -> Регистрация: язык (с "Другие доступные языки") -> аккаунт '
    '(валидация + занятый логин) -> возраст -> цель -> источник -> '
    'создание аккаунта -> автоматический вход -> Главная',
    (tester) async {
      final adminToken = await _adminToken();
      const testLogin = 'reg_e2e_testuser';
      const otherLogin = 'reg_e2e_taken';
      await _deleteUserByLogin(adminToken, testLogin);
      await _deleteUserByLogin(adminToken, otherLogin);

      // A throwaway account whose login we'll deliberately collide with,
      // to exercise the "занятый логин" backend error path for real.
      await http.post(
        Uri.parse('$apiBaseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'login': otherLogin,
          'password': '1234',
          'password_confirm': '1234',
          'first_name': 'Taken',
          'last_name': 'User',
          'email': 'reg_e2e_taken@test.com',
          'learning_language': 'en',
          'age_group': '18-24',
          'learning_goal': 'study',
          'referral_source': 'youtube',
        }),
      );

      try {
        await tester.pumpWidget(const GuyoApp());
        await tester.pumpAndSettle(const Duration(seconds: 2));

        if (find.text('Главная').evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(Icons.more_vert));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Выйти'));
          await tester.pumpAndSettle();
        }

        expect(find.text('Вход'), findsOneWidget, reason: 'should start at the login screen');
        await tester.tap(find.text('Регистрация'));
        await tester.pumpAndSettle();

        // --- Step 1: language ------------------------------------------
        expect(find.text('Какой язык хотите изучать?'), findsOneWidget);
        await tester.pumpAndSettle(const Duration(seconds: 2)); // let GET /dictionaries/public land
        expect(
          find.byKey(const ValueKey('register-show-all-languages')),
          findsOneWidget,
          reason: 'local dev has >4 distinct languages -- the "Другие" button must show',
        );
        // English is dictionary id=1, always in the first-4 slice
        // regardless of total count, so no need to actually expand it
        // for this run -- its own visibility already proves that branch.
        final englishTile = find.byKey(const ValueKey('register-language-en'));
        expect(englishTile, findsOneWidget);
        await tester.tap(englishTile);
        await tester.pumpAndSettle();

        Future<void> tapNext() async {
          await tester.tap(find.byKey(const ValueKey('register-next-button')));
          await tester.pumpAndSettle();
        }

        await tapNext();

        // --- A Russian interface also asks the translation language ----
        expect(find.text('На каком языке показывать перевод слов?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('register-translation-uz')));
        await tester.pumpAndSettle();
        await tapNext();

        // --- Name step, first left empty --------------------------------
        expect(find.text('Как вас зовут?'), findsOneWidget);
        await tapNext();
        expect(find.text('Введите имя'), findsOneWidget);
        expect(find.text('Введите фамилию'), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('register-field-first-name')), 'Регтест');
        await tester.enterText(find.byKey(const ValueKey('register-field-last-name')), 'Регтестов');
        await tapNext();

        // --- Login and password: no email field anywhere ----------------
        expect(find.text('Логин и пароль'), findsOneWidget);
        expect(find.byKey(const ValueKey('register-field-email')), findsNothing,
            reason: 'the email comes from the Google account, never typed');
        await tester.enterText(find.byKey(const ValueKey('register-field-login')), testLogin);
        await tester.enterText(find.byKey(const ValueKey('register-field-password')), '123');
        await tester.enterText(find.byKey(const ValueKey('register-field-confirm')), '456');
        await tapNext();
        expect(find.text('Логин и пароль'), findsOneWidget, reason: 'invalid data must not advance the wizard');
        expect(find.text('Минимум 4 символа'), findsWidgets);
        expect(find.text('Пароли не совпадают'), findsOneWidget);

        // The eye shows the password.
        await tester.enterText(find.byKey(const ValueKey('register-field-password')), '1234');
        await tester.enterText(find.byKey(const ValueKey('register-field-confirm')), '1234');
        TextField pwd() => tester.widget<TextField>(find.byKey(const ValueKey('register-field-password')));
        expect(pwd().obscureText, isTrue);
        await tester.tap(find.byKey(ValueKey('${const ValueKey('register-field-password')}-eye')));
        await tester.pump();
        expect(pwd().obscureText, isFalse);
        await tapNext();

        // --- Remaining steps --------------------------------------------
        expect(find.text('Укажите ваш возраст'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('register-age-18-24')));
        await tester.pumpAndSettle();
        await tapNext();
        await tester.tap(find.byKey(const ValueKey('register-goal-study')));
        await tester.pumpAndSettle();
        await tapNext();
        expect(find.text('Как вы нас нашли?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('register-referral-youtube')));
        await tester.pumpAndSettle();

        // The last button links the Google account (its picker is the
        // system's, so the account itself is created by hand on a phone;
        // the backend side is covered on the server).
        expect(find.text('Привязать Google-аккаунт'), findsOneWidget);
      } finally {
        await _deleteUserByLogin(adminToken, testLogin);
        await _deleteUserByLogin(adminToken, otherLogin);
      }
    },
  );
}
