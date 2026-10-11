/// A mini-phrase ("Я покушал") as the app gets it: the ready text, its
/// translation, its parts in order (each with the role and translation of
/// its dictionary word), the explanation already rendered from its
/// template into segments, and the extra tiles for "Собери фразу".
class MiniPhrasePart {
  final int position;
  final String text;
  final int wordId;
  final String? role;
  final String? translation;

  const MiniPhrasePart({
    required this.position,
    required this.text,
    required this.wordId,
    this.role,
    this.translation,
  });

  factory MiniPhrasePart.fromJson(Map<String, dynamic> json) => MiniPhrasePart(
        position: json['position'] as int,
        text: json['text'] as String,
        wordId: json['word_id'] as int,
        role: json['role'] as String?,
        translation: json['translation'] as String?,
      );
}

/// One piece of the explanation: plain `text`, a `part` (coloured by its
/// role), the whole `phrase`, or a `translation`.
class MiniPhraseSegment {
  final String kind;
  final String text;
  final String? role;

  const MiniPhraseSegment({required this.kind, required this.text, this.role});

  factory MiniPhraseSegment.fromJson(Map<String, dynamic> json) => MiniPhraseSegment(
        kind: json['kind'] as String,
        text: json['text'] as String,
        role: json['role'] as String?,
      );
}

class MiniPhrase {
  final int id;
  final int dictionaryId;
  final String text;
  final String? translation;
  final String? audioUrl;
  final String templateKind;
  final List<MiniPhrasePart> parts;
  final List<MiniPhraseSegment> explanation;

  /// Extra wrong tiles (already-learned words, picked by priority).
  final List<String> distractors;

  const MiniPhrase({
    required this.id,
    required this.dictionaryId,
    required this.text,
    this.translation,
    this.audioUrl,
    this.templateKind = 'ordered_parts',
    required this.parts,
    required this.explanation,
    this.distractors = const [],
  });

  factory MiniPhrase.fromJson(Map<String, dynamic> json) => MiniPhrase(
        id: json['id'] as int,
        dictionaryId: json['dictionary_id'] as int,
        text: json['text'] as String,
        translation: json['translation'] as String?,
        audioUrl: json['audio_url'] as String?,
        templateKind: (json['template_kind'] as String?) ?? 'ordered_parts',
        parts: [
          for (final p in (json['parts'] as List? ?? const [])) MiniPhrasePart.fromJson(p as Map<String, dynamic>),
        ],
        explanation: [
          for (final s in (json['explanation'] as List? ?? const []))
            MiniPhraseSegment.fromJson(s as Map<String, dynamic>),
        ],
        distractors: [
          for (final d in (json['distractors'] as List? ?? const [])) (d as Map<String, dynamic>)['text'] as String,
        ],
      );

  /// Case and punctuation never matter -- same rule as the server.
  static String normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

  bool isCorrect(List<String> answer) {
    final given = normalize(answer.join(' '));
    return given.isNotEmpty &&
        (given == normalize(text) || given == normalize(parts.map((p) => p.text).join(' ')));
  }
}
