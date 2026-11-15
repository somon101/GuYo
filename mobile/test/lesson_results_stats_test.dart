// The end-of-lesson statistics block, and the results screen without it.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:guyo_app/models/lesson.dart';
import 'package:guyo_app/screens/lesson_results_screen.dart';

final _lesson = Lesson.fromJson({
  'id': 7,
  'dictionary_id': 1,
  'number': 2,
  'is_completed': false,
  'exercise_keys': ['true_or_false', 'build_word'],
  'words': [
    {'word_id': 1, 'word': 'cat', 'translation': 'кот', 'score': 100, 'is_learned': true},
    {'word_id': 2, 'word': 'dog', 'translation': 'собака', 'score': 40, 'is_learned': false},
  ],
});

final _stats = LessonPassStats.fromJson({
  'started_at': '2026-09-28T10:00:00Z',
  'duration_seconds': 95,
  'total_answers': 8,
  'correct_answers': 6,
  'wrong_answers': 2,
  'accuracy': 75,
  'exercises': [
    {'exercise_key': 'true_or_false', 'correct': 4, 'total': 4},
    {'exercise_key': 'build_word', 'correct': 2, 'total': 4},
  ],
  'words': [
    {'word_id': 1, 'word': 'cat', 'score_before': 80, 'score_after': 100, 'gained': 20, 'became_learned': true},
    {'word_id': 2, 'word': 'dog', 'score_before': 30, 'score_after': 40, 'gained': 10, 'became_learned': false},
  ],
  'score_gained': 30,
  'newly_learned': 1,
});

final _client = MockClient((_) async => http.Response('[]', 200));

Future<void> _open(WidgetTester tester, LessonPassStats? stats) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: LessonResultsScreen(lesson: _lesson, stats: stats)));
  await tester.pumpAndSettle();
}

final _passedLesson = Lesson.fromJson({
  'id': 7,
  'dictionary_id': 1,
  'number': 2,
  'is_completed': true,
  'exercise_keys': ['true_or_false', 'build_word'],
  'words': [
    {'word_id': 1, 'word': 'cat', 'translation': 'кот', 'score': 100, 'is_learned': true},
    {'word_id': 2, 'word': 'dog', 'translation': 'собака', 'score': 100, 'is_learned': true},
  ],
});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('words still short: no «failure», the words left, a locked next lesson and the repeat button', (tester) async {
    await http.runWithClient(() async {
      await _open(tester, _stats);
      expect(find.text('Осталось слов: 1'), findsOneWidget);
      expect(find.text('Слова: 1 из 2'), findsOneWidget);
      expect(find.text('75% точность'), findsOneWidget);
      expect(find.text('1:35'), findsOneWidget);
      expect(find.byKey(const ValueKey('road-current-part')), findsOneWidget);
      expect(find.byKey(const ValueKey('road-next-locked')), findsOneWidget);
      expect(find.byKey(const ValueKey('lesson-results-repeat')), findsOneWidget);
      expect(find.byKey(const ValueKey('lesson-results-next')), findsNothing);
      // No list of words on this screen any more.
      expect(find.text('cat'), findsNothing);
    }, () => _client);
  });

  testWidgets('lesson passed: its node is lit, the next one is open and the main button starts it', (tester) async {
    await http.runWithClient(() async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      bool? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => popped = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => LessonResultsScreen(lesson: _passedLesson, stats: _stats))),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Урок 2 пройден'), findsOneWidget);
      expect(find.byKey(const ValueKey('road-current-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('road-next-open')), findsOneWidget);
      expect(find.text('Урок 3 открыт'), findsOneWidget);
      expect(find.byKey(const ValueKey('lesson-results-repeat')), findsNothing);
      expect(takeNextLessonRequest(), isFalse);
      await tester.tap(find.byKey(const ValueKey('lesson-results-next')));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(popped, isFalse);
      expect(takeNextLessonRequest(), isTrue); // asked once...
      expect(takeNextLessonRequest(), isFalse); // ...and only once
    }, () => _client);
  });

  testWidgets('without statistics the result still shows, just without accuracy and time', (tester) async {
    await http.runWithClient(() async {
      await _open(tester, null);
      expect(find.text('Осталось слов: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('chip-accuracy')), findsNothing);
      expect(find.byKey(const ValueKey('lesson-results-repeat')), findsOneWidget);
    }, () => _client);
  });
}
