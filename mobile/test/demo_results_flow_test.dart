// The demo build's end of a lesson: results always; streak and the chest of the day only after the
// first passed lesson of a day; «Добить слова» / «Позже» when words are still short.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:guyo_app/demo/demo_results_flow.dart';
import 'package:guyo_app/demo/demo_state.dart';
import 'package:guyo_app/models/lesson.dart';

Lesson _lesson({required bool passed}) => Lesson.fromJson({
      'id': 7,
      'dictionary_id': 1,
      'number': 3,
      'is_completed': passed,
      'exercise_keys': ['true_or_false'],
      'words': [
        {'word_id': 1, 'word': 'cat', 'translation': 'кот', 'score': 100, 'is_learned': true},
        {'word_id': 2, 'word': 'dog', 'translation': 'собака', 'score': passed ? 100 : 40, 'is_learned': passed},
      ],
    });

final _stats = LessonPassStats.fromJson({
  'started_at': '2026-09-28T10:00:00Z',
  'duration_seconds': 120,
  'total_answers': 10,
  'correct_answers': 9,
  'wrong_answers': 1,
  'accuracy': 90,
  'exercises': <Object>[],
  'words': <Object>[],
  'score_gained': 30,
  'newly_learned': 1,
});

final _client = MockClient((_) async => http.Response('[]', 200));

/// Opens the screen from a button and records what it pops with.
Future<List<bool?>> _open(WidgetTester tester, {required bool passed}) async {
  final popped = <bool?>[];
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => popped.add(await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => demoResultsFlow(_lesson(passed: passed), _stats)),
        )),
        child: const Text('go'),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return popped;
}

/// Lets the opening animation finish (the buttons are there after about two seconds).
Future<void> _settle(WidgetTester tester, [int ms = 6000]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _freshDay() {
  final ds = DemoState.instance;
  ds
    ..chestDate = ''
    ..streakDate = ''
    ..streak = 13
    ..passLevel = 7
    ..passXp = 370
    ..rankPos = 7
    ..diamonds = 240
    ..wordsToday = 12
    ..goal = 20;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    DemoSfx.enabled = false;
    _freshDay();
  });

  testWidgets('the first passed lesson of the day: results, streak, then the chest of the day, opened right there', (tester) async {
    await http.runWithClient(() async {
      final popped = await _open(tester, passed: true);
      await _settle(tester);

      // The results: the points, the day's goal, the pass and the rating.
      expect(find.text('УРОК 3 ПРОЙДЕН'), findsOneWidget);
      expect(find.text('+48'), findsOneWidget); // 30 for the lesson, 10 for accuracy, 8 for speed
      expect(find.text('Цель дня'), findsOneWidget);
      expect(find.text('Рейтинг'), findsOneWidget);
      expect(find.text('#6'), findsOneWidget); // up one place
      expect(find.text('Ур. 8'), findsOneWidget); // 370 + 48 = a new level
      expect(find.text('18 / 400'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('score-continue')));
      await _settle(tester, 3000);

      // The streak: one more day, today ticked.
      expect(find.text('14'), findsOneWidget);
      expect(find.text('дней подряд'), findsOneWidget);
      expect(DemoState.instance.streak, 14);

      await tester.tap(find.byKey(const ValueKey('streak-continue')));
      await _settle(tester, 1500);

      // The chest of the day: tap it, one prize, then back to the lessons.
      expect(find.text('СУНДУК ДНЯ'), findsOneWidget);
      expect(find.text('Он ваш'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chest-open')));
      await _settle(tester, 1500);
      expect(find.text('Забрано'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-chest-prize')), findsOneWidget);
      expect(DemoState.instance.diamonds, greaterThan(240));
      expect(DemoState.instance.chestDate, DemoState.today());

      await tester.tap(find.byKey(const ValueKey('chest-done')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(popped, [false]);
    }, () => _client);
  });

  testWidgets('the second lesson of the same day shows only the results', (tester) async {
    await http.runWithClient(() async {
      DemoState.instance
        ..chestDate = DemoState.today() // the chest of the day is already taken
        ..streakDate = DemoState.today();
      final popped = await _open(tester, passed: true);
      await _settle(tester);
      expect(find.text('УРОК 3 ПРОЙДЕН'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('score-continue')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('дней подряд'), findsNothing);
      expect(find.text('СУНДУК ДНЯ'), findsNothing);
      expect(popped, [false]);
      expect(DemoState.instance.streak, 13); // not counted twice
    }, () => _client);
  });

  testWidgets('the next day the whole path shows again', (tester) async {
    await http.runWithClient(() async {
      DemoState.instance
        ..chestDate = '2000-01-01'
        ..streakDate = '2000-01-01';
      await _open(tester, passed: true);
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('score-continue')));
      await _settle(tester, 3000);
      expect(find.text('дней подряд'), findsOneWidget);
    }, () => _client);
  });

  testWidgets('words still short: the same results, «Добить слова» repeats, nothing moves on', (tester) async {
    await http.runWithClient(() async {
      final popped = await _open(tester, passed: false);
      await _settle(tester);

      expect(find.text('УРОК 3: ОСТАЛОСЬ СЛОВ: 1'), findsOneWidget);
      expect(find.text('Добить слова: 1'.toUpperCase()), findsOneWidget);
      expect(find.text('ПОЗЖЕ'), findsNothing); // the quiet button is not shouted
      expect(find.text('Позже'), findsOneWidget);
      expect(find.text('#7'), findsOneWidget); // the place does not move
      expect(DemoState.instance.passXp, 370);
      expect(DemoState.instance.rankPos, 7);

      await tester.tap(find.byKey(const ValueKey('score-repeat')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(popped, [true]);
    }, () => _client);
  });

  testWidgets('«Позже» leaves without a repeat', (tester) async {
    await http.runWithClient(() async {
      final popped = await _open(tester, passed: false);
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('score-later')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(popped, [false]);
    }, () => _client);
  });
}
