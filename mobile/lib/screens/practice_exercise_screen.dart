import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../exercises/exercise_type.dart';
import '../models/dictionary.dart';
import '../models/exercise.dart';
import '../models/lesson.dart';
import '../theme/app_colors.dart';
import '../widgets/exercises/build_word_exercise.dart';
import '../widgets/exercises/listen_word_exercise.dart';
import '../widgets/exercises/practice_round_complete.dart';
import '../widgets/exercises/speaking_word_exercise.dart';
import '../widgets/exercises/true_or_false_exercise.dart';
import '../widgets/guyo_ui.dart';

/// «Практика» for the 4 word-scoped exercise types whose round is a plain
/// sequence of items: «Правда или ложь», «Собери слово», «Произнеси
/// слово», «Услышь слово» (Сопоставление has its own host,
/// practice_matching_screen.dart, because its round shape -- a board, not
/// a sequence -- is different).
///
/// Renders the EXACT SAME widget -- widgets/exercises/*_exercise.dart --
/// that Уроки and Квесты already use for these types. This screen's only
/// job is fetching a fresh random round from "Мои изученные слова" (see
/// backend/app/routers/practice.py) and sequencing through it; it never
/// reports an answer anywhere, since Practice keeps no score of its own.
class PracticeExerciseScreen extends StatefulWidget {
  final GuyoDictionary dictionary;
  final ExerciseTypeInfo type;
  const PracticeExerciseScreen({super.key, required this.dictionary, required this.type});

  @override
  State<PracticeExerciseScreen> createState() => _PracticeExerciseScreenState();
}

class _PracticeExerciseScreenState extends State<PracticeExerciseScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  TrueOrFalseRound? _trueOrFalse;
  BuildWordRound? _buildWord;
  SpeakingWordRound? _speakingWord;
  ListenWordRound? _listenWord;

  int _index = 0;
  int _correctCount = 0;

  int get _total => switch (widget.type.key) {
        'true_or_false' => _trueOrFalse?.items.length ?? 0,
        'build_word' => _buildWord?.items.length ?? 0,
        'speaking_word' => _speakingWord?.items.length ?? 0,
        'listen_word' => _listenWord?.items.length ?? 0,
        _ => 0,
      };

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
      final dictionaryId = widget.dictionary.id;
      switch (widget.type.key) {
        case 'true_or_false':
          _trueOrFalse = await ApiClient.instance.fetchPracticeTrueOrFalseRound(dictionaryId);
        case 'build_word':
          _buildWord = await ApiClient.instance.fetchPracticeBuildWordRound(dictionaryId);
        case 'speaking_word':
          _speakingWord = await ApiClient.instance.fetchPracticeSpeakingWordRound(dictionaryId);
        case 'listen_word':
          _listenWord = await ApiClient.instance.fetchPracticeListenWordRound(dictionaryId);
      }
      if (!mounted) return;
      setState(() {
        _index = 0;
        _correctCount = 0;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить упражнение';
      });
    }
  }

  void _onAnswer(bool correct) {
    if (!mounted) return;
    setState(() {
      if (correct) _correctCount++;
      _index++;
    });
  }

  Widget _currentItem() {
    switch (widget.type.key) {
      case 'true_or_false':
        final item = _trueOrFalse!.items[_index];
        return TrueOrFalseExercise(key: ValueKey(item.wordId), item: item, onAnswer: _onAnswer);
      case 'build_word':
        final round = _buildWord!;
        final item = round.items[_index];
        return BuildWordExercise(key: ValueKey(item.wordId), item: item, caseSensitive: round.caseSensitive, onAnswer: _onAnswer);
      case 'speaking_word':
        final round = _speakingWord!;
        final item = round.items[_index];
        // No onUnavailable: unlike a Lesson (which skips to its next
        // exercise), Practice IS this one exercise -- the widget's own
        // built-in "recognition unavailable" message and retry button are
        // already the right thing to show here, with nowhere to skip to.
        return SpeakingWordExercise(key: ValueKey(item.wordId), item: item, matchThreshold: round.matchThreshold, onAnswer: _onAnswer);
      case 'listen_word':
        final item = _listenWord!.items[_index];
        return ListenWordExercise(key: ValueKey(item.wordId), item: item, onAnswer: _onAnswer);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(widget.type.label)),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
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
    final total = _total;
    if (total == 0) {
      return const PracticeEmptyState();
    }
    if (_index >= total) {
      return PracticeRoundComplete(
        correctCount: _correctCount,
        total: total,
        onPlayAgain: _load,
        onBack: () => Navigator.of(context).pop(),
      );
    }
    return Column(
      children: [
        _PracticeProgressHeader(correctCount: _correctCount, position: _index + 1, total: total),
        const SizedBox(height: 20),
        Expanded(child: Center(child: SingleChildScrollView(child: _currentItem()))),
      ],
    );
  }
}

/// Practice's own progress readout: a correct-so-far count with a check
/// icon (never a star -- Practice grants no real rating points, and a star
/// would read as if it did) plus "Слово N из M", in the same pill family
/// every other exercise header uses.
class _PracticeProgressHeader extends StatelessWidget {
  final int correctCount;
  final int position;
  final int total;
  const _PracticeProgressHeader({required this.correctCount, required this.position, required this.total});

  @override
  Widget build(BuildContext context) {
    return GuyoCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
          const SizedBox(width: 6),
          Text('$correctCount', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          const SizedBox(width: 14),
          Container(width: 1, height: 20, color: AppColors.cardBorder),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(AppShapes.pillRadius)),
            child: Text(
              'Слово $position из $total',
              style: const TextStyle(fontSize: 13, color: AppColors.primaryDark, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
