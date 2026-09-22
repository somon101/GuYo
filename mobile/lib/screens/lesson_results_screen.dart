import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import '../models/word.dart';

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

/// Position-based red-to-green color for a word level -- same purely
/// visual mapping learned_words_screen.dart's own _wordLevelColor uses
/// (the backend decides which level a word is in and the levels' order;
/// only "what color goes at this position" is left to the client).
Color _wordLevelColor(int index, int total) {
  if (total <= 1) return const Color(0xFF43A047);
  final t = index / (total - 1);
  return Color.lerp(const Color(0xFFE53935), const Color(0xFF43A047), t)!;
}

class _WordProgressRow extends StatelessWidget {
  final LessonWord word;
  final List<WordLevelSummary> levels;
  const _WordProgressRow({required this.word, required this.levels});

  @override
  Widget build(BuildContext context) {
    final levelIndex = word.wordLevelId == null ? -1 : levels.indexWhere((l) => l.id == word.wordLevelId);
    final levelColor = levelIndex == -1 ? null : _wordLevelColor(levelIndex, levels.length);
    final color = word.isLearned ? Colors.green.shade600 : (levelColor ?? Colors.orange.shade700);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: word.isLearned ? Colors.green.shade50 : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: word.isLearned ? Colors.green.shade300 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(word.word, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    if (word.translation != null && word.translation!.isNotEmpty)
                      Text(word.translation!, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
              if (word.isLearned)
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 20)
              else if (word.wordLevelName != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    word.wordLevelName!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                  ),
                )
              else
                Text('${word.score}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (word.score / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.grey.shade200,
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
