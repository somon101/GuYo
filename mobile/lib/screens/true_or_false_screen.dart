import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/exercise.dart';
import '../theme/app_colors.dart';
import '../widgets/exercises/exercise_progress_header.dart';
import '../widgets/exercises/true_or_false_exercise.dart';
import 'lesson_exercise_flow.dart';

/// "Правда или ложь", as one of a Lesson's exercises: the backend hands back
/// a round built from THIS lesson's fixed word set (wrong-answer candidates
/// come from the user's previously-learned pool, never from other words in
/// this same lesson). All of the actual card/buttons/tap logic lives in
/// [TrueOrFalseExercise] -- the SAME widget Quest renders for this exercise
/// type (see quest_attempt_screen.dart) -- so this screen's only job is to
/// fetch this lesson's round, sequence through its items, and track this
/// round's own progress header. A design change to the exercise itself
/// never touches this file.
///
/// After every answer, this screen reports {word_id, is_correct} to the
/// backend via submitLessonAnswer, which is the ONLY place a word's score
/// (and any rating points it earns crossing the learned threshold) actually
/// changes -- this screen never computes either itself, it just sums up
/// `pointsAwarded` from what the backend already decided on each answer.
class TrueOrFalseScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  const TrueOrFalseScreen({super.key, required this.lessonId, required this.lessonNumber});

  @override
  State<TrueOrFalseScreen> createState() => _TrueOrFalseScreenState();
}

class _TrueOrFalseScreenState extends State<TrueOrFalseScreen> with LessonExerciseFlow {
  bool _isLoading = true;
  String? _errorMessage;
  List<TrueOrFalseItem> _items = [];
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
      final round = await ApiClient.instance.fetchLessonTrueOrFalseRound(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _items = round.items;
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

  /// Called by [TrueOrFalseExercise] once per item, already after its own
  /// reveal flash -- this only needs to save the answer and move on.
  Future<void> _onAnswer(bool correct) async {
    final item = _items[_index];
    try {
      final result = await ApiClient.instance.submitLessonAnswer(
        widget.lessonId,
        'true_or_false',
        wordId: item.wordId,
        isCorrect: correct,
      );
      if (!mounted) return;
      setState(() => _pointsEarned += result.pointsAwarded);
    } catch (_) {
      // A failed score update must never interrupt the flow card by card.
    }
    if (!mounted) return;
    setState(() => _index++);
    // Last card answered -- the lesson runner takes over straight away.
    if (_index >= _items.length) finishExercise();
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
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Для этого упражнения пока нет слов', textAlign: TextAlign.center),
        ),
      );
    }

    final isRoundComplete = _index >= _items.length;

    return Container(
      color: AppColors.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            ExerciseProgressHeader(points: _pointsEarned, position: _index + 1, total: _items.length),
            Expanded(
              // Center + a non-scrolling min-size column: the card and its
              // buttons travel as one block, floating in the middle of
              // whatever space is left under the header -- never pinned
              // apart, which is what made the buttons hard to reach.
              child: isRoundComplete
                  ? const LessonExerciseHandoff()
                  : Center(
                      child: SingleChildScrollView(
                        child: TrueOrFalseExercise(item: _items[_index], onAnswer: _onAnswer),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
