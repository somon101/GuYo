import 'dart:convert';

import '../models/exercise_scoring.dart';
import '../models/lesson.dart';
import 'disk_cache.dart';

/// A pass that was scored on the phone.
class ScoredPass {
  /// The lesson with the scores this pass produced.
  final Lesson lesson;

  /// The pass's statistics, in the server's own shape.
  final LessonPassStats stats;

  const ScoredPass({required this.lesson, required this.stats});
}

/// Scoring one lesson pass on the phone, by exactly the server's rules.
///
/// Used while a pass's answers are still on the device (no network): the user
/// sees the real outcome at once instead of an error. The server recomputes
/// everything from those same answers the moment they arrive, and its numbers
/// are the ones that last -- see ApiClient.finishPassOrQueue.
///
/// The mirror is faithful by construction rather than by copying numbers: the
/// points come from the server's own rules ([ExerciseScoring], downloaded when
/// the lesson was prepared), the scores start from the lesson as it was before
/// the pass, and every answer moves one word by those points, clamped to 0..100
/// exactly as the backend does (see `_hold_answer_for_pass`).
class LessonScoring {
  LessonScoring._();

  static ScoredPass score({
    required Lesson before,
    required List<Map<String, dynamic>> answers,
    required ExerciseScoring rules,
    DateTime? startedAt,
  }) {
    final beforeScores = {for (final word in before.words) word.wordId: word.score};
    final pending = <int, int>{};
    final perExercise = <String, List<int>>{};
    var correctAnswers = 0;
    DateTime? lastAt;

    for (final answer in answers) {
      final wordId = answer['word_id'] as int?;
      if (wordId == null) continue;
      final exerciseKey = answer['exercise_key'] as String? ?? '';
      final isCorrect = answer['is_correct'] == true;

      pending.putIfAbsent(wordId, () => beforeScores[wordId] ?? 0);
      final points = rules.forExercise(exerciseKey);
      final delta = isCorrect ? points.correct : -points.incorrect;
      pending[wordId] = (pending[wordId]! + delta).clamp(0, 100).toInt();

      final counts = perExercise.putIfAbsent(exerciseKey, () => [0, 0]);
      counts[1] += 1;
      if (isCorrect) {
        counts[0] += 1;
        correctAnswers++;
      }

      final at = answer['at'];
      if (at is int) {
        final time = DateTime.fromMillisecondsSinceEpoch(at);
        if (lastAt == null || time.isAfter(lastAt)) lastAt = time;
      }
    }

    int scoreOf(int wordId) => pending[wordId] ?? beforeScores[wordId] ?? 0;

    // One row per word of the lesson: what it was, what it is now, and whether
    // this pass is what pushed it over the learned threshold.
    final words = [
      for (final word in before.words)
        PassWordStat(
          wordId: word.wordId,
          word: word.word,
          scoreBefore: beforeScores[word.wordId] ?? 0,
          scoreAfter: scoreOf(word.wordId),
          gained: scoreOf(word.wordId) - (beforeScores[word.wordId] ?? 0),
          becameLearned:
              (beforeScores[word.wordId] ?? 0) < rules.threshold && scoreOf(word.wordId) >= rules.threshold,
        ),
    ];

    final keys = _inLessonOrder(before, perExercise.keys);
    final stats = LessonPassStats(
      durationSeconds: _duration(startedAt, lastAt),
      totalAnswers: answers.length,
      correctAnswers: correctAnswers,
      wrongAnswers: answers.length - correctAnswers,
      accuracy: answers.isEmpty ? 0 : (correctAnswers * 100 / answers.length).round(),
      exercises: [
        for (final key in keys)
          PassExerciseStat(exerciseKey: key, correct: perExercise[key]![0], total: perExercise[key]![1]),
      ],
      words: words,
      scoreGained: words.fold(0, (sum, word) => sum + word.gained),
      newlyLearned: words.where((word) => word.becameLearned).length,
    );

    // The lesson as it now stands, so the next screen (and the next offline
    // pass) starts from the scores this pass produced.
    final updated = Lesson(
      id: before.id,
      dictionaryId: before.dictionaryId,
      number: before.number,
      isCompleted: before.isCompleted || (before.words.isNotEmpty && words.every((w) => w.scoreAfter >= rules.threshold)),
      exerciseKeys: before.exerciseKeys,
      words: [
        for (final word in before.words)
          LessonWord(
            wordId: word.wordId,
            word: word.word,
            translation: word.translation,
            score: scoreOf(word.wordId),
            isLearned: scoreOf(word.wordId) >= rules.threshold,
            wordLevelId: word.wordLevelId,
            wordLevelName: word.wordLevelName,
            transcription: word.transcription,
            wordAudioUrl: word.wordAudioUrl,
            translationAudioUrl: word.translationAudioUrl,
            imageUrl: word.imageUrl,
          ),
      ],
      miniPhrases: before.miniPhrases,
    );
    LessonScoreOverlay.remember(
      before.id,
      {for (final word in words) word.wordId: word.scoreAfter},
    );
    return ScoredPass(lesson: updated, stats: stats);
  }

