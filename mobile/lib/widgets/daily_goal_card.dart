import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/daily_goal.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import 'reward_chips.dart';
import 'reward_claim_effect.dart';

/// "Цель дня" on Главная: a ring that fills as the day's words are practised.
/// Tap it to pick 5, 10 or 20 words. Finishing the goal plays a small
/// celebration (once a day -- the server says which call finished it).
class DailyGoalCard extends StatefulWidget {
  /// «Продолжить»: takes the person to the lessons.
  final VoidCallback? onContinue;
  const DailyGoalCard({super.key, this.onContinue});

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

  void _unlisten() => dailyGoalTick.removeListener(_load);

  Future<void> _load() async {
    final goal = await ApiClient.instance.fetchDailyGoal();
    if (!mounted || goal == null) return;
    setState(() => _goal = goal);
  }

  String? _notice;
  Timer? _noticeTimer;
  bool _claiming = false;

  void _say(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  /// «Получить»: takes the earned reward, then plays the opening effect.
  Future<void> _claim() async {
    final goal = _goal;
    final id = goal?.claimId;
    if (goal == null || id == null || _claiming) return;
    _claiming = true;
    try {
      final updated = await ApiClient.instance.claimDailyGoal(id);
      if (!mounted) return;
      setState(() => _goal = updated);
      ApiClient.instance.fetchEconomy();
      await showRewardClaimEffect(context, title: tr('Цель дня выполнена!'), rewards: goal.tiers[goal.goal] ?? const []);
      dailyGoalTick.value++;
    } on ApiException catch (e) {
      if (mounted) _say(e.message);
    } catch (_) {
      if (mounted) _say(tr('Не удалось. Проверьте интернет.'));
    } finally {
      _claiming = false;
    }
  }

  @override
  void dispose() {
    _unlisten();
    _noticeTimer?.cancel();
    super.dispose();
  }

  Future<void> _pick() async {
    final goal = _goal;
    if (goal == null) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DailyGoalSheet(goal: goal),
    );
    if (chosen == -1) {
      await _claim();
      return;
    }
    if (chosen == null || chosen == goal.goal || goal.locked) return;
    final updated = await ApiClient.instance.setDailyGoal(chosen);
    if (mounted && updated != null) setState(() => _goal = updated);
  }

  @override
  Widget build(BuildContext context) {
    final goal = _goal;
    if (goal == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DailyGoalCardView(
        goal: goal,
        // A filled goal is fixed for the day; it still opens the list when a reward waits there.
        onTap: (!goal.locked || goal.rewardReady) ? _pick : null,
        onClaim: goal.rewardReady ? _claim : null,
        onContinue: widget.onContinue,
        notice: _notice,
      ),
    );
  }
}

class DailyGoalCardView extends StatelessWidget {
  final DailyGoal goal;
  final VoidCallback? onTap;
  final VoidCallback? onClaim;
  final VoidCallback? onContinue;
  final String? notice;
  const DailyGoalCardView({super.key, required this.goal, required this.onTap, this.onClaim, this.onContinue, this.notice});

