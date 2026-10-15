import '../models/user_profile.dart';

/// Achievements this device can already see are earned.
///
/// The server is the one that grants them (app/achievements): it counts the
/// whole account and writes each achievement down once. But a lesson played with
/// no network has not reached it yet, so on its own the phone would show nothing
/// at the end of a lesson -- while the user is looking right at the words they
/// just learned.
///
/// This works out the same conditions from what the phone knows: the profile's
/// counters (which the server sent, so they are short by exactly the work this
/// device has done since) plus this pass's own result. When the pass goes over,
/// the server counts everything itself: what it confirms stays, what it does not
/// confirm simply closes again (see LessonResultsScreen -- nothing is announced
/// about the correction).
class LocalAchievements {
  LocalAchievements._();

  /// [all] = every achievement the server has, worked through with this pass's
  /// own result. Only conditions a lesson can actually move are predicted:
  /// anything else (friends, phrases, quests) waits for the server instead of
  /// guessing.
  static List<UserAchievement> afterLesson({
    required List<UserAchievement> all,
    required UserProfile? profile,
    required int newWordsLearned,
    required int newLessonsCompleted,
    required int newMiniPhrasesDone,
  }) {
    if (profile == null) return const [];
    final predicted = <UserAchievement>[];
    for (final achievement in all) {
      if (achievement.earned) continue;
      final type = achievement.conditionType;
      final target = achievement.conditionValue;
      if (type == null || target == null) continue;
      final int? value = switch (type) {
        'words_learned' => profile.wordsLearned + newWordsLearned,
        'lessons_completed' => profile.lessonsCompleted + newLessonsCompleted,
        // The server's own current value is right here: a lesson's mini-phrases
        // are the only ones this pass can add, and it is what it just went
        // through.
        'mini_phrases_done' => (achievement.currentValue ?? 0) + newMiniPhrasesDone,
        _ => null,
      };
      if (value != null && value >= target) predicted.add(achievement);
    }
    return predicted;
  }
}
