import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/season_pass.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';

String passSeasonName(SeasonPass pass) {
  final lang = appLanguage.value;
  if (lang == 'tg' && (pass.seasonNameTg ?? '').isNotEmpty) return pass.seasonNameTg!;
  if (lang == 'uz' && (pass.seasonNameUz ?? '').isNotEmpty) return pass.seasonNameUz!;
  return pass.seasonName;
}

String _rewardText(PassReward r) =>
    r.type == 'premium_days' ? tr('Premium: +{0} дн.', [r.amount]) : tr('Очки рейтинга: +{0}', [r.amount]);

IconData _rewardIcon(PassReward r) => r.type == 'premium_days' ? Icons.workspace_premium_rounded : Icons.star_rounded;

String _taskText(PassTask t) => switch (t.metric) {
      'word' => tr('Выучить слов: {0}', [t.target]),
      'lesson' => tr('Пройти уроков: {0}', [t.target]),
      'review' => tr('Ответов в «Повторить сегодня»: {0}', [t.target]),
      'quest' => tr('Выполнить заданий квестов: {0}', [t.target]),
      'streak' => tr('Дней серии: {0}', [t.target]),
      _ => '${t.metric}: ${t.target}',
    };

/// «Пропуск сезона»: XP earned by studying fills a ladder of levels, each with
/// a free reward and a Premium one, plus small tasks for the week. Everything
/// is decided on the server; this screen only shows it and sends the claims.
class SeasonPassScreen extends StatefulWidget {
  const SeasonPassScreen({super.key});

  @override
  State<SeasonPassScreen> createState() => _SeasonPassScreenState();
}

class _SeasonPassScreenState extends State<SeasonPassScreen> {
  SeasonPass? _pass;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pass = await ApiClient.instance.fetchSeasonPass();
    if (!mounted) return;
    setState(() {
      _pass = pass;
      _loading = false;
    });
  }

  Future<void> _claim(Future<SeasonPass> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pass = await action();
      if (!mounted) return;
      setState(() => _pass = pass);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Не удалось. Проверьте интернет.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pass = _pass;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(tr('Пропуск сезона'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pass == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('Сейчас нет активного сезона'), textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(onRefresh: _load, child: _body(pass)),
    );
  }

  Widget _body(SeasonPass pass) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _Header(pass: pass),
        const SizedBox(height: 14),
        if (pass.premiumEnabled && !pass.isPremium)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GuyoCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('С Premium откроются награды справа, в том числе за уже пройденные уровни.'),
                      style: TextStyle(fontSize: 13.5, color: AppColors.primaryDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
        _SectionTitle(tr('Награды')),
        _LaneHeader(showPremium: pass.premiumEnabled),
        for (final level in pass.levels)
          _LevelRow(
            level: level,
            reached: level.level <= pass.level,
            showPremium: pass.premiumEnabled,
            busy: _busy,
            onClaim: (track) => _claim(() => ApiClient.instance.claimPassLevel(level.level, track)),
          ),
        const SizedBox(height: 18),
        _SectionTitle(tr('Задания недели')),
        if (pass.tasks.isEmpty)
          Text(tr('На этой неделе заданий нет'), style: TextStyle(color: AppColors.secondaryText))
        else
          for (final task in pass.tasks)
            _TaskRow(
              task: task,
              busy: _busy,
              onClaim: () => _claim(() => ApiClient.instance.claimPassTask(task.id)),
            ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
      );
}

class _Header extends StatelessWidget {
  final SeasonPass pass;
  const _Header({required this.pass});

  @override
  Widget build(BuildContext context) {
    final next = pass.xpForNext;
    final value = next == null || next == 0 ? 1.0 : (pass.xpIntoLevel / next).clamp(0.0, 1.0);
    final left = pass.endsAt?.difference(DateTime.now()).inDays;
    return GuyoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(passSeasonName(pass), style: TextStyle(fontSize: 13.5, color: AppColors.secondaryText)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tr('Уровень {0}', [pass.level]),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
              const Spacer(),
              Text('${pass.xp} XP', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: AppColors.progressTrack,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            next == null ? tr('Все уровни пройдены') : tr('{0} из {1} XP до следующего уровня', [pass.xpIntoLevel, next]),
            style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
          ),
          if (left != null && left >= 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('До конца сезона дней: {0}', [left]), style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
            ),
        ],
      ),
    );
  }
}

class _LaneHeader extends StatelessWidget {
  final bool showPremium;
  const _LaneHeader({required this.showPremium});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondaryText);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(tr('Бесплатно'), style: style)),
          const SizedBox(width: 56),
          if (showPremium) Expanded(child: Text('Premium', textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  final PassLevel level;
  final bool reached;
  final bool showPremium;
  final bool busy;
  final void Function(String track) onClaim;

  const _LevelRow({
    required this.level,
    required this.reached,
    required this.showPremium,
    required this.busy,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _RewardTile(reward: level.free, busy: busy, onClaim: () => onClaim('free'))),
          SizedBox(
            width: 56,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: reached ? AppColors.primary : AppColors.softFill,
                ),
                child: Text(
                  '${level.level}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: reached ? Colors.white : AppColors.secondaryText),
                ),
              ),
            ),
          ),
          if (showPremium) Expanded(child: _RewardTile(reward: level.premium, busy: busy, onClaim: () => onClaim('premium'))),
        ],
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  final PassReward? reward;
  final bool busy;
  final VoidCallback onClaim;

  const _RewardTile({required this.reward, required this.busy, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final r = reward;
    if (r == null) return const SizedBox.shrink();
    final Color fill;
    if (r.claimed) {
      fill = AppColors.successLight;
    } else if (r.claimable) {
      fill = AppColors.violetSurface;
    } else {
      fill = AppColors.softFill;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppShapes.rowRadius),
        border: r.claimable ? Border.all(color: AppColors.primary, width: 1.4) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_rewardIcon(r), size: 22, color: r.claimed ? AppColors.success : AppColors.primary),
          const SizedBox(height: 2),
          Text(
            _rewardText(r),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 4),
          if (r.claimed)
            Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success)
          else if (r.claimable)
            SizedBox(
              height: 28,
              child: FilledButton(
                onPressed: busy ? null : onClaim,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                child: Text(tr('Забрать'), style: const TextStyle(fontSize: 12.5)),
              ),
            )
          else if (r.lockedByPremium)
            Icon(Icons.lock_rounded, size: 16, color: AppColors.muted),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final PassTask task;
  final bool busy;
  final VoidCallback onClaim;

  const _TaskRow({required this.task, required this.busy, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GuyoCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_taskText(task), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: task.target == 0 ? 1 : (task.progress / task.target).clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor: AppColors.progressTrack,
                      color: task.claimed ? AppColors.success : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${task.progress} / ${task.target} · +${task.xp} XP',
                      style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (task.claimed)
              Icon(Icons.check_circle_rounded, color: AppColors.success)
            else if (task.claimable)
              FilledButton(onPressed: busy ? null : onClaim, child: Text(tr('Забрать'))),
          ],
        ),
      ),
    );
  }
}
