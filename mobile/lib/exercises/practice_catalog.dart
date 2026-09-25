import 'package:flutter/material.dart';
import '../models/dictionary.dart';
import '../screens/build_phrase_by_ear_screen.dart';
import '../screens/build_phrase_screen.dart';
import '../screens/practice_exercise_screen.dart';
import '../screens/practice_matching_screen.dart';
import 'exercise_type.dart';

/// One entry in "Практика": an exercise type plus how to open it.
///
/// The name and the icon are NOT repeated here -- they come from the
/// [ExerciseTypeInfo] this entry points at, the same canonical description
/// «Уроки» already uses, so renaming an exercise or changing its icon is
/// still a one-line change in exercises/exercise_type.dart.
class PracticeExercise {
  final ExerciseTypeInfo type;

  /// One short line about what the user will actually do. Practice is
  /// self-directed, so unlike inside a lesson the user picks blind unless
  /// something says what a name means.
  final String description;

  final WidgetBuilder builder;

  const PracticeExercise({
    required this.type,
    required this.description,
    required this.builder,
  });
}

/// Everything "Практика" offers, in display order.
///
/// This list IS the extension point: a new practice exercise is a new
/// [ExerciseTypeInfo] in exercise_type.dart plus one entry here, and the
/// screen picks it up with no changes to its layout, its grid or any
/// widget -- nothing anywhere counts these or assumes which ones exist.
///
/// The 5 word-scoped types (true_or_false, matching, build_word,
/// speaking_word, listen_word) lead the list because they are the same
/// canonical set «Уроки» offers, in the same order -- each one here opens
/// the EXACT SAME widget a Lesson (or a Quest) does for that type, just
/// fed a random sample of "Мои изученные слова" instead of a lesson's
/// fixed word set or a quest's one target (see backend/app/routers/
/// practice.py). No new exercise implementation exists for Практика.
List<PracticeExercise> practiceExercises(GuyoDictionary dictionary) => [
      PracticeExercise(
        type: trueOrFalseExerciseType,
        description: 'Определите, правильно ли показан перевод слова',
        builder: (_) => PracticeExerciseScreen(dictionary: dictionary, type: trueOrFalseExerciseType),
      ),
      PracticeExercise(
        type: matchingExerciseType,
        description: 'Соедините слова с их переводами',
        builder: (_) => PracticeMatchingScreen(dictionary: dictionary),
      ),
      PracticeExercise(
        type: buildWordExerciseType,
        description: 'Соберите слово по переводу из букв',
        builder: (_) => PracticeExerciseScreen(dictionary: dictionary, type: buildWordExerciseType),
      ),
      PracticeExercise(
        type: speakingWordExerciseType,
        description: 'Произнесите слово вслух',
        builder: (_) => PracticeExerciseScreen(dictionary: dictionary, type: speakingWordExerciseType),
      ),
      PracticeExercise(
        type: listenWordExerciseType,
        description: 'Прослушайте слово и выберите его среди вариантов',
        builder: (_) => PracticeExerciseScreen(dictionary: dictionary, type: listenWordExerciseType),
      ),
      PracticeExercise(
        type: buildPhraseExerciseType,
        description: 'Восстановите пропущенное слово по переводу',
        builder: (_) => BuildPhraseScreen(dictionary: dictionary),
      ),
      PracticeExercise(
        type: buildPhraseByEarExerciseType,
        description: 'Прослушайте фразу и соберите её из слов',
        builder: (_) => BuildPhraseByEarScreen(dictionary: dictionary),
      ),
    ];
