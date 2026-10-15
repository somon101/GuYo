// The device's queue of lesson work (see PendingAnswers): the order it is sent
// in is what makes a pass played with no network count at all. A pass opening is
// what everything else of that pass hangs off, so it is written down where it
// belongs -- after the previous pass's ending, before its own answers -- whatever
// order the requests themselves happened to fail in.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/services/pending_answers.dart';

Map<String, dynamic> _answer(int lessonId, int wordId) => {
      'lesson_id': lessonId,
      'exercise_key': 'true_or_false',
      'word_id': wordId,
      'is_correct': true,
      'at': 1,
    };

/// The queue of one lesson, in the order it would be flushed.
List<String> _queue(int lessonId) => [
      for (final entry in PendingAnswers.forLesson(lessonId))
        (entry['kind'] ?? 'answer') == 'answer' ? 'answer:${entry['word_id']}' : entry['kind'] as String,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await PendingAnswers.clear();
  });

  test('no network: the opening is queued ahead of the answers given before it', () async {
    // The lesson started answering before its opening could even be written down
    // (the opening is a request, and it has to fail first).
    await PendingAnswers.add(_answer(7, 1));
    await PendingAnswers.addStart(7);
    await PendingAnswers.add(_answer(7, 2));

    expect(_queue(7), ['start', 'answer:1', 'answer:2'],
        reason: 'the pass must be opened before the server is told about its answers');
  });

  test('a new pass opens after the previous pass\'s ending, before its own answers', () async {
    // The first pass: its opening went over, its ending is still waiting.
    final start = await PendingAnswers.addStart(7);
    await PendingAnswers.add(_answer(7, 1));
    await PendingAnswers.remove(start);
    await PendingAnswers.addFinish(7);

    // The second pass starts and answers at once -- with no network either.
    await PendingAnswers.add(_answer(7, 2));
    await PendingAnswers.addStart(7);

    expect(_queue(7), ['answer:1', 'finish', 'start', 'answer:2'],
        reason: 'the pass that was played first counts first, and the new opening comes before its answers');
  });

  test('a lesson\'s own work never jumps another lesson\'s', () async {
    await PendingAnswers.addStart(7);
    await PendingAnswers.addStart(9);
    await PendingAnswers.add(_answer(9, 5));
    await PendingAnswers.add(_answer(7, 1));

    expect(_queue(7), ['start', 'answer:1']);
    expect(_queue(9), ['start', 'answer:5']);
  });
}
