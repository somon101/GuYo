// Confirms the new AnswerSound.play() calls wired into every exercise
// widget's own correctness-reveal moment (true_or_false, matching) never
// throw or hang the widget tree, even though this test environment has no
// working audio device -- AnswerSound.play() must swallow that silently
// (see lib/services/answer_sound.dart's own try/catch) rather than let it
// escape into the exercise's answer flow. No backend needed: pure widget
// test with hand-built fixture data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/exercise.dart';
import 'package:guyo_app/models/word.dart';
import 'package:guyo_app/widgets/exercises/matching_board.dart';
import 'package:guyo_app/widgets/exercises/true_or_false_exercise.dart';

void main() {
  testWidgets('TrueOrFalseExercise plays a feedback sound on answer without throwing', (tester) async {
    final item = TrueOrFalseItem(
      wordId: 1,
      original: 'apple',
      shownTranslation: 'яблоко',
      isCorrect: true,
    );
    bool? answered;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrueOrFalseExercise(item: item, onAnswer: (v) => answered = v),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('true-or-false-answer-true')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(answered, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MatchingBoard plays a feedback sound on each attempt without throwing', (tester) async {
    final words = [
      GuyoWord(id: 1, dictionaryId: 1, word: 'apple', translation: 'яблоко'),
      GuyoWord(id: 2, dictionaryId: 1, word: 'dog', translation: 'собака'),
    ];
    final attempts = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchingBoard(
            words: words,
            onAttempt: (wordId, isCorrect) => attempts.add(isCorrect),
            onComplete: () {},
          ),
        ),
      ),
    );

    // Tap the first left card, then its own matching right card (word_id
    // 1 on both sides) -- a real, deterministic correct attempt regardless
    // of the board's own internal shuffle.
    await tester.tap(find.byKey(const ValueKey('match-left-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('match-right-1')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(attempts, [true]);
    expect(tester.takeException(), isNull);
  });
}
