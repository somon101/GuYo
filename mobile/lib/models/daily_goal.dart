import 'reward_spec.dart';

/// Today's progress towards the daily word goal (GET /daily-goal).
class DailyGoal {
  final int goal;
  final int done;
  final bool completed;
  final bool justCompleted;
  final int xp;
  final List<int> options;
  final bool locked;
  final bool rewardReady;
  final int? claimId;
  final List<String> chests;
  final int diamonds;
  final int points;
  final Map<int, List<RewardSpec>> tiers;

  const DailyGoal({
    required this.goal,
    required this.done,
    required this.completed,
    this.justCompleted = false,
    this.xp = 0,
    this.options = const [5, 10, 20],
    this.locked = false,
    this.rewardReady = false,
    this.claimId,
    this.chests = const [],
    this.diamonds = 0,
    this.points = 0,
    this.tiers = const {},
  });

  factory DailyGoal.fromJson(Map<String, dynamic> json) => DailyGoal(
        goal: json['goal'] as int,
        done: json['done'] as int,
        completed: json['completed'] as bool,
        justCompleted: (json['just_completed'] as bool?) ?? false,
        xp: (json['xp'] as int?) ?? 0,
        chests: ((json['chests'] as List<dynamic>?) ?? const []).cast<String>(),
        diamonds: (json['diamonds'] as int?) ?? 0,
        points: (json['points'] as int?) ?? 0,
        tiers: {
          for (final t in (json['tiers'] as List<dynamic>? ?? const []))
            (t as Map<String, dynamic>)['words'] as int: RewardSpec.list(t['rewards']),
        },
        locked: (json['locked'] as bool?) ?? (json['completed'] as bool),
        rewardReady: (json['reward_ready'] as bool?) ?? false,
        claimId: json['claim_id'] as int?,
        options: ((json['options'] as List<dynamic>?) ?? const [5, 10, 20]).cast<int>(),
      );
}
