import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/exercise.dart';
import '../widgets/audio_button.dart';
import 'lesson_exercise_flow.dart';

/// "Правда или ложь", as one of a Lesson's exercises: the backend hands back
/// a round built from THIS lesson's fixed word set (wrong-answer candidates
/// come from the user's previously-learned pool, never from other words in
/// this same lesson) -- this screen only renders one card at a time and
/// compares the tapped button to `item.isCorrect`.
///
/// After every answer, this screen reports {word_id, is_correct} to the
/// backend via submitLessonAnswer, which is the ONLY place a word's score
/// actually changes -- this screen never computes or trusts a score itself,
/// it just shows whatever the backend already decided next.
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
  int _correctCount = 0;
  bool _isAnswering = false;

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
        _correctCount = 0;
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

  /// The one rule of the whole exercise, kept as a plain function separate
  /// from any button/layout: independent of how many buttons there are or
  /// where they sit on screen, "Правда" is correct exactly when the shown
  /// translation is the real one.
  bool _isAnswerCorrect(TrueOrFalseItem item, bool userSaidTrue) => userSaidTrue == item.isCorrect;

  Future<void> _answer(bool userSaidTrue) async {
    if (_isAnswering || _index >= _items.length) return;
    final item = _items[_index];
    final correct = _isAnswerCorrect(item, userSaidTrue);
    setState(() {
      _isAnswering = true;
      if (correct) _correctCount++;
    });
    _showFeedback(correct ? 'Правильно' : 'Неправильно', isError: !correct);

    // The result itself is no longer read here: whether the lesson is
    // complete is decided once, at the end, by the lesson's own results
    // screen from fresh backend state. Still awaited, so the answer is
    // saved before the lesson moves on and the next exercise's round is
    // built from up-to-date scores.
    final submit = ApiClient.instance
        .submitLessonAnswer(widget.lessonId, 'true_or_false', wordId: item.wordId, isCorrect: correct)
        .then<void>((_) {})
        .catchError((_) {
      // A failed score update must never interrupt the flow card by card.
    });
    await Future.wait([submit, Future.delayed(const Duration(milliseconds: 500))]);

    if (!mounted) return;
    setState(() {
      _index++;
      _isAnswering = false;
    });
    // Last card answered -- the lesson runner takes over straight away.
    if (_index >= _items.length) finishExercise();
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
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Для этого упражнения пока нет слов', textAlign: TextAlign.center),
        ),
      );
    }

    final isRoundComplete = _index >= _items.length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Правильно: $_correctCount/${_items.length}',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: isRoundComplete
                ? const LessonExerciseHandoff()
                : Center(child: SingleChildScrollView(child: _TrueOrFalseCard(item: _items[_index]))),
          ),
          if (!isRoundComplete) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isAnswering ? null : () => _answer(false),
                    child: const Text('Ложь'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isAnswering ? null : () => _answer(true),
                    child: const Text('Правда'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TrueOrFalseCard extends StatelessWidget {
  final TrueOrFalseItem item;
  const _TrueOrFalseCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final hasTranscription = item.transcription != null && item.transcription!.isNotEmpty;
    final hasWordAudio = item.wordAudioUrl != null && item.wordAudioUrl!.isNotEmpty;
    final hasTranslationAudio = item.shownTranslationAudioUrl != null && item.shownTranslationAudioUrl!.isNotEmpty;

    return Container(
      key: ValueKey('true-or-false-card-${item.wordId}'),
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                ApiClient.instance.mediaUrl(item.imageUrl!),
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(height: 0),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  item.original,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
              ),
              if (hasWordAudio) ...[
                const SizedBox(width: 8),
                AudioButton(url: ApiClient.instance.mediaUrl(item.wordAudioUrl!), size: 22),
              ],
            ],
          ),
          if (hasTranscription)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(item.transcription!, style: const TextStyle(fontSize: 15, color: Colors.black45)),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  item.shownTranslation,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
              if (hasTranslationAudio) ...[
                const SizedBox(width: 8),
                AudioButton(url: ApiClient.instance.mediaUrl(item.shownTranslationAudioUrl!), size: 22),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
