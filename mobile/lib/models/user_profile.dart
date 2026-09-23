/// The current user's own profile: their permanent `id` (never `login`,
/// which is only credentials/display text), their avatar -- a real
/// uploaded photo's URL, or null when the UI should render its own
/// generated default avatar instead -- and their current activity streak.
/// Both the avatar and the streak live entirely on the backend (Postgres),
/// never only on this device: logging in from a different phone returns
/// the exact same values. Mirrors the backend's UserProfileOut exactly.
class UserProfile {
  final int id;
  final String login;
  final String? avatarUrl;
  final int currentStreakDays;
  // The same counters the "Уроки"/"Слова" achievement condition_types are
  // measured against (app/achievements/conditions.py) -- never a second,
  // profile-only way of counting either one.
  final int lessonsCompleted;
  final int wordsLearned;

  UserProfile({
    required this.id,
    required this.login,
    required this.avatarUrl,
    required this.currentStreakDays,
    required this.lessonsCompleted,
    required this.wordsLearned,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      login: json['login'] as String,
      avatarUrl: json['avatar_url'] as String?,
      currentStreakDays: json['current_streak_days'] as int,
      lessonsCompleted: json['lessons_completed'] as int,
      wordsLearned: json['words_learned'] as int,
    );
  }
}

/// One achievement as shown in the Profile screen: the definition (title/
/// description/icon/color/condition) plus THIS user's own status against
/// it -- earned or not, and (while not yet earned) their current progress,
/// all decided entirely by the backend. Mirrors UserAchievementOut exactly.
///
/// `title`/`description`/`conditionType`/`conditionValue`/`currentValue`
/// come back null for an achievement that's hidden and not yet earned --
/// the backend itself withholds the condition, not just this screen's
/// styling (see app/routers/users.py). `isLocked` is true exactly when
/// that's the case, and is this class's own signal for rendering the
/// generic mystery tile -- never re-derived from anything achievement-
/// specific, since the whole point is that nothing specific is known yet.
class UserAchievement {
  final int id;
  final String? title;
  final String? description;
  final String? iconUrl;
  final String color;
  final String? conditionType;
  final int? conditionValue;
  final bool earned;
  final DateTime? earnedAt;
  final int? currentValue;

  bool get isLocked => !earned && title == null;

  UserAchievement({
    required this.id,
    required this.title,
    required this.description,
    required this.iconUrl,
    required this.color,
    required this.conditionType,
    required this.conditionValue,
    required this.earned,
    required this.earnedAt,
    required this.currentValue,
  });

  factory UserAchievement.fromJson(Map<String, dynamic> json) {
    return UserAchievement(
      id: json['id'] as int,
      title: json['title'] as String?,
      description: json['description'] as String?,
      iconUrl: json['icon_url'] as String?,
      color: json['color'] as String,
      conditionType: json['condition_type'] as String?,
      conditionValue: json['condition_value'] as int?,
      earned: json['earned'] as bool,
      earnedAt: json['earned_at'] == null ? null : DateTime.parse(json['earned_at'] as String),
      currentValue: json['current_value'] as int?,
    );
  }
}
