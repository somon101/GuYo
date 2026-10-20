/// «Мой путь»: learning per week (GET /users/me/progress).
class ProgressWeek {
  final DateTime weekStart;
  final int words;
  final int activeDays;
  const ProgressWeek({required this.weekStart, required this.words, required this.activeDays});

  factory ProgressWeek.fromJson(Map<String, dynamic> json) => ProgressWeek(
        weekStart: DateTime.parse(json['week_start'] as String),
        words: json['words'] as int,
        activeDays: json['active_days'] as int,
      );
}

class MyProgress {
  final int totalWords;
  final int totalActiveDays;
  final List<ProgressWeek> weeks;
  const MyProgress({required this.totalWords, required this.totalActiveDays, required this.weeks});

  factory MyProgress.fromJson(Map<String, dynamic> json) => MyProgress(
        totalWords: json['total_words'] as int,
        totalActiveDays: json['total_active_days'] as int,
        weeks: (json['weeks'] as List<dynamic>).map((e) => ProgressWeek.fromJson(e as Map<String, dynamic>)).toList(),
      );

  /// Words learned in the current (last) week and the one before it.
  int get thisWeek => weeks.isEmpty ? 0 : weeks.last.words;
  int get lastWeek => weeks.length < 2 ? 0 : weeks[weeks.length - 2].words;
}
