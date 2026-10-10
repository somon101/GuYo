import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../services/session_cache.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_fire.dart';
import '../widgets/skeleton.dart';
import '../exercises/exercise_type.dart';
import '../models/dictionary.dart';
import 'lesson_run_screen.dart' show lessonExerciseLabels;
import 'practice_exercise_screen.dart';
import 'streak_sheet.dart' show streakDaysLabel;

const _blue = Color(0xFF3B7BF6);
const _fire = Color(0xFFFF7A29);
const _exerciseColors = [Color(0xFF2BB5E8), Color(0xFF34C759), Color(0xFFC86DD7), Color(0xFFFF6B6B), Color(0xFFFF8A3D)];

/// GET /users/me/stats.
class UserStats {
  final int accuracy;
  final int totalAnswers;
  final List<({String key, int correct, int total})> exercises;
  final List<({DateTime date, int points})> chart;
  final int pointsTotal;
  final int pointsPrevTotal;
  final List<({DateTime date, bool active, int answers})> calendar;
  final int currentStreak;
  final int bestStreak;
  final int lessonsCompleted;
  final int wordsLearned;
  final int wordsLearnedWeek;
  final int timeMinutes;
  final int timeWeekMinutes;
  final double? avgAnswerSeconds;
  final int? bestWeekday;
  final List<({int wordId, String word, int? dictionaryId, int mistakes})> hardWords;

  UserStats.fromJson(Map<String, dynamic> j)
      : accuracy = j['accuracy'] as int,
        totalAnswers = j['total_answers'] as int,
        exercises = [
          for (final e in j['exercises'] as List<dynamic>)
            (key: e['exercise_key'] as String, correct: e['correct'] as int, total: e['total'] as int),
        ],
        chart = [
          for (final p in j['points_chart'] as List<dynamic>)
            (date: DateTime.parse(p['date'] as String), points: p['points'] as int),
        ],
        pointsTotal = j['points_total'] as int,
        pointsPrevTotal = j['points_prev_total'] as int,
        calendar = [
          for (final c in j['calendar'] as List<dynamic>)
            (date: DateTime.parse(c['date'] as String), active: c['active'] as bool, answers: c['answers'] as int),
        ],
        currentStreak = j['current_streak'] as int,
        bestStreak = j['best_streak'] as int,
        lessonsCompleted = j['lessons_completed'] as int,
        wordsLearned = j['words_learned'] as int,
        wordsLearnedWeek = j['words_learned_week'] as int,
        timeMinutes = j['time_minutes'] as int,
        timeWeekMinutes = (j['time_week_minutes'] as int?) ?? 0,
        avgAnswerSeconds = (j['avg_answer_seconds'] as num?)?.toDouble(),
        bestWeekday = j['best_weekday'] as int?,
        hardWords = [
          for (final w in j['hard_words'] as List<dynamic>)
            (
              wordId: w['word_id'] as int,
              word: w['word'] as String,
              dictionaryId: w['dictionary_id'] as int?,
              mistakes: w['mistakes'] as int,
            ),
        ];
}

/// "Статистика": how the user is doing -- accuracy overall and per
/// exercise, points by day, activity, totals and the words that trip them
/// up most. Everything plays in on opening.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _days = 7;
  UserStats? _stats;
  bool _failed = false;

  String get _cacheKey => 'stats-$_days';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _stats = SessionCache.get<UserStats>(_cacheKey) ?? _stats;
      _failed = false;
    });
    try {
      final stats = await ApiClient.instance.fetchMyStats(_days);
      SessionCache.put(_cacheKey, stats);
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      if (mounted && _stats == null) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text(
          tr('Статистика'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: IconThemeData(color: AppColors.primaryDark),
      ),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('Не удалось загрузить данные')),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
                ],
              ),
            )
          : stats == null
              ? const Skeleton(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SkeletonBox(height: 250, radius: 24),
                        SizedBox(height: 14),
                        SkeletonBox(height: 220, radius: 24),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    children: [
                      _StudyTimeCard(stats: stats),
                      const SizedBox(height: 14),
                      _AccuracyCard(stats: stats),
                      const SizedBox(height: 14),
                      _PointsCard(
                        stats: stats,
                        days: _days,
                        onDays: (d) {
                          setState(() => _days = d);
                          _load();
                        },
                      ),
                      const SizedBox(height: 14),
                      _TotalsGrid(stats: stats),
                      const SizedBox(height: 14),
                      _ActivityCard(stats: stats),
                      if (stats.hardWords.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _HardWordsCard(stats: stats),
                      ],
                    ],
                  ),
                ),
    );
  }
}

