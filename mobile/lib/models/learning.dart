import 'word.dart';

/// Mirrors the backend's LearningSessionOut exactly. `currentWord` reuses
/// the existing GuyoWord model -- the learning card is the same Word card
/// used everywhere else, never a separate copy.
class LearningSession {
  final int id;
  final int dictionaryId;
  final int totalCount;
  final int remainingCount;
  final int learnedCount;
  final bool isCompleted;
  final GuyoWord? currentWord;

  LearningSession({
    required this.id,
    required this.dictionaryId,
    required this.totalCount,
    required this.remainingCount,
    required this.learnedCount,
    required this.isCompleted,
    required this.currentWord,
  });

  factory LearningSession.fromJson(Map<String, dynamic> json) {
    return LearningSession(
      id: json['id'] as int,
      dictionaryId: json['dictionary_id'] as int,
      totalCount: json['total_count'] as int,
      remainingCount: json['remaining_count'] as int,
      learnedCount: json['learned_count'] as int,
      isCompleted: json['is_completed'] as bool,
      currentWord: json['current_word'] == null
          ? null
          : GuyoWord.fromJson(json['current_word'] as Map<String, dynamic>),
    );
  }
}

class LearnedCategory {
  final int? categoryId;
  final String categoryName;
  final int learnedCount;
  /// The category's own picture, uploaded by an admin (see the backend's
  /// Category.icon_key). Null both for "Без категории" and for a real
  /// category whose icon nobody has set yet -- the client draws its own
  /// generic folder icon in either case.
  final String? iconUrl;

  LearnedCategory({
    required this.categoryId,
    required this.categoryName,
    required this.learnedCount,
    this.iconUrl,
  });

  factory LearnedCategory.fromJson(Map<String, dynamic> json) {
    return LearnedCategory(
      categoryId: json['category_id'] as int?,
      categoryName: json['category_name'] as String,
      learnedCount: json['learned_count'] as int,
      iconUrl: json['icon_url'] as String?,
    );
  }
}
