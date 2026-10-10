import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import '../theme/app_colors.dart';
import '../widgets/exercises/exercise_progress_header.dart';
import '../widgets/exercises/listen_word_exercise.dart';
import 'lesson_exercise_flow.dart';
import '../widgets/skeleton.dart';

/// "Услышь слово", as one of a Lesson's exercises: the backend hands back a
/// round built from THIS lesson's own words -- one word's own recording
/// per task, a shuffled multiple-choice among other lesson words.
/// Correctness is decided purely by comparing the tapped option's word_id
/// to the item's own word_id -- never by comparing text.
///
/// All of the actual playback/options/tap logic lives in
/// [ListenWordExercise] -- the SAME widget Quest renders for this exercise
/// type -- so this screen's only job is to fetch this lesson's round,
/// sequence through its items, and track this round's own progress
/// header.
///
/// After every answer, this screen reports {word_id, is_correct} to the
/// backend via submitLessonAnswer, which is the ONLY place a word's score
/// actually changes.
class ListenWordScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  /// This pass's round, already fetched by the lesson runner (see
  /// LessonRounds) -- shown at once, with no request. Null: fetch it here.
  final ListenWordRound? initialRound;

  const ListenWordScreen({super.key, required this.lessonId, required this.lessonNumber, this.initialRound});

  @override
  State<ListenWordScreen> createState() => _ListenWordScreenState();
}

class _ListenWordScreenState extends State<ListenWordScreen> with LessonExerciseFlow {
  bool _isLoading = true;
  String? _errorMessage;
  List<ListenWordItem> _items = [];
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
      final round = widget.initialRound ?? await ApiClient.instance.fetchLessonListenWordRound(widget.lessonId);
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
        _errorMessage = tr('Не удалось загрузить упражнение');
      });
    }
  }

  void _onAnswer(bool correct) {
    final item = _items[_index];
    // Judged right here; the server gets it in the background, so the next
    // item shows at once.
    ApiClient.instance.queueLessonAnswer(widget.lessonId, 'listen_word', wordId: item.wordId, isCorrect: correct);
    if (!mounted) return;
    setState(() => _index++);
    // Last item answered -- the lesson runner takes over straight away.
    if (_index >= _items.length) finishExercise();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SkeletonExercise(options: 4);
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
              FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(tr('Для этого упражнения пока нет слов'), textAlign: TextAlign.center),
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
            const SizedBox(height: 16),
            Expanded(
              child: isRoundComplete
                  ? const LessonExerciseHandoff()
                  : SingleChildScrollView(
                      child: ListenWordExercise(
                        key: ValueKey(_items[_index].wordId),
                        item: _items[_index],
                        onAnswer: _onAnswer,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
