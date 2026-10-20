/// The pre-lesson word check -- mirrors the backend's CheckOut
/// (GET /lessons/{id}/check).
class CheckOption {
  final int wordId;
  final String text;
  const CheckOption({required this.wordId, required this.text});

  factory CheckOption.fromJson(Map<String, dynamic> json) =>
      CheckOption(wordId: json['word_id'] as int, text: json['text'] as String);
}

class CheckItem {
  final int wordId;
  final String original;
  final String? transcription;
  final String? imageUrl;
  final String? wordAudioUrl;
  final List<CheckOption> options;

  const CheckItem({
    required this.wordId,
    required this.original,
    this.transcription,
    this.imageUrl,
    this.wordAudioUrl,
    required this.options,
  });

  factory CheckItem.fromJson(Map<String, dynamic> json) => CheckItem(
        wordId: json['word_id'] as int,
        original: json['original'] as String,
        transcription: json['transcription'] as String?,
        imageUrl: json['image_url'] as String?,
        wordAudioUrl: json['word_audio_url'] as String?,
        options: (json['options'] as List<dynamic>)
            .map((e) => CheckOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class WordCheck {
  final bool enabled;
  final bool skipAllowed;
  final List<CheckItem> items;

  const WordCheck({required this.enabled, required this.skipAllowed, required this.items});

  bool get hasWork => enabled && items.isNotEmpty;

  factory WordCheck.fromJson(Map<String, dynamic> json) => WordCheck(
        enabled: json['enabled'] as bool,
        skipAllowed: json['skip_allowed'] as bool,
        items: (json['items'] as List<dynamic>)
            .map((e) => CheckItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// How easy a right answer was, said by the learner.
enum CheckRating { guess, hard, normal, easy }
