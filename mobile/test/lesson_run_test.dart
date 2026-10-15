// A lesson is one continuous run on one screen: every available exercise back to
// back, an empty one skipped, then the results once. Nothing in between is ever
// allowed to sit and wait: the pass opens on the server BEHIND the first
// exercise, the next exercise follows in the same frame, and the results open on
// the numbers the phone worked out for itself -- the server's own arrive into the
// screen that is already up (see LessonResultsRefresh).
//
// These drive LessonRunScreen through a fake LessonRunDriver -- no backend, no
// real exercise screens -- so they pin the sequencing itself.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/models/exercise.dart';
import 'package:guyo_app/models/lesson.dart';
import 'package:guyo_app/models/lesson_rounds.dart';
import 'package:guyo_app/models/mini_phrase.dart';
import 'package:guyo_app/screens/lesson_exercise_flow.dart';
import 'package:guyo_app/screens/lesson_results_screen.dart';
import 'package:guyo_app/screens/lesson_run_screen.dart';
import 'package:guyo_app/services/session_cache.dart';

class _FakeExercise extends StatefulWidget {
  final String name;
  const _FakeExercise(this.name);

  @override
  State<_FakeExercise> createState() => _FakeExerciseState();
}

class _FakeExerciseState extends State<_FakeExercise> with LessonExerciseFlow {
  @override
  Widget build(BuildContext context) {
    // The real exercises' own shape: their state first, and the handoff once
    // they have declared themselves finished (see LessonExerciseHandoff).
    if (isFinishing) return const LessonExerciseHandoff();
    return Column(
      children: [
        Text('EX ${widget.name}'),
        TextButton(
          onPressed: () {
            setState(() {});
            finishExercise();
          },
          child: const Text('finish'),
        ),
      ],
    );
  }
}

/// The lesson as the Уроки list hands it over: one word, still short of its
/// level -- what an offline pass is scored against.
Lesson _lesson({int score = 0}) => Lesson.fromJson({
      'id': 7,
      'dictionary_id': 1,
      'number': 3,
      'is_completed': false,
      'exercise_keys': ['a', 'b', 'c'],
      'words': [
        {'word_id': 1, 'word': 'cat', 'translation': 'кот', 'score': score, 'is_learned': false},
      ],
    });

/// The rounds as the server sends them: one real round per key that has
/// something to play, so a pass is skipped exactly the way the real runner skips
/// it (see LessonRounds.hasWork).
LessonRounds _roundsFor(Map<String, bool> available) => LessonRounds({
      for (final entry in available.entries)
        if (entry.value)
          entry.key: TrueOrFalseRound(
            dictionaryId: 1,
            availableCount: 1,
            items: [TrueOrFalseItem(wordId: 1, original: 'cat', shownTranslation: 'кот', isCorrect: true)],
          ),
    });

class _FakeDriver implements LessonRunDriver {
  final Map<String, bool> pending;
  int passes = 0;
  final List<String> built = [];

  _FakeDriver(this.pending);

  /// Held until the test lets it go: the pass opening, and everything the server
  /// does once the pass is over. Null means the server answers at once.
  Completer<void>? passGate;
  Completer<void>? serverGate;

  @override
  Future<void> startPass(int lessonId) async {
    final gate = passGate;
    if (gate != null) await gate.future;
    passes++;
  }

  int finished = 0;

  @override
  Future<void> finishPass(int lessonId) async {
    final gate = serverGate;
    if (gate != null) await gate.future;
    finished++;
  }

  int prepared = 0;

  @override
  Future<LessonRounds> prepareRounds(int lessonId, List<String> exerciseKeys) async {
    prepared++;
    return _roundsFor(pending);
  }

  @override
  Widget buildExercise(int lessonId, int lessonNumber, String key, LessonRounds rounds) {
    built.add(key);
    return _FakeExercise(key);
  }

  /// The server's own copy of the lesson: the same lesson, with the word moved
  /// to 60 by the pass the phone has just handed over.
  @override
  Future<Lesson> fetchLesson(int lessonId) async => _lesson(score: 60);

  @override
  Future<LessonPassStats?> fetchPassStats(int lessonId) async => null;

  /// What the results were opened with, and the server's own version of them
  /// when it arrives.
  Lesson? shownLesson;
  LessonPassStats? shownStats;
  Future<LessonResultsRefresh?>? shownRefresh;

