/// The recap of a finished season -- mirrors the backend's SummaryOut
/// (GET /season-pass/summary).
class SeasonTitle {
  final String text;
  final String? textTg;
  final String? textUz;
  const SeasonTitle({required this.text, this.textTg, this.textUz});

  factory SeasonTitle.fromJson(Map<String, dynamic> json) =>
      SeasonTitle(text: json['text'] as String, textTg: json['text_tg'] as String?, textUz: json['text_uz'] as String?);
}

class SeasonSummary {
  final int seasonId;
  final String seasonName;
  final String? seasonNameTg;
  final String? seasonNameUz;
  final int xp;
  final int level;
  final int maxLevel;
  final int wordsLearned;
  final int activeDays;
  final int rewardsClaimed;
  final String? rankName;
  final int? seasonPoints;
  final List<String> badges;
  final List<SeasonTitle> titles;

  const SeasonSummary({
    required this.seasonId,
    required this.seasonName,
    this.seasonNameTg,
    this.seasonNameUz,
    required this.xp,
    required this.level,
    required this.maxLevel,
    required this.wordsLearned,
    required this.activeDays,
    required this.rewardsClaimed,
    this.rankName,
    this.seasonPoints,
    this.badges = const [],
    this.titles = const [],
  });

  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
        seasonId: json['season_id'] as int,
        seasonName: json['season_name'] as String,
        seasonNameTg: json['season_name_tg'] as String?,
        seasonNameUz: json['season_name_uz'] as String?,
        xp: json['xp'] as int,
        level: json['level'] as int,
        maxLevel: json['max_level'] as int,
        wordsLearned: json['words_learned'] as int,
        activeDays: json['active_days'] as int,
        rewardsClaimed: json['rewards_claimed'] as int,
        rankName: json['rank_name'] as String?,
        seasonPoints: json['season_points'] as int?,
        badges: (json['badges'] as List<dynamic>? ?? []).cast<String>(),
        titles: (json['titles'] as List<dynamic>? ?? [])
            .map((e) => SeasonTitle.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
