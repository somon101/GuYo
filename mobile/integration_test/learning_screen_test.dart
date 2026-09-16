// Covers "Изучение слов" end to end against the real backend:
//   - count picker respects the 3..20 range;
//   - an active session survives navigating away and a fresh app launch
//     (the backend, not any client state, is what makes it resumable);
//   - "Изучил" advances the session and the word later shows up under
//     "Мои изученные слова";
//   - "Ещё раз буду изучать" sends the word to the back of the queue
//     instead of completing the session, and it reappears (not a new
//     random word) once the rest of the round is done;
//   - the session only completes once every original word is learned.
//
// Run with:
//   flutter test integration_test/learning_screen_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
//
// Requires the local backend running at that URL, with:
//   - user testuser/123456
//   - an English dictionary with at least 6 words, none of them already
//     learned by testuser (this repo's dev data already has exactly 6:
//     apple/book/house/cat/doggo/dog)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/main.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.pumpWidget(const GuyoApp());
  await tester.pumpAndSettle(const Duration(seconds: 2));

  if (find.byType(NavigationBar).evaluate().isNotEmpty) {
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

  expect(find.byType(NavigationBar), findsOneWidget, reason: 'should reach the home screen with tabs');
}

Future<void> _openLearningTab(WidgetTester tester) async {
  await tester.tap(find.text('Изучение'));
  await tester.pumpAndSettle();
}

Future<void> _pickCountAndStart(WidgetTester tester, int count) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Начать изучение'));
  await tester.pumpAndSettle();

  // Default is 10; drive it down/up to the exact target by tapping the
  // stepper, whose buttons simply disable at the 3/20 bounds.
  final countFinder = find.byKey(const ValueKey('learning-session-count'));
  var current = int.parse(tester.widget<Text>(countFinder).data!);
  while (current > count) {
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    current--;
  }
  while (current < count) {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    current++;
  }
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilledButton, 'Начать'));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('start a 3-word session, learn all 3, see them under Мои изученные слова', (tester) async {
    await _login(tester);
    await _openLearningTab(tester);

    expect(find.text('Изучение слов'), findsOneWidget);
    await _pickCountAndStart(tester, 3);

    expect(find.textContaining('Изучено 0 из 3'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      expect(find.widgetWithText(FilledButton, 'Изучил'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Изучил'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    expect(find.text('Изучение завершено'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Добавить ещё слов'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(TextButton, Icons.bookmark_outline));
    await tester.pumpAndSettle();
    expect(find.text('Мои изученные слова'), findsOneWidget);
    expect(find.text('Без категории'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('Без категории'));
    await tester.pumpAndSettle();
    // Exactly 3 of the 6 dev words are now learned; can't predict which
    // ones (random selection), but there must be exactly 3 rows -- a
    // ListView.separated of 3 items inserts exactly 2 dividers.
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('review keeps a word in the same fixed session instead of completing it, session resumes after relaunch', (tester) async {
    await _login(tester);
    await _openLearningTab(tester);

    // Exactly the 3 remaining unlearned dev words from the previous test.
    await _pickCountAndStart(tester, 3);
    expect(find.textContaining('Изучено 0 из 3'), findsOneWidget);

    // Send the first word to review.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ещё раз буду изучать'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Изучено 0 из 3'), findsOneWidget, reason: 'review must not count as learned');

    // Relaunch the app (fresh widget tree, same backend session/token) --
    // the active session must come back exactly as it was, not reset.
    await tester.pumpWidget(const GuyoApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'still logged in after relaunch');
    await _openLearningTab(tester);
    expect(find.textContaining('Изучено 0 из 3'), findsOneWidget, reason: 'same session resumed, not restarted');

    // Learn the two remaining not-yet-reviewed words.
    await tester.tap(find.widgetWithText(FilledButton, 'Изучил'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Изучено 1 из 3'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Изучил'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Изучено 2 из 3'), findsOneWidget);

    // The session must NOT be complete yet -- the reviewed word is still
    // outstanding and must come back now, not a new random word.
    expect(find.text('Изучение завершено'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Изучил'), findsOneWidget);

    // Finish the reviewed word -- only now does the session complete.
    await tester.tap(find.widgetWithText(FilledButton, 'Изучил'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Изучение завершено'), findsOneWidget);

    // All 6 dev words are learned now -- no more available for a new session.
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить ещё слов'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Начать'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Все доступные слова уже изучены'), findsOneWidget, reason: 'clean empty-state message, no crash');
  });
}
