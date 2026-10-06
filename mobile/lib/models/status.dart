/// Leaderboard statuses: GuYo's own emoji pictures and admin-written
/// phrases a user picks from (backend app/models/status.py).
class StatusEmojiOption {
  final int id;
  final String name;
  final String? imageUrl;

  StatusEmojiOption({required this.id, required this.name, required this.imageUrl});

  factory StatusEmojiOption.fromJson(Map<String, dynamic> json) => StatusEmojiOption(
        id: json['id'] as int,
        name: json['name'] as String,
        imageUrl: json['image_url'] as String?,
      );
}

class StatusPhraseOption {
  final int id;
  final String text;

  StatusPhraseOption({required this.id, required this.text});

  factory StatusPhraseOption.fromJson(Map<String, dynamic> json) =>
      StatusPhraseOption(id: json['id'] as int, text: json['text'] as String);
}

/// The user's status as everyone sees it; a part is null when unset.
class MyStatus {
  final int? emojiId;
  final String? emojiUrl;
  final int? phraseId;
  final String? text;

  MyStatus({this.emojiId, this.emojiUrl, this.phraseId, this.text});

  bool get isEmpty => emojiId == null && phraseId == null;

  factory MyStatus.fromJson(Map<String, dynamic> json) => MyStatus(
        emojiId: json['emoji_id'] as int?,
        emojiUrl: json['emoji_url'] as String?,
        phraseId: json['phrase_id'] as int?,
        text: json['text'] as String?,
      );
}

class StatusOptions {
  final List<StatusEmojiOption> emojis;
  final List<StatusPhraseOption> phrases;
  final MyStatus mine;

  StatusOptions({required this.emojis, required this.phrases, required this.mine});

  factory StatusOptions.fromJson(Map<String, dynamic> json) => StatusOptions(
        emojis: (json['emojis'] as List<dynamic>)
            .map((e) => StatusEmojiOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        phrases: (json['phrases'] as List<dynamic>)
            .map((e) => StatusPhraseOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        mine: MyStatus.fromJson(json['mine'] as Map<String, dynamic>),
      );
}
