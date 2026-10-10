import '../l10n/l10n.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import '../models/word.dart';
import '../theme/app_colors.dart';
import '../widgets/word_card.dart';
import 'lesson_run_screen.dart' show lessonExerciseLabels;
import '../widgets/achievement_celebration.dart';

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

class _LessonResultsScreenState extends State<LessonResultsScreen> with SingleTickerProviderStateMixin {
  late Future<List<WordLevelSummary>> _levelsFuture;

  /// The opening sequence: the centre ring, then the rings around it one
  /// by one, then the cards below one by one, each bar filling as its card
  /// appears.
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))
        // Achievements this lesson earned are celebrated right here, once
        // the results have played in.
        ..forward().whenComplete(() {
          if (mounted) celebrateNewAchievements(context);
        });

  Animation<double> _at(double begin, double end) =>
      CurvedAnimation(parent: _intro, curve: Interval(begin, end.clamp(0.0, 1.0), curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

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
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ScoreOrbit(
                    intro: _intro,
                    value: hasStats ? stats.accuracy : (total == 0 ? 0 : (learnedCount * 100 / total).round()),
                    caption: hasStats ? tr('точность') : tr('закреплено'),
                    satellites: _satellites(stats, learnedCount, total),
                  ),
                  const SizedBox(height: 10),
                  _Reveal(
                    animation: _at(0.50, 0.68),
                    child: _OutcomeCard(
                      allLearned: allLearned,
                      learnedCount: learnedCount,
                      total: total,
                      scoreGained: hasStats ? stats.scoreGained : null,
                    ),
                  ),
                  if (hasStats) ...[
                    const SizedBox(height: 12),
                    _TileGrid(key: const ValueKey('lesson-pass-stats'), children: [
                      _Reveal(
                        animation: _at(0.58, 0.78),
                        child: _MetricTile(
                        icon: Icons.check_circle_rounded,
                        label: tr('Верно'),
                        value: '${stats.correctAnswers}',
                        suffix: '/ ${stats.totalAnswers}',
                        ratio: stats.correctAnswers / stats.totalAnswers,
                        color: AppColors.success,
                      ),
                      ),
                      _Reveal(
                        animation: _at(0.64, 0.84),
                        child: _MetricTile(
                        icon: Icons.cancel_rounded,
                        label: tr('Ошибки'),
                        value: '${stats.wrongAnswers}',
                        suffix: '/ ${stats.totalAnswers}',
                        ratio: stats.wrongAnswers / stats.totalAnswers,
                        color: AppColors.danger,
                      ),
                      ),
                      _Reveal(
                        animation: _at(0.70, 0.90),
                        child: _MetricTile(
                        icon: Icons.timer_rounded,
                        label: tr('Время'),
                        value: _formatDuration(stats.durationSeconds),
                        color: const Color(0xFF2BB5E8),
                      ),
                      ),
                      _Reveal(
                        animation: _at(0.76, 0.96),
                        child: _MetricTile(
                        icon: Icons.auto_awesome_rounded,
                        label: tr('Выучено новых'),
                        value: '${stats.newlyLearned}',
                        suffix: total == 0 ? null : '/ $total',
                        ratio: total == 0 ? null : stats.newlyLearned / total,
                        color: const Color(0xFFFF8A3D),
                      ),
                      ),
                    ]),
                    if (stats.exercises.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _Reveal(animation: _at(0.76, 0.9), child: _SectionLabel(tr('По упражнениям'))),
                      const SizedBox(height: 8),
                      _TileGrid(children: [
                        for (var i = 0; i < stats.exercises.length; i++)
                          _Reveal(
                            animation: _at(0.80 + 0.04 * i, 0.98),
                            child: _ExerciseTile(stat: stats.exercises[i], color: _palette[i % _palette.length]),
                          ),
                      ]),
                    ],
                  ],
                  const SizedBox(height: 20),
                  _Reveal(animation: _at(0.84, 1.0), child: _SectionLabel(tr('Прогресс по словам'))),
                  const SizedBox(height: 8),
                  for (final word in lesson.words)
                    _Reveal(
                      animation: _at(0.85, 1.0),
                      child: _WordProgressRow(word: word, levels: levels, gained: stats?.forWord(word.wordId)?.gained),
                    ),
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
                      child: Text(tr('Закончить'), style: TextStyle(color: AppColors.secondaryText)),
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

/// The rings around the centre: one per exercise of the pass, or -- with
/// fewer than two exercises -- right answers and words learned.
List<_Satellite> _satellites(LessonPassStats? stats, int learned, int total) {
  if (stats != null && stats.exercises.length >= 2) {
    return [
      for (var i = 0; i < stats.exercises.length; i++)
        _Satellite(
          label: lessonExerciseLabels[stats.exercises[i].exerciseKey] ?? stats.exercises[i].exerciseKey,
          percent: stats.exercises[i].total == 0 ? 0 : (stats.exercises[i].correct * 100 / stats.exercises[i].total).round(),
          color: _palette[i % _palette.length],
        ),
    ];
  }
  return [
    if (stats != null && stats.totalAnswers > 0)
      _Satellite(label: tr('Верно'), percent: (stats.correctAnswers * 100 / stats.totalAnswers).round(), color: _palette[1]),
    _Satellite(label: tr('Закреплено'), percent: total == 0 ? 0 : (learned * 100 / total).round(), color: _palette[4]),
  ];
}

const _palette = [Color(0xFF2BB5E8), Color(0xFF34C759), Color(0xFFC86DD7), Color(0xFFFF6B6B), Color(0xFFFF8A3D)];

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
      );
}

