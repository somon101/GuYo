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
