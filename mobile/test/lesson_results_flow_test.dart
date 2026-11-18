// The end of a lesson in the real app: the screen works from a ResultsSource, shows only the steps
// that apply (the streak only when this lesson counted today, the chest only when it can be taken),
// leaves out what the server did not give, and shows whatever the chest of the day really gave.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/models/lesson.dart';
import 'package:guyo_app/screens/lesson_results_flow.dart';

class _Fake extends ResultsSource {
  final bool withStreak;
  final bool chest;
  final bool pass;
  _Fake({this.withStreak = false, this.chest = true, this.pass = false});

  @override
  Future<ResultsOutcome> outcome(Lesson lesson, LessonPassStats? stats) async => ResultsOutcome(
        number: 3,
        left: 0,
        passed: true,
        showStreak: withStreak,
        showChest: chest,
        total: 21,
        goalFrom: 4,
        goalTo: 6,
        goalOf: 10,
        hasPass: pass,
        levelFrom: 2,
        levelTo: 2,
        xpFrom: 10,
        xpTo: 31,
        sizeFrom: 100,
        sizeTo: 100,
        rankFrom: 5,
        rankTo: 4,
        rival: 'Aziz',
      );

  @override
  StreakView streak() => const StreakView(before: 4, grew: true);

  @override
  Future<DailyPrize?> openDailyChest() async => DailyPrize('freeze', 2);
}

Lesson _lesson() => Lesson.fromJson({
      'id': 7,
      'dictionary_id': 1,
      'number': 3,
      'is_completed': true,
      'exercise_keys': ['true_or_false'],
      'words': [
        {'word_id': 1, 'word': 'cat', 'translation': 'кот', 'score': 100, 'is_learned': true},
      ],
    });

Future<void> _settle(WidgetTester tester, [int ms = 6000]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(WidgetTester tester, ResultsSource source) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonResultsFlow(lesson: _lesson(), source: source))),
        child: const Text('go'),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => ResultsSfx.enabled = false);

  testWidgets('no streak step when this lesson did not count today; the chest shows what it gave', (tester) async {
    await _open(tester, _Fake());
    await _settle(tester);
    expect(find.text('+21'), findsOneWidget);
    expect(find.text('Пропуск'), findsNothing); // no season: the block is left out
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('Вы обошли Aziz'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('score-continue')));
    await _settle(tester, 1500);
    expect(find.text('дней подряд'), findsNothing);
    expect(find.text('СУНДУК ДНЯ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chest-open')));
    await _settle(tester, 1500);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('заморозок серии'), findsOneWidget);
  });

  testWidgets('streak and chest both: streak first; nothing to follow: the results alone', (tester) async {
    await _open(tester, _Fake(withStreak: true, pass: true));
    await _settle(tester);
    expect(find.text('Пропуск'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('score-continue')));
    await _settle(tester, 3000);
    expect(find.text('5'), findsOneWidget); // 4 days, then the lesson counted
    expect(find.text('дней подряд'), findsOneWidget);
  });

  testWidgets('without streak and chest the results close the flow', (tester) async {
    await _open(tester, _Fake(chest: false));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('score-continue')));
    await _settle(tester, 3500); // leaving waits a moment for new achievements
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(LessonResultsFlow), findsNothing);
  });
}
