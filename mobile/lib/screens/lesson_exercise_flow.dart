import 'package:flutter/material.dart';

/// Connects an exercise to the lesson run hosting it (LessonRunScreen):
/// the run plays every exercise in place, inside one screen, and this is
/// how an exercise tells it "my round is over, show the next one".
class LessonRunScope extends InheritedWidget {
  final VoidCallback onExerciseFinished;

  const LessonRunScope({super.key, required this.onExerciseFinished, required super.child});

  static LessonRunScope of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LessonRunScope>();
    assert(scope != null, 'A lesson exercise must be shown inside LessonRunScreen');
    return scope!;
  }

  @override
  bool updateShouldNotify(LessonRunScope oldWidget) => onExerciseFinished != oldWidget.onExerciseFinished;
}

/// What every exercise inside a lesson does when its round is over: hand
/// control straight back to the lesson run.
///
/// A lesson is ONE continuous run. LessonRunScreen walks the lesson's
/// available exercises in order and swaps each one in, in place; an
/// exercise's only job is to play its round over the lesson's words and
/// then report that it's done, so the next exercise starts by itself --
/// the user never lands back on the lesson's word list in between.
///
/// That is why there is deliberately no per-exercise completion screen --
/// no "Упражнение завершено!", no "Играть ещё раз", no "К уроку", no
/// manual step of any kind between exercises. The one completion screen
/// in a lesson is LessonResultsScreen, shown once, after every available
/// exercise has been through every word.
///
/// Repeating is a property of the LESSON, not of one exercise: if some
/// words are still short of their level, the results screen offers
/// "Повторить урок", and the whole sequence runs again -- covering only
/// the words that still need it, since every round re-fetches what is
/// actually pending.
mixin LessonExerciseFlow<T extends StatefulWidget> on State<T> {
  bool _finished = false;

  /// Ends this exercise. Safe to call from anywhere, including twice: only
  /// the first call reports, so a round that finishes while the handoff is
  /// already under way can never make the run skip an exercise.
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

    LessonRunScope.of(context).onExerciseFinished();
  }

  /// Whether [finishExercise] has already run -- what `build` checks so it
  /// never tries to render an item past the end of a finished round during
  /// the frame between the call and the next exercise replacing this one.
  bool get isFinishing => _finished;
}

/// The neutral frame shown in the instant between one exercise ending and
/// the next appearing. Not a completion screen: it carries no result, no
/// buttons and nothing to read.
class LessonExerciseHandoff extends StatelessWidget {
  const LessonExerciseHandoff({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
