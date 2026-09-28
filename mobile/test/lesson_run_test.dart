// A lesson is one continuous run on one screen: every available exercise
// back to back, an empty one skipped, then the results once. These drive
// LessonRunScreen through a fake LessonRunDriver -- no backend, no real
// exercise screens -- so they pin the sequencing itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/models/lesson.dart';
import 'package:guyo_app/screens/lesson_exercise_flow.dart';
import 'package:guyo_app/screens/lesson_run_screen.dart';

class _FakeExercise extends StatefulWidget {
  final String name;
  const _FakeExercise(this.name);

  @override
  State<_FakeExercise> createState() => _FakeExerciseState();
}

class _FakeExerciseState extends State<_FakeExercise> with LessonExerciseFlow {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('EX ${widget.name}'),
        TextButton(onPressed: finishExercise, child: const Text('finish')),
      ],
    );
  }
}

class _FakeDriver implements LessonRunDriver {
  final Map<String, bool> pending;
  int passes = 0;
  final List<String> built = [];

  _FakeDriver(this.pending);

  @override
  Future<void> startPass(int lessonId) async => passes++;

  @override
  Future<bool> hasPendingWork(int lessonId, String key) async => pending[key] ?? false;

  @override
  Widget buildExercise(int lessonId, int lessonNumber, String key) {
    built.add(key);
    return _FakeExercise(key);
  }

  @override
  Future<Lesson> fetchLesson(int lessonId) async => Lesson.fromJson({
        'id': lessonId,
        'dictionary_id': 1,
        'number': 3,
        'is_completed': false,
        'exercise_keys': ['a', 'b', 'c'],
        'words': <dynamic>[],
      });

  @override
  Future<bool?> showResults(BuildContext context, Lesson lesson) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (resultsContext) => Scaffold(
          body: Column(
            children: [
              const Text('RESULTS'),
              TextButton(onPressed: () => Navigator.of(resultsContext).pop(true), child: const Text('repeat')),
              TextButton(onPressed: () => Navigator.of(resultsContext).pop(false), child: const Text('done')),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _open(WidgetTester tester, _FakeDriver driver) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              const Text('LESSON LIST'),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LessonRunScreen(
                      lessonId: 7,
                      lessonNumber: 3,
                      exerciseKeys: const ['a', 'b', 'c'],
                      driver: driver,
                    ),
                  ),
                ),
                child: const Text('start'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('start'));
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.tap(find.text('finish'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('exercises follow each other on one screen, an empty one is skipped', (tester) async {
    final driver = _FakeDriver({'a': true, 'b': false, 'c': true});
    await _open(tester, driver);

    expect(driver.passes, 1, reason: 'the pass is started before the first exercise');
    expect(find.text('EX a'), findsOneWidget);
    expect(find.text('LESSON LIST'), findsNothing);

    await _finish(tester);
    expect(find.text('EX c'), findsOneWidget, reason: 'b has nothing to test and is skipped');
    expect(find.text('LESSON LIST'), findsNothing, reason: 'never back to a list between exercises');
    expect(driver.built, ['a', 'c']);

    await _finish(tester);
    expect(find.text('RESULTS'), findsOneWidget);
  });

  testWidgets('"Повторить урок" runs a new pass right away; "Готово" closes the lesson', (tester) async {
    final driver = _FakeDriver({'a': true, 'b': true, 'c': false});
    await _open(tester, driver);

    await _finish(tester);
    await _finish(tester);
    expect(find.text('RESULTS'), findsOneWidget);

    await tester.tap(find.text('repeat'));
    await tester.pumpAndSettle();
    expect(driver.passes, 2);
    expect(find.text('EX a'), findsOneWidget);

    await _finish(tester);
    await _finish(tester);
    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();
    expect(find.text('LESSON LIST'), findsOneWidget);
    expect(find.byType(LessonRunScreen), findsNothing);
  });

  testWidgets('finishing twice never skips the next exercise', (tester) async {
    final driver = _FakeDriver({'a': true, 'b': true, 'c': true});
    await _open(tester, driver);

    final state = tester.state<_FakeExerciseState>(find.byType(_FakeExercise));
    state.finishExercise();
    state.finishExercise();
    await tester.pumpAndSettle();
    expect(find.text('EX b'), findsOneWidget);
  });

  testWidgets('back asks before leaving the lesson', (tester) async {
    final driver = _FakeDriver({'a': true, 'b': true, 'c': true});
    await _open(tester, driver);

    final dynamic navigator = tester.state(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Прервать урок?'), findsOneWidget);

    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('EX a'), findsOneWidget);

    await navigator.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.text('LESSON LIST'), findsOneWidget);
  });
}
