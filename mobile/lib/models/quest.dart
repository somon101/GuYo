import 'user_rating.dart';

/// Quests: a system entirely separate from achievements/rating's own
/// models -- mirrors the backend's AvailableQuestOut/QuestRoundOut/
/// QuestAnswerOut exactly. The backend decides eligibility, round content,
/// and the reward; this screen only renders what it's given and reports
/// {word_id, is_correct}, same principle every exercise already follows.
class AvailableQuest {
  final int id;
  final String name;
  final String wordLevelName;
  final String exerciseKey;
  final int rewardPoints;
  final bool available;

  /// How many successful attempts count as "done for today" (the admin's
  /// own per-quest setting), how many the user has actually made since the
  /// daily reset, and whether that target is met. All three come straight
  /// from the backend -- the client never counts completions itself.
  final int dailyTarget;
  final int completedToday;
  final bool isDoneToday;

  AvailableQuest({
    required this.id,
    required this.name,
    required this.wordLevelName,
    required this.exerciseKey,
    required this.rewardPoints,
    required this.available,
    required this.dailyTarget,
    required this.completedToday,
    required this.isDoneToday,
  });

  factory AvailableQuest.fromJson(Map<String, dynamic> json) {
    return AvailableQuest(
      id: json['id'] as int,
      name: json['name'] as String,
      wordLevelName: json['word_level_name'] as String,
      exerciseKey: json['exercise_key'] as String,
      rewardPoints: json['reward_points'] as int,
      available: json['available'] as bool,
      dailyTarget: json['daily_target'] as int,
      completedToday: json['completed_today'] as int,
      isDoneToday: json['is_done_today'] as bool,
    );
  }
}

/// The season a user is currently playing, as the quests section shows it.
/// Mirrors the backend's SeasonOut: `iconUrl` is the picture an admin
/// uploaded in the season settings, and is the ONLY season image the app
/// ever renders.
class QuestSeason {
  final int id;
  final String name;
  final String? iconUrl;
  final DateTime startsAt;
  final DateTime? endsAt;

  QuestSeason({
    required this.id,
    required this.name,
    required this.iconUrl,
    required this.startsAt,
    required this.endsAt,
  });

  factory QuestSeason.fromJson(Map<String, dynamic> json) {
    return QuestSeason(
      id: json['id'] as int,
      name: json['name'] as String,
      iconUrl: json['icon_url'] as String?,
      startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
      endsAt: json['ends_at'] == null ? null : DateTime.parse(json['ends_at'] as String).toLocal(),
    );
  }
}

/// Everything the "Квесты сезона" block on Главная and the season quests
/// screen render, in one round trip -- mirrors the backend's
/// SeasonQuestOverviewOut.
///
/// Every number here is the backend's own: the season comes from the
/// season system, the rank position is the same one the Profile screen
/// shows, the points are counted from the rating ledgers, and quest
/// progress is counted from the quest completions themselves. This screen
/// computes none of it and holds no second copy of it.
class SeasonQuestOverview {
  final QuestSeason? season;

  /// The season's own timeline, both already rounded by the backend:
  /// whole days left, and how many whole days the season runs in total.
  /// Both null when the season has no scheduled end -- then there is
  /// neither a countdown nor a range to draw. Deliberately separate from
  /// quest progress below: the two mean different things and must never
  /// share a bar.
  final int? daysLeft;
  final int? daysTotal;

  /// Rating points earned today: newly learned words plus quest rewards.
  final int pointsToday;
  final int totalPoints;
  final RankSummary? rank;

  /// The user's real place within their own rank.
  final int? rankPosition;

  final int questsDoneToday;
  final int questsTotal;

  /// The permanent "изучение новых слов" quest: what one newly learned
  /// word is worth right now, and how many were learned today.
  final int pointsPerLearnedWord;
  final int wordsLearnedToday;

  final List<AvailableQuest> quests;

  SeasonQuestOverview({
    required this.season,
    required this.daysLeft,
    required this.daysTotal,
    required this.pointsToday,
    required this.totalPoints,
    required this.rank,
    required this.rankPosition,
    required this.questsDoneToday,
    required this.questsTotal,
    required this.pointsPerLearnedWord,
    required this.wordsLearnedToday,
    required this.quests,
  });

  factory SeasonQuestOverview.fromJson(Map<String, dynamic> json) {
    return SeasonQuestOverview(
      season: json['season'] == null ? null : QuestSeason.fromJson(json['season'] as Map<String, dynamic>),
      daysLeft: json['days_left'] as int?,
      daysTotal: json['days_total'] as int?,
      pointsToday: json['points_today'] as int,
      totalPoints: json['total_points'] as int,
      rank: json['rank'] == null ? null : RankSummary.fromJson(json['rank'] as Map<String, dynamic>),
      rankPosition: json['rank_position'] as int?,
      questsDoneToday: json['quests_done_today'] as int,
      questsTotal: json['quests_total'] as int,
      pointsPerLearnedWord: json['points_per_learned_word'] as int,
      wordsLearnedToday: json['words_learned_today'] as int,
      quests: (json['quests'] as List<dynamic>)
          .map((e) => AvailableQuest.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// `payload` is the SAME round shape Lessons already use for this
/// exercise_key (ExerciseWordsOut / TrueOrFalseRoundOut / BuildWordRoundOut
/// / SpeakingWordRoundOut / ListenWordRoundOut) -- QuestAttemptScreen parses
/// it with the exact same model classes the Lesson screens already use.
class QuestRound {
  final int questId;
  final int wordId;
  final String exerciseKey;
  final Map<String, dynamic> payload;

  QuestRound({required this.questId, required this.wordId, required this.exerciseKey, required this.payload});

  factory QuestRound.fromJson(Map<String, dynamic> json) {
    return QuestRound(
      questId: json['quest_id'] as int,
      wordId: json['word_id'] as int,
      exerciseKey: json['exercise_key'] as String,
      payload: json['payload'] as Map<String, dynamic>,
    );
  }
}

class QuestAnswerResult {
  final int wordId;
  final int score;
  final bool isCorrect;
  final int rewardGranted;

  QuestAnswerResult({required this.wordId, required this.score, required this.isCorrect, required this.rewardGranted});

  factory QuestAnswerResult.fromJson(Map<String, dynamic> json) {
    return QuestAnswerResult(
      wordId: json['word_id'] as int,
      score: json['score'] as int,
      isCorrect: json['is_correct'] as bool,
      rewardGranted: json['reward_granted'] as int,
    );
  }
}
