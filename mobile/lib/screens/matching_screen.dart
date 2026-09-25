import 'dart:math';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import '../widgets/audio_button.dart';
import '../widgets/guyo_ui.dart';
import 'lesson_exercise_flow.dart';

/// A drag-free "tap word, then tap its translation" matching drill, as one
/// of a Lesson's exercises.
///
/// This screen never creates, copies, or persists any Word/translation --
/// it only calls GET /lessons/{id}/exercises/matching (via ApiClient.
/// fetchLessonMatchingWords), which returns exactly this lesson's fixed
/// word set. Word selection was already decided once, at lesson creation;
/// this screen only shuffles that fixed list into two independently-ordered
/// display columns and tracks a purely in-memory round: which of the given
/// word_ids are matched, and a mistake count. A correct match is decided by
/// comparing `Word.id` (word_id) between the tapped left and right card,
/// never by comparing the translation text -- so two different words that
/// happen to share a translation (e.g. "big" and "large" both -> "большой")
/// are still distinguished correctly.
///
/// Every match (right or wrong) is reported to the backend via
/// submitLessonAnswer, which is the ONLY place a word's score actually
/// changes. A wrong match involves two distinct cards (the tapped left card
/// and the tapped right card); only the LEFT card's word_id is scored as
/// incorrect -- it's the "prompt" side being tested (does the player know
/// this word's translation), while the right card is just the wrong guess,
/// not itself a demonstrated failure to recognize its own word.
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

  List<GuyoWord>? _left; // word_id order for the left ("word") column
  List<GuyoWord>? _right; // word_id order for the right ("translation") column
  final Set<int> _matchedIds = {};
  int? _selectedLeftId;
  int? _selectedRightId;
  int _mistakes = 0;
  bool _awaitingMismatchClear = false;
  // Every match's score submission is fire-and-forget for a snappy per-tap
  // feel, EXCEPT the one that finishes the round: the lesson moves straight
  // on to the next exercise once this board is done, and that exercise's own
  // round is built from these very scores -- so the last match waits for
  // every submission to actually land before handing control back.
  final List<Future<void>> _pendingSubmits = [];
  bool _roundFinished = false;

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
        _startRound(usable);
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

  void _startRound(List<GuyoWord> selected) {
    final random = Random();
    // Independent shuffles: the left (word) order and right (translation)
    // order must not line up, otherwise position alone would give the
    // answer away.
    final left = List<GuyoWord>.from(selected)..shuffle(random);
    final right = List<GuyoWord>.from(selected)..shuffle(random);

    setState(() {
      _left = left;
      _right = right;
      _matchedIds.clear();
      _selectedLeftId = null;
      _selectedRightId = null;
      _mistakes = 0;
      _awaitingMismatchClear = false;
      _isLoading = false;
      _roundFinished = false;
      _pendingSubmits.clear();
    });
  }

  void _tapLeft(int wordId) {
    if (_awaitingMismatchClear || _matchedIds.contains(wordId)) return;
    setState(() => _selectedLeftId = wordId);
    _evaluateIfReady();
  }

  void _tapRight(int wordId) {
    if (_awaitingMismatchClear || _matchedIds.contains(wordId)) return;
    setState(() => _selectedRightId = wordId);
    _evaluateIfReady();
  }

  void _evaluateIfReady() {
    final leftId = _selectedLeftId;
    final rightId = _selectedRightId;
    if (leftId == null || rightId == null) return;

    // The only rule that matters: do the two selected cards share the same
    // underlying word_id? Never compare the displayed text.
    final isCorrect = leftId == rightId;

    _submitAnswer(leftId, isCorrect);

    if (isCorrect) {
      final left = _left!;
      setState(() {
        _matchedIds.add(leftId);
        _selectedLeftId = null;
        _selectedRightId = null;
      });

      if (_matchedIds.length == left.length) {
        // This match just finished the board -- wait for every submission
        // (this one included) to land, then hand control straight back to
        // the lesson runner so the next exercise starts by itself.
        final pending = List<Future<void>>.from(_pendingSubmits);
        Future.wait(pending).then((_) {
          if (!mounted) return;
          setState(() => _roundFinished = true);
          finishExercise();
        });
      }
    } else {
      _mistakes++;
      _awaitingMismatchClear = true;
      Future.delayed(const Duration(milliseconds: 550), () {
        if (!mounted) return;
        setState(() {
          _selectedLeftId = null;
          _selectedRightId = null;
          _awaitingMismatchClear = false;
        });
      });
    }
  }

  void _submitAnswer(int wordId, bool isCorrect) {
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

    final left = _left;
    final right = _right;
    if (left == null || right == null || left.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Для этого упражнения пока нет слов', textAlign: TextAlign.center),
        ),
      );
    }

    final isFullyMatched = _matchedIds.length == left.length;
    final isRoundComplete = isFullyMatched && _roundFinished;

    return Container(
      color: AppColors.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            _MatchingProgressHeader(matched: _matchedIds.length, total: left.length, mistakes: _mistakes),
            const SizedBox(height: 16),
            if (isRoundComplete)
              const Expanded(child: LessonExerciseHandoff())
            else if (isFullyMatched)
              // Every pair is matched but the last match's score submission
              // hasn't resolved yet -- a brief, real (not padded) wait rather
              // than a fixed delay, since it's usually near-instant on a
              // normal connection.
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MatchColumn(
                        words: left,
                        matchedIds: _matchedIds,
                        selectedId: _selectedLeftId,
                        isMismatched: _awaitingMismatchClear,
                        labelOf: (w) => w.word,
                        audioUrlOf: (w) => w.wordAudioUrl,
                        onTap: _tapLeft,
                        columnKeyPrefix: 'left',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MatchColumn(
                        words: right,
                        matchedIds: _matchedIds,
                        selectedId: _selectedRightId,
                        isMismatched: _awaitingMismatchClear,
                        labelOf: (w) => w.translation,
                        audioUrlOf: (w) => w.translationAudioUrl,
                        onTap: _tapRight,
                        columnKeyPrefix: 'right',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Matching's own progress readout: pairs found plus a mistake count when
/// there is one, in the same GuyoCard pill every other exercise's header
/// uses -- not [ExerciseProgressHeader] itself (that one's shape is
/// "points + position", which a two-column board has no use for), but the
/// same visual family.
class _MatchingProgressHeader extends StatelessWidget {
  final int matched;
  final int total;
  final int mistakes;
  const _MatchingProgressHeader({required this.matched, required this.total, required this.mistakes});

  @override
  Widget build(BuildContext context) {
    return GuyoCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Text('$matched/$total', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          const Spacer(),
          if (mistakes > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.dangerLight, borderRadius: BorderRadius.circular(AppShapes.pillRadius)),
              child: Text(
                'Ошибок: $mistakes',
                style: const TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _MatchColumn extends StatelessWidget {
  final List<GuyoWord> words;
  final Set<int> matchedIds;
  final int? selectedId;
  final bool isMismatched;
  final String Function(GuyoWord) labelOf;
  final String? Function(GuyoWord) audioUrlOf;
  final void Function(int wordId) onTap;
  // Distinguishes the left ("word") column from the right ("translation")
  // one in each card's Key, purely so widget/integration tests can target
  // an exact card deterministically (e.g. "the right-side card for word_id
  // 7") instead of guessing between same-looking duplicate translations.
  // Has no effect on matching logic, which is entirely id-based already.
  final String columnKeyPrefix;

  const _MatchColumn({
    required this.words,
    required this.matchedIds,
    required this.selectedId,
    required this.isMismatched,
    required this.labelOf,
    required this.audioUrlOf,
    required this.onTap,
    required this.columnKeyPrefix,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: words.length,
      itemBuilder: (context, index) {
        final word = words[index];
        final isMatched = matchedIds.contains(word.id);
        final isSelected = selectedId == word.id;
        final audioUrl = audioUrlOf(word);
        return Padding(
          key: ValueKey('match-$columnKeyPrefix-${word.id}'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _MatchCard(
            label: labelOf(word),
            audioUrl: audioUrl != null && audioUrl.isNotEmpty ? ApiClient.instance.mediaUrl(audioUrl) : null,
            isMatched: isMatched,
            // A selected card only reads as "wrong" once its pair failed to
            // match -- while still waiting for the second tap, selected
            // just means selected.
            isMismatched: isSelected && isMismatched,
            isSelected: isSelected,
            onTap: isMatched ? null : () => onTap(word.id),
          ),
        );
      },
    );
  }
}

class _MatchCard extends StatelessWidget {
  final String label;
  final String? audioUrl;
  final bool isMatched;
  final bool isMismatched;
  final bool isSelected;
  final VoidCallback? onTap;

  const _MatchCard({
    required this.label,
    required this.audioUrl,
    required this.isMatched,
    required this.isMismatched,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color background = Colors.white;
    Color border = AppColors.cardBorder;
    Color textColor = AppColors.primaryDark;

    if (isMatched) {
      background = AppColors.successLight;
      border = AppColors.success;
      textColor = AppColors.success;
    } else if (isMismatched) {
      background = AppColors.dangerLight;
      border = AppColors.danger;
      textColor = AppColors.danger;
    } else if (isSelected) {
      background = AppColors.violetSurface;
      border = AppColors.primary;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppShapes.rowRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShapes.rowRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppShapes.rowRadius),
            border: Border.all(color: border, width: (isMatched || isMismatched || isSelected) ? 1.6 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: isMatched ? TextDecoration.lineThrough : null,
                    color: textColor,
                  ),
                ),
              ),
              if (audioUrl != null) ...[
                const SizedBox(width: 4),
                AudioButton(url: audioUrl!, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