/// One small ring around the centre.
class _Satellite {
  final String label;
  final int percent;
  final Color color;
  const _Satellite({required this.label, required this.percent, required this.color});
}

/// The centrepiece: the big score in a ring, and around it a small ring
/// per part of the lesson with its name written along the circle, little
/// coloured dots beside each and a pastel glow in their colours. On
/// opening, the centre comes first, then the rings around it one by one,
/// each filling up as it lands.
class _ScoreOrbit extends StatelessWidget {
  final Animation<double> intro;
  final int value;
  final String caption;
  final List<_Satellite> satellites;
  const _ScoreOrbit({required this.intro, required this.value, required this.caption, required this.satellites});

  static const double _size = 330;
  static const double _orbit = 104;
  static const double _labelRadius = 152;
  static const double _sat = 56;

  Color get _color => value >= 80
      ? AppColors.success
      : value >= 50
          ? AppColors.primary
          : AppColors.danger;

  double _phase(double begin, double end) =>
      Interval(begin, end, curve: Curves.easeOutBack).transform(intro.value).clamp(0.0, 1.2);

  double _fill(double begin, double end) => Interval(begin, end, curve: Curves.easeOutCubic).transform(intro.value);

  @override
  Widget build(BuildContext context) {
    final n = satellites.length;
    double angleOf(int i) => -math.pi / 2 + 2 * math.pi * i / n;
    // Satellite i lands in its own slice of the first half of the intro.
    (double, double) slot(int i) {
      final begin = 0.14 + 0.32 * i / n;
      return (begin, begin + 0.2);
    }

    return SizedBox(
      height: _size,
      child: AnimatedBuilder(
        animation: intro,
        builder: (context, _) {
          final centreIn = _phase(0.0, 0.2);
          final centreFill = _fill(0.05, 0.5);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // The glow, tinted by every ring's colour.
              Opacity(
                opacity: _fill(0.0, 0.3),
                child: SizedBox(
                  width: _size,
                  height: _size,
                  child: Stack(
                    children: [
                      for (var i = 0; i < n; i++)
                        Positioned(
                          left: _size / 2 + math.cos(angleOf(i)) * 60 - 90,
                          top: _size / 2 + math.sin(angleOf(i)) * 60 - 90,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [satellites[i].color.withValues(alpha: 0.16), satellites[i].color.withValues(alpha: 0)],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Labels along the circle and the decorative dots.
              CustomPaint(
                size: const Size(_size, _size),
                painter: _OrbitDecorPainter(
                  satellites: satellites,
                  orbit: _orbit,
                  labelRadius: _labelRadius,
                  appear: [for (var i = 0; i < n; i++) _fill(slot(i).$1, slot(i).$2)],
                ),
              ),
              for (var i = 0; i < n; i++)
                Positioned(
                  left: _size / 2 + math.cos(angleOf(i)) * _orbit - _sat / 2,
                  top: _size / 2 + math.sin(angleOf(i)) * _orbit - _sat / 2,
                  child: Transform.scale(
                    scale: _phase(slot(i).$1, slot(i).$2),
                    child: SizedBox(
                      width: _sat,
                      height: _sat,
                      child: CustomPaint(
                        painter: _RingPainter(
                          progress: satellites[i].percent / 100 * _fill(slot(i).$1 + 0.05, slot(i).$2 + 0.2),
                          color: satellites[i].color,
                          stroke: 4.5,
                        ),
                        child: Center(
                          child: Text(
                            '${(satellites[i].percent * _fill(slot(i).$1 + 0.05, slot(i).$2 + 0.2)).round()}',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.scale(
                scale: centreIn,
                child: SizedBox(
                  width: 122,
                  height: 122,
                  child: CustomPaint(
                    painter: _RingPainter(progress: value / 100 * centreFill, color: _color, stroke: 8),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(value * centreFill).round()}',
                            style: TextStyle(
                              fontSize: 40,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text('/ 100', style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                          Text(caption, style: TextStyle(fontSize: 10.5, color: AppColors.secondaryText)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Each satellite's name written along the circle (upright at the top and
/// the bottom alike), two dots of its colour beside it and grey dots in
/// the gaps between satellites.
class _OrbitDecorPainter extends CustomPainter {
  final List<_Satellite> satellites;
  final double orbit;
  final double labelRadius;
  final List<double> appear;
  _OrbitDecorPainter({required this.satellites, required this.orbit, required this.labelRadius, required this.appear});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final n = satellites.length;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / n;
      final t = appear[i].clamp(0.0, 1.0);
      if (t <= 0) continue;
      final color = satellites[i].color;
      // Dots of the satellite's colour on either side of it.
      for (final d in [-0.36, 0.36]) {
        final p = c + Offset(math.cos(a + d), math.sin(a + d)) * orbit;
        canvas.drawCircle(p, 5.5 * t, Paint()..color = color.withValues(alpha: 0.75 * t));
      }
      for (final d in [-0.55, 0.55]) {
        final p = c + Offset(math.cos(a + d), math.sin(a + d)) * (orbit + 14);
        canvas.drawCircle(p, 2.2 * t, Paint()..color = color.withValues(alpha: 0.45 * t));
      }
      // Grey dots halfway to the next satellite.
      final mid = a + math.pi / n;
      canvas.drawCircle(c + Offset(math.cos(mid), math.sin(mid)) * orbit, 9 * t,
          Paint()..color = (AppColors.dark ? const Color(0xFF3A3F5C) : const Color(0xFFDCDDE3)).withValues(alpha: t));
      canvas.drawCircle(c + Offset(math.cos(mid), math.sin(mid)) * (orbit + 24), 4 * t,
          Paint()..color = (AppColors.dark ? const Color(0xFF2E3350) : const Color(0xFFE6E7EC)).withValues(alpha: t));
      _drawArcText(canvas, c, a, satellites[i].label.toUpperCase(), t);
    }
  }

  void _drawArcText(Canvas canvas, Offset c, double a, String text, double t) {
    final style = TextStyle(
      fontSize: 11,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w600,
      color: AppColors.secondaryText.withValues(alpha: t),
    );
    final chars = [
      for (final ch in text.characters) (TextPainter(text: TextSpan(text: ch, style: style), textDirection: TextDirection.ltr)..layout()),
    ];
    final total = chars.fold<double>(0, (sum, p) => sum + p.width);
    final bottom = math.sin(a) > 0.2;
    // Left to right means clockwise at the top, anticlockwise at the bottom.
    final dir = bottom ? -1.0 : 1.0;
    final r = bottom ? labelRadius + 6 : labelRadius;
    var angle = a - dir * (total / 2) / r;
    for (final p in chars) {
      final half = p.width / 2 / r;
      angle += dir * half;
      canvas.save();
      canvas.translate(c.dx + math.cos(angle) * r, c.dy + math.sin(angle) * r);
      canvas.rotate(bottom ? angle - math.pi / 2 : angle + math.pi / 2);
      p.paint(canvas, Offset(-p.width / 2, -p.height / 2));
      canvas.restore();
      angle += dir * half;
    }
  }

  @override
  bool shouldRepaint(_OrbitDecorPainter old) => true;
}

/// Fades and slides [child] in as [animation] runs; bars inside read the
/// same animation (see _RevealScope) so they fill as the card appears.
class _Reveal extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _Reveal({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return _RevealScope(
      animation: animation,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 18 * (1 - animation.value)), child: child),
        ),
        child: child,
      ),
    );
  }
}

class _RevealScope extends InheritedWidget {
  final Animation<double> animation;
  const _RevealScope({required this.animation, required super.child});

  /// The nearest card's reveal, or an already-finished one.
  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RevealScope>()?.animation ?? kAlwaysCompleteAnimation;

  @override
  bool updateShouldNotify(_RevealScope old) => old.animation != animation;
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double stroke;
  _RingPainter({required this.progress, required this.color, this.stroke = 12});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawCircle(
      rect.center,
      arcRect.width / 2,
      Paint()
        ..color = AppColors.surface
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
        color: AppColors.surface,
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
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.success),
              ),
            ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                allLearned ? tr('Урок пройден') : tr('Почти готово'),
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 2),
              Text(
                tr('Закреплено {0} из {1}', [learnedCount, total]),
                style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
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
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
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
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  ),
                  if (suffix != null)
                    TextSpan(text: ' $suffix', style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
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
  final Color? _track;
  Color get track => _track ?? AppColors.surface;
  const _Bar({required this.ratio, required this.color, Color? track}) : _track = track;

  @override
  Widget build(BuildContext context) {
    final reveal = _RevealScope.of(context);
    return AnimatedBuilder(
      animation: reveal,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: ratio.clamp(0.0, 1.0) * reveal.value,
          minHeight: 7,
          backgroundColor: track,
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
        color: AppColors.surface,
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
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${stat.correct}',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                TextSpan(text: ' / ${stat.total}', style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Bar(ratio: ratio, color: color, track: AppColors.progressTrack),
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
    final check = word.isLearned ? Icon(Icons.check_circle, color: AppColors.success, size: 18) : null;
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
              backgroundColor: AppColors.cardBorder,
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