  /// The lesson's own exercise order first (the order the runner walks and the
  /// backend reports), anything unexpected after it.
  static List<String> _inLessonOrder(Lesson lesson, Iterable<String> keys) {
    final known = [for (final key in lesson.exerciseKeys) if (keys.contains(key)) key];
    return [...known, for (final key in keys) if (!known.contains(key)) key];
  }

  static int _duration(DateTime? startedAt, DateTime? lastAt) {
    if (startedAt == null || lastAt == null) return 0;
    final seconds = lastAt.difference(startedAt).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }
}

/// The scores this phone has advanced past what the server has confirmed, per
/// lesson.
///
/// Without it a lesson opened again while still offline would show the scores
/// from before the pass, right after the results screen showed the new ones.
/// Dropped as soon as the server's own copy arrives (ApiClient), because from
/// then on the server's numbers are the true ones.
class LessonScoreOverlay {
  LessonScoreOverlay._();

  static const String _prefix = 'lesson-scores-';

  static Map<int, int> scoresFor(int lessonId) {
    final raw = DiskCache.get('$_prefix$lessonId');
    if (raw == null) return const {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final entry in json.entries) int.parse(entry.key): entry.value as int};
    } catch (_) {
      return const {};
    }
  }

  static void remember(int lessonId, Map<int, int> scores) => DiskCache.put(
        '$_prefix$lessonId',
        jsonEncode({for (final entry in scores.entries) '${entry.key}': entry.value}),
      );

  static void forget(int lessonId) => DiskCache.put('$_prefix$lessonId', '{}');

  /// [lesson] with this device's own scores applied, or the same lesson when
  /// there are none waiting.
  static Lesson applied(Lesson lesson, ExerciseScoring rules) {
    final scores = scoresFor(lesson.id);
    if (scores.isEmpty) return lesson;
    var allLearned = lesson.words.isNotEmpty;
    final words = <LessonWord>[];
    for (final word in lesson.words) {
      final score = scores[word.wordId] ?? word.score;
      if (score < rules.threshold) allLearned = false;
      if (!scores.containsKey(word.wordId)) {
        words.add(word);
        continue;
      }
      words.add(
        LessonWord(
          wordId: word.wordId,
          word: word.word,
          translation: word.translation,
          score: score,
          isLearned: score >= rules.threshold,
          wordLevelId: word.wordLevelId,
          wordLevelName: word.wordLevelName,
          transcription: word.transcription,
          wordAudioUrl: word.wordAudioUrl,
          translationAudioUrl: word.translationAudioUrl,
          imageUrl: word.imageUrl,
        ),
      );
    }
    return Lesson(
      id: lesson.id,
      dictionaryId: lesson.dictionaryId,
      number: lesson.number,
      isCompleted: lesson.isCompleted || allLearned,
      exerciseKeys: lesson.exerciseKeys,
      words: words,
      miniPhrases: lesson.miniPhrases,
    );
  }
}
