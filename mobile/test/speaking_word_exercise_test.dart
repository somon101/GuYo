// "Произнеси слово" must never get stuck: a recognizer error, a stop tap
// or a failed start always hands the mic back, a wrong word can be said
// again, and every word is reported exactly once.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

import 'package:guyo_app/models/lesson.dart';
import 'package:guyo_app/widgets/exercises/speaking_word_exercise.dart';

/// Plays the device recognizer: the test decides what gets "heard".
class _FakeRecognizer extends SpeechToTextPlatform {
  bool failNextListen = false;
  int listens = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> initialize({debugLogging = false, List<SpeechConfigOption>? options}) async => true;

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    if (failNextListen) {
      failNextListen = false;
      throw PlatformException(code: 'busy');
    }
    listens++;
    onStatus?.call('listening');
    return true;
  }

  @override
  Future<void> stop() async => onStatus?.call('notListening');

  @override
  Future<void> cancel() async => onStatus?.call('notListening');

  void hear(String words, {bool last = true}) => onTextRecognition?.call(jsonEncode({
        'alternates': [
          {'recognizedWords': words, 'confidence': 0.9},
        ],
        'resultType': last ? 2 : 0,
      }));

  void fail(String message) => onError?.call(jsonEncode({'errorMsg': message, 'permanent': true}));
}

final _mic = find.byKey(const ValueKey('speaking-word-mic-button'));

SpeakingWordItem _item(int id, String word) => SpeakingWordItem.fromJson({'word_id': id, 'word': word});

Future<void> _show(WidgetTester tester, SpeakingWordItem item, List<bool> answers) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SpeakingWordExercise(key: ValueKey(item.wordId), item: item, matchThreshold: 80, onAnswer: answers.add),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _tapMic(WidgetTester tester) async {
  await tester.tap(_mic);
  await tester.pump();
}

void main() {
  late _FakeRecognizer recognizer;

  setUpAll(() {
    recognizer = _FakeRecognizer();
    SpeechToTextPlatform.instance = recognizer;
  });

  testWidgets('an error on a LATER word hands the mic back instead of hanging', (tester) async {
    final answers = <bool>[];
    // First word: the one that used to keep the recognizer's callbacks.
    await _show(tester, _item(1, 'хона'), answers);
    await _tapMic(tester);
    recognizer.hear('хона');
    await tester.pump(const Duration(seconds: 2));
    expect(answers, [true]);

    // Second word, new widget: the recognizer gives up on a bad attempt.
    await _show(tester, _item(2, 'китоб'), answers);
    await _tapMic(tester);
    expect(find.text('Нажмите, чтобы остановить'), findsOneWidget);
    recognizer.fail('error_no_match');
    await tester.pump();
    expect(find.text('Речь не распознана, попробуйте ещё раз'), findsOneWidget);

    final before = recognizer.listens;
    await _tapMic(tester);
    expect(recognizer.listens, before + 1, reason: 'the mic works again');
    recognizer.hear('китоб');
    await tester.pump(const Duration(seconds: 2));
    expect(answers, [true, true]);
  });

  testWidgets('tapping while recording stops and checks what was heard', (tester) async {
    final answers = <bool>[];
    await _show(tester, _item(3, 'мактаб'), answers);
    await _tapMic(tester);
    recognizer.hear('мактаб', last: false);
    await tester.pump();
    await _tapMic(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(answers, [true]);
  });

  testWidgets('stop with nothing heard just returns to the mic', (tester) async {
    final answers = <bool>[];
    await _show(tester, _item(4, 'нон'), answers);
    await _tapMic(tester);
    await _tapMic(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(answers, isEmpty);
    expect(find.text('Нажмите и произнесите слово'), findsOneWidget);
  });

  testWidgets('a failed start never leaves it recording', (tester) async {
    final answers = <bool>[];
    await _show(tester, _item(5, 'об'), answers);
    recognizer.failNextListen = true;
    await _tapMic(tester);
    await tester.pump();
    expect(find.text('Нажмите и произнесите слово'), findsOneWidget);
    await _tapMic(tester);
    expect(find.text('Нажмите, чтобы остановить'), findsOneWidget);
    await _tapMic(tester);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a wrong word: "Ещё раз" lets you say it again, "Дальше" counts it wrong', (tester) async {
    final answers = <bool>[];
    await _show(tester, _item(6, 'дарахт'), answers);
    await _tapMic(tester);
    recognizer.hear('собака');
    await tester.pump(const Duration(seconds: 3));
    expect(answers, isEmpty, reason: 'waits for the user to choose');
    expect(find.text('Неправильно'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('speaking-word-retry')));
    await tester.pump();
    expect(find.textContaining('Попытка 2 из 3'), findsOneWidget);
    await _tapMic(tester);
    recognizer.hear('кошка');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('speaking-word-next')));
    await tester.pump();
    expect(answers, [false]);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the third wrong try counts as wrong on its own', (tester) async {
    final answers = <bool>[];
    await _show(tester, _item(7, 'дарахт'), answers);
    for (var i = 0; i < 3; i++) {
      await _tapMic(tester);
      recognizer.hear('собака');
      await tester.pump(const Duration(milliseconds: 500));
      if (i < 2) {
        await tester.tap(find.byKey(const ValueKey('speaking-word-retry')));
        await tester.pump();
      }
    }
    expect(find.byKey(const ValueKey('speaking-word-retry')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(answers, [false]);
  });

  testWidgets('a close enough match counts as right', (tester) async {
    final answers = <bool>[];
    await _show(tester, _item(8, 'китоб'), answers);
    await _tapMic(tester);
    // "кито" is 80% similar -- at the threshold, so right straight away.
    recognizer.hear('кито');
    await tester.pump(const Duration(seconds: 3));
    expect(answers, [true]);
  });
}
