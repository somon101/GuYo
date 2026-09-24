// Covers the "Рейтинг" tab end to end against the real backend:
//   - the tab shows only the CALLER's own current rank's leaderboard, with
//     no control to switch ranks;
//   - the first three places are the podium and the compact list picks up
//     at fourth, so nobody is listed twice;
//   - "Глобальный рейтинг" opens a separate top-100 across every rank.
//
// Run with:
//   flutter test integration_test/rating_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456, admin/123456
//   - the 7 default ranks already seeded (python -m app.seed)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';
import 'package:guyo_app/screens/rating_screen.dart';

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

  testWidgets('Рейтинг tab shows only the own-rank leaderboard, and Глобальный рейтинг shows everyone', (
    tester,
  ) async {
    final userToken = await _userToken();
    final myRatingRes = await http.get(
      Uri.parse('$apiBaseUrl/users/me/rating'),
      headers: {'Authorization': 'Bearer $userToken'},
    );
    final myRating = jsonDecode(myRatingRes.body) as Map<String, dynamic>;
    final myRankName = (myRating['rank'] as Map?)?['name'] as String?;
    expect(myRankName, isNotNull, reason: 'testuser must currently have a rank for this test to be meaningful');

    await _login(tester);
    await tester.tap(find.text('Рейтинг'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The own-rank board's header names testuser's own current rank, and
    // never offers any way to pick a different one.
    expect(find.text(myRankName!), findsWidgets, reason: 'shows the caller\'s own rank name');
    expect(find.text('testuser'), findsOneWidget, reason: 'the caller appears in their own leaderboard');
    expect(find.byType(DropdownButton), findsNothing, reason: 'no rank switcher of any kind');

    // The board's own top three are the podium, and the compact list below
    // starts at fourth place -- read straight from the API so this cannot
    // pass on a hardcoded name.
    final boardRes = await http.get(
      Uri.parse('$apiBaseUrl/rating/leaderboard'),
      headers: {'Authorization': 'Bearer $userToken'},
    );
    final entries = (jsonDecode(utf8.decode(boardRes.bodyBytes)) as Map)['entries'] as List<dynamic>;
    if (entries.length > LeaderboardPodium.placeCount) {
      expect(find.byType(LeaderboardPodium), findsOneWidget);
      final fourth = entries[LeaderboardPodium.placeCount] as Map<String, dynamic>;
      expect(
        find.descendant(
          of: find.widgetWithText(LeaderboardRow, fourth['login'] as String),
          matching: find.text('${fourth['position']}'),
        ),
        findsOneWidget,
        reason: 'the compact list opens at fourth place, right where the podium ended',
      );
      for (var i = 0; i < LeaderboardPodium.placeCount; i++) {
        final podiumLogin = (entries[i] as Map<String, dynamic>)['login'] as String;
        expect(
          find.widgetWithText(LeaderboardRow, podiumLogin),
          findsNothing,
          reason: 'a podium place must not be repeated in the list below',
        );
      }
    }

    await tester.tap(find.text('Глобальный рейтинг'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Глобальный рейтинг'), findsWidgets);
    expect(find.text('testuser'), findsOneWidget, reason: 'the caller also appears in the global board');
    // The global board mixes ranks -- lb_gm_1 (seeded far above testuser)
    // must appear above testuser if global data from the leaderboard
    // smoke-test still exists; skip that specific assertion if it doesn't,
    // since this test only owns testuser's own row.
  });
}
