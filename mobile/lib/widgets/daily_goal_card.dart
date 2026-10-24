import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/daily_goal.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import 'game_icons.dart';
import 'reward_chips.dart';
import 'season_pass_ui.dart';

/// "Цель дня" on Главная: a ring that fills as the day's words are practised.
/// Tap it to pick 5, 10 or 20 words. Finishing the goal plays a small
/// celebration (once a day -- the server says which call finished it).
class DailyGoalCard extends StatefulWidget {
  const DailyGoalCard({super.key});

  @override
  State<DailyGoalCard> createState() => _DailyGoalCardState();
}

class _DailyGoalCardState extends State<DailyGoalCard> {
  DailyGoal? _goal = ApiClient.instance.cachedDailyGoal();

  @override
  void initState() {
    super.initState();
    dailyGoalTick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dailyGoalTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final goal = await ApiClient.instance.fetchDailyGoal();
    if (!mounted || goal == null) return;
    setState(() => _goal = goal);
    if (goal.justCompleted) {
      await showRewardDialog(
        context,
        style: const RewardStyle(
          [Color(0xFFFFD54F), Color(0xFFFF9800)],
          Icons.local_fire_department_rounded,
          '',
        ),
        title: tr('Цель дня выполнена!'),
        text: _prizeText(goal),
      );
    }
  }

  String _prizeText(DailyGoal g) {
    final parts = [
      if (g.xp > 0) '+${g.xp} ⚡',
      if (g.diamonds > 0) '+${compactNumber(g.diamonds)} ${tr('бриллиантов')}',
      if (g.points > 0) '+${g.points} ${tr('очков рейтинга')}',
      if (g.chests.isNotEmpty) '${tr('Сундук')} ×${g.chests.length}',
    ];
    return parts.isEmpty ? tr('Так держать!') : parts.join('  ');
  }

  Future<void> _pick() async {
    final goal = _goal;
    if (goal == null) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                tr('Сколько слов в день?'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            for (final n in goal.options)
              ListTile(
                key: ValueKey('daily-goal-$n'),
                title: Text(
                  tr('{0} слов', [n]),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: (goal.tiers[n] ?? const []).isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: RewardChips(rewards: goal.tiers[n]!, color: AppColors.primaryDark),
                      ),
                trailing: n == goal.goal
                    ? Icon(Icons.check_circle_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(n),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == goal.goal) return;
    final updated = await ApiClient.instance.setDailyGoal(chosen);
    if (mounted && updated != null) setState(() => _goal = updated);
  }

  @override
  Widget build(BuildContext context) {
    final goal = _goal;
    if (goal == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DailyGoalCardView(goal: goal, onTap: _pick),
    );
  }
}

class DailyGoalCardView extends StatelessWidget {
  final DailyGoal goal;
  final VoidCallback onTap;
  const DailyGoalCardView({super.key, required this.goal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final value = goal.goal == 0
        ? 1.0
        : (goal.done / goal.goal).clamp(0.0, 1.0);
    final done = goal.completed;
    final percent = (value * 100).round();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: done ? AppColors.success : AppColors.violetSurface,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Цель дня'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      done
                          ? tr('Выполнена! Можно заниматься дальше')
                          : tr('{0} из {1} слов', [goal.done, goal.goal]),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: done ? AppColors.success : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.success : AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: .22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  done ? Icons.check_rounded : Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
