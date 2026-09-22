/// One grammatical form of a Word, in a given language -- mirrors the
/// backend's WordFormOut. Only meaningful together with the language it's
/// in: matching a phrase token against a learned word's forms must only
/// ever consider the dictionary's OWN language (see
/// GuyoDictionary.language), never a translation-language form (e.g. a
/// Tajik form describes Tajik grammar, not this dictionary's own
/// sentences) -- same rule the backend's phrase-availability check uses.
class GuyoWordForm {
  final String language;
  final String text;
  GuyoWordForm({required this.language, required this.text});

  factory GuyoWordForm.fromJson(Map<String, dynamic> json) {
    return GuyoWordForm(language: json['language'] as String, text: json['text'] as String);
  }
}

/// One rung of the word-reinforcement ladder -- mirrors the backend's
/// WordLevelOut (GET /word-levels), enabled levels only, lowest
/// score-range first. This list's own index is what "Мои слова" uses to
/// pick a word's red-to-green badge color: the backend decides which
/// level a word is in and the levels' order; the color-per-position
/// mapping is the only thing left to the client.
class WordLevelSummary {
  final int id;
  final String name;
  final int minPoints;
  final int? maxPoints;

  WordLevelSummary({required this.id, required this.name, required this.minPoints, required this.maxPoints});

  factory WordLevelSummary.fromJson(Map<String, dynamic> json) {
    return WordLevelSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      minPoints: json['min_points'] as int,
      maxPoints: json['max_points'] as int?,
    );
  }
}

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
  // Present wherever the backend's WordOut is used (e.g. /learned-words);
  // empty when the endpoint's own schema never includes it at all.
  final List<GuyoWordForm> forms;
  // Only populated by /learned-words?include_in_progress=true (see
  // learned_words_screen.dart) -- this user's own WordProgress score and
  // the word-reinforcement level it currently falls in. Null everywhere
  // else, including the default (threshold-only) /learned-words call.
  final int? score;
  final int? wordLevelId;
  final String? wordLevelName;

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
    this.forms = const [],
    this.score,
    this.wordLevelId,
    this.wordLevelName,
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
      forms: json['forms'] == null
          ? const []
          : (json['forms'] as List<dynamic>)
              .map((e) => GuyoWordForm.fromJson(e as Map<String, dynamic>))
              .toList(),
      score: json['score'] as int?,
      wordLevelId: json['word_level_id'] as int?,
      wordLevelName: json['word_level_name'] as String?,
    );
  }
}
