import '../l10n/l10n.dart';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/phrase.dart';
import '../models/word.dart';
import '../services/answer_sound.dart';
import '../theme/app_colors.dart';
import '../widgets/exercises/practice_round_complete.dart';
import '../widgets/guyo_ui.dart';
import '../widgets/skeleton.dart';

/// Max phrases per practice round -- a bite-sized session, not "grind
/// through everything you've ever unlocked" in one sitting. Re-opening or
/// replaying draws a fresh random batch, same convention as Matching/
/// True-or-False's own rounds.
const int _roundSize = 10;
const int _maxWrongOptions = 3;

class _Option {
  final String text;
  final int? wordId;
  const _Option({required this.text, this.wordId});
}

class _PhraseTask {
  final GuyoPhrase phrase;
  final List<String> displayTokens;
  final int blankIndex;
  final _Option correctOption;
  final List<_Option> options;

  const _PhraseTask({
    required this.phrase,
    required this.displayTokens,
    required this.blankIndex,
    required this.correctOption,
    required this.options,
  });
}

/// Strips punctuation/symbols from the edges of [token], keeping internal
/// characters (so "don't" or a hyphenated word stays whole) -- purely for
/// matching a phrase's own display token against a learned Word's text or
/// one of its forms, never for deciding phrase availability itself (that
/// stays entirely the backend's job, see ApiClient.fetchAvailablePhrases).
String _stripEdgePunctuation(String token) {
  return token.replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');
}

/// "Собери фразу": pick a random already-available phrase (backend-decided
/// -- see ApiClient.fetchAvailablePhrases, the exact same definition "Мои
/// фразы" uses), blank out one of its words, and offer it as a multiple-
/// choice among the user's own learned words (ApiClient.fetchLearnedWords).
///
/// Deliberately has no score/progress of its own: this is Practice, not a
/// Lesson -- nothing here reports an answer to the backend or touches
/// WordProgress. Both the phrase pool and the word pool are read-only,
/// already-existing data; no Word/Phrase copy is ever created.
class BuildPhraseScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  const BuildPhraseScreen({super.key, required this.dictionary});

  @override
  State<BuildPhraseScreen> createState() => _BuildPhraseScreenState();
}

class _BuildPhraseScreenState extends State<BuildPhraseScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<_PhraseTask> _tasks = [];

  int _index = 0;
  int _correctCount = 0;
  _Option? _selected;
  bool _isLocked = false; // true briefly while the correct/incorrect state shows before advancing

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
      final results = await Future.wait([
        ApiClient.instance.fetchAvailablePhrases(widget.dictionary.id),
        ApiClient.instance.fetchLearnedWords(widget.dictionary.id),
      ]);
      final phrases = results[0] as List<GuyoPhrase>;
      final learnedWords = results[1] as List<GuyoWord>;

      final tokenToWord = <String, GuyoWord>{};
      for (final w in learnedWords) {
        tokenToWord.putIfAbsent(w.word.trim().toLowerCase(), () => w);
        for (final f in w.forms) {
          if (f.language == widget.dictionary.language) {
            tokenToWord.putIfAbsent(f.text.trim().toLowerCase(), () => w);
          }
        }
      }

      final random = Random();
      final shuffledPhrases = List<GuyoPhrase>.from(phrases)..shuffle(random);
      final tasks = <_PhraseTask>[];
      for (final phrase in shuffledPhrases) {
        if (tasks.length >= _roundSize) break;
        final task = _buildTask(phrase, learnedWords, tokenToWord, random);
        if (task != null) tasks.add(task);
      }

      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _index = 0;
        _correctCount = 0;
        _selected = null;
        _isLocked = false;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = tr('Не удалось загрузить упражнение');
      });
    }
  }

  /// One task from [phrase], or null if it can't produce a meaningful
  /// multiple-choice (no tokens at all, or no other learned word to offer
  /// as a wrong option).
  _PhraseTask? _buildTask(
    GuyoPhrase phrase,
    List<GuyoWord> learnedWords,
    Map<String, GuyoWord> tokenToWord,
    Random random,
  ) {
    final tokens = phrase.original.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;

    final blankIndex = random.nextInt(tokens.length);
    final rawBlankedToken = _stripEdgePunctuation(tokens[blankIndex]);
    final clean = rawBlankedToken.toLowerCase();
    if (clean.isEmpty) return null;
    // Resolved purely to (a) find the word_id this token belongs to, via
    // the existing word_id/forms system -- e.g. "могу" resolves to the
    // learned Word "мочь" -- and (b) exclude that SAME word from the wrong
    // options below. The correct answer text itself is deliberately the
    // token AS IT ACTUALLY APPEARS in this phrase ("могу"), never the
    // word's own base/dictionary form ("мочь") -- a phrase's grammar
    // decided that surface form, and that's what the user must pick.
    final resolvedWord = tokenToWord[clean];
    final correctText = rawBlankedToken;

    final candidates = learnedWords.where((w) {
      if (resolvedWord != null) return w.id != resolvedWord.id;
      return w.word.trim().toLowerCase() != clean;
    }).toList()
      ..shuffle(random);
    if (candidates.isEmpty) return null;

    final wrongCount = candidates.length < _maxWrongOptions ? candidates.length : _maxWrongOptions;
    final correctOption = _Option(text: correctText, wordId: resolvedWord?.id);
    final options = [
      correctOption,
      for (final w in candidates.take(wrongCount)) _Option(text: w.word, wordId: w.id),
    ]..shuffle(random);

    return _PhraseTask(
      phrase: phrase,
      displayTokens: tokens,
      blankIndex: blankIndex,
      correctOption: correctOption,
      options: options,
    );
  }

  void _choose(_Option option) {
    if (_isLocked || _index >= _tasks.length) return;
    final correct = option == _tasks[_index].correctOption;
    setState(() {
      _selected = option;
      _isLocked = true;
      if (correct) _correctCount++;
    });
    AnswerSound.play(correct);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _index++;
        _selected = null;
        _isLocked = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(tr('Собери фразу')), backgroundColor: AppColors.canvas),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SkeletonExercise(options: 3);
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
    if (_tasks.isEmpty) {
      return GuyoEmptyState(
        icon: Icons.auto_awesome_rounded,
        title: tr('Пока недостаточно данных для практики'),
        message: tr('Изучите больше слов, чтобы открыть фразы для тренировки.'),
      );
    }

    if (_index >= _tasks.length) {
      return PracticeRoundComplete(
        correctCount: _correctCount,
        total: _tasks.length,
        onPlayAgain: _load,
        onBack: () => Navigator.of(context).pop(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          _ProgressHeader(current: _index + 1, total: _tasks.length, correctCount: _correctCount),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Carries the current task's correct answer for
                  // integration tests to read -- otherwise a test would
                  // have no way to know it without racing the random
                  // blank/option selection with a second, separate check.
                  _PhraseTaskCard(
                    key: ValueKey('build-phrase-task-${_tasks[_index].phrase.id}-${_tasks[_index].correctOption.text}'),
                    task: _tasks[_index],
                  ),
                  const SizedBox(height: 20),
                  _OptionsList(
                    task: _tasks[_index],
                    selected: _selected,
                    onSelect: _choose,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int current;
  final int total;
  final int correctCount;
  const _ProgressHeader({required this.current, required this.total, required this.correctCount});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr('Фраза {0} из {1}', [current, total]),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
            ),
            Row(
              children: [
                Icon(Icons.check_circle, size: 15, color: AppColors.success),
                const SizedBox(width: 4),
                Text('$correctCount', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: current / total,
            minHeight: 6,
            backgroundColor: AppColors.progressTrack,
          ),
        ),
      ],
    );
  }
}

