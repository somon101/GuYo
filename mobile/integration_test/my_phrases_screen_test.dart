// Covers "Мои фразы" end to end against the real backend/UI wiring:
//   - reachable from "Мои слова" (which is itself reached from "Уроки");
//   - a phrase whose every word is already learned by the user shows up,
//     with its translation.
//
// Run with:
//   flutter test integration_test/my_phrases_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456
//   - the English dictionary (id 1 in this repo's dev data) containing a
//     phrase "apple house" -> "hona-i-seb", and testuser already having
//     learned both "apple" and "house" (WordProgress.score >= threshold)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

  testWidgets('a phrase with every word learned appears under Мои фразы, with its translation', (tester) async {
    await _login(tester);

    await tester.tap(find.text('Уроки'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Мои слова'));
    await tester.pumpAndSettle();
    expect(find.text('Мои изученные слова'), findsOneWidget);

    await tester.tap(find.text('Мои фразы'));
    await tester.pumpAndSettle();

    expect(find.text('apple house'), findsOneWidget, reason: 'both "apple" and "house" are already learned');
    expect(find.text('hona-i-seb'), findsOneWidget);
  });
}
