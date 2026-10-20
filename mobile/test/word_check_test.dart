// The pre-lesson word check: a right answer asks how easy it was, a wrong one
// does not, and the whole session ends with onDone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/models/word_check.dart';
import 'package:guyo_app/widgets/word_check_session.dart';

WordCheck _check({bool skip = true}) => WordCheck(
      enabled: true,
      skipAllowed: skip,
      items: [
        CheckItem(
          wordId: 1,
          original: 'water',
          options: const [
            CheckOption(wordId: 2, text: 'fire'),
            CheckOption(wordId: 1, text: 'вода'),
            CheckOption(wordId: 3, text: 'земля'),
            CheckOption(wordId: 4, text: 'ветер'),
          ],
        ),
      ],
    );

void main() {
  testWidgets('shows the word and four options; skipping ends the check', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WordCheckSession(lessonId: 7, check: _check(), onDone: () => done = true)),
    ));
    expect(find.text('water'), findsOneWidget);
    for (final t in ['fire', 'вода', 'земля', 'ветер']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Пропустить'), findsOneWidget);
    expect(done, isFalse);
  });

  testWidgets('no skip button when the admin turned it off', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WordCheckSession(lessonId: 7, check: _check(skip: false), onDone: () {})),
    ));
    expect(find.text('Пропустить'), findsNothing);
  });

  testWidgets('a right answer asks how easy it was', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WordCheckSession(lessonId: 7, check: _check(), onDone: () {})),
    ));
    await tester.tap(find.text('вода'));
    await tester.pump();
    expect(find.text('Насколько это было легко?'), findsOneWidget);
    for (final t in ['Угадал', 'Трудно', 'Нормально', 'Легко']) {
      expect(find.text(t), findsOneWidget);
    }
  });

  testWidgets('a wrong answer asks nothing more', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WordCheckSession(lessonId: 7, check: _check(), onDone: () {})),
    ));
    await tester.tap(find.text('fire'));
    await tester.pump();
    expect(find.text('Насколько это было легко?'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}
