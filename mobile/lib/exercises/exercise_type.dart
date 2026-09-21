import 'package:flutter/material.dart';

/// One exercise type's identity: its key (matches the backend's
/// exercise_key exactly, see backend/app/exercises/), display label and
/// icon. The SAME entry is used everywhere this exercise type can be
/// launched from -- today "Уроки" (LessonDetailScreen) for the five
/// word-based types, and "Практика" (PracticeScreen) for the two
/// phrase-based ones -- so a label/icon change is made once, and a future
/// context (Practice, a future Test mode, ...) reusing an existing type
/// never needs its own copy of this metadata.
///
/// This mirrors, on the client, the same principle the backend's
/// app/exercises/__init__.py registry follows: one canonical description
/// of "what this exercise type is" that every caller looks up instead of
/// hardcoding its own list.
class ExerciseTypeInfo {
  final String key;
  final String label;
  final IconData icon;
  const ExerciseTypeInfo({required this.key, required this.label, required this.icon});
}

const trueOrFalseExerciseType = ExerciseTypeInfo(
  key: 'true_or_false',
  label: 'Правда или ложь',
  icon: Icons.rule_outlined,
);
const matchingExerciseType = ExerciseTypeInfo(
  key: 'matching',
  label: 'Сопоставление',
  icon: Icons.extension_outlined,
);
const buildWordExerciseType = ExerciseTypeInfo(
  key: 'build_word',
  label: 'Собери слово',
  icon: Icons.abc_outlined,
);
const speakingWordExerciseType = ExerciseTypeInfo(
  key: 'speaking_word',
  label: 'Произнеси слово 🎙️',
  icon: Icons.mic_rounded,
);
const listenWordExerciseType = ExerciseTypeInfo(
  key: 'listen_word',
  label: 'Услышь слово 🔊',
  icon: Icons.hearing_rounded,
);
const buildPhraseExerciseType = ExerciseTypeInfo(
  key: 'build_phrase',
  label: 'Собери фразу',
  icon: Icons.text_fields_rounded,
);
const buildPhraseByEarExerciseType = ExerciseTypeInfo(
  key: 'build_phrase_by_ear',
  label: 'Собери фразу на слух',
  icon: Icons.headphones_rounded,
);

/// Every exercise type a Lesson can include, keyed exactly like the
/// backend's LessonOut.exercise_keys -- LessonDetailScreen looks itself up
/// in here instead of keeping its own separate label/icon map.
const Map<String, ExerciseTypeInfo> lessonExerciseTypes = {
  'true_or_false': trueOrFalseExerciseType,
  'matching': matchingExerciseType,
  'build_word': buildWordExerciseType,
  'speaking_word': speakingWordExerciseType,
  'listen_word': listenWordExerciseType,
};
