import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/mini_phrase.dart';
import 'package:guyo_app/widgets/mini_phrases/mini_phrase_build.dart';
import 'package:guyo_app/widgets/mini_phrases/mini_phrase_explanation.dart';

const _phrase = MiniPhrase(
  id: 1,
  dictionaryId: 1,
  text: 'Я покушал',
  translation: 'Ман хӯрок хӯрдам',
  parts: [
    MiniPhrasePart(position: 1, text: 'Я', wordId: 1, role: 'pronoun', translation: 'ман'),
    MiniPhrasePart(position: 2, text: 'покушал', wordId: 2, role: 'verb', translation: 'хӯрок хӯрдан'),
  ],
  explanation: [
    MiniPhraseSegment(kind: 'text', text: 'Сначала '),
    MiniPhraseSegment(kind: 'part', text: 'Я', role: 'pronoun'),
  ],
  distractors: ['дом'],
);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('answers ignore case and punctuation', () {
    expect(_phrase.isCorrect(['я', 'ПОКУШАЛ!']), isTrue);
    expect(_phrase.isCorrect(['покушал', 'я']), isFalse);
    expect(_phrase.isCorrect(['я', 'дом']), isFalse);
  });

  testWidgets('placing the parts in order is judged correct', (tester) async {
    bool? result;
    await tester.pumpWidget(_host(MiniPhraseBuildExercise(phrase: _phrase, onDone: (r) => result = r)));
    await tester.tap(find.text('Я'));
    await tester.pump();
    await tester.tap(find.text('покушал'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mini-phrase-check')));
    await tester.pump(const Duration(seconds: 2));
    expect(result, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a wrong order shows the right answer and waits for "Дальше"', (tester) async {
    bool? result;
    await tester.pumpWidget(_host(MiniPhraseBuildExercise(phrase: _phrase, onDone: (r) => result = r)));
    await tester.tap(find.text('покушал'));
    await tester.pump();
    await tester.tap(find.text('Я'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mini-phrase-check')));
    await tester.pump(const Duration(seconds: 2));
    expect(result, isNull);
    expect(find.textContaining('Я покушал'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('mini-phrase-check')));
    expect(result, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('the explanation shows the parts and moves on', (tester) async {
    var next = false;
    await tester.pumpWidget(
      _host(MiniPhraseExplanation(phrase: _phrase, nextLabel: 'Дальше', onNext: () => next = true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('покушал'), findsWidgets);
    expect(find.text('Ман хӯрок хӯрдам'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mini-phrase-next')));
    expect(next, isTrue);
  });
}
