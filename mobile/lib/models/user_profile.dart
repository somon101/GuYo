/// The current user's own profile: their permanent `id` (never `login`,
/// which is only credentials/display text), and their avatar -- a real
/// uploaded photo's URL, or null when the UI should render its own
/// generated default avatar instead. Mirrors the backend's UserProfileOut
/// exactly.
class UserProfile {
  final int id;
  final String login;
  final String? avatarUrl;

  UserProfile({required this.id, required this.login, required this.avatarUrl});

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      login: json['login'] as String,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

/// One achievement as shown in the Profile screen: the definition (title/
/// description/icon/condition) plus THIS user's own status against it --
/// earned or not, and (while not yet earned) their current progress, all
/// decided entirely by the backend. Mirrors UserAchievementOut exactly.
class UserAchievement {
  final int id;
  final String title;
  final String description;
  final String icon;
  final String conditionType;
  final int conditionValue;
  final bool earned;
  final DateTime? earnedAt;
  final int currentValue;

  UserAchievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.conditionType,
    required this.conditionValue,
    required this.earned,
    required this.earnedAt,
    required this.currentValue,
  });

  factory UserAchievement.fromJson(Map<String, dynamic> json) {
    return UserAchievement(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String,
      conditionType: json['condition_type'] as String,
      conditionValue: json['condition_value'] as int,
      earned: json['earned'] as bool,
      earnedAt: json['earned_at'] == null ? null : DateTime.parse(json['earned_at'] as String),
      currentValue: json['current_value'] as int,
    );
  }
}
