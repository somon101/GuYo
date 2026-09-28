// The per-answer timers: "Правда или ложь" gives 15 seconds and running
// out counts as a wrong answer; "Собери слово" gives 25.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/models/exercise.dart';
import 'package:guyo_app/widgets/exercises/build_word_exercise.dart';
import 'package:guyo_app/widgets/exercises/exercise_timer.dart';
import 'package:guyo_app/widgets/exercises/true_or_false_exercise.dart';

TrueOrFalseItem _tf(int id) => TrueOrFalseItem.fromJson({
      'word_id': id,
      'original': 'word$id',
      'shown_translation': 'перевод$id',
      'is_correct': true,
    });

int _badgeSeconds(WidgetTester tester) =>
    tester.widget<ExerciseTimerBadge>(find.byType(ExerciseTimerBadge)).secondsLeft;

void main() {
  testWidgets('Правда или ложь: 15 seconds, timeout is a wrong answer, restarts per item', (tester) async {
    final answers = <bool>[];
    var item = _tf(1);
    late StateSetter setOuter;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return SingleChildScrollView(child: TrueOrFalseExercise(item: item, onAnswer: answers.add));
        }),
      ),
    ));

    expect(_badgeSeconds(tester), 15);
    await tester.pump(const Duration(seconds: 5));
    expect(_badgeSeconds(tester), 10);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 2)); // reveal flash
    expect(answers, [false], reason: 'running out of time counts as wrong');

    setOuter(() => item = _tf(2));
    await tester.pump();
    expect(_badgeSeconds(tester), 15, reason: 'a new card gets the full time again');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Собери слово starts at 25 seconds', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BuildWordExercise(
            item: BuildWordItem.fromJson({
              'word_id': 1,
              'translation': 'кот',
              'correct_word': 'cat',
              'letters': ['t', 'a', 'c'],
            }),
            caseSensitive: false,
            onAnswer: (_) {},
          ),
        ),
      ),
    ));
    expect(ExerciseTimeLimits.buildWordSeconds, 25);
    expect(_badgeSeconds(tester), 25);
    await tester.pump(const Duration(seconds: 1));
    expect(_badgeSeconds(tester), 24);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Собери слово: a used letter leaves its place, the others stay put', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BuildWordExercise(
            item: BuildWordItem.fromJson({
              'word_id': 1,
              'translation': 'кот',
              'correct_word': 'cat',
              'letters': ['t', 'a', 'c'],
            }),
            caseSensitive: false,
            onAnswer: (_) {},
          ),
        ),
      ),
    ));
    final pool = find.byKey(const ValueKey('build-word-pool'));
    final before = tester.getCenter(find.descendant(of: pool, matching: find.text('c')));
    await tester.tap(find.descendant(of: pool, matching: find.text('t')));
    await tester.pump();
    expect(find.descendant(of: pool, matching: find.text('t')), findsNothing);
    expect(tester.getCenter(find.descendant(of: pool, matching: find.text('c'))), before);
    await tester.pumpWidget(const SizedBox());
  });
}