  @override
  Widget build(BuildContext context) {
    final value = goal.goal == 0 ? 1.0 : (goal.done / goal.goal).clamp(0.0, 1.0);
    final done = goal.completed;
    final ready = goal.rewardReady;
    final rewards = goal.tiers[goal.goal] ?? const [];
    final big = ready
        ? tr('Выполнена! Заберите награду')
        : done
            ? tr('Награда получена')
            : tr('{0} из {1} слов', [goal.done, goal.goal]);
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(26)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          // The switcher pill: «Цель дня ›» opens the choice of 5, 10 or 20 words.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: done ? AppColors.success : AppColors.primary),
                  child: Icon(done ? Icons.check_rounded : Icons.flag_rounded, size: 14, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text(tr('Цель дня'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.secondaryText),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(done || ready ? tr('Сегодня') : tr('Выучено слов сегодня'), style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
          const SizedBox(height: 2),
          Text(big, style: TextStyle(fontSize: done || ready ? 20 : 34, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: done || ready ? -0.3 : -1.2, color: AppColors.primaryDark)),
          if (done && !ready) ...[
            const SizedBox(height: 2),
            Text(tr('Новую цель выберете завтра'), style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: AppColors.progressTrack)),
                FractionallySizedBox(
                  widthFactor: value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: LinearGradient(colors: done ? [AppColors.success, AppColors.success] : AppColors.brandGradient)),
                  ),
                ),
              ]),
            ),
          ),
          if (ready && onClaim != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: rewards.isEmpty ? const SizedBox.shrink() : RewardChips(rewards: rewards, size: 22, soft: true)),
              _ClaimPill(key: const ValueKey('goal-claim'), onTap: onClaim!),
            ]),
          ] else if (!done && onContinue != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              key: const ValueKey('goal-continue'),
              onTap: onContinue,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                child: Text(tr('Продолжить'), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          if (done && !ready)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(99)),
              child: Text(tr('Новая цель появится завтра'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.secondaryText)),
            ),
          if (notice != null)
            Container(
              key: const ValueKey('goal-notice'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0x33FFB020), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x80FFB020))),
              child: Text(notice!, style: const TextStyle(color: Color(0xFFB36A00), fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    ]);
  }
}

/// «Получить»: the indigo pill (the same colour as «Продолжить»).
class _ClaimPill extends StatelessWidget {
  final VoidCallback onTap;
  const _ClaimPill({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
          child: Text(tr('Получить'), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      );
}

/// «Сколько слов в день?»: a light sheet in the new style (variant A): three rows with the reward as
/// soft chips; the chosen one has an indigo frame. A filled goal is fixed for the day, so its row
/// carries «Получить» (while the reward waits) and the others are dimmed.
class DailyGoalSheet extends StatefulWidget {
  final DailyGoal goal;
  const DailyGoalSheet({required this.goal});

  @override
  State<DailyGoalSheet> createState() => DailyGoalSheetState();
}

class DailyGoalSheetState extends State<DailyGoalSheet> {
  late int _picked = widget.goal.goal;

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.progressTrack, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 14),
          Text(tr('Сколько слов в день?'), style: TextStyle(color: AppColors.primaryDark, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 4),
          Text(tr('Чем больше цель, тем больше награда'), style: TextStyle(color: AppColors.secondaryText, fontSize: 13)),
          const SizedBox(height: 14),
          for (final n in goal.options) _row(context, n),
          if (goal.locked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(child: Text(tr('Выполненную цель до завтра сменить нельзя'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText, fontSize: 12))),
            )
          else
            GestureDetector(
              key: const ValueKey('daily-goal-choose'),
              onTap: () => Navigator.of(context).pop(_picked),
              child: Container(
                height: 50,
                margin: const EdgeInsets.only(top: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                child: Text(tr('Выбрать цель'), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, int n) {
    final goal = widget.goal;
    final mine = goal.locked ? n == goal.goal : n == _picked;
    final dim = goal.locked && n != goal.goal;
    final rewards = goal.tiers[n] ?? const [];
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: GestureDetector(
        key: ValueKey('daily-goal-$n'),
        behavior: HitTestBehavior.opaque,
        onTap: goal.locked ? null : () => setState(() => _picked = n),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: mine ? AppColors.violetSurface : AppColors.surface,
            border: Border.all(color: mine ? AppColors.primary : Colors.transparent, width: 2),
          ),
          child: Row(children: [
            SizedBox(
              width: 70,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$n', style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 26, letterSpacing: -0.8)),
                TextSpan(text: ' ${tr('слов')}', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
              ])),
            ),
            Expanded(child: rewards.isEmpty ? const SizedBox.shrink() : RewardChips(rewards: rewards, size: 18, soft: true)),
            if (mine && goal.rewardReady)
              _ClaimPill(key: const ValueKey('goal-claim-sheet'), onTap: () => Navigator.of(context).pop(-1))
            else if (goal.locked && mine)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.success),
                child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(shape: BoxShape.circle, color: mine ? AppColors.primary : null, border: mine ? null : Border.all(color: AppColors.progressTrack, width: 2)),
                child: mine ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
              ),
          ]),
        ),
      ),
    );
  }
}
