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
  // Classified via the same WordLevel ladder "Мои слова" shows -- see
  // GET /word-levels (ApiClient.fetchWordLevels), never a second scoring
  // system.
  final int? wordLevelId;
  final String? wordLevelName;
  // Carried so a lesson's word list renders the SAME shared word card
  // (widgets/word_card.dart) every other list uses, and its chevron can
  // open the same word detail screen, without a second fetch.
  final String? transcription;
  final String? wordAudioUrl;
  final String? translationAudioUrl;
  final String? imageUrl;

  LessonWord({
    required this.wordId,
    required this.word,
    required this.translation,
    required this.score,
    required this.isLearned,
    this.wordLevelId,
    this.wordLevelName,
    this.transcription,
    this.wordAudioUrl,
    this.translationAudioUrl,
    this.imageUrl,
  });

  factory LessonWord.fromJson(Map<String, dynamic> json) {
    return LessonWord(
      wordId: json['word_id'] as int,
      word: json['word'] as String,
      translation: json['translation'] as String?,
      score: json['score'] as int,
      isLearned: json['is_learned'] as bool,
      wordLevelId: json['word_level_id'] as int?,
      wordLevelName: json['word_level_name'] as String?,
      transcription: json['transcription'] as String?,
      wordAudioUrl: json['word_audio_url'] as String?,
      translationAudioUrl: json['translation_audio_url'] as String?,
      imageUrl: json['image_url'] as String?,
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

/// One "Произнеси слово" task: just the word itself (plus its optional
/// transcription/image, purely for the card) -- there is no audio here,
/// the user speaks it, the app's own on-device speech recognizer produces
/// text, and that text is compared to `word` right on the client. Mirrors
/// the backend's SpeakingWordItemOut/RoundOut exactly.
class SpeakingWordItem {
  final int wordId;
  final String word;
  final String? transcription;
  final String? imageUrl;

  SpeakingWordItem({required this.wordId, required this.word, this.transcription, this.imageUrl});

  factory SpeakingWordItem.fromJson(Map<String, dynamic> json) {
    return SpeakingWordItem(
      wordId: json['word_id'] as int,
      word: json['word'] as String,
      transcription: json['transcription'] as String?,
      imageUrl: json['image_url'] as String?,
    );
  }
}

class SpeakingWordRound {
  final int dictionaryId;
  final int availableCount;
  // Minimum recognized-text-vs-target similarity (0-100) the admin
  // configured for accepting a spoken answer -- carried on the round
  // itself so the client never has to fetch admin settings separately,
  // same pattern as BuildWordRound.caseSensitive.
  final int matchThreshold;
  final List<SpeakingWordItem> items;

  SpeakingWordRound({
    required this.dictionaryId,
    required this.availableCount,
    required this.matchThreshold,
    required this.items,
  });

  factory SpeakingWordRound.fromJson(Map<String, dynamic> json) {
    return SpeakingWordRound(
      dictionaryId: json['dictionary_id'] as int,
      availableCount: json['available_count'] as int,
      matchThreshold: json['match_threshold'] as int,
      items: (json['items'] as List<dynamic>)
          .map((e) => SpeakingWordItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One button of a "Услышь слово" task -- just enough to render a choice
/// and compare the tap by word_id, never by text.
class ListenWordOption {
  final int wordId;
  final String word;

  ListenWordOption({required this.wordId, required this.word});

  factory ListenWordOption.fromJson(Map<String, dynamic> json) {
    return ListenWordOption(wordId: json['word_id'] as int, word: json['word'] as String);
  }
}

/// One "Услышь слово" task: the word being played (by word_id, `word`
/// itself deliberately NOT included here -- the whole point is the user
/// hasn't been shown the text yet) plus the shuffled multiple-choice.
class ListenWordItem {
  final int wordId;
  final String? wordAudioUrl;
  final List<ListenWordOption> options;

  ListenWordItem({required this.wordId, required this.wordAudioUrl, required this.options});

  factory ListenWordItem.fromJson(Map<String, dynamic> json) {
    return ListenWordItem(
      wordId: json['word_id'] as int,
      wordAudioUrl: json['word_audio_url'] as String?,
      options: (json['options'] as List<dynamic>)
          .map((e) => ListenWordOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ListenWordRound {
  final int dictionaryId;
  final int availableCount;
  final List<ListenWordItem> items;

  ListenWordRound({required this.dictionaryId, required this.availableCount, required this.items});

  factory ListenWordRound.fromJson(Map<String, dynamic> json) {
    return ListenWordRound(
      dictionaryId: json['dictionary_id'] as int,
      availableCount: json['available_count'] as int,
      items: (json['items'] as List<dynamic>).map((e) => ListenWordItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
