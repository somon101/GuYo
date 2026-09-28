import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import '../widgets/word_card.dart';
import 'lesson_run_screen.dart' show lessonExerciseLabels;

/// Shown once a "Начать урок" run has walked every available exercise type
/// (see LessonRunScreen) -- the ONE place a lesson's
/// pass/fail outcome is decided and shown, with the real, per-word reason
/// why. Never computes "is this word learned" itself: `lesson.words` here
/// is a FRESH fetch (GET /lessons/{id}) taken right after the exercise
/// sequence finished, so `isLearned`/`score`/`wordLevelName` are exactly
/// what the backend's own WordProgress/WordLevel ladder says -- the same
/// ladder "Мои слова" renders (GET /word-levels), never a second one.
///
/// Pops `true` if the user chooses "Повторить урок" (the caller re-runs
/// the exact same exercise sequence; the new pass covers only the words
/// still short of their level, so the repeat only ever re-tests those),
/// or `false`/nothing for "Готово".
class LessonResultsScreen extends StatefulWidget {
  final Lesson lesson;

  /// The pass's statistics; null (couldn't be loaded) just hides them.
  final LessonPassStats? stats;
  const LessonResultsScreen({super.key, required this.lesson, this.stats});

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
                  if (widget.stats != null && widget.stats!.totalAnswers > 0) ...[
                    const SizedBox(height: 16),
                    _PassStatsBlock(stats: widget.stats!),
                  ],
                  const SizedBox(height: 24),
                  const Text('Прогресс по словам', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (final word in lesson.words)
                    _WordProgressRow(word: word, levels: levels, gained: widget.stats?.forWord(word.wordId)?.gained),
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
  Widget? _trailing() {
    final check = word.isLearned ? const Icon(Icons.check_circle, color: AppColors.success, size: 18) : null;
    final g = gained;
    if (g == null || g == 0) return check;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: g > 0 ? AppColors.successLight : AppColors.dangerLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            g > 0 ? '+$g' : '$g',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: g > 0 ? AppColors.success : AppColors.danger,
            ),
          ),
        ),
        if (check != null) ...[const SizedBox(width: 6), check],
      ],
    );
  }

  final LessonWord word;
  final List<WordLevelSummary> levels;

  /// Score gained in this pass, when the statistics loaded.
  final int? gained;
  const _WordProgressRow({required this.word, required this.levels, this.gained});

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
      trailing: _trailing(),
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

String _formatDuration(int seconds) {
  if (seconds < 60) return '$seconds с';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '$m мин' : '$m мин $s с';
}

/// The pass in numbers: an accuracy ring, right / wrong / time tiles, a
/// bar per exercise, and the score gained.
class _PassStatsBlock extends StatelessWidget {
  final LessonPassStats stats;
  const _PassStatsBlock({required this.stats});

  @override
  Widget build(BuildContext context) {
    final ringColor = stats.accuracy >= 80
        ? AppColors.success
        : stats.accuracy >= 50
            ? AppColors.primary
            : AppColors.danger;
    return Container(
      key: const ValueKey('lesson-pass-stats'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: CircularProgressIndicator(
                        value: stats.accuracy / 100,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: AppColors.progressTrack,
                        valueColor: AlwaysStoppedAnimation(ringColor),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${stats.accuracy}%',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ringColor),
                        ),
                        const Text('точность', style: TextStyle(fontSize: 10.5, color: AppColors.secondaryText)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Статистика урока',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Pill(
                          text: '+${stats.scoreGained} очков',
                          color: AppColors.rewardText,
                          background: AppColors.gold.withValues(alpha: 0.35),
                        ),
                        if (stats.newlyLearned > 0)
                          _Pill(
                            text: 'Выучено новых: ${stats.newlyLearned}',
                            color: AppColors.success,
                            background: AppColors.successLight,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _StatTile(label: 'Верно', value: '${stats.correctAnswers}', color: AppColors.success)),
              const SizedBox(width: 8),
              Expanded(child: _StatTile(label: 'Ошибки', value: '${stats.wrongAnswers}', color: AppColors.danger)),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  label: 'Время',
                  value: _formatDuration(stats.durationSeconds),
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (stats.exercises.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'ПО УПРАЖНЕНИЯМ',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            for (final e in stats.exercises) _ExerciseBar(stat: e),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  const _Pill({required this.text, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
        ],
      ),
    );
  }
}

class _ExerciseBar extends StatelessWidget {
  final PassExerciseStat stat;
  const _ExerciseBar({required this.stat});

  @override
  Widget build(BuildContext context) {
    final ratio = stat.total == 0 ? 0.0 : stat.correct / stat.total;
    final color = ratio >= 0.8
        ? AppColors.success
        : ratio >= 0.5
            ? AppColors.primary
            : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lessonExerciseLabels[stat.exerciseKey] ?? stat.exerciseKey,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                ),
              ),
              Text(
                '${stat.correct} из ${stat.total}',
                style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.progressTrack,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
