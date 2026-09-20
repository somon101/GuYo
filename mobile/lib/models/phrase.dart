/// Mirrors the backend's PhraseOut exactly. A Phrase is never copied or
/// scored -- this is a plain read of existing data, same principle as
/// GuyoWord.
class GuyoPhrase {
  final int id;
  final int dictionaryId;
  final int? categoryId;
  final String? categoryName;
  final String original;
  final String? transcription;
  final String translationTg;
  final String? originalAudioUrl;
  final String? translationAudioUrl;

  GuyoPhrase({
    required this.id,
    required this.dictionaryId,
    required this.categoryId,
    required this.categoryName,
    required this.original,
    required this.transcription,
    required this.translationTg,
    required this.originalAudioUrl,
    required this.translationAudioUrl,
  });

  factory GuyoPhrase.fromJson(Map<String, dynamic> json) {
    return GuyoPhrase(
      id: json['id'] as int,
      dictionaryId: json['dictionary_id'] as int,
      categoryId: json['category_id'] as int?,
      categoryName: json['category_name'] as String?,
      original: json['original'] as String,
      transcription: json['transcription'] as String?,
      translationTg: json['translation_tg'] as String,
      originalAudioUrl: json['original_audio_url'] as String?,
      translationAudioUrl: json['translation_audio_url'] as String?,
    );
  }
}
