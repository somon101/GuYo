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

        // --- Step 2: account, first with deliberately bad data ---------
        expect(find.text('Данные аккаунта'), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('register-field-first-name')), '');
        await tester.enterText(find.byKey(const ValueKey('register-field-email')), 'not-an-email');
        await tester.enterText(find.byKey(const ValueKey('register-field-password')), '123');
        await tester.enterText(find.byKey(const ValueKey('register-field-confirm')), '456');
        await tapNext();

        // Still on the account step -- inline errors, not a giant banner.
        expect(find.text('Данные аккаунта'), findsOneWidget, reason: 'invalid data must not advance the wizard');
        expect(find.text('Введите имя'), findsOneWidget);
        expect(find.text('Некорректный email'), findsOneWidget);
        expect(find.text('Пароли не совпадают'), findsOneWidget);

        // Now fill it in for real, but with the ALREADY-TAKEN login first.
        await tester.enterText(find.byKey(const ValueKey('register-field-first-name')), 'Регтест');
        await tester.enterText(find.byKey(const ValueKey('register-field-last-name')), 'Регтестов');
        await tester.enterText(find.byKey(const ValueKey('register-field-email')), 'reg_e2e_new@test.com');
        await tester.enterText(find.byKey(const ValueKey('register-field-login')), otherLogin);
        await tester.enterText(find.byKey(const ValueKey('register-field-password')), '1234');
        await tester.enterText(find.byKey(const ValueKey('register-field-confirm')), '1234');
        await tapNext();

        // --- Steps 3/4/5 ------------------------------------------------
        expect(find.text('Укажите ваш возраст'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('register-age-18-24')));
        await tester.pumpAndSettle();
        await tapNext();

        expect(find.text('Для чего вы изучаете язык?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('register-goal-study')));
        await tester.pumpAndSettle();
        await tapNext();

        expect(find.text('Как вы нас нашли?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('register-referral-youtube')));
        await tester.pumpAndSettle();

        // Submit with the taken login -- expect the backend's own
        // message, still on this same step, nothing lost.
        await tester.tap(find.byKey(const ValueKey('register-next-button')));
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.textContaining('Login already taken'), findsOneWidget);
        expect(
          find.text('Как вы нас нашли?'),
          findsOneWidget,
          reason: 'a failed submit must not lose the wizard state',
        );

        // Go back to fix the login -- every earlier field must still be
        // exactly as typed.
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Данные аккаунта'), findsOneWidget);
        expect(find.text('Регтест'), findsOneWidget, reason: 'first name must have survived the round trip');
        await tester.enterText(find.byKey(const ValueKey('register-field-login')), testLogin);
        await tapNext();
        await tester.tap(find.byKey(const ValueKey('register-age-18-24')));
        await tester.pumpAndSettle();
        await tapNext();
        await tester.tap(find.byKey(const ValueKey('register-goal-study')));
        await tester.pumpAndSettle();
        await tapNext();
        await tester.tap(find.byKey(const ValueKey('register-referral-youtube')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('register-next-button')));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(find.text('Главная'), findsOneWidget, reason: 'should auto-login straight to Главная');

        // --- Verify real backend persistence of every collected field ---
        final usersRes = await http.get(
          Uri.parse('$apiBaseUrl/users'),
          headers: {'Authorization': 'Bearer $adminToken'},
        );
        final users = (jsonDecode(utf8.decode(usersRes.bodyBytes)) as List<dynamic>).cast<Map<String, dynamic>>();
        final created = users.firstWhere((u) => u['login'] == testLogin);
        expect(created['public_id'], greaterThanOrEqualTo(100000000));
        expect(created['public_id'], lessThanOrEqualTo(999999999));
        expect(created['first_name'], 'Регтест');
        expect(created['last_name'], 'Регтестов');
        expect(created['email'], 'reg_e2e_new@test.com');

        final profileRes = await http.post(
          Uri.parse('$apiBaseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'login': testLogin, 'password': '1234'}),
        );
        final userToken = (jsonDecode(profileRes.body) as Map)['access_token'] as String;
        final meRes = await http.get(
          Uri.parse('$apiBaseUrl/users/me/profile'),
          headers: {'Authorization': 'Bearer $userToken'},
        );
        final me = jsonDecode(utf8.decode(meRes.bodyBytes)) as Map<String, dynamic>;
        expect(me['learning_language'], 'en');
        expect(me['age_group'], '18-24');
        expect(me['learning_goal'], 'study');
        expect(me['referral_source'], 'youtube');
      } finally {
        await _deleteUserByLogin(adminToken, testLogin);
        await _deleteUserByLogin(adminToken, otherLogin);
      }
    },
  );
}
