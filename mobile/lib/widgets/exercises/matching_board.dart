import 'dart:math';

import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../models/word.dart';
import '../../services/answer_sound.dart';
import '../../theme/app_colors.dart';
import '../audio_button.dart';
import '../guyo_ui.dart';

/// "Сопоставление", as ONE self-contained widget: shuffles [words] into two
/// independently-ordered columns, owns the whole tap-to-match state machine
/// (selection, the mismatch flash, the mistake count), and reports what a
/// host needs to know through two callbacks -- the SAME widget a Lesson
/// host and a Practice host both render for this exercise type.
///
/// A correct match is decided by comparing `Word.id` between the tapped
/// left and right card, never by comparing the translation text -- so two
/// different words that happen to share a translation (e.g. "big" and
/// "large" both -> "большой") are still distinguished correctly.
///
/// [onAttempt] fires on every match attempt (right or wrong) with the
/// tapped LEFT card's word_id -- it's the "prompt" side being tested (does
/// the player know this word's translation), while the right card is just
/// the wrong guess, not itself a demonstrated failure to recognize its own
/// word. A host that scores this (Lesson) reports it to the backend here;
/// one that doesn't (Practice) only needs it for a local correct count, or
/// can ignore it entirely.
///
/// [onComplete] fires once, the instant the last pair is matched -- before
/// any async work a host's own [onAttempt] for that pair might still be
/// doing. A host that must wait for that (Lesson, saving scores before the
/// next exercise starts) does its own waiting after this fires; the board
/// itself keeps showing the completed, all-matched columns throughout, so
/// there is never a jarring swap to a bare spinner.
class MatchingBoard extends StatefulWidget {
  final List<GuyoWord> words;
  final void Function(int wordId, bool isCorrect)? onAttempt;
  final VoidCallback onComplete;

  const MatchingBoard({super.key, required this.words, this.onAttempt, required this.onComplete});

  @override
  State<MatchingBoard> createState() => _MatchingBoardState();
}

class _MatchingBoardState extends State<MatchingBoard> {
  late List<GuyoWord> _left;
  late List<GuyoWord> _right;
  final Set<int> _matchedIds = {};
  int? _selectedLeftId;
  int? _selectedRightId;
  int _mistakes = 0;
  bool _awaitingMismatchClear = false;

  @override
  void initState() {
    super.initState();
    final random = Random();
    // Independent shuffles: the left (word) order and right (translation)
    // order must not line up, otherwise position alone would give the
    // answer away.
    _left = List<GuyoWord>.from(widget.words)..shuffle(random);
    _right = List<GuyoWord>.from(widget.words)..shuffle(random);
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
    AnswerSound.play(isCorrect);
    widget.onAttempt?.call(leftId, isCorrect);

    if (isCorrect) {
      setState(() {
        _matchedIds.add(leftId);
        _selectedLeftId = null;
        _selectedRightId = null;
      });
      if (_matchedIds.length == _left.length) {
        widget.onComplete();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MatchingProgressHeader(matched: _matchedIds.length, total: _left.length, mistakes: _mistakes),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MatchColumn(
                  words: _left,
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
                  words: _right,
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
    );
  }
}

/// Matching's own progress readout: pairs found plus a mistake count when
/// there is one, in the same GuyoCard pill every other exercise's header
/// uses -- not ExerciseProgressHeader itself (that one's shape is "points +
/// position", which a two-column board has no use for), but the same
/// visual family.
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
  // an exact card deterministically. Has no effect on matching logic,
  // which is entirely id-based already.
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
