import 'dart:async';

import '../api/api_client.dart';
import '../models/exercise_scoring.dart';
import '../models/lesson_rounds.dart';
import 'media_cache.dart';

/// Which part of a lesson's preparation is running. The screen turns this into
/// words itself, so every label goes through the app's own translation.
enum PrepStage { rounds, media, rules, done }

/// One step of a lesson's preparation, for the screen that shows it.
class PrepStep {
  final PrepStage stage;

  /// 0..1 across the whole preparation.
  final double progress;

  const PrepStep(this.stage, this.progress);
}

/// What a prepared lesson came back with.
class PreparedLesson {
  final LessonRounds rounds;
  final ExerciseScoring scoring;

  /// Pictures and recordings that could not be downloaded. 0 means the lesson
  /// is ready to run with no network at all.
  final int missingMedia;

  const PreparedLesson({required this.rounds, required this.scoring, required this.missingMedia});
}

/// Making one lesson runnable with no network.
///
/// A lesson is created ONLINE (that is the only way the server can decide its
/// words, exercises and season) and then PREPARED: every exercise's round, every
/// picture and recording it will use, and the scoring rules are fetched and kept
/// on the device. From then on the lesson opens instantly and runs to the end
/// offline -- the answers wait on the phone and go to the server when there is a
/// connection again.
///
/// The rules are re-downloaded on every preparation, so a lesson is always
/// scored by the settings in force when it was prepared; the server still
/// recomputes everything it is sent (see [ExerciseScoring]).
class LessonPreparation {
  LessonPreparation._();

  /// Whether this lesson can already open instantly and run offline: its
  /// rounds and the scoring rules are on the device.
  static bool isReady(int lessonId, List<String> exerciseKeys) =>
      ApiClient.instance.cachedExerciseScoring() != null && LessonRounds.fromCache(lessonId, exerciseKeys) != null;

  /// Everything a lesson needs AFTER its rounds: the pictures and recordings it
  /// will show and play, and the scoring rules.
  ///
  /// The media are AWAITED here, unlike the background prefetch a pass does --
  /// after preparation the lesson must work with no connection at all, so
  /// nothing may be left to load later. A file that fails is counted in
  /// [PreparedLesson.missingMedia] rather than thrown: one broken recording must
  /// never block a whole lesson.
  static Future<PreparedLesson> finish(
    LessonRounds rounds, {
    Iterable<String> extraMedia = const [],
    void Function(PrepStep)? onProgress,
  }) async {
    // The mini-phrases played after the words are part of the lesson too, so
    // their recordings are downloaded along with the exercises'.
    final urls = [...rounds.mediaUrls, ...extraMedia].toList();
    onProgress?.call(const PrepStep(PrepStage.media, 0.5));
    final missing = await MediaCache.instance.downloadAll(
      urls,
      onProgress: (done, total) =>
          onProgress?.call(PrepStep(PrepStage.media, total == 0 ? 0.9 : 0.5 + 0.4 * done / total)),
    );

    // Rules last: they are small, and a lesson cannot be scored offline
    // without them.
    onProgress?.call(const PrepStep(PrepStage.rules, 0.95));
    final scoring = await ApiClient.instance.fetchExerciseScoring();
    onProgress?.call(const PrepStep(PrepStage.done, 1));
    return PreparedLesson(rounds: rounds, scoring: scoring, missingMedia: missing);
  }

  /// Makes playback read the lesson's media from the device instead of the
  /// network. Cheap and silent: called when a prepared lesson starts, so its
  /// recordings still play after the app was closed (the files are on disk, but
  /// the player's map is rebuilt on every launch).
  static void warmMedia(LessonRounds rounds) => unawaited(MediaCache.instance.warm(rounds.mediaUrls));
}
