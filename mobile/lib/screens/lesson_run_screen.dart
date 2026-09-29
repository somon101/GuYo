import 'dart:async';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import 'build_word_screen.dart';
import 'lesson_exercise_flow.dart';
import 'lesson_results_screen.dart';
import 'listen_word_screen.dart';
import 'matching_screen.dart';
import 'speaking_word_screen.dart';
import 'true_or_false_screen.dart';

const Map<String, String> _exerciseLabels = {
  'true_or_false': 'Правда или ложь',
  'matching': 'Сопоставление',
  'build_word': 'Собери слово',
  'speaking_word': 'Произнеси слово',
  'listen_word': 'Услышь слово',
};

/// One "Начать урок" run, as ONE screen: every available exercise of the
/// lesson plays inside it, one after another, swapped in place -- the
/// lesson's word list is never shown again until the run is over, so there
/// is no "back to the lesson" between exercises.
///
/// Walks `lesson.exerciseKeys` in the backend's own fixed order. An
/// exercise whose round has nothing left to test right now is skipped
/// without ever appearing. After the last one, [LessonResultsScreen] shows
/// the one outcome of the whole lesson; "Повторить урок" there runs the
/// sequence again in this same screen, "Готово" closes it.
class LessonRunScreen extends StatefulWidget {
  final Lesson lesson;
  const LessonRunScreen({super.key, required this.lesson});

  @override
  State<LessonRunScreen> createState() => _LessonRunScreenState();
}

class _LessonRunScreenState extends State<LessonRunScreen> {
  // The exercise on screen right now; null while the next one is being
  // looked up (a neutral spinner, never a menu).
  String? _currentKey;
  VoidCallback? _finishCurrent;
  // Bumped per exercise shown, so a repeat pass of the same exercise type
  // gets a fresh widget instead of reusing the finished one.
  int _step = 0;
  late String _title = 'Урок ${widget.lesson.number}';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  /// Whether exercise [key]'s round currently has anything left to test --
  /// fetched fresh every time (never cached), since an earlier exercise
  /// type in this same pass can push a word over its required level and
  /// shrink what THIS exercise still needs to cover. Сопоставление alone
  /// needs at least 2 remaining words to form a board at all; every other
  /// type is meaningful with just 1.
  Future<bool> _hasPendingWork(String key) async {
    final id = widget.lesson.id;
    switch (key) {
      case 'true_or_false':
        return (await ApiClient.instance.fetchLessonTrueOrFalseRound(id)).items.isNotEmpty;
      case 'matching':
        return (await ApiClient.instance.fetchLessonMatchingWords(id)).length >= 2;
      case 'build_word':
        return (await ApiClient.instance.fetchLessonBuildWordRound(id)).items.isNotEmpty;
      case 'speaking_word':
        return (await ApiClient.instance.fetchLessonSpeakingWordRound(id)).items.isNotEmpty;
      case 'listen_word':
        return (await ApiClient.instance.fetchLessonListenWordRound(id)).items.isNotEmpty;
      default:
        return false;
    }
  }

  /// Shows exercise [key] in place and completes once it calls
  /// finishExercise() (see LessonRunScope).
  Future<void> _play(String key) {
    final done = Completer<void>();
    setState(() {
      _step++;
      _currentKey = key;
      _title = _exerciseLabels[key] ?? key;
      _finishCurrent = () {
        if (!done.isCompleted) done.complete();
      };
    });
    return done.future;
  }

  Future<void> _run() async {
    try {
      while (true) {
        for (final key in widget.lesson.exerciseKeys) {
          bool hasWork;
          try {
            hasWork = await _hasPendingWork(key);
          } catch (_) {
            // A single exercise's own availability check failing (a network
            // blip) shouldn't derail the whole run -- try to still show it
            // rather than silently skip a real round.
            hasWork = true;
          }
          if (!mounted) return;
          if (!hasWork) continue;
          await _play(key);
          if (!mounted) return;
          setState(() => _currentKey = null);
        }

        final fresh = await ApiClient.instance.fetchLesson(widget.lesson.id);
        if (!mounted) return;
        final repeat = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => LessonResultsScreen(lesson: fresh)),
        );
        if (!mounted) return;
        if (repeat != true) {
          Navigator.of(context).pop();
          return;
        }
        setState(() => _title = 'Урок ${widget.lesson.number}');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось продолжить урок, попробуйте ещё раз')),
      );
      Navigator.of(context).pop();
    }
  }

  Widget _exercise(String key) {
    final lesson = widget.lesson;
    return switch (key) {
      'true_or_false' => TrueOrFalseScreen(lessonId: lesson.id, lessonNumber: lesson.number),
      'matching' => MatchingScreen(lessonId: lesson.id, lessonNumber: lesson.number),
      'build_word' => BuildWordScreen(lessonId: lesson.id, lessonNumber: lesson.number),
      'speaking_word' => SpeakingWordScreen(lessonId: lesson.id, lessonNumber: lesson.number),
      'listen_word' => ListenWordScreen(lessonId: lesson.id, lessonNumber: lesson.number),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final key = _currentKey;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: key == null
            ? const LessonExerciseHandoff(key: ValueKey('lesson-run-handoff'))
            : LessonRunScope(
                key: ValueKey('lesson-run-step-$_step'),
                onExerciseFinished: _finishCurrent!,
                child: _exercise(key),
              ),
      ),
    );
  }
}
