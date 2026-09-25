import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/exercise.dart';
import '../theme/app_colors.dart';
import '../widgets/exercises/build_word_exercise.dart';
import '../widgets/exercises/exercise_progress_header.dart';
import 'lesson_exercise_flow.dart';

/// "Собери слово", as one of a Lesson's exercises: shows a lesson word's
/// translation, then the player taps individual letter buttons (this
/// word's own letters, plus a few wrong ones -- both already decided by
/// the backend) to build the original word, against a 15-second timer.
///
/// All of the actual slots/pool/timer/checking logic lives in
/// [BuildWordExercise] -- the SAME widget Quest renders for this exercise
/// type -- so this screen's only job is to fetch this lesson's round,
/// sequence through its items keyed by word id (a fresh key per item
/// means a fresh widget, and with it a freshly-started timer), and track
/// this round's own progress header.
///
/// Every attempt's outcome is reported to the backend via
/// submitLessonAnswer, which is the ONLY place a word's score actually
/// changes.
class BuildWordScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  const BuildWordScreen({super.key, required this.lessonId, required this.lessonNumber});

  @override
  State<BuildWordScreen> createState() => _BuildWordScreenState();
}

class _BuildWordScreenState extends State<BuildWordScreen> with LessonExerciseFlow {
  bool _isLoading = true;
  String? _errorMessage;
  BuildWordRound? _round;
  int _index = 0;
  int _pointsEarned = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final round = await ApiClient.instance.fetchLessonBuildWordRound(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _round = round;
        _index = 0;
        _pointsEarned = 0;
        _isLoading = false;
      });
      // Nothing left for this exercise to test -- skip it instead of
      // stalling the lesson on a dead end.
      if (round.items.isEmpty) finishExercise();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить упражнение';
      });
    }
  }

  Future<void> _onAnswer(bool correct) async {
    final item = _round!.items[_index];
    try {
      final result = await ApiClient.instance.submitLessonAnswer(
        widget.lessonId,
        'build_word',
        wordId: item.wordId,
        isCorrect: correct,
      );
      if (!mounted) return;
      setState(() => _pointsEarned += result.pointsAwarded);
    } catch (_) {
      // A failed score update must never interrupt the flow word by word.
    }
    if (!mounted) return;
    setState(() => _index++);
    // Last word built -- the lesson runner takes over straight away.
    if (_index >= _round!.items.length) finishExercise();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }

    final round = _round;
    if (round == null || round.items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Для этого упражнения пока нет слов', textAlign: TextAlign.center),
        ),
      );
    }

    final isRoundComplete = _index >= round.items.length;

    return Container(
      color: AppColors.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            ExerciseProgressHeader(points: _pointsEarned, position: _index + 1, total: round.items.length),
            Expanded(
              child: isRoundComplete
                  ? const LessonExerciseHandoff()
                  : Center(
                      child: SingleChildScrollView(
                        child: BuildWordExercise(
                          // A fresh key per word -- a new item is a brand
                          // new instance, and with it a freshly-started
                          // 15-second timer, never one continuing an old
                          // item's countdown into the next word.
                          key: ValueKey(round.items[_index].wordId),
                          item: round.items[_index],
                          caseSensitive: round.caseSensitive,
                          onAnswer: _onAnswer,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
