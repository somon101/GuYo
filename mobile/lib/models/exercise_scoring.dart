/// The rules behind every number a lesson shows, so the phone can score a
/// lesson by itself when there is no network.
///
/// Downloaded when a lesson is PREPARED (so it always reflects the admin's
/// settings at that moment) and kept on the device. The server still recomputes
/// every score from the answers it is sent -- see the backend's
/// `/exercises/scoring` and `submit_answer` -- so these numbers decide only
/// what the user sees immediately; the authoritative result always comes back
/// from the server and replaces them.
class ExerciseScoring {
  /// exercise key -> what a right and a wrong answer do to a word's score.
  final Map<String, ({int correct, int incorrect})> points;

  /// The score a word needs to count as learned (the top enabled level).
  final int threshold;

  const ExerciseScoring({required this.points, required this.threshold});

  /// The fallback mirror of the backend's own DEFAULT_POINTS, used only when
  /// the rules could not be downloaded at all -- an exercise must still score
  /// something rather than nothing.
  static const ExerciseScoring fallback = ExerciseScoring(
    points: {
      'true_or_false': (correct: 10, incorrect: 5),
      'matching': (correct: 20, incorrect: 10),
      'build_word': (correct: 30, incorrect: 15),
      'speaking_word': (correct: 15, incorrect: 5),
      'listen_word': (correct: 15, incorrect: 5),
    },
    threshold: 100,
  );

  ({int correct, int incorrect}) forExercise(String key) =>
      points[key] ?? const (correct: 10, incorrect: 5);

  factory ExerciseScoring.fromJson(Map<String, dynamic> json) {
    final raw = json['points'] as Map<String, dynamic>? ?? const {};
    return ExerciseScoring(
      points: {
        for (final entry in raw.entries)
          entry.key: (
            correct: (entry.value as Map<String, dynamic>)['correct'] as int? ?? 10,
            incorrect: (entry.value as Map<String, dynamic>)['incorrect'] as int? ?? 5,
          ),
      },
      threshold: json['threshold'] as int? ?? 100,
    );
  }
}
