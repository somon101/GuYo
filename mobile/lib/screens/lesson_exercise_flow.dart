import 'package:flutter/material.dart';

import '../widgets/skeleton.dart';

/// What every exercise inside a lesson does when its round is over: hand
/// control straight back to the lesson runner.
///
/// A lesson is ONE continuous run on ONE screen (LessonRunScreen): its
/// exercises replace each other in place, so the user never sees the
/// lesson's word list, a menu, or any other screen between them. An
/// exercise's only job is to play its round over the lesson's words and
/// then say it is done, so the next exercise starts by itself.
///
/// That is why there is deliberately no per-exercise completion screen --
/// no "Упражнение завершено!", no "Играть ещё раз", no "К уроку", no manual
/// step of any kind between exercises. The one completion screen in a
/// lesson is LessonResultsScreen, shown once, after every available
/// exercise has been through every word.
///
/// Repeating is a property of the LESSON, not of one exercise: if some
/// words are still short of their level, the results screen offers
/// "Повторить урок", and the whole sequence runs again -- covering only
/// the words that still need it.
mixin LessonExerciseFlow<T extends StatefulWidget> on State<T> {
  bool _finished = false;

  /// Ends this exercise. Safe to call from anywhere, including twice: only
  /// the first call counts, so a round that finishes while the hand-off is
  /// already in flight can never skip the next exercise.
  ///
  /// Inside a LessonRunScreen this tells the runner, which swaps in the
  /// next exercise on the same screen. Anywhere else (an exercise pushed
  /// as a route of its own) it pops, as before.
  ///
  /// [skippedBecause] is for an exercise that could not run at all (a
  /// device with no speech recognition, say). The lesson still moves on --
  /// a blocked exercise must never stall the run -- but the user is told
  /// why in passing, rather than being left wondering why a step flashed
  /// by. A message, never a screen or a button.
  void finishExercise({String? skippedBecause}) {
    if (_finished || !mounted) return;
    _finished = true;

    if (skippedBecause != null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(skippedBecause), duration: const Duration(milliseconds: 2200)),
      );
    }

    final scope = LessonRunScope.maybeOf(context);
    if (scope != null) {
      scope.onExerciseFinished();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  /// Whether [finishExercise] has already run -- what `build` checks so it
  /// never tries to render an item past the end of a finished round during
  /// the frame between the call and the next exercise actually appearing.
  bool get isFinishing => _finished;
}

/// Put above the current exercise by LessonRunScreen: how an exercise's
/// [LessonExerciseFlow.finishExercise] reaches the runner without knowing
/// anything about it.
class LessonRunScope extends InheritedWidget {
  final VoidCallback onExerciseFinished;

  const LessonRunScope({super.key, required this.onExerciseFinished, required super.child});

  static LessonRunScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<LessonRunScope>();

  @override
  bool updateShouldNotify(LessonRunScope oldWidget) => false;
}

/// The neutral frame an exercise shows in the instant between its round
/// ending and the next exercise appearing. Not a completion screen: it
/// carries no result, no buttons and nothing to read -- it exists only so
/// the last frame isn't an empty or half-built layout.
class LessonExerciseHandoff extends StatelessWidget {
  const LessonExerciseHandoff({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonExercise();
  }
}
