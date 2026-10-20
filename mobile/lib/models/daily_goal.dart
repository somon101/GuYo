/// Today's progress towards the daily word goal (GET /daily-goal).
class DailyGoal {
  final int goal;
  final int done;
  final bool completed;
  final bool justCompleted;
  final int xp;
  final List<int> options;

  const DailyGoal({
    required this.goal,
    required this.done,
    required this.completed,
    this.justCompleted = false,
    this.xp = 0,
    this.options = const [5, 10, 20],
  });

  factory DailyGoal.fromJson(Map<String, dynamic> json) => DailyGoal(
        goal: json['goal'] as int,
        done: json['done'] as int,
        completed: json['completed'] as bool,
        justCompleted: (json['just_completed'] as bool?) ?? false,
        xp: (json['xp'] as int?) ?? 0,
        options: ((json['options'] as List<dynamic>?) ?? const [5, 10, 20]).cast<int>(),
      );
}