BoxDecoration _card() => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      boxShadow: AppShapes.cardShadow,
    );

Widget _title(String text, {Widget? trailing}) => Row(
      children: [
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        ),
        ?trailing,
      ],
    );

/// Plays a value from 0 to 1 once, when first shown.
Widget _grow({required Widget Function(double t) builder, int ms = 1100}) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => builder(t),
    );

String _hm(int minutes) =>
    minutes < 60 ? tr('{0} мин', [minutes]) : tr('{0} ч {1} мин', [minutes ~/ 60, minutes % 60]);

/// All the time spent studying -- every lesson, practice and quest
/// together -- with this week's share. Counted per answer, only while the
/// app is in front, at most 2 minutes per answer (longer is idling).
class _StudyTimeCard extends StatelessWidget {
  final UserStats stats;
  const _StudyTimeCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6C74F0), Color(0xFF8E6CF0)],
        ),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Время учёбы'),
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                _grow(
                  builder: (t) => Text(
                    _hm((stats.timeMinutes * t).round()),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                Text(
                  tr('за всё время, во всех уроках'),
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                Text(
                  _hm(stats.timeWeekMinutes),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                Text(tr('за неделю'), style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Accuracy as a segmented half-dial, with a chip per exercise type below.
class _AccuracyCard extends StatelessWidget {
  final UserStats stats;
  const _AccuracyCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: _card(),
      child: Column(
        children: [
          _title(tr('Точность ответов')),
          const SizedBox(height: 10),
          _grow(
            builder: (t) => SizedBox(
              height: 150,
              child: CustomPaint(
                size: const Size(double.infinity, 150),
                painter: _DialPainter(value: stats.accuracy / 100 * t),
                child: Align(
                  alignment: const Alignment(0, 0.75),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(stats.accuracy * t).round()}%',
                        style: TextStyle(fontSize: 34, height: 1, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('{0} ответов', [stats.totalAnswers]),
                        style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (stats.exercises.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < stats.exercises.length; i++)
                  _ExerciseChip(
                    label: lessonExerciseLabels[stats.exercises[i].key] ?? stats.exercises[i].key,
                    percent: stats.exercises[i].total == 0
                        ? 0
                        : (stats.exercises[i].correct * 100 / stats.exercises[i].total).round(),
                    color: _exerciseColors[i % _exerciseColors.length],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double value;
  _DialPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    const segments = 26;
    final c = Offset(size.width / 2, size.height - 6);
    final outer = math.min(size.width / 2, size.height) - 4;
    final inner = outer - 30;
    final lit = (value * segments).round();
    for (var i = 0; i < segments; i++) {
      final a = math.pi + math.pi * (i + 0.5) / segments;
      final paint = Paint()
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = i < lit ? Color.lerp(const Color(0xFF7FA8FF), _blue, i / segments)! : const Color(0xFFE3E7F2);
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * inner,
        c + Offset(math.cos(a), math.sin(a)) * outer,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.value != value;
}

class _ExerciseChip extends StatelessWidget {
  final String label;
  final int percent;
  final Color color;
  const _ExerciseChip({required this.label, required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    // A small ring with the percent inside and the exercise's name under it.
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: _grow(
              builder: (t) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      value: percent / 100 * t,
                      strokeWidth: 4.5,
                      strokeCap: StrokeCap.round,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  Text(
                    '${(percent * t).round()}%',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // A single long word shrinks to fit rather than breaking mid-word.
          if (!label.contains(' '))
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: TextStyle(fontSize: 10.5, color: AppColors.secondaryText)),
            )
          else
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 10.5, height: 1.2, color: AppColors.secondaryText),
            ),
        ],
      ),
    );
  }
}

/// Points by day as bars, today's highlighted, with a week/month switch
/// and how the period compares with the one before.
class _PointsCard extends StatelessWidget {
  final UserStats stats;
  final int days;
  final ValueChanged<int> onDays;
  const _PointsCard({required this.stats, required this.days, required this.onDays});

  @override
  Widget build(BuildContext context) {
    final maxPoints = stats.chart.fold<int>(0, (m, p) => math.max(m, p.points));
    final diff = stats.pointsPrevTotal == 0
        ? null
        : ((stats.pointsTotal - stats.pointsPrevTotal) * 100 / stats.pointsPrevTotal).round();
    final letters = [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            tr('Очки'),
            trailing: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (d, label) in [(7, tr('Неделя')), (30, tr('Месяц'))])
                    GestureDetector(
                      onTap: () => onDays(d),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: d == days ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: d == days ? Colors.white : AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stats.pointsTotal}',
                style: TextStyle(fontSize: 30, height: 1, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(tr('очков'), style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
              ),
              const Spacer(),
              if (diff != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: diff >= 0 ? AppColors.successLight : AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        diff >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        size: 15,
                        color: diff >= 0 ? AppColors.success : AppColors.danger,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${diff >= 0 ? '+' : ''}$diff% ${days == 7 ? tr('к прошлой неделе') : tr('к прошлому месяцу')}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: diff >= 0 ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: _grow(
              ms: 900,
              builder: (t) => Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < stats.chart.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: days == 7 ? 6 : 1.5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: maxPoints == 0
                                      ? 0.04
                                      : math.max(0.04, stats.chart[i].points / maxPoints * t),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(days == 7 ? 10 : 4),
                                      gradient: i == stats.chart.length - 1
                                          ? LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [Color(0xFF8C93F0), AppColors.primary],
                                            )
                                          : null,
                                      color: i == stats.chart.length - 1 ? null : AppColors.progressTrack,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (days == 7) ...[
                              const SizedBox(height: 6),
                              Text(
                                letters[stats.chart[i].date.weekday - 1],
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: i == stats.chart.length - 1 ? FontWeight.w800 : FontWeight.w500,
                                  color: i == stats.chart.length - 1 ? AppColors.primary : AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
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

/// Four pastel tiles: lessons, words, time, speed -- and the best day.
class _TotalsGrid extends StatelessWidget {
  final UserStats stats;
  const _TotalsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final weekdays = [
      tr('понедельник'),
      tr('вторник'),
      tr('среда'),
      tr('четверг'),
      tr('пятница'),
      tr('суббота'),
      tr('воскресенье'),
    ];
    Widget row(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
          ),
        );
    return Column(
      children: [
        row(
          _Tile(
            color: const Color(0xFFFFE3B8),
            icon: Icons.menu_book_rounded,
            value: '${stats.lessonsCompleted}',
            label: tr('Уроков пройдено'),
          ),
          _Tile(
            color: const Color(0xFFC9EFD3),
            icon: Icons.star_rounded,
            value: '${stats.wordsLearned}',
            label: tr('Слов выучено'),
            note: stats.wordsLearnedWeek > 0 ? tr('+{0} за неделю', [stats.wordsLearnedWeek]) : null,
          ),
        ),
        const SizedBox(height: 12),
        row(
          _Tile(
            color: const Color(0xFFD5E4FF),
            icon: Icons.task_alt_rounded,
            value: '${stats.totalAnswers}',
            label: tr('Всего ответов'),
          ),
          _Tile(
            color: const Color(0xFFF6D6F4),
            icon: Icons.bolt_rounded,
            value: stats.avgAnswerSeconds == null ? '—' : tr('{0} с', [stats.avgAnswerSeconds!.toStringAsFixed(1)]),
            label: tr('Средний ответ'),
          ),
        ),
        if (stats.bestWeekday != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.tile(const Color(0xFFFFF6DD)),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFE7A6)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_rounded, color: Color(0xFFF5B400), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Чаще всего вы занимаетесь: {0}', [weekdays[stats.bestWeekday!]]),
                    style: TextStyle(fontSize: 13.5, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String value;
  final String label;
  final String? note;
  const _Tile({required this.color, required this.icon, required this.value, required this.label, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(color: AppColors.tile(color), borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
          if (note != null)
            Text(note!, style: TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// The last five weeks, a cell per day lit by how much was done, plus the
/// current and best streaks.
class _ActivityCard extends StatelessWidget {
  final UserStats stats;
  const _ActivityCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final maxAnswers = stats.calendar.fold<int>(0, (m, c) => math.max(m, c.answers));
    final letters = [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')];
    // Columns are weeks, Monday on top; pad the first week to its Monday.
    final first = stats.calendar.first.date;
    final pad = first.weekday - 1;
    final cells = [...List<({DateTime date, bool active, int answers})?>.filled(pad, null), ...stats.calendar];
    final weeks = (cells.length / 7).ceil();
    final today = stats.calendar.last.date;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(tr('Активность')),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    SizedBox(
                      height: 24,
                      child: Center(
                        child: Text(
                          letters[d],
                          style: TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var w = 0; w < weeks; w++)
                      Column(
                        children: [
                          for (var d = 0; d < 7; d++)
                            Builder(builder: (context) {
                              final i = w * 7 + d;
                              final cell = i < cells.length ? cells[i] : null;
                              final level = cell == null || !cell.active
                                  ? 0.0
                                  : maxAnswers == 0
                                      ? 0.5
                                      : 0.35 + 0.65 * cell.answers / maxAnswers;
                              return Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: cell == null
                                      ? Colors.transparent
                                      : level == 0
                                          ? AppColors.softFill
                                          : _fire.withValues(alpha: level),
                                  borderRadius: BorderRadius.circular(6),
                                  border: cell != null && cell.date == today
                                      ? Border.all(color: AppColors.primaryDark, width: 1.5)
                                      : null,
                                ),
                              );
                            }),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StreakPill(
                  leading: const AnimatedFire(size: 26),
                  value: '${stats.currentStreak} ${streakDaysLabel(stats.currentStreak).split(' ').first}',
                  label: tr('Текущая серия'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StreakPill(
                  leading: const Icon(Icons.emoji_events_rounded, color: Color(0xFFF5B400), size: 24),
                  value: '${stats.bestStreak} ${streakDaysLabel(stats.bestStreak).split(' ').first}',
                  label: tr('Рекорд'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  final Widget leading;
  final String value;
  final String label;
  const _StreakPill({required this.leading, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.tile(const Color(0xFFFFF3EA)), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The words answered wrong most often.
class _HardWordsCard extends StatelessWidget {
  final UserStats stats;
  const _HardWordsCard({required this.stats});

  /// The dictionary most of the hard words come from -- the practice runs
  /// in one dictionary, so the button repeats that one's words.
  int? get _practiceDictionary {
    final counts = <int, int>{};
    for (final w in stats.hardWords) {
      if (w.dictionaryId != null) counts[w.dictionaryId!] = (counts[w.dictionaryId!] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  @override
  Widget build(BuildContext context) {
    final worst = stats.hardWords.first.mistakes;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            tr('Трудные слова'),
            trailing: _practiceDictionary == null
                ? null
                : FilledButton.icon(
                    key: const ValueKey('stats-practice-hard'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PracticeExerciseScreen(
                          dictionary: GuyoDictionary(id: _practiceDictionary!, name: '', language: '', wordCount: 0),
                          type: buildWordExerciseType,
                          wordIds: [
                            for (final w in stats.hardWords)
                              if (w.dictionaryId == _practiceDictionary) w.wordId,
                          ],
                        ),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B6B),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: Text(tr('Повторить'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
          ),
          const SizedBox(height: 2),
          Text(
            tr('В них вы ошибаетесь чаще всего'),
            style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
          ),
          const SizedBox(height: 10),
          for (final w in stats.hardWords)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      w.word,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                    ),
                  ),
                  Expanded(
                    child: _grow(
                      builder: (t) => ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: w.mistakes / worst * t,
                          minHeight: 8,
                          backgroundColor: AppColors.dangerLight,
                          valueColor: const AlwaysStoppedAnimation(Color(0xFFFF6B6B)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tr('{0} ош.', [w.mistakes]),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.danger),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
