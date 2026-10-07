import '../l10n/l10n.dart';
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
    final stats = widget.stats;
    final learnedCount = lesson.words.where((w) => w.isLearned).length;
    final total = lesson.words.length;
    final allLearned = lesson.isCompleted || (total > 0 && learnedCount == total);
    final hasStats = stats != null && stats.totalAnswers > 0;

    return PopScope(
      // Leaving via the system back gesture must mean the same thing as
      // tapping the primary button below -- never strand the user with an
      // ambiguous "which action did that count as" state.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: FutureBuilder<List<WordLevelSummary>>(
            future: _levelsFuture,
            builder: (context, snapshot) {
              final levels = snapshot.data ?? const [];
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Center(
                    child: Text(
                      tr('Урок {0}', [lesson.number]),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ScoreRing(
                    value: hasStats ? stats.accuracy : (total == 0 ? 0 : (learnedCount * 100 / total).round()),
                    caption: hasStats ? tr('точность') : tr('закреплено'),
                  ),
                  const SizedBox(height: 14),
                  _OutcomeCard(
                    allLearned: allLearned,
                    learnedCount: learnedCount,
                    total: total,
                    scoreGained: hasStats ? stats.scoreGained : null,
                  ),
                  if (hasStats) ...[
                    const SizedBox(height: 12),
                    _TileGrid(key: const ValueKey('lesson-pass-stats'), children: [
                      _MetricTile(
                        icon: Icons.check_circle_rounded,
                        label: tr('Верно'),
                        value: '${stats.correctAnswers}',
                        suffix: '/ ${stats.totalAnswers}',
                        ratio: stats.correctAnswers / stats.totalAnswers,
                        color: AppColors.success,
                      ),
                      _MetricTile(
                        icon: Icons.cancel_rounded,
                        label: tr('Ошибки'),
                        value: '${stats.wrongAnswers}',
                        suffix: '/ ${stats.totalAnswers}',
                        ratio: stats.wrongAnswers / stats.totalAnswers,
                        color: AppColors.danger,
                      ),
                      _MetricTile(
                        icon: Icons.timer_rounded,
                        label: tr('Время'),
                        value: _formatDuration(stats.durationSeconds),
                        color: const Color(0xFF2BB5E8),
                      ),
                      _MetricTile(
                        icon: Icons.auto_awesome_rounded,
                        label: tr('Выучено новых'),
                        value: '${stats.newlyLearned}',
                        suffix: total == 0 ? null : '/ $total',
                        ratio: total == 0 ? null : stats.newlyLearned / total,
                        color: const Color(0xFFFF8A3D),
                      ),
                    ]),
                    if (stats.exercises.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _SectionLabel(tr('По упражнениям')),
                      const SizedBox(height: 8),
                      _TileGrid(children: [
                        for (var i = 0; i < stats.exercises.length; i++)
                          _ExerciseTile(stat: stats.exercises[i], color: _palette[i % _palette.length]),
                      ]),
                    ],
                  ],
                  const SizedBox(height: 20),
                  _SectionLabel(tr('Прогресс по словам')),
                  const SizedBox(height: 8),
                  for (final word in lesson.words)
                    _WordProgressRow(word: word, levels: levels, gained: stats?.forWord(word.wordId)?.gained),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(!allLearned),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      icon: Icon(allLearned ? Icons.check_rounded : Icons.refresh_rounded),
                      label: Text(
                        allLearned ? tr('Готово') : tr('Повторить урок'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (!allLearned)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(tr('Закончить'), style: const TextStyle(color: AppColors.secondaryText)),
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

const _palette = [Color(0xFF2BB5E8), Color(0xFF34C759), Color(0xFFC86DD7), Color(0xFFFF6B6B), Color(0xFFFF8A3D)];

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
      );
}

/// The big number in the middle: a soft colourful glow, a ring that fills
/// up to [value] (out of 100) and the number counting up with it.
class _ScoreRing extends StatelessWidget {
  final int value;
  final String caption;
  const _ScoreRing({required this.value, required this.caption});

  Color get _color => value >= 80
      ? AppColors.success
      : value >= 50
          ? AppColors.primary
          : AppColors.danger;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The pastel glow behind the ring.
          Container(
            width: 220,
            height: 220,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x3354D2F0), Color(0x22C86DD7), Color(0x0034C759)],
                stops: [0.2, 0.6, 1],
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => SizedBox(
              width: 168,
              height: 168,
              child: CustomPaint(
                painter: _RingPainter(progress: v / 100, color: _color),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${v.round()}',
                        style: const TextStyle(
                          fontSize: 52,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('/ 100 · $caption', style: const TextStyle(fontSize: 13, color: AppColors.secondaryText)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawCircle(
      rect.center,
      arcRect.width / 2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawArc(
      arcRect,
      0,
      6.2832,
      false,
      Paint()
        ..color = AppColors.progressTrack
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress > 0) {
      canvas.drawArc(
        arcRect,
        -1.5708,
        6.2832 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..shader = SweepGradient(
            startAngle: -1.5708,
            endAngle: 4.7124,
            colors: [color.withValues(alpha: 0.55), color],
          ).createShader(arcRect)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

/// "Урок пройден" / "Ещё не всё закреплено", how many words made it, and
/// the points gained as a green badge -- one compact white card.
class _OutcomeCard extends StatelessWidget {
  final bool allLearned;
  final int learnedCount;
  final int total;
  final int? scoreGained;
  const _OutcomeCard({required this.allLearned, required this.learnedCount, required this.total, this.scoreGained});

  @override
  Widget build(BuildContext context) {
    final color = allLearned ? AppColors.success : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
            ),
            child: Icon(allLearned ? Icons.emoji_events_rounded : Icons.trending_up_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          if (scoreGained != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Text(
                tr('+{0} очков', [scoreGained!]),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.success),
              ),
            ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                allLearned ? tr('Урок пройден') : tr('Почти готово'),
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 2),
              Text(
                tr('Закреплено {0} из {1}', [learnedCount, total]),
                style: const TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Two tiles per row, like a dashboard.
class _TileGrid extends StatelessWidget {
  final List<Widget> children;
  const _TileGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: children[i]),
                  const SizedBox(width: 10),
                  Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A soft tinted tile: icon + label, the value big, and a thin bar.
class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? suffix;
  final double? ratio;
  final Color color;
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.suffix,
    this.ratio,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0.03)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  ),
                  if (suffix != null)
                    TextSpan(text: ' $suffix', style: const TextStyle(fontSize: 13, color: AppColors.secondaryText)),
                ],
              ),
            ),
          ),
          if (ratio != null) ...[
            const SizedBox(height: 10),
            _Bar(ratio: ratio!, color: color),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double ratio;
  final Color color;
  const _Bar({required this.ratio, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: v,
          minHeight: 7,
          backgroundColor: Colors.white,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

/// One exercise in the pass: its name, right answers out of all, a bar.
class _ExerciseTile extends StatelessWidget {
  final PassExerciseStat stat;
  final Color color;
  const _ExerciseTile({required this.stat, required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio = stat.total == 0 ? 0.0 : stat.correct / stat.total;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lessonExerciseLabels[stat.exerciseKey] ?? stat.exerciseKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${stat.correct}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                TextSpan(text: ' / ${stat.total}', style: const TextStyle(fontSize: 13, color: AppColors.secondaryText)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 7,
                backgroundColor: AppColors.progressTrack,
                valueColor: AlwaysStoppedAnimation(color),
              ),
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
            word.isLearned ? tr('Закреплено') : tr('Нужно ещё · {0}/100', [word.score]),
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds < 60) return tr('{0} с', [seconds]);
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? tr('{0} мин', [m]) : tr('{0} мин {1} с', [m, s]);
}

