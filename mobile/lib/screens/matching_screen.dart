import 'dart:math';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/word.dart';
import '../widgets/audio_button.dart';

/// exercise_key for this screen's admin-configurable word count (Admin
/// Web's "Упражнения" page) -- same mechanism "Правда или ложь" uses.
const String _exerciseKey = 'matching';

/// Below this many usable words, a round can't be built meaningfully.
const int _minWordsForRound = 2;

/// A drag-free "tap word, then tap its translation" matching drill.
///
/// This screen never creates, copies, or persists any Word/translation --
/// it only calls GET /dictionaries/{id}/exercises/matching/learned-words
/// (via ApiClient.fetchExerciseLearnedWords), which already returns just
/// this user's LEARNED words, capped at the admin-configured count for
/// "matching" -- never the full dictionary. Word selection and the count
/// cap are entirely the backend's decision; this screen only shuffles the
/// already-chosen round into two independently-ordered display columns
/// and tracks a purely in-memory round: which of the given word_ids are
/// matched, and a mistake count. A correct match is decided by comparing
/// `Word.id` (word_id) between the tapped left and right card, never by
/// comparing the translation text -- so two different words that happen
/// to share a translation (e.g. "big" and "large" both -> "большой") are
/// still distinguished correctly.
class MatchingScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const MatchingScreen({super.key, required this.dictionary});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  int _availableCount = 0; // how many learned+usable words exist in total

  List<GuyoWord>? _left; // word_id order for the left ("word") column
  List<GuyoWord>? _right; // word_id order for the right ("translation") column
  final Set<int> _matchedIds = {};
  int? _selectedLeftId;
  int? _selectedRightId;
  int _mistakes = 0;
  bool _awaitingMismatchClear = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Fetches a fresh round from the backend -- called on first open AND on
  /// every "Играть ещё раз", so a replay is a genuinely new random
  /// selection (same as every other exercise built on learned words),
  /// not just a client-side reshuffle of a stale list.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final words = await ApiClient.instance.fetchExerciseLearnedWords(widget.dictionary.id, _exerciseKey);
      // A word with no translation can't be matched to anything; the
      // backend already excludes these, but this stays defensive rather
      // than assuming that holds forever.
      final usable = words.where((w) => w.translation.trim().isNotEmpty).toList();
      if (!mounted) return;
      setState(() => _availableCount = usable.length);
      if (usable.length >= _minWordsForRound) {
        _startRound(usable);
      } else {
        setState(() => _isLoading = false);
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

    if (isCorrect) {
      setState(() {
        _matchedIds.add(leftId);
        _selectedLeftId = null;
        _selectedRightId = null;
      });
      _showFeedback('Правильно', isError: false);
    } else {
      _mistakes++;
      _awaitingMismatchClear = true;
      _showFeedback('Неправильно', isError: true);
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

  void _showFeedback(String text, {required bool isError}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        duration: const Duration(milliseconds: 700),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    if (_availableCount < _minWordsForRound) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Для тренажёра «Сопоставление» нужно изучить хотя бы $_minWordsForRound слова.\n'
            'Изучите слова в разделе «Изучение слов», чтобы начать.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final left = _left;
    final right = _right;
    if (left == null || right == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isRoundComplete = _matchedIds.length == left.length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Правильно: ${_matchedIds.length}/${left.length}'
            '${_mistakes > 0 ? '  ·  Ошибок: $_mistakes' : ''}',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          if (isRoundComplete)
            Expanded(child: _RoundCompleteView(onPlayAgain: _load, mistakes: _mistakes))
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
                      labelOf: (w) => w.word,
                      audioUrlOf: (w) => w.wordAudioUrl,
                      onTap: _tapLeft,
                      columnKeyPrefix: 'left',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MatchColumn(
                      words: right,
                      matchedIds: _matchedIds,
                      selectedId: _selectedRightId,
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
    );
  }
}

class _MatchColumn extends StatelessWidget {
  final List<GuyoWord> words;
  final Set<int> matchedIds;
  final int? selectedId;
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
  final bool isSelected;
  final VoidCallback? onTap;

  const _MatchCard({
    required this.label,
    required this.audioUrl,
    required this.isMatched,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    final Color border;
    if (isMatched) {
      background = Colors.green.shade50;
      border = Colors.green.shade400;
    } else if (isSelected) {
      background = scheme.primaryContainer;
      border = scheme.primary;
    } else {
      background = Theme.of(context).colorScheme.surface;
      border = Colors.grey.shade300;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    decoration: isMatched ? TextDecoration.lineThrough : null,
                    color: isMatched ? Colors.green.shade700 : null,
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

class _RoundCompleteView extends StatelessWidget {
  final VoidCallback onPlayAgain;
  final int mistakes;

  const _RoundCompleteView({required this.onPlayAgain, required this.mistakes});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 56),
          const SizedBox(height: 12),
          const Text('Раунд завершён!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            mistakes == 0 ? 'Без единой ошибки' : 'Ошибок: $mistakes',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onPlayAgain,
            icon: const Icon(Icons.refresh),
            label: const Text('Играть ещё раз'),
          ),
        ],
      ),
    );
  }
}
