import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/daily_goal.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import 'game_icons.dart';
import 'counted_chest.dart' show GreenButton;
import 'reward_chips.dart';
import 'reward_claim_effect.dart';

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
                    ? (goal.rewardReady
                        ? GreenButton(key: const ValueKey('goal-claim-sheet'), label: tr('Получить'), onTap: () => Navigator.of(ctx).pop(-1), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8))
                        : Icon(Icons.check_circle_rounded, color: AppColors.primary))
                    : null,
                onTap: goal.locked ? null : () => Navigator.of(ctx).pop(n),
              ),
          ],
        ),
      ),
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
        notice: _notice,
      ),
    );
  }
}

class DailyGoalCardView extends StatelessWidget {
  final DailyGoal goal;
  final VoidCallback? onTap;
  final VoidCallback? onClaim;
  final String? notice;
  const DailyGoalCardView({super.key, required this.goal, required this.onTap, this.onClaim, this.notice});

  @override
  Widget build(BuildContext context) {
    final value = goal.goal == 0 ? 1.0 : (goal.done / goal.goal).clamp(0.0, 1.0);
    final done = goal.completed;
    final ready = goal.rewardReady;
    final percent = (value * 100).round();
    final rewards = goal.tiers[goal.goal] ?? const [];
    return Stack(clipBehavior: Clip.none, children: [
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: ready ? const Color(0xFFFFD54F) : done ? AppColors.success : AppColors.violetSurface, width: 1.5),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Цель дня'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
                        const SizedBox(height: 2),
                        Text(
                          ready
                              ? tr('Выполнена! Заберите награду')
                              : done
                                  ? tr('Выполнена! Новую цель выберете завтра')
                                  : tr('{0} из {1} слов', [goal.done, goal.goal]),
                          style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                  Text('$percent%', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: done ? AppColors.success : AppColors.primary)),
                  const SizedBox(width: 12),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? AppColors.success : AppColors.primary,
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: .22), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Icon(done ? Icons.check_rounded : Icons.chevron_right_rounded, color: Colors.white, size: 25),
                  ),
                ],
              ),
              if (ready && onClaim != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: rewards.isEmpty ? const SizedBox.shrink() : RewardChips(rewards: rewards, size: 22)),
                  GreenButton(key: const ValueKey('goal-claim'), label: tr('Получить'), onTap: onClaim, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                ]),
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
          ),
        ),
      ),
      if (ready)
        const Positioned(top: -14, right: 10, child: IgnorePointer(child: _WobblingGift())),
    ]);
  }
}

/// The small gift on the card's corner: a reward is waiting.
class _WobblingGift extends StatefulWidget {
  const _WobblingGift();

  @override
  State<_WobblingGift> createState() => _WobblingGiftState();
}

class _WobblingGiftState extends State<_WobblingGift> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Transform.rotate(
          angle: (_c.value - 0.5) * 0.24,
          child: Transform.scale(scale: 1 + 0.14 * _c.value, child: const GiftIcon(size: 40)),
        ),
      );
}
