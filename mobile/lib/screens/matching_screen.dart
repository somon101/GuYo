import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import '../widgets/exercises/matching_board.dart';
import 'lesson_exercise_flow.dart';

/// "Сопоставление", as one of a Lesson's exercises: this screen never
/// creates, copies, or persists any Word/translation -- it only calls GET
/// /lessons/{id}/exercises/matching (via ApiClient.fetchLessonMatchingWords),
/// which returns exactly this lesson's fixed word set. Word selection was
/// already decided once, at lesson creation.
///
/// All of the actual board/tap/match logic lives in [MatchingBoard] -- the
/// SAME widget Practice renders for this exercise type -- so this screen's
/// only job is to fetch this lesson's word list and report each match to
/// the backend via submitLessonAnswer, which is the ONLY place a word's
/// score actually changes.
class MatchingScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  const MatchingScreen({super.key, required this.lessonId, required this.lessonNumber});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> with LessonExerciseFlow {
  bool _isLoading = true;
  String? _errorMessage;
  List<GuyoWord>? _words;

  // Every match's score submission is fire-and-forget for a snappy per-tap
  // feel, EXCEPT the one that finishes the round: the lesson moves straight
  // on to the next exercise once the board is done, and that exercise's own
  // round is built from these very scores -- so onComplete waits for every
  // submission to actually land before handing control back.
  final List<Future<void>> _pendingSubmits = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Fetches a fresh round from the backend. Called once per visit: a
  /// lesson plays each exercise through once and then moves on, and
  /// repeating is a property of the lesson, not of this board.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final words = await ApiClient.instance.fetchLessonMatchingWords(widget.lessonId);
      // A word with no translation can't be matched to anything; the
      // backend already excludes these, but this stays defensive rather
      // than assuming that holds forever.
      final usable = words.where((w) => w.translation.trim().isNotEmpty).toList();
      if (!mounted) return;
      if (usable.isNotEmpty) {
        setState(() {
          _words = usable;
          _isLoading = false;
          _pendingSubmits.clear();
        });
      } else {
        setState(() => _isLoading = false);
        // Nothing here can be matched -- skip this exercise instead of
        // stalling the lesson on an empty board.
        finishExercise();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить слова для тренажёра';
      });
    }
  }

  void _onAttempt(int wordId, bool isCorrect) {
    late final Future<void> future;
    future = ApiClient.instance
        .submitLessonAnswer(widget.lessonId, 'matching', wordId: wordId, isCorrect: isCorrect)
        .then<void>((_) {})
        .catchError((_) {
      // The score update failed to save -- the round itself still plays
      // out locally; there's nothing actionable to show mid-round for a
      // single failed save.
    }).whenComplete(() => _pendingSubmits.remove(future));
    _pendingSubmits.add(future);
  }

  void _onComplete() {
    // Wait for every submission (the board's last match included) to
    // actually land, then hand control straight back to the lesson runner
    // so the next exercise starts by itself.
    Future.wait(List<Future<void>>.from(_pendingSubmits)).then((_) {
      if (!mounted) return;
      finishExercise();
    });
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

    final words = _words;
    if (words == null || words.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Для этого упражнения пока нет слов', textAlign: TextAlign.center),
        ),
      );
    }

    return Container(
      color: AppColors.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: MatchingBoard(words: words, onAttempt: _onAttempt, onComplete: _onComplete),
      ),
    );
  }
}
