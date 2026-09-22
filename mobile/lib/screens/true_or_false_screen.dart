import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/exercise.dart';
import '../widgets/audio_button.dart';

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

class _TrueOrFalseScreenState extends State<TrueOrFalseScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<TrueOrFalseItem> _items = [];
  int _index = 0;
  int _correctCount = 0;
  bool _isAnswering = false;
  bool _lessonCompleted = false;

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

    final submit = ApiClient.instance
        .submitLessonAnswer(widget.lessonId, 'true_or_false', wordId: item.wordId, isCorrect: correct)
        .then((result) {
      if (result.lessonCompleted) _lessonCompleted = true;
    }).catchError((_) {
      // The score update failed to save -- surfaced once at round-complete
      // rather than interrupting the quiz flow card by card.
    });
    await Future.wait([submit, Future.delayed(const Duration(milliseconds: 500))]);

    if (!mounted) return;
    setState(() {
      _index++;
      _isAnswering = false;
    });
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
                ? _RoundCompleteView(
                    correctCount: _correctCount,
                    total: _items.length,
                    lessonCompleted: _lessonCompleted,
                    onPlayAgain: _load,
                    // Always a plain pop back to the lesson-runner
                    // sequencer -- see matching_screen.dart's identical
                    // comment.
                    onBackToLesson: () => Navigator.of(context).pop(),
                  )
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

class _RoundCompleteView extends StatelessWidget {
  final int correctCount;
  final int total;
  final bool lessonCompleted;
  final VoidCallback onPlayAgain;
  final VoidCallback onBackToLesson;

  const _RoundCompleteView({
    required this.correctCount,
    required this.total,
    required this.lessonCompleted,
    required this.onPlayAgain,
    required this.onBackToLesson,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 56),
          const SizedBox(height: 12),
          const Text('Упражнение завершено!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Правильно: $correctCount из $total', style: const TextStyle(color: Colors.black54)),
          if (lessonCompleted) ...[
            const SizedBox(height: 8),
            const Text('Урок пройден!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onBackToLesson,
            icon: Icon(lessonCompleted ? Icons.emoji_events_outlined : Icons.arrow_back),
            label: Text(lessonCompleted ? 'Продолжить' : 'К уроку'),
          ),
          const SizedBox(height: 8),
          if (!lessonCompleted)
            OutlinedButton.icon(
              onPressed: onPlayAgain,
              icon: const Icon(Icons.refresh),
              label: const Text('Играть ещё раз'),
            ),
        ],
      ),
    );
  }
}