  @override
  Future<bool?> showResults(
    BuildContext context,
    Lesson lesson,
    LessonPassStats? stats, {
    Future<LessonResultsRefresh?>? refresh,
  }) {
    shownLesson = lesson;
    shownStats = stats;
    shownRefresh = refresh;
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

/// A lesson this device has ALREADY prepared (the Уроки list prepares the next
/// one in the background): its rounds are on the device, so it opens straight
/// into the first exercise -- no preparation screen, no skeleton.
void _prepareOnDevice(Map<String, bool> available) {
  SessionCache.clear();
  SessionCache.put(lessonRoundsCacheKey(7), _roundsFor(available));
}

Future<void> _open(WidgetTester tester, _FakeDriver driver, {Lesson? lesson}) async {
  _prepareOnDevice(driver.pending);
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
                      lesson: lesson ?? _lesson(),
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

/// Lets the device's own caches settle before the test ends.
///
/// A finished pass is written to the device (LessonScoreOverlay, the lesson's
/// scored copy) and that write is delayed by a moment (DiskCache), so a test that
/// has been through the results still has one timer in the air.
Future<void> _settleDevice(WidgetTester tester) => tester.pump(const Duration(seconds: 2));

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('exercises follow each other on one screen, an empty one is skipped', (tester) async {
    final driver = _FakeDriver({'a': true, 'b': false, 'c': true});
    await _open(tester, driver);

    expect(find.text('EX a'), findsOneWidget);
    expect(find.text('LESSON LIST'), findsNothing);

    await _finish(tester);
    expect(find.text('EX c'), findsOneWidget, reason: 'b has nothing to test and is skipped');
    expect(find.text('LESSON LIST'), findsNothing, reason: 'never back to a list between exercises');
    expect(driver.built, ['a', 'c']);

    await _finish(tester);
    expect(find.text('RESULTS'), findsOneWidget);
    expect(driver.prepared, 0, reason: 'every round was prepared before the lesson was opened');
    await _settleDevice(tester);
  });

  testWidgets('the first exercise is playable while the pass is still opening', (tester) async {
    final driver = _FakeDriver({'a': true, 'b': true, 'c': false})..passGate = Completer<void>();
    await _open(tester, driver);

    expect(driver.passes, 0, reason: 'the server has not taken the pass opening yet');
    expect(find.text('EX a'), findsOneWidget, reason: 'and the lesson does not wait for it');
    expect(find.byType(LessonExerciseHandoff), findsNothing, reason: 'no logo between the tap and the first card');

    driver.passGate!.complete();
    await tester.pump();
    expect(driver.passes, 1, reason: 'the pass opens behind the exercise');
    expect(find.text('EX a'), findsOneWidget, reason: 'which is still the same exercise');
  });

  testWidgets('the next exercise is there in the same frame, with no handoff in between', (tester) async {
    final driver = _FakeDriver({'a': true, 'b': false, 'c': true});
    await _open(tester, driver);

    await tester.tap(find.text('finish'));
    await tester.pump();
    expect(find.text('EX c'), findsOneWidget, reason: 'the next exercise appears at once');
    expect(find.byType(LessonExerciseHandoff), findsNothing, reason: 'the handoff never gets a frame of its own');
  });

  testWidgets('the results open on this device\'s own score, without waiting for the server', (tester) async {
    final driver = _FakeDriver({'a': true, 'b': false, 'c': true})..serverGate = Completer<void>();
    await _open(tester, driver);

    await _finish(tester);
    await _finish(tester);

    expect(driver.finished, 0, reason: 'the server has not counted the pass yet');
    expect(find.text('RESULTS'), findsOneWidget, reason: 'and the results are already up');
    expect(driver.shownStats, isNotNull, reason: 'with the numbers the phone worked out for itself');
    expect(driver.shownLesson!.words.first.score, 0, reason: 'the device\'s own copy of the lesson, not the server\'s');

    driver.serverGate!.complete();
    await tester.pumpAndSettle();
    final refresh = await driver.shownRefresh;
    expect(refresh, isNotNull, reason: 'the server\'s own version arrives into the screen that is already open');
    expect(refresh!.lesson.words.first.score, 60, reason: 'and it is the server\'s lesson');
    await _settleDevice(tester);
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
    expect(driver.prepared, 1, reason: 'a new pass prepares its own rounds');

    await _finish(tester);
    await _finish(tester);
    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();
    expect(find.text('LESSON LIST'), findsOneWidget);
    expect(find.byType(LessonRunScreen), findsNothing);
    await _settleDevice(tester);
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

  testWidgets('mini-phrases come after the word exercises, before the results', (tester) async {
    final driver = _FakeDriver({'a': true, 'b': false, 'c': false});
    _prepareOnDevice(driver.pending);
    const phrase = MiniPhrase(
      id: 5,
      dictionaryId: 1,
      text: 'Я иду',
      translation: 'Ман меравам',
      parts: [
        MiniPhrasePart(position: 1, text: 'Я', wordId: 1, role: 'pronoun'),
        MiniPhrasePart(position: 2, text: 'иду', wordId: 2, role: 'verb'),
      ],
      explanation: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LessonRunScreen(
          lessonId: 7,
          lessonNumber: 3,
          exerciseKeys: const ['a', 'b', 'c'],
          lesson: _lesson(),
          miniPhrases: const [phrase],
          driver: driver,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EX a'), findsOneWidget);
    await _finish(tester);

    expect(find.byKey(const ValueKey('mini-phrase-next')), findsOneWidget, reason: 'the explanation comes first');
    expect(driver.finished, 0, reason: 'the pass is finished only after the mini-phrases');
    await tester.tap(find.byKey(const ValueKey('mini-phrase-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Я'));
    await tester.pump();
    await tester.tap(find.text('иду'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mini-phrase-check')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('RESULTS'), findsOneWidget);
    expect(driver.finished, 1);
    await _settleDevice(tester);
  });
}
