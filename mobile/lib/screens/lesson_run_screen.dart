import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/lesson.dart';
import '../models/lesson_rounds.dart';
import '../theme/app_colors.dart';
import 'build_word_screen.dart';
import 'lesson_exercise_flow.dart';
import 'lesson_results_screen.dart';
import 'listen_word_screen.dart';
import 'matching_screen.dart';
import 'speaking_word_screen.dart';
import 'true_or_false_screen.dart';

/// The human-readable name of each exercise type, for the run's title bar.
const Map<String, String> lessonExerciseLabels = {
  'true_or_false': 'Правда или ложь',
  'matching': 'Сопоставление',
  'build_word': 'Собери слово',
  'speaking_word': 'Произнеси слово',
  'listen_word': 'Услышь слово',
};

/// Everything the run needs from outside -- the backend and the screens --
/// behind one seam, so a test can drive the whole sequence without either.
abstract class LessonRunDriver {
  /// Freezes this pass's words (POST /lessons/{id}/pass).
  Future<void> startPass(int lessonId);

  /// Every exercise's round for this pass, plus the media they use --
  /// fetched once, up front, so the pass then runs without a request or a
  /// loading screen between exercises.
  Future<LessonRounds> prepareRounds(int lessonId, List<String> exerciseKeys);

  /// The exercise itself, given its prepared round. It ends by calling
  /// finishExercise().
  Widget buildExercise(int lessonId, int lessonNumber, String key, LessonRounds rounds);

  Future<Lesson> fetchLesson(int lessonId);

  /// The finished pass's statistics; null when they can't be loaded -- the
  /// results then show without them.
  Future<LessonPassStats?> fetchPassStats(int lessonId);

  /// Shows the one results screen; true means "Повторить урок".
  Future<bool?> showResults(BuildContext context, Lesson lesson, LessonPassStats? stats);
}

class ApiLessonRunDriver implements LessonRunDriver {
  const ApiLessonRunDriver();

  @override
  Future<void> startPass(int lessonId) => ApiClient.instance.startLessonPass(lessonId);

  @override
  Future<LessonRounds> prepareRounds(int lessonId, List<String> exerciseKeys) =>
      LessonRounds.prepare(lessonId, exerciseKeys);

  @override
  Widget buildExercise(int lessonId, int lessonNumber, String key, LessonRounds rounds) {
    return switch (key) {
      'true_or_false' =>
        TrueOrFalseScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      'matching' => MatchingScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      'build_word' =>
        BuildWordScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      'speaking_word' =>
        SpeakingWordScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      'listen_word' =>
        ListenWordScreen(lessonId: lessonId, lessonNumber: lessonNumber, initialRound: rounds.round(key)),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Future<Lesson> fetchLesson(int lessonId) => ApiClient.instance.fetchLesson(lessonId);

  @override
  Future<LessonPassStats?> fetchPassStats(int lessonId) async {
    try {
      return await ApiClient.instance.fetchLessonPassStats(lessonId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool?> showResults(BuildContext context, Lesson lesson, LessonPassStats? stats) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LessonResultsScreen(lesson: lesson, stats: stats)),
    );
  }
}

/// One lesson, start to finish, on ONE screen.
///
/// Walks the lesson's `exerciseKeys` (decided by the backend when the
/// lesson was created) in order. Each exercise replaces the previous one
/// in place -- nothing is pushed or popped between them, so the lesson's
/// word list or any menu never shows in between. An exercise with nothing
/// to test is skipped. After the last one, the results screen is shown
/// once; "Повторить урок" there runs the sequence again right here,
/// anything else closes the lesson.
///
/// Every pass starts with POST /lessons/{id}/pass, which freezes the words
/// that pass covers, so every chosen word goes through every exercise.
/// If that call fails the pass still runs (on the backend's older, live
/// set) -- a lesson must never stall on it.
///
/// Right after that, every exercise's round and its pictures and sounds
/// are prepared at once (LessonRounds): the one wait of a pass is up front,
/// behind a skeleton, and exercises then follow each other with no request
/// and no loading screen in between.
///
/// Scoring, progress and the exercises themselves are untouched: each
/// exercise still submits its own answers exactly as before.
class LessonRunScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  final List<String> exerciseKeys;
  final LessonRunDriver driver;

  const LessonRunScreen({
    super.key,
    required this.lessonId,
    required this.lessonNumber,
    required this.exerciseKeys,
    this.driver = const ApiLessonRunDriver(),
  });

  LessonRunScreen.forLesson(Lesson lesson, {Key? key, LessonRunDriver driver = const ApiLessonRunDriver()})
      : this(
          key: key,
          lessonId: lesson.id,
          lessonNumber: lesson.number,
          exerciseKeys: lesson.exerciseKeys,
          driver: driver,
        );

  @override
  State<LessonRunScreen> createState() => _LessonRunScreenState();
}

class _LessonRunScreenState extends State<LessonRunScreen> {
  int _pass = 0;
  int _index = 0;
  bool _showingExercise = false;
  bool _failed = false;
  Completer<void>? _current;
  LessonRounds _rounds = const LessonRounds({});

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final driver = widget.driver;
    setState(() {
      _pass++;
      _index = 0;
      _showingExercise = false;
      _failed = false;
    });
    try {
      await driver.startPass(widget.lessonId);
    } catch (_) {
      // Runs anyway, on the live set -- see the class comment.
    }

