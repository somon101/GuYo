/// One card of a "Правда или ложь" round. The backend already decided
/// whether [shownTranslation] is the word's real translation or one
/// borrowed from a different learned word -- [isCorrect] is that decision,
/// never recomputed here. The UI only renders this and compares the
/// user's tap to it.
class TrueOrFalseItem {
  final int wordId;
  final String original;
  final String? transcription;
  final String? imageUrl;
  final String? wordAudioUrl;
  final String shownTranslation;
  final String? shownTranslationAudioUrl;
  final bool isCorrect;

  TrueOrFalseItem({
    required this.wordId,
    required this.original,
    this.transcription,
    this.imageUrl,
    this.wordAudioUrl,
    required this.shownTranslation,
    this.shownTranslationAudioUrl,
    required this.isCorrect,
  });

  factory TrueOrFalseItem.fromJson(Map<String, dynamic> json) {
    return TrueOrFalseItem(
      wordId: json['word_id'] as int,
      original: json['original'] as String,
      transcription: json['transcription'] as String?,
      imageUrl: json['image_url'] as String?,
      wordAudioUrl: json['word_audio_url'] as String?,
      shownTranslation: json['shown_translation'] as String,
      shownTranslationAudioUrl: json['shown_translation_audio_url'] as String?,
      isCorrect: json['is_correct'] as bool,
    );
  }
}

class TrueOrFalseRound {
  final int dictionaryId;
  final int availableCount;
  final List<TrueOrFalseItem> items;

  TrueOrFalseRound({required this.dictionaryId, required this.availableCount, required this.items});

  factory TrueOrFalseRound.fromJson(Map<String, dynamic> json) {
    return TrueOrFalseRound(
      dictionaryId: json['dictionary_id'] as int,
      availableCount: json['available_count'] as int,
      items: (json['items'] as List<dynamic>)
          .map((e) => TrueOrFalseItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One "Собери слово" task. [letters] is already the full shuffled set
/// (real letters + distractors) the backend decided -- nothing about
/// which/how many wrong letters, or the shuffle, happens on-device.
/// [correctWord] is used only for local, immediate comparison as the
/// player builds their answer; the backend never re-checks it.
class BuildWordItem {
  final int wordId;
  final String translation;
  final String correctWord;
  final List<String> letters;
  final String? transcription;
  final String? imageUrl;
  final String? wordAudioUrl;
  final String? translationAudioUrl;

  BuildWordItem({
    required this.wordId,
    required this.translation,
    required this.correctWord,
    required this.letters,
    this.transcription,
    this.imageUrl,
    this.wordAudioUrl,
    this.translationAudioUrl,
  });

  factory BuildWordItem.fromJson(Map<String, dynamic> json) {
    return BuildWordItem(
      wordId: json['word_id'] as int,
      translation: json['translation'] as String,
      correctWord: json['correct_word'] as String,
      letters: (json['letters'] as List<dynamic>).map((e) => e as String).toList(),
      transcription: json['transcription'] as String?,
      imageUrl: json['image_url'] as String?,
      wordAudioUrl: json['word_audio_url'] as String?,
      translationAudioUrl: json['translation_audio_url'] as String?,
    );
  }
}

class BuildWordRound {
  final int dictionaryId;
  final int availableCount;
  final bool caseSensitive;
  final List<BuildWordItem> items;

  BuildWordRound({
    required this.dictionaryId,
    required this.availableCount,
    required this.caseSensitive,
    required this.items,
  });

  factory BuildWordRound.fromJson(Map<String, dynamic> json) {
    return BuildWordRound(
      dictionaryId: json['dictionary_id'] as int,
      availableCount: json['available_count'] as int,
      caseSensitive: json['case_sensitive'] as bool,
      items: (json['items'] as List<dynamic>)
          .map((e) => BuildWordItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