/// The glass task card: original phrase with one word blanked out, plus
/// the translation as the hint. This is the one place on the screen that
/// genuinely earns a frosted-glass treatment -- everything the player's
/// attention needs to be on.
class _PhraseTaskCard extends StatelessWidget {
  final _PhraseTask task;
  const _PhraseTaskCard({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cardBorder, width: 1.2),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            children: [
              Wrap(
                key: const ValueKey('build-phrase-sentence'),
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < task.displayTokens.length; i++)
                    if (i == task.blankIndex)
                      const _BlankToken()
                    else
                      Text(
                        task.displayTokens[i],
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                      ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: AppColors.primary.withValues(alpha: 0.08)),
              const SizedBox(height: 14),
              // Deliberately no audio button here: the phrase's own
              // recording is of the FULL sentence, blanked word included --
              // playing it would just hand the player the answer.
              Text(
                task.phrase.shownTranslation,
                style: TextStyle(fontSize: 15, color: AppColors.secondaryText),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlankToken extends StatelessWidget {
  const _BlankToken();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary, width: 1.5),
        color: AppColors.primary.withValues(alpha: 0.06),
      ),
      child: Text(
        '   ',
        style: TextStyle(fontSize: 19, decoration: TextDecoration.underline, decorationColor: AppColors.primary),
      ),
    );
  }
}

class _OptionsList extends StatelessWidget {
  final _PhraseTask task;
  final _Option? selected;
  final ValueChanged<_Option> onSelect;

  const _OptionsList({required this.task, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in task.options) ...[
          _OptionTile(
            option: option,
            isSelected: selected == option,
            isRevealed: selected != null,
            isCorrectOption: option == task.correctOption,
            onTap: () => onSelect(option),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final _Option option;
  final bool isSelected;
  final bool isRevealed;
  final bool isCorrectOption;
  final VoidCallback onTap;

  const _OptionTile({
    required this.option,
    required this.isSelected,
    required this.isRevealed,
    required this.isCorrectOption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color background = AppColors.surface;
    Color border = AppColors.primary.withValues(alpha: 0.12);
    Widget? trailing;
    Color textColor = AppColors.primaryDark;

    if (isRevealed) {
      if (isCorrectOption) {
        background = AppColors.successLight;
        border = AppColors.success;
        textColor = AppColors.success;
        trailing = Icon(Icons.check_circle, color: AppColors.success, size: 20);
      } else if (isSelected) {
        background = AppColors.dangerLight;
        border = AppColors.danger;
        textColor = AppColors.danger;
        trailing = Icon(Icons.cancel, color: AppColors.danger, size: 20);
      } else {
        background = AppColors.surface.withValues(alpha: 0.5);
        textColor = AppColors.muted;
      }
    } else if (isSelected) {
      background = AppColors.primary.withValues(alpha: 0.1);
      border = AppColors.primary;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isRevealed ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border, width: 1.3),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.text,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

