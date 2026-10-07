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

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('shows accuracy, right/wrong/time, per exercise and per word gain', (tester) async {
    await http.runWithClient(() async {
      await _open(tester, _stats);
      expect(find.byKey(const ValueKey('lesson-pass-stats')), findsOneWidget);
      expect(find.text('75'), findsOneWidget);
      expect(find.textContaining('6 / 8', findRichText: true), findsOneWidget);
      expect(find.textContaining('2 / 8', findRichText: true), findsOneWidget);
      expect(find.text('1 мин 35 с', findRichText: true), findsOneWidget);
      expect(find.text('Правда или ложь'), findsOneWidget);
      expect(find.textContaining('2 / 4', findRichText: true), findsOneWidget);
      expect(find.text('+30 очков'), findsOneWidget);
      expect(find.text('Выучено новых'), findsOneWidget);
      expect(find.textContaining('1 / 2', findRichText: true), findsOneWidget);
      expect(find.text('+20'), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);
      expect(find.text('Повторить урок'), findsOneWidget);
    }, () => _client);
  });

  testWidgets('without statistics the results still show', (tester) async {
    await http.runWithClient(() async {
      await _open(tester, null);
      expect(find.byKey(const ValueKey('lesson-pass-stats')), findsNothing);
      expect(find.text('cat'), findsOneWidget);
      expect(find.text('Повторить урок'), findsOneWidget);
    }, () => _client);
  });
}
