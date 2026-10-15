// The results screen opens on the numbers the phone worked out for itself and
// swaps in the server's own the moment they arrive -- it never waits for the
// network to show a result the device already knows. The server's version is
// handed over by LessonRunScreen as a future (see LessonResultsRefresh).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:guyo_app/models/lesson.dart';
import 'package:guyo_app/screens/lesson_results_screen.dart';

final _client = MockClient((_) async => http.Response('[]', 200));

Lesson _lesson(int score) => Lesson.fromJson({
      'id': 7,
      'dictionary_id': 1,
      'number': 2,
      'is_completed': false,
      'exercise_keys': ['true_or_false'],
      'words': [
        {'word_id': 1, 'word': 'cat', 'translation': 'кот', 'score': score, 'is_learned': score >= 80},
      ],
    });

LessonPassStats _stats({required int accuracy, required int gained}) => LessonPassStats.fromJson({
      'started_at': '2026-09-28T10:00:00Z',
      'duration_seconds': 40,
      'total_answers': 8,
      'correct_answers': (accuracy * 8 / 100).round(),
      'wrong_answers': 8 - (accuracy * 8 / 100).round(),
      'accuracy': accuracy,
      'exercises': [
        {'exercise_key': 'true_or_false', 'correct': (accuracy * 8 / 100).round(), 'total': 8},
      ],
      'words': [
        {
          'word_id': 1,
          'word': 'cat',
          'score_before': 0,
          'score_after': _afterScore(gained),
          'gained': gained,
          'became_learned': false,
        },
      ],
      'score_gained': gained,
      'newly_learned': 0,
    });

/// The score a pass with [gained] points leaves the single word on.
int _afterScore(int gained) => gained < 0 ? 0 : (gained > 100 ? 100 : gained);

/// What the runner hands the screen while the pass is still going over: the
/// server's own version of it, once [gate] is let go of.
Future<LessonResultsRefresh?> _serverNumbers(Completer<void> gate, Lesson lesson, LessonPassStats stats) async {
  await gate.future;
  return LessonResultsRefresh(lesson, stats);
}

Future<void> _open(
  WidgetTester tester, {
  required Lesson lesson,
  required LessonPassStats stats,
  Future<LessonResultsRefresh?>? refresh,
}) async {  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: LessonResultsScreen(lesson: lesson, stats: stats, refresh: refresh)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('the server\'s own numbers replace the device\'s, in place', (tester) async {
    final gate = Completer<void>();
    await http.runWithClient(() async {
      await _open(
        tester,
        lesson: _lesson(0),
        stats: _stats(accuracy: 12, gained: 4),
        refresh: _serverNumbers(gate, _lesson(40), _stats(accuracy: 88, gained: 40)),
      );

      // Up at once, on what the phone itself worked out.
      expect(find.text('12'), findsWidgets, reason: 'the device\'s own accuracy');
      expect(find.text('+4 очков'), findsOneWidget, reason: 'and its own points gained');

      // The server answers the hand-over the runner is doing behind this screen.
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('88'), findsWidgets, reason: 'the server\'s accuracy, in place');
      expect(find.text('+40 очков'), findsOneWidget, reason: 'and the points it counted');
      expect(find.text('+4 очков'), findsNothing, reason: 'nothing of the device\'s guess is left over');
      expect(find.text('12'), findsNothing);
    }, () => _client);
  });

  testWidgets('a pass the server never answers keeps the numbers the phone worked out', (tester) async {
    await http.runWithClient(() async {
      await _open(
        tester,
        lesson: _lesson(0),
        stats: _stats(accuracy: 12, gained: 4),
        refresh: Future.value(null),
      );

      expect(find.text('12'), findsWidgets);
      expect(find.text('+4 очков'), findsOneWidget);
    }, () => _client);
  });
}
