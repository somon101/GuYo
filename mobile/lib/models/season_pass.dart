/// The season pass -- mirrors the backend's PassOut (GET /season-pass).
class PassReward {
  final String type; // rating_points | premium_days
  final int amount;
  final bool claimed;
  final bool claimable;
  final bool lockedByPremium;

  /// A badge's look (an icon key) and a badge's / title's own name.
  final String? key;
  final String? text;

  const PassReward({
    required this.type,
    required this.amount,
    this.key,
    this.text,
    required this.claimed,
    required this.claimable,
    required this.lockedByPremium,
  });

  factory PassReward.fromJson(Map<String, dynamic> json) => PassReward(
        type: json['type'] as String,
        amount: json['amount'] as int,
        key: json['key'] as String?,
        text: json['text'] as String?,
        claimed: json['claimed'] as bool,
        claimable: json['claimable'] as bool,
        lockedByPremium: (json['locked_by_premium'] as bool?) ?? false,
      );
}

class PassLevel {
  final int level;
  final int xp;
  final PassReward? free;
  final PassReward? premium;

  const PassLevel({required this.level, required this.xp, this.free, this.premium});

  factory PassLevel.fromJson(Map<String, dynamic> json) => PassLevel(
        level: json['level'] as int,
        xp: json['xp'] as int,
        free: json['free'] == null ? null : PassReward.fromJson(json['free'] as Map<String, dynamic>),
        premium: json['premium'] == null ? null : PassReward.fromJson(json['premium'] as Map<String, dynamic>),
      );
}

class PassTask {
  final String id;
  final String metric; // word | lesson | review | quest | streak
  final int target;
  final int xp;
  final int progress;
  final bool claimed;
  final bool claimable;

  const PassTask({
    required this.id,
    required this.metric,
    required this.target,
    required this.xp,
    required this.progress,
    required this.claimed,
    required this.claimable,
  });

  factory PassTask.fromJson(Map<String, dynamic> json) => PassTask(
        id: json['id'] as String,
        metric: json['metric'] as String,
        target: json['target'] as int,
        xp: json['xp'] as int,
        progress: json['progress'] as int,
        claimed: json['claimed'] as bool,
        claimable: json['claimable'] as bool,
      );
}

class SeasonPass {
  final String seasonName;
  final String? seasonNameTg;
  final String? seasonNameUz;
  final DateTime? endsAt;
  final int xp;
  final int level;
  final int xpIntoLevel;
  final int? xpForNext;
  final bool isPremium;
  final bool premiumEnabled;
  final List<PassLevel> levels;
  final DateTime weekEndsAt;
  final List<PassTask> tasks;

  const SeasonPass({
    required this.seasonName,
    this.seasonNameTg,
    this.seasonNameUz,
    this.endsAt,
    required this.xp,
    required this.level,
    required this.xpIntoLevel,
    required this.xpForNext,
    required this.isPremium,
    required this.premiumEnabled,
    required this.levels,
    required this.weekEndsAt,
    required this.tasks,
  });

  /// Rewards waiting to be taken -- the dot on the home card.
  int get claimableCount =>
      levels.fold<int>(0, (n, l) => n + ((l.free?.claimable ?? false) ? 1 : 0) + ((l.premium?.claimable ?? false) ? 1 : 0)) +
      tasks.where((t) => t.claimable).length;

  factory SeasonPass.fromJson(Map<String, dynamic> json) {
    final week = json['week'] as Map<String, dynamic>;
    return SeasonPass(
      seasonName: json['season_name'] as String,
      seasonNameTg: json['season_name_tg'] as String?,
      seasonNameUz: json['season_name_uz'] as String?,
      endsAt: json['ends_at'] == null ? null : DateTime.parse(json['ends_at'] as String).toLocal(),
      xp: json['xp'] as int,
      level: json['level'] as int,
      xpIntoLevel: json['xp_into_level'] as int,
      xpForNext: json['xp_for_next'] as int?,
      isPremium: json['is_premium'] as bool,
      premiumEnabled: json['premium_enabled'] as bool,
      levels: (json['levels'] as List<dynamic>).map((e) => PassLevel.fromJson(e as Map<String, dynamic>)).toList(),
      weekEndsAt: DateTime.parse(week['ends_at'] as String).toLocal(),
      tasks: (week['tasks'] as List<dynamic>).map((e) => PassTask.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// A badge or title earned in a season pass.
class Cosmetic {
  final int id;
  final String kind; // badge | title | frame
  final String key;
  final String label;
  final String? seasonName;

  const Cosmetic({required this.id, required this.kind, required this.key, required this.label, this.seasonName});

  factory Cosmetic.fromJson(Map<String, dynamic> json) => Cosmetic(
        id: json['id'] as int,
        kind: json['kind'] as String,
        key: json['key'] as String,
        label: json['label'] as String,
        seasonName: json['season_name'] as String?,
      );
}

class CosmeticCollection {
  final List<Cosmetic> badges;
  final List<Cosmetic> titles;
  final List<Cosmetic> frames;
  final int? equippedBadgeId;
  final int? equippedTitleId;
  final int? equippedFrameId;

  const CosmeticCollection({
    required this.badges,
    required this.titles,
    this.frames = const [],
    this.equippedBadgeId,
    this.equippedTitleId,
    this.equippedFrameId,
  });

  factory CosmeticCollection.fromJson(Map<String, dynamic> json) => CosmeticCollection(
        badges: (json['badges'] as List<dynamic>).map((e) => Cosmetic.fromJson(e as Map<String, dynamic>)).toList(),
        titles: (json['titles'] as List<dynamic>).map((e) => Cosmetic.fromJson(e as Map<String, dynamic>)).toList(),
        frames: ((json['frames'] as List<dynamic>?) ?? const []).map((e) => Cosmetic.fromJson(e as Map<String, dynamic>)).toList(),
        equippedBadgeId: json['equipped_badge_id'] as int?,
        equippedTitleId: json['equipped_title_id'] as int?,
        equippedFrameId: json['equipped_frame_id'] as int?,
      );
}
