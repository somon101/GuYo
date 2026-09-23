/// The Profile screen's "Рейтинг" block -- a system entirely separate from
/// achievements (see UserAchievement in user_profile.dart): different
/// backend tables, different admin section, never cross-referenced. Mirrors
/// UserRatingOut exactly; the backend decides everything here (current
/// rank, progress to the next one, season history) -- this screen only
/// renders it.
class RankSummary {
  final int id;
  final String name;
  final String? iconUrl;
  final String color;
  final int minPoints;
  final int? maxPoints;

  RankSummary({
    required this.id,
    required this.name,
    required this.iconUrl,
    required this.color,
    required this.minPoints,
    required this.maxPoints,
  });

  factory RankSummary.fromJson(Map<String, dynamic> json) {
    return RankSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      iconUrl: json['icon_url'] as String?,
      color: json['color'] as String,
      minPoints: json['min_points'] as int,
      maxPoints: json['max_points'] as int?,
    );
  }
}

class RatingSeason {
  final int id;
  final String name;
  final String status;

  RatingSeason({required this.id, required this.name, required this.status});

  factory RatingSeason.fromJson(Map<String, dynamic> json) {
    return RatingSeason(id: json['id'] as int, name: json['name'] as String, status: json['status'] as String);
  }
}

class SeasonHistoryEntry {
  final int seasonId;
  final String seasonName;
  final int points;
  final RankSummary? rank;
  final DateTime endedAt;

  SeasonHistoryEntry({
    required this.seasonId,
    required this.seasonName,
    required this.points,
    required this.rank,
    required this.endedAt,
  });

  factory SeasonHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SeasonHistoryEntry(
      seasonId: json['season_id'] as int,
      seasonName: json['season_name'] as String,
      points: json['points'] as int,
      rank: json['rank'] == null ? null : RankSummary.fromJson(json['rank'] as Map<String, dynamic>),
      endedAt: DateTime.parse(json['ended_at'] as String),
    );
  }
}

/// One row of a leaderboard -- mirrors LeaderboardEntryOut. `rank` is only
/// populated on the global board (every row of the own-rank board shares
/// the same rank the screen already shows once, at the top).
class LeaderboardEntry {
  final int position;
  final int userId;
  final String login;
  final String? avatarUrl;
  final int totalPoints;
  final RankSummary? rank;
  final bool isMe;

  LeaderboardEntry({
    required this.position,
    required this.userId,
    required this.login,
    required this.avatarUrl,
    required this.totalPoints,
    required this.rank,
    required this.isMe,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      position: json['position'] as int,
      userId: json['user_id'] as int,
      login: json['login'] as String,
      avatarUrl: json['avatar_url'] as String?,
      totalPoints: json['total_points'] as int,
      rank: json['rank'] == null ? null : RankSummary.fromJson(json['rank'] as Map<String, dynamic>),
      isMe: json['is_me'] as bool,
    );
  }
}

/// `rank` is the CALLER's own current rank for the own-rank board (never
/// user-chosen -- see ApiClient.fetchMyRankLeaderboard), and always null
/// for the global board, which has no single rank of its own.
class Leaderboard {
  final RankSummary? rank;
  final List<LeaderboardEntry> entries;

  Leaderboard({required this.rank, required this.entries});

  factory Leaderboard.fromJson(Map<String, dynamic> json) {
    return Leaderboard(
      rank: json['rank'] == null ? null : RankSummary.fromJson(json['rank'] as Map<String, dynamic>),
      entries: (json['entries'] as List<dynamic>).map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class UserRating {
  final int totalPoints;
  final RatingSeason? season;
  final RankSummary? rank;
  final RankSummary? nextRank;
  final int? pointsToNextRank;
  final List<SeasonHistoryEntry> history;

  /// The same reward award_word_points_if_new grants on every newly-learned
  /// word -- shown as-is on the Квесты screen's permanent "изучение новых
  /// слов" system tile, never a second, quest-specific setting.
  final int pointsPerLearnedWord;

  /// This user's own real 1-based place among everyone currently in the
  /// SAME rank -- the exact position the own-rank leaderboard would show
  /// them at, never capped at its top-100. Null when they have no rank.
  final int? rankPosition;

  UserRating({
    required this.totalPoints,
    required this.season,
    required this.rank,
    required this.nextRank,
    required this.pointsToNextRank,
    required this.history,
    required this.pointsPerLearnedWord,
    required this.rankPosition,
  });

  factory UserRating.fromJson(Map<String, dynamic> json) {
    return UserRating(
      totalPoints: json['total_points'] as int,
      season: json['season'] == null ? null : RatingSeason.fromJson(json['season'] as Map<String, dynamic>),
      rank: json['rank'] == null ? null : RankSummary.fromJson(json['rank'] as Map<String, dynamic>),
      nextRank: json['next_rank'] == null ? null : RankSummary.fromJson(json['next_rank'] as Map<String, dynamic>),
      pointsToNextRank: json['points_to_next_rank'] as int?,
      history: (json['history'] as List<dynamic>)
          .map((e) => SeasonHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      pointsPerLearnedWord: json['points_per_learned_word'] as int,
      rankPosition: json['rank_position'] as int?,
    );
  }
}
