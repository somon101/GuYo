class GuyoWord {
  final int id;
  final int dictionaryId;
  final String word;
  final String translation;
  final String? transcription;
  final String? wordAudioUrl;
  final String? translationAudioUrl;
  final String? imageUrl;
  // Only populated by endpoints whose backend WordOut includes them (e.g.
  // the lesson candidate-words list, used to group the manual picker by
  // category) -- absent/null wherever a caller doesn't need it.
  final int? categoryId;
  final String? categoryName;

  GuyoWord({
    required this.id,
    required this.dictionaryId,
    required this.word,
    required this.translation,
    this.transcription,
    this.wordAudioUrl,
    this.translationAudioUrl,
    this.imageUrl,
    this.categoryId,
    this.categoryName,
  });

  factory GuyoWord.fromJson(Map<String, dynamic> json) {
    return GuyoWord(
      id: json['id'] as int,
      dictionaryId: json['dictionary_id'] as int,
      word: json['word'] as String,
      translation: json['translation'] as String,
      // Optional fields are simply absent/null -- rendering code must not
      // assume they exist.
      transcription: json['transcription'] as String?,
      wordAudioUrl: json['word_audio_url'] as String?,
      translationAudioUrl: json['translation_audio_url'] as String?,
      imageUrl: json['image_url'] as String?,
      categoryId: json['category_id'] as int?,
      categoryName: json['category_name'] as String?,
    );
  }
}
