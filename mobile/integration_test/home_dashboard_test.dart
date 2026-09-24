// Covers the redesigned "Главная" and the "Квесты сезона" screen behind
// it, against the real backend:
//   - the greeting shows the logged-in user's own login and avatar;
//   - the season block shows the ACTIVE season's own name and its real
//     remaining days, computed by the backend from the season's end date;
//   - the three stats are the backend's own numbers (points earned today,
//     place in the rating, quests done today), never placeholders;
//   - the block opens the season quests screen, whose banner repeats the
//     same season and whose "Ежедневные квесты" list is built from
//     whatever quests the backend actually returns.
//
// Everything asserted here is cross-checked against GET /quests/overview
// in the same run, so the test can never pass on a hardcoded number.
//
// Run with:
//   flutter test integration_test/home_dashboard_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL with user testuser/123456
// and admin/123456, and an active season.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';
import 'package:guyo_app/screens/learned_words_screen.dart';
import 'package:guyo_app/screens/lessons_screen.dart';
import 'package:guyo_app/widgets/quest_ui.dart';
import 'package:guyo_app/widgets/user_avatar.dart';

Future<String> _userToken() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'testuser', 'password': '123456'}),
  );
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}

Future<Map<String, dynamic>> _overview(String token) async {
  final res = await http.get(
    Uri.parse('$apiBaseUrl/quests/overview').replace(queryParameters: {'dictionary_id': '1'}),
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

  testWidgets('Главная greets the real user and shows the real season with real numbers', (tester) async {
    final token = await _userToken();
    final data = await _overview(token);

    await _login(tester);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // --- Greeting ---
    expect(find.textContaining('Привет, testuser'), findsOneWidget);
    expect(find.byType(UserAvatar), findsWidgets, reason: 'the greeting uses the shared avatar widget');

    // --- Season block ---
    expect(find.text('Квесты сезона'), findsOneWidget);
    final season = data['season'] as Map<String, dynamic>?;
    expect(season, isNotNull, reason: 'this test needs an active season on the backend');

    final daysLeft = data['days_left'] as int?;
    final daysTotal = data['days_total'] as int?;
    expect(daysLeft, isNotNull, reason: 'this test needs a season with a scheduled end');
    expect(daysTotal, isNotNull, reason: 'a season with an end also has a length');
    expect(
      find.textContaining('${season!['name']}'),
      findsOneWidget,
      reason: "the block names the backend's OWN active season",
    );

    // --- The season's own stretch of time, in its own panel ---
    expect(
      find.byType(SeasonTimeline),
      findsOneWidget,
      reason: 'the season range is its own panel, not a bar floating on the banner gradient',
    );
    expect(
      find.text(daysLeftLabel(daysLeft!)),
      findsOneWidget,
      reason: "the countdown is the backend's own day count",
    );
    final start = DateTime.parse(season['starts_at'] as String).toLocal();
    final end = DateTime.parse(season['ends_at'] as String).toLocal();
    expect(find.text(shortDate(start)), findsOneWidget, reason: 'the range shows where the season began');
    expect(find.text(shortDate(end)), findsOneWidget, reason: 'and where it ends');

    // --- Stats: every one of them cross-checked against the API ---
    // Scoped to their own StatColumn, since a reward badge elsewhere on
    // the screen can legitimately carry the same number.
    expect(
      find.descendant(
        of: find.widgetWithText(StatColumn, 'очков сегодня'),
        matching: find.text('+${data['points_today']}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(StatColumn, 'место в рейтинге'),
        matching: find.text('#${data['rank_position']}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(StatColumn, 'заданий выполнено'),
        matching: find.text('${data['quests_done_today']}/${data['quests_total']}'),
      ),
      findsOneWidget,
    );

    // --- Квест дня: the existing "изучение новых слов" system quest ---
    expect(find.text('Квест дня'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RewardBadge),
        matching: find.text('+${data['points_per_learned_word']}'),
      ),
      findsWidgets,
      reason: 'its reward is the SAME points-per-learned-word setting, not a quest-specific one',
    );

    // --- Opening the season quests screen ---
    await tester.tap(find.text('Квесты сезона'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Квесты'), findsWidgets, reason: 'the season quests screen opened');
    expect(
      find.byType(SeasonTimeline),
      findsOneWidget,
      reason: 'the banner shows the season range once, and only the season range',
    );
    expect(find.text('Ежедневные квесты'), findsOneWidget);
    expect(
      find.text('${data['quests_done_today']} / ${data['quests_total']}'),
      findsWidgets,
      reason: 'the section counter is the backend\'s own done/total',
    );

    // Every quest the backend returned is listed, whatever their number.
    final quests = data['quests'] as List<dynamic>;
    for (final quest in quests) {
      expect(
        find.text(quest['name'] as String),
        findsOneWidget,
        reason: 'the daily quest list is built from the backend, not a fixed set',
      );
      expect(
        find.text('${quest['completed_today']} / ${quest['daily_target']}'),
        findsWidgets,
        reason: "each quest's progress is the backend's own count against its own target",
      );
    }
  });

  testWidgets('the lesson chain carries nothing but lessons', (tester) async {
    await _login(tester);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Словарь'), findsNothing, reason: 'the standalone dictionary entry was removed');

    await tester.tap(find.text('Уроки'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.text('Квесты'),
      findsNothing,
      reason: 'quests are a season-wide system and live on Главная, not inside Уроки',
    );
    expect(
      find.text('Мои слова'),
      findsNothing,
      reason: "the user's own vocabulary lives on Профиль, not above the lesson chain",
    );

    // ...and it is reachable there, opening the app's existing screen.
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Мои слова'), findsOneWidget, reason: 'the words card replaced the plain "Слова" counter');
    expect(find.text('Слова'), findsNothing);

    await tester.tap(find.text('Мои слова'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(
      find.byType(LearnedWordsScreen),
      findsOneWidget,
      reason: 'the SAME screen as before, not a new one',
    );

    // The lessons counter next to it is a way in too: it switches to the
    // existing Уроки tab rather than pushing a second copy of it. Scoped
    // to the profile's own body, since the bottom bar also says "Уроки".
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(
      find.descendant(of: find.byType(ListView), matching: find.text('Уроки')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(LessonsScreen), findsOneWidget, reason: 'the existing lesson chain, not a new screen');
  });
}