    LessonRounds rounds;
    try {
      rounds = await driver.prepareRounds(widget.lessonId, widget.exerciseKeys);
    } catch (_) {
      // Preparing failed as a whole (a network blip) -- that shouldn't drop
      // real rounds: every exercise runs and loads its own, as before.
      rounds = LessonRounds({for (final key in widget.exerciseKeys) key: null});
    }
    _rounds = rounds;

    for (var i = 0; i < widget.exerciseKeys.length; i++) {
      if (!mounted) return;
      final key = widget.exerciseKeys[i];
      if (!rounds.hasWork(key)) continue;
      setState(() {
        _index = i;
        _showingExercise = false;
      });
      final done = Completer<void>();
      _current = done;
      setState(() => _showingExercise = true);
      await done.future;
    }

    if (!mounted) return;
    setState(() => _showingExercise = false);
    await _showResults();
  }

  Future<void> _showResults() async {
    final Lesson fresh;
    try {
      fresh = await widget.driver.fetchLesson(widget.lessonId);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final stats = await widget.driver.fetchPassStats(widget.lessonId);
    if (!mounted) return;
    final repeat = await widget.driver.showResults(context, fresh, stats);
    if (!mounted) return;
    if (repeat == true) {
      unawaited(_run());
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onExerciseFinished() {
    final current = _current;
    if (current != null && !current.isCompleted) current.complete();
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Прервать урок?'),
        content: const Text('Ответы уже сохранены. Урок можно продолжить позже.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Продолжить')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Выйти')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.exerciseKeys;
    final key = keys.isEmpty ? null : keys[_index];
    final title = key == null ? 'Урок ${widget.lessonNumber}' : (lessonExerciseLabels[key] ?? key);
    final progress = keys.isEmpty ? 0.0 : (_index + (_showingExercise ? 0 : 1)) / keys.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              if (keys.isNotEmpty)
                Text(
                  'Урок ${widget.lessonNumber} · упражнение ${_index + 1} из ${keys.length}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
                ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppColors.progressTrack,
              color: AppColors.primary,
            ),
          ),
        ),
        body: _buildBody(key),
      ),
    );
  }

  Widget _buildBody(String? key) {
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не удалось загрузить результаты урока', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() => _failed = false);
                  _showResults();
                },
                child: const Text('Повторить'),
              ),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Выйти')),
            ],
          ),
        ),
      );
    }
    if (!_showingExercise || key == null) {
      return const LessonExerciseHandoff();
    }
    return LessonRunScope(
      onExerciseFinished: _onExerciseFinished,
      // A fresh key per exercise AND per pass: a repeated exercise must
      // start from a clean state, never reuse the previous round's.
      child: KeyedSubtree(
        key: ValueKey('$_pass-$_index'),
        child: widget.driver.buildExercise(widget.lessonId, widget.lessonNumber, key, _rounds),
      ),
    );
  }
}
