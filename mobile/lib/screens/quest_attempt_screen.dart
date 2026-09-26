import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/dictionary.dart';
import '../models/exercise.dart';
import '../models/lesson.dart';
import '../models/quest.dart';
import '../models/word.dart';
import '../services/answer_sound.dart';
import '../theme/app_colors.dart';
import '../widgets/exercises/build_word_exercise.dart';
import '../widgets/exercises/choice_tile.dart';
import '../widgets/exercises/listen_word_exercise.dart';
import '../widgets/exercises/speaking_word_exercise.dart';
import '../widgets/exercises/true_or_false_exercise.dart';

/// One quest attempt: fetches a ONE-target-word round and renders whichever
/// of the 5 exercise types the quest uses, reporting exactly one
/// {word_id, is_correct} back -- same "backend decides the round and
/// points, client only compares" principle the Lesson screens already
/// follow. Deliberately NOT a multi-round chain like a Lesson: a quest is
/// over the moment this one word is answered.
///
/// For 4 of the 5 types (true_or_false, build_word, speaking_word,
/// listen_word) this renders the EXACT SAME widget a Lesson round does --
/// widgets/exercises/*_exercise.dart -- so a design change to one of those
/// is a design change here too, automatically. Сопоставление is the one
/// exception: the backend hands a quest a genuinely different round shape
/// for it (a flat word list to pick from, never a real pair-matching
/// board -- see _MatchingQuest's own note for why) and this screen keeps
/// that interaction, just restyled to the same visual language.
class QuestAttemptScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  final int questId;
  final String questName;
  const QuestAttemptScreen({super.key, required this.dictionary, required this.questId, required this.questName});

  @override
  State<QuestAttemptScreen> createState() => _QuestAttemptScreenState();
}

class _QuestAttemptScreenState extends State<QuestAttemptScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  QuestRound? _round;
  QuestAnswerResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _round = null;
      _result = null;
    });
    try {
      final round = await ApiClient.instance.fetchQuestRound(widget.questId, widget.dictionary.id);
      if (!mounted) return;
      setState(() {
        _round = round;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить квест';
      });
    }
  }

  Future<void> _submit(bool isCorrect) async {
    final round = _round;
    if (round == null || _result != null) return;
    try {
      final result = await ApiClient.instance.submitQuestAnswer(
        widget.questId,
        widget.dictionary.id,
        wordId: round.wordId,
        isCorrect: isCorrect,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Не удалось сохранить результат');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(widget.questName)),
        body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: _buildBody())),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _round == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    }
    final round = _round!;
    final result = _result;
    if (result != null) {
      return _QuestResultView(result: result, onDone: () => Navigator.of(context).pop());
    }
    return Center(child: SingleChildScrollView(child: _exerciseFor(round)));
  }

  /// Renders whichever of the 5 exercise types this round uses. 4 of them
  /// parse `payload` into the EXACT SAME round models a Lesson fetch
  /// returns and hand the widget its one item -- see this file's own doc
  /// comment for why that means one shared implementation, not five.
  Widget _exerciseFor(QuestRound round) {
    switch (round.exerciseKey) {
      case 'true_or_false':
        final item = TrueOrFalseRound.fromJson(round.payload).items.first;
        return TrueOrFalseExercise(item: item, onAnswer: _submit);
      case 'build_word':
        final parsed = BuildWordRound.fromJson(round.payload);
        return BuildWordExercise(item: parsed.items.first, caseSensitive: parsed.caseSensitive, onAnswer: _submit);
      case 'speaking_word':
        final parsed = SpeakingWordRound.fromJson(round.payload);
        return SpeakingWordExercise(item: parsed.items.first, matchThreshold: parsed.matchThreshold, onAnswer: _submit);
      case 'listen_word':
        final item = ListenWordRound.fromJson(round.payload).items.first;
        return ListenWordExercise(item: item, onAnswer: _submit);
      case 'matching':
        return _MatchingQuest(payload: round.payload, onAnswer: _submit);
      default:
        return const Text('Неизвестный тип упражнения');
    }
  }
}

class _QuestResultView extends StatelessWidget {
  final QuestAnswerResult result;
  final VoidCallback onDone;
  const _QuestResultView({required this.result, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final correct = result.isCorrect;
    final color = correct ? AppColors.success : AppColors.danger;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(correct ? Icons.check_rounded : Icons.close_rounded, color: color, size: 48),
          ),
          const SizedBox(height: 18),
          Text(
            correct ? 'Квест выполнен!' : 'Не в этот раз',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 6),
          Text('Очки закрепления слова: ${result.score}', style: const TextStyle(color: AppColors.secondaryText)),
          if (result.rewardGranted > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: AppColors.rewardBackground, borderRadius: BorderRadius.circular(AppShapes.pillRadius)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 16, color: AppColors.rewardText),
                  const SizedBox(width: 4),
                  Text(
                    '+${result.rewardGranted} рейтинговых очков',
                    style: const TextStyle(color: AppColors.rewardText, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(width: 200, child: FilledButton(onPressed: onDone, child: const Text('Готово'))),
        ],
      ),
    );
  }
}

// --- Сопоставление (Quest-only shape) --------------------------------------
// Simplified for a single-target quest: the target word (always first --
// see backend/app/quests/rounds.py's build_matching_round) plus a few
// sibling translations as multiple-choice options, rather than the full
// multi-pair board «Сопоставление» uses in a Lesson (which has no single
// "target" word to score against, and gets a different round shape from
// the backend entirely). Business logic unchanged from before this
// redesign pass -- only the tiles are now [ChoiceTile], the same one
// «Услышь слово» uses, so this still reads as part of the same family
// even though the interaction itself can't be unified with Lesson
// matching without changing what the backend hands a quest.
class _MatchingQuest extends StatefulWidget {
  final Map<String, dynamic> payload;
  final ValueChanged<bool> onAnswer;
  const _MatchingQuest({required this.payload, required this.onAnswer});

  @override
  State<_MatchingQuest> createState() => _MatchingQuestState();
}

class _MatchingQuestState extends State<_MatchingQuest> {
  late final GuyoWord _target;
  late final List<GuyoWord> _options;
  GuyoWord? _selected;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    final words = (widget.payload['words'] as List<dynamic>).map((e) => GuyoWord.fromJson(e as Map<String, dynamic>)).toList();
    _target = words.first;
    _options = [...words]..shuffle();
  }

  void _tap(GuyoWord option) {
    if (_locked) return;
    final correct = option.id == _target.id;
    setState(() {
      _selected = option;
      _locked = true;
    });
    AnswerSound.play(correct);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted) widget.onAnswer(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRevealed = _selected != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppShapes.cardRadius),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: AppShapes.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _target.word,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                textAlign: TextAlign.center,
              ),
              if (_target.transcription != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_target.transcription!, style: const TextStyle(color: AppColors.secondaryText)),
                ),
              const SizedBox(height: 6),
              const Text('Выберите перевод', style: TextStyle(color: AppColors.secondaryText, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final option in _options) ...[
          ChoiceTile(
            label: option.translation,
            isSelected: _selected?.id == option.id,
            isRevealed: isRevealed,
            isCorrectOption: option.id == _target.id,
            onTap: isRevealed ? null : () => _tap(option),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
