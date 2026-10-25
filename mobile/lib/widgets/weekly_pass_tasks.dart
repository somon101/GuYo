import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/season_pass.dart';
import '../theme/app_colors.dart';
import 'season_pass_ui.dart';

const _metricStyles = <String, ({IconData icon, List<Color> colors})>{
  'word': (
    icon: Icons.menu_book_rounded,
    colors: [Color(0xFF5EE0A0), Color(0xFF14A85C)],
  ),
  'lesson': (
    icon: Icons.school_rounded,
    colors: [Color(0xFF7FB2FF), Color(0xFF3A6BFF)],
  ),
  'review': (
    icon: Icons.replay_rounded,
    colors: [Color(0xFFFFC46B), Color(0xFFF5871F)],
  ),
  'quest': (
    icon: Icons.flag_rounded,
    colors: [Color(0xFFFF8AB8), Color(0xFFD62F8A)],
  ),
  'streak': (
    icon: Icons.local_fire_department_rounded,
    colors: [Color(0xFFFFA06B), Color(0xFFE5391F)],
  ),
};

String _taskText(PassTask task) => switch (task.metric) {
  'word' => tr('Выучить слов: {0}', [task.target]),
  'lesson' => tr('Пройти уроков: {0}', [task.target]),
  'review' => tr('Ответов в «Повторить сегодня»: {0}', [task.target]),
  'quest' => tr('Выполнить заданий квестов: {0}', [task.target]),
  'streak' => tr('Дней серии: {0}', [task.target]),
  _ => '${task.metric}: ${task.target}',
};

/// Weekly season-pass tasks are shown in «Квесты сезона».
class WeeklyPassTasks extends StatefulWidget {
  const WeeklyPassTasks({super.key});

  @override
  State<WeeklyPassTasks> createState() => _WeeklyPassTasksState();
}

class _WeeklyPassTasksState extends State<WeeklyPassTasks>
    with SingleTickerProviderStateMixin {
  SeasonPass? _pass;
  bool _loading = true;
  bool _busy = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);
  late final Animation<double> _animation = CurvedAnimation(
    parent: _pulse,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pass = await ApiClient.instance.fetchSeasonPass();
    if (!mounted) return;
    setState(() {
      _pass = pass;
      _loading = false;
    });
  }

  Future<void> _claim(PassTask task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pass = await ApiClient.instance.claimPassTask(task.id);
      if (!mounted) return;
      setState(() => _pass = pass);
      await showRewardDialog(
        context,
        style: RewardStyle(
          _metricStyles[task.metric]?.colors ??
              const [Color(0xFFA48BFF), Color(0xFF5862DD)],
          _metricStyles[task.metric]?.icon ?? Icons.bolt_rounded,
          '⚡',
        ),
        title: tr('Награда получена!'),
        text: '+${task.xp} ${tr('энергии')}',
      );
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
          SnackBar(content: Text(tr('Не удалось. Проверьте интернет.'))),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pass = _pass;
    final days = pass == null
        ? null
        : pass.weekEndsAt.difference(DateTime.now()).inDays + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('Задания недели'),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              if (days != null && days >= 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.violetSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr('Дней до обновления: {0}', [days]),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          )
        else if (pass == null || pass.tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr('На этой неделе заданий нет'),
              style: TextStyle(color: AppColors.secondaryText),
            ),
          )
        else
          for (final task in pass.tasks)
            _TaskCard(
              task: task,
              pulse: _animation,
              busy: _busy,
              onClaim: () => _claim(task),
            ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final PassTask task;
  final Animation<double> pulse;
  final bool busy;
  final VoidCallback onClaim;
  const _TaskCard({
    required this.task,
    required this.pulse,
    required this.busy,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final style = _metricStyles[task.metric];
    final colors =
        style?.colors ?? const [Color(0xFFA48BFF), Color(0xFF5862DD)];
    final value = task.target == 0
        ? 1.0
        : (task.progress / task.target).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: task.claimable
                ? colors.last.withValues(alpha: 0.5 + 0.5 * pulse.value)
                : AppColors.cardBorder,
            width: task.claimable ? 2 : 1,
          ),
          boxShadow: [
            if (task.claimable)
              BoxShadow(
                color: colors.last.withValues(alpha: 0.18 + 0.2 * pulse.value),
                blurRadius: 14,
              )
            else
              ...AppShapes.cardShadow,
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: colors),
              ),
              child: Icon(
                style?.icon ?? Icons.bolt_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _taskText(task),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Container(height: 9, color: AppColors.progressTrack),
                        FractionallySizedBox(
                          widthFactor: value,
                          child: Container(
                            height: 9,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: task.claimed
                                    ? const [
                                        Color(0xFF34D17F),
                                        Color(0xFF14A85C),
                                      ]
                                    : colors,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${task.progress} / ${task.target}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (task.claimed)
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 30,
              )
            else if (task.claimable)
              FilledButton(
                onPressed: busy ? null : onClaim,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.last,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('Забрать'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('+${task.xp} ⚡', style: const TextStyle(fontSize: 11)),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.violetSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '+${task.xp} ⚡',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
