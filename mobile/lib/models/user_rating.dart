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

class UserRating {
  final int totalPoints;
  final RatingSeason? season;
  final RankSummary? rank;
  final RankSummary? nextRank;
  final int? pointsToNextRank;
  final List<SeasonHistoryEntry> history;

  UserRating({
    required this.totalPoints,
    required this.season,
    required this.rank,
    required this.nextRank,
    required this.pointsToNextRank,
    required this.history,
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
    );
  }
}
