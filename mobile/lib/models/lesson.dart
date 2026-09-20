import 'word.dart';

/// One word inside a Lesson, with its own cumulative WordProgress.score
/// (0-100, shared across every lesson that ever touches this word_id --
/// never reset per lesson) and whether that score has reached the admin's
/// threshold. Mirrors the backend's LessonWordOut exactly.
class LessonWord {
  final int wordId;
  final String word;
  final String? translation;
  final int score;
  final bool isLearned;

  LessonWord({
    required this.wordId,
    required this.word,
    required this.translation,
    required this.score,
    required this.isLearned,
  });

  factory LessonWord.fromJson(Map<String, dynamic> json) {
    return LessonWord(
      wordId: json['word_id'] as int,
      word: json['word'] as String,
      translation: json['translation'] as String?,
      score: json['score'] as int,
      isLearned: json['is_learned'] as bool,
    );
  }
}

/// A fixed, <=15-word set the user picked for one dictionary, plus whichever
/// exercise types the backend decided were available for that exact set
/// (`exerciseKeys`) -- decided once at creation, never recomputed here.
/// Mirrors the backend's LessonOut exactly.
class Lesson {
  final int id;
  final int dictionaryId;
  final int number;
  final bool isCompleted;
  final List<String> exerciseKeys;
  final List<LessonWord> words;

  Lesson({
    required this.id,
    required this.dictionaryId,
    required this.number,
    required this.isCompleted,
    required this.exerciseKeys,
    required this.words,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as int,
      dictionaryId: json['dictionary_id'] as int,
      number: json['number'] as int,
      isCompleted: json['is_completed'] as bool,
      exerciseKeys: (json['exercise_keys'] as List<dynamic>).map((e) => e as String).toList(),
      words: (json['words'] as List<dynamic>).map((e) => LessonWord.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// The pool a new lesson's word picker (random or manual) draws from --
/// every not-yet-learned word in this dictionary. Reuses GuyoWord (with its
/// category_id/category_name) so the manual picker can group by category
/// exactly like "Мои изученные слова" does, without a separate model.
class LessonCandidateWords {
  final int dictionaryId;
  final int availableCount;
  final List<GuyoWord> words;

  LessonCandidateWords({required this.dictionaryId, required this.availableCount, required this.words});

  factory LessonCandidateWords.fromJson(Map<String, dynamic> json) {
    return LessonCandidateWords(
      dictionaryId: json['dictionary_id'] as int,
      availableCount: json['available_count'] as int,
      words: (json['words'] as List<dynamic>).map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// One row of a dictionary's full, permanent lesson history (see
/// GET /dictionaries/{id}/lessons) -- everything the "Уроки" chain screen
/// needs to render one link without fetching every lesson's full word
/// list up front. Mirrors the backend's LessonSummaryOut exactly.
class LessonSummary {
  final int id;
  final int number;
  final bool isCompleted;
  final int wordCount;
  final int learnedCount;

  LessonSummary({
    required this.id,
    required this.number,
    required this.isCompleted,
    required this.wordCount,
    required this.learnedCount,
  });

  factory LessonSummary.fromJson(Map<String, dynamic> json) {
    return LessonSummary(
      id: json['id'] as int,
      number: json['number'] as int,
      isCompleted: json['is_completed'] as bool,
      wordCount: json['word_count'] as int,
      learnedCount: json['learned_count'] as int,
    );
  }
}

/// What submitting one answer changed: this specific word_id's new score,
/// whether it just became learned, and whether the whole lesson just
/// completed as a result (every word reached the threshold) -- all decided
/// entirely by the backend, never computed on-device.
class SubmitAnswerResult {
  final int wordId;
  final int score;
  final bool isLearned;
  final bool lessonCompleted;

  SubmitAnswerResult({
    required this.wordId,
    required this.score,
    required this.isLearned,
    required this.lessonCompleted,
  });

  factory SubmitAnswerResult.fromJson(Map<String, dynamic> json) {
    return SubmitAnswerResult(
      wordId: json['word_id'] as int,
      score: json['score'] as int,
      isLearned: json['is_learned'] as bool,
      lessonCompleted: json['lesson_completed'] as bool,
    );
  }
}
