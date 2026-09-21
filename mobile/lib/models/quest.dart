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

  AvailableQuest({
    required this.id,
    required this.name,
    required this.wordLevelName,
    required this.exerciseKey,
    required this.rewardPoints,
    required this.available,
  });

  factory AvailableQuest.fromJson(Map<String, dynamic> json) {
    return AvailableQuest(
      id: json['id'] as int,
      name: json['name'] as String,
      wordLevelName: json['word_level_name'] as String,
      exerciseKey: json['exercise_key'] as String,
      rewardPoints: json['reward_points'] as int,
      available: json['available'] as bool,
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
