import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import '../widgets/word_card.dart';

/// Shown once a "Начать урок" run has walked every available exercise type
/// (see LessonDetailScreen._startLesson) -- the ONE place a lesson's
/// pass/fail outcome is decided and shown, with the real, per-word reason
/// why. Never computes "is this word learned" itself: `lesson.words` here
/// is a FRESH fetch (GET /lessons/{id}) taken right after the exercise
/// sequence finished, so `isLearned`/`score`/`wordLevelName` are exactly
/// what the backend's own WordProgress/WordLevel ladder says -- the same
/// ladder "Мои слова" renders (GET /word-levels), never a second one.
///
/// Pops `true` if the user chooses "Повторить урок" (the caller re-runs
/// the exact same exercise sequence; each exercise's own round already
/// narrows itself to only the words still short of their level, so the
/// repeat only ever re-tests those), or `false`/nothing for "Готово".
class LessonResultsScreen extends StatefulWidget {
  final Lesson lesson;
  const LessonResultsScreen({super.key, required this.lesson});

  @override
  State<LessonResultsScreen> createState() => _LessonResultsScreenState();
}

class _LessonResultsScreenState extends State<LessonResultsScreen> {
  late Future<List<WordLevelSummary>> _levelsFuture;

  @override
  void initState() {
    super.initState();
    // Best-effort only -- the per-word level BADGE is a nice-to-have on
    // top of the always-shown score/progress bar, never required to
    // render the pass/fail outcome itself.
    _levelsFuture = ApiClient.instance.fetchWordLevels().catchError((_) => <WordLevelSummary>[]);
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final learnedCount = lesson.words.where((w) => w.isLearned).length;
    final total = lesson.words.length;
    final allLearned = lesson.isCompleted || (total > 0 && learnedCount == total);

    return PopScope(
      // Leaving via the system back gesture must mean the same thing as
      // tapping the primary button below -- never strand the user with an
      // ambiguous "which action did that count as" state.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Урок ${lesson.number}: результаты'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: FutureBuilder<List<WordLevelSummary>>(
            future: _levelsFuture,
            builder: (context, snapshot) {
              final levels = snapshot.data ?? const [];
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  _OutcomeBanner(allLearned: allLearned, learnedCount: learnedCount, total: total),
                  const SizedBox(height: 24),
                  const Text('Прогресс по словам', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (final word in lesson.words) _WordProgressRow(word: word, levels: levels),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(!allLearned),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text(allLearned ? 'Готово' : 'Повторить урок'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  final bool allLearned;
  final int learnedCount;
  final int total;
  const _OutcomeBanner({required this.allLearned, required this.learnedCount, required this.total});

  @override
  Widget build(BuildContext context) {
    final color = allLearned ? Colors.green : Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(allLearned ? Icons.check_circle : Icons.timelapse_rounded, color: color, size: 26),
              const SizedBox(width: 10),
              Text(
                allLearned ? 'Урок пройден' : 'Ещё не всё закреплено',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            allLearned
                ? 'Все $total слов этого урока достигли нужного уровня.'
                : 'Достигли нужного уровня: $learnedCount из $total. Остальные слова нужно закрепить ещё раз.',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0.0 : learnedCount / total,
              minHeight: 7,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// One word's result: the app's shared word card, plus the progress bar
/// that is this screen's whole point -- how far this word still is from
/// its required level. The score and the level are the backend's own
/// (see the class docstring); only the bar is drawn here.
class _WordProgressRow extends StatelessWidget {
  final LessonWord word;
  final List<WordLevelSummary> levels;
  const _WordProgressRow({required this.word, required this.levels});

  @override
  Widget build(BuildContext context) {
    final level = WordLevelView.resolve(word.wordLevelId, word.wordLevelName, levels);
    final color = word.isLearned ? AppColors.success : level.color;

    return WordCard(
      word: word.word,
      transcription: word.transcription,
      translation: word.translation,
      audioUrl: word.wordAudioUrl,
      level: level,
      trailing: word.isLearned ? const Icon(Icons.check_circle, color: AppColors.success, size: 18) : null,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (word.score / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: const Color(0xFFEDEFF7),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            word.isLearned ? 'Закреплено' : 'Нужно ещё · ${word.score}/100',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
