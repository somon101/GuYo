import 'package:flutter/material.dart';
import '../models/dictionary.dart';
import '../screens/build_phrase_by_ear_screen.dart';
import '../screens/build_phrase_screen.dart';
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
List<PracticeExercise> practiceExercises(GuyoDictionary dictionary) => [
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
