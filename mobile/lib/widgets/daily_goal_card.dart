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

  /// The goal to start from (tests); otherwise the remembered one.
  final DailyGoal? initialGoal;
  const DailyGoalCard({super.key, this.onContinue, this.initialGoal});

  @override
  State<DailyGoalCard> createState() => _DailyGoalCardState();
}

class _DailyGoalCardState extends State<DailyGoalCard> {
  late DailyGoal? _goal = widget.initialGoal ?? ApiClient.instance.cachedDailyGoal();

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
    // A finished goal whose reward is taken leaves Главная altogether: the blocks below rise into its
    // place (smoothly), and a new goal comes with the next day. While the reward still waits, the
    // card stays -- it is where it is taken.
    final gone = goal == null || (goal.completed && !goal.rewardReady);
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: gone
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: const ValueKey('goal-card'),
              padding: const EdgeInsets.only(top: 14),
              child: DailyGoalCardView(
                goal: goal,
                // A filled goal is fixed for the day; it still opens the list when a reward waits there.
                onTap: (!goal.locked || goal.rewardReady) ? _pick : null,
                onClaim: goal.rewardReady ? _claim : null,
                onContinue: widget.onContinue,
                notice: _notice,
              ),
            ),
    );
  }
}

/// The soft colours of this card (the owner's pick, the same as the end of a lesson): the green of
/// the bar and the button, with a darker edge; a light and a dark value.
class _G {
  _G._();
  static bool get _d => AppColors.dark;
  static Color get green => _d ? const Color(0xFF7BDA5E) : const Color(0xFF62C94A);
  static Color get edge => _d ? const Color(0xFF4FA936) : const Color(0xFF47A72F);
  static Color get onGreen => _d ? const Color(0xFF10300A) : const Color(0xFF123D0A);
  static Color get text => _d ? const Color(0xFF8EE878) : const Color(0xFF3A8A27);
}

/// «Цель дня» on Главная, variant 3 («блок как в итогах урока»): the title and the count on one line,
/// a green bar, then «Осталось N слов» with «Продолжить». With a reward waiting: «Цель дня выполнена»,
/// the reward as soft tiles and «Получить». The whole top line opens the choice of 5, 10 or 20 words.
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
    final left = (goal.goal - goal.done).clamp(0, goal.goal);
    final label = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondaryText);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.cardBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          key: const ValueKey('goal-top'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(children: [
            Expanded(
              child: Text(ready ? tr('Цель дня выполнена') : tr('Цель дня'), style: label.copyWith(color: ready ? _G.text : AppColors.secondaryText)),
            ),
            if (!ready && !done)
              Text(tr('{0} / {1} слов', [goal.done, goal.goal]), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.primaryDark)),
            if (ready || done) Icon(Icons.check_circle_rounded, size: 22, color: _G.green),
            if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.secondaryText),
          ]),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 10,
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: AppColors.progressTrack)),
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: value),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v,
                    child: DecoratedBox(decoration: BoxDecoration(color: _G.green, borderRadius: BorderRadius.circular(99))),
                  ),
                ),
              ),
            ]),
          ),
        ),
        if (ready && onClaim != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: rewards.isEmpty ? const SizedBox.shrink() : RewardChips(rewards: rewards, size: 24, soft: true)),
            const SizedBox(width: 10),
            _GreenButton(key: const ValueKey('goal-claim'), label: tr('Получить'), onTap: onClaim!, width: 130),
          ]),
        ] else if (!done && onContinue != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(tr('Осталось {0} слов', [left]), style: label)),
            const SizedBox(width: 10),
            _GreenButton(key: const ValueKey('goal-continue'), label: tr('Продолжить'), onTap: onContinue!, width: 150),
          ]),
        ],
        if (done && !ready) ...[
          const SizedBox(height: 10),
          Text(tr('Награда получена'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          const SizedBox(height: 2),
          Text(tr('Новая цель появится завтра'), style: label),
        ],
        if (notice != null)
          Container(
            key: const ValueKey('goal-notice'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0x33FFB020), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x80FFB020))),
            child: Text(notice!, style: const TextStyle(color: Color(0xFFB36A00), fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

/// The flat green button of the day's goal: a face on a darker edge that sinks when pressed.
class _GreenButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final double width;
  const _GreenButton({super.key, required this.label, required this.onTap, required this.width});

  @override
  State<_GreenButton> createState() => _GreenButtonState();
}

class _GreenButtonState extends State<_GreenButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          height: 48,
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              margin: EdgeInsets.only(top: _down ? 4 : 0),
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _G.green,
                borderRadius: BorderRadius.circular(14),
                boxShadow: _down ? null : [BoxShadow(color: _G.edge, offset: const Offset(0, 4))],
              ),
              child: Text(widget.label.toUpperCase(), style: TextStyle(color: _G.onGreen, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
            ),
          ),
        ),
      );
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
