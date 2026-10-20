import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/season_pass.dart';
import '../theme/app_colors.dart';
import '../widgets/season_pass_ui.dart';
import 'cosmetics_screen.dart';

String passSeasonName(SeasonPass pass) {
  final lang = appLanguage.value;
  if (lang == 'tg' && (pass.seasonNameTg ?? '').isNotEmpty) return pass.seasonNameTg!;
  if (lang == 'uz' && (pass.seasonNameUz ?? '').isNotEmpty) return pass.seasonNameUz!;
  return pass.seasonName;
}

/// "Фраза" for a reward: "Очки рейтинга +20", "Дни Premium +3".
String rewardSentence(PassReward r) {
  final style = rewardStyle(r);
  final amount = rewardAmountText(r);
  return amount.isEmpty ? style.label : '${style.label} $amount';
}

class _MetricStyle {
  final IconData icon;
  final List<Color> colors;
  const _MetricStyle(this.icon, this.colors);
}

const _metricStyles = <String, _MetricStyle>{
  'word': _MetricStyle(Icons.menu_book_rounded, [Color(0xFF5EE0A0), Color(0xFF14A85C)]),
  'lesson': _MetricStyle(Icons.school_rounded, [Color(0xFF7FB2FF), Color(0xFF3A6BFF)]),
  'review': _MetricStyle(Icons.replay_rounded, [Color(0xFFFFC46B), Color(0xFFF5871F)]),
  'quest': _MetricStyle(Icons.flag_rounded, [Color(0xFFFF8AB8), Color(0xFFD62F8A)]),
  'streak': _MetricStyle(Icons.local_fire_department_rounded, [Color(0xFFFFA06B), Color(0xFFE5391F)]),
};

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
  /// Shown at once with no request (used by tests and previews).
  final SeasonPass? initialPass;

  const SeasonPassScreen({super.key, this.initialPass});

  @override
  State<SeasonPassScreen> createState() => _SeasonPassScreenState();
}

class _SeasonPassScreenState extends State<SeasonPassScreen> with SingleTickerProviderStateMixin {
  SeasonPass? _pass;
  bool _loading = true;
  bool _busy = false;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);
  late final Animation<double> _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);

  @override
  void initState() {
    super.initState();
    if (widget.initialPass != null) {
      _pass = widget.initialPass;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
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

  Future<void> _claim(Future<SeasonPass> Function() action, {required RewardStyle style, required String text}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pass = await action();
      if (!mounted) return;
      setState(() => _pass = pass);
      await showRewardDialog(context, style: style, title: tr('Награда получена!'), text: text);
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
      appBar: AppBar(
        title: Text(tr('Пропуск сезона')),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: tr('Мои награды'),
            icon: const Icon(Icons.military_tech_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CosmeticsScreen())),
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        _Hero(pass: pass),
        const SizedBox(height: 14),
        if (pass.levels.isNotEmpty) _GrandPrize(pass: pass),
        if (pass.premiumEnabled && !pass.isPremium) const _PremiumBanner(),
        const SizedBox(height: 6),
        _SectionTitle(tr('Награды')),
        _LaneHeader(showPremium: pass.premiumEnabled),
        for (var i = 0; i < pass.levels.length; i++)
          _LevelRow(
            level: pass.levels[i],
            reached: pass.levels[i].level <= pass.level,
            current: pass.levels[i].level == pass.level + 1,
            first: i == 0,
            last: i == pass.levels.length - 1,
            showPremium: pass.premiumEnabled,
            pulse: _pulse,
            busy: _busy,
            onClaim: (track, reward) => _claim(
              () => ApiClient.instance.claimPassLevel(pass.levels[i].level, track),
              style: rewardStyle(reward),
              text: rewardSentence(reward),
            ),
          ),
        const SizedBox(height: 18),
        _SectionTitle(tr('Задания недели'), trailing: _WeekLeft(endsAt: pass.weekEndsAt)),
        if (pass.tasks.isEmpty)
          Text(tr('На этой неделе заданий нет'), style: TextStyle(color: AppColors.secondaryText))
        else
          for (final task in pass.tasks)
            _TaskCard(
              task: task,
              pulse: _pulse,
              busy: _busy,
              onClaim: () => _claim(
                () => ApiClient.instance.claimPassTask(task.id),
                style: RewardStyle(_metricStyles[task.metric]?.colors ?? const [Color(0xFFA48BFF), Color(0xFF5862DD)],
                    _metricStyles[task.metric]?.icon ?? Icons.bolt_rounded, 'XP'),
                text: '+${task.xp} XP',
              ),
            ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionTitle(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
        ),
        ?trailing,
      ],
    ),
  );
}

class _Hero extends StatelessWidget {
  final SeasonPass pass;
  const _Hero({required this.pass});

  @override
  Widget build(BuildContext context) {
    final next = pass.xpForNext;
    final value = next == null || next == 0 ? 1.0 : pass.xpIntoLevel / next;
    final left = pass.endsAt?.difference(DateTime.now()).inDays;
    final waiting = pass.claimableCount;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: passHeroGradient(AppColors.dark)),
        boxShadow: [BoxShadow(color: const Color(0xFF5862DD).withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              LevelRing(size: 112, progress: value, level: pass.level),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(passSeasonName(pass), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: 2),
                    Text('${pass.xp} XP', style: const TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      next == null ? tr('Все уровни пройдены') : tr('{0} из {1} XP до следующего уровня', [pass.xpIntoLevel, next]),
                      style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                    if (left != null && left >= 0) ...[
                      const SizedBox(height: 8),
                      _Pill(icon: Icons.timer_outlined, text: tr('До конца сезона дней: {0}', [left])),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (waiting > 0) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(colors: [Color(0xFFFFE066), Color(0xFFFFA000)]),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.card_giftcard_rounded, size: 20, color: Color(0xFF5A3B00)),
                  const SizedBox(width: 8),
                  Text(
                    tr('Наград к получению: {0}', [waiting]),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFF5A3B00)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 5),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
      ],
    ),
  );
}

/// The last level's rewards, shown up front: what the whole season is for.
class _GrandPrize extends StatelessWidget {
  final SeasonPass pass;
  const _GrandPrize({required this.pass});

  @override
  Widget build(BuildContext context) {
    final last = pass.levels.last;
    final rewards = [
      if (last.free != null) last.free!,
      if (pass.premiumEnabled && last.premium != null) last.premium!,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF3A2A00), Color(0xFF6B4B00)]),
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.6),
        boxShadow: [BoxShadow(color: const Color(0xFFFFB300).withValues(alpha: 0.28), blurRadius: 18)],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFFE066), Color(0xFFFF9800)])),
            child: const Icon(Icons.emoji_events_rounded, color: Color(0xFF5A3B00), size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Главная награда сезона'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFFFE066))),
                const SizedBox(height: 2),
                Text(
                  tr('Уровень {0}', [last.level]),
                  style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.75)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final r in rewards)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(rewardStyle(r).icon, size: 14, color: const Color(0xFFFFE066)),
                            const SizedBox(width: 4),
                            Text(rewardSentence(r), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumBanner extends StatelessWidget {
  const _PremiumBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFFFFF3B0), Color(0xFFFFD54F)]),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_rounded, color: Color(0xFF7A5600), size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('С Premium откроются награды справа, в том числе за уже пройденные уровни.'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5A3B00)),
            ),
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
    Widget chip(String text, IconData icon, List<Color> colors) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(colors: colors)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: chip(tr('Бесплатно'), Icons.card_giftcard_rounded, const [Color(0xFF7C84F0), Color(0xFF5862DD)]),
            ),
          ),
          const SizedBox(width: 52),
          if (showPremium)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: chip('Premium', Icons.workspace_premium_rounded, const [Color(0xFFFFB300), Color(0xFFFF7A00)]),
              ),
            ),
        ],
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  final PassLevel level;
  final bool reached;
  final bool current;
  final bool first;
  final bool last;
  final bool showPremium;
  final Animation<double> pulse;
  final bool busy;
  final void Function(String track, PassReward reward) onClaim;

  const _LevelRow({
    required this.level,
    required this.reached,
    required this.current,
    required this.first,
    required this.last,
    required this.showPremium,
    required this.pulse,
    required this.busy,
    required this.onClaim,
  });

  Widget _slot(PassReward? reward, String track) => reward == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: RewardCard(reward: reward, reached: reached, pulse: pulse, busy: busy, onClaim: () => onClaim(track, reward)),
        );

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _slot(level.free, 'free')),
          SizedBox(
            width: 52,
            child: _Node(level: level.level, reached: reached, current: current, first: first, last: last, pulse: pulse),
          ),
          Expanded(child: showPremium ? _slot(level.premium, 'premium') : const SizedBox.shrink()),
        ],
      ),
    );
  }
}

/// The level marker on the vertical track: a lit disc once reached, a ringed
/// one for the level being worked on, a quiet one for the rest.
class _Node extends StatelessWidget {
  final int level;
  final bool reached;
  final bool current;
  final bool first;
  final bool last;
  final Animation<double> pulse;

  const _Node({
    required this.level,
    required this.reached,
    required this.current,
    required this.first,
    required this.last,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final lit = reached ? const Color(0xFF7C6BFF) : AppColors.progressTrack;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: first ? 24 : 0,
          bottom: last ? 24 : 0,
          child: Container(width: 5, decoration: BoxDecoration(color: lit, borderRadius: BorderRadius.circular(3))),
        ),
        AnimatedBuilder(
          animation: pulse,
          builder: (_, __) => Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: reached ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF9B8CFF), Color(0xFF5862DD)]) : null,
              color: reached ? null : AppColors.surface,
              border: Border.all(color: current ? const Color(0xFFFFB300) : (reached ? Colors.white : AppColors.progressTrack), width: current ? 3 : 2),
              boxShadow: [
                if (reached) BoxShadow(color: const Color(0xFF7C6BFF).withValues(alpha: 0.45), blurRadius: 10),
                if (current) BoxShadow(color: const Color(0xFFFFB300).withValues(alpha: 0.25 + 0.4 * pulse.value), blurRadius: 8 + 8 * pulse.value),
              ],
            ),
            child: Text(
              '$level',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: reached ? Colors.white : AppColors.secondaryText),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekLeft extends StatelessWidget {
  final DateTime endsAt;
  const _WeekLeft({required this.endsAt});

  @override
  Widget build(BuildContext context) {
    final days = endsAt.difference(DateTime.now()).inDays + 1;
    if (days < 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(tr('Дней до обновления: {0}', [days]), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final PassTask task;
  final Animation<double> pulse;
  final bool busy;
  final VoidCallback onClaim;

  const _TaskCard({required this.task, required this.pulse, required this.busy, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final m = _metricStyles[task.metric] ?? const _MetricStyle(Icons.bolt_rounded, [Color(0xFFA48BFF), Color(0xFF5862DD)]);
    final value = task.target == 0 ? 1.0 : (task.progress / task.target).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: task.claimable ? m.colors.last.withValues(alpha: 0.5 + 0.5 * pulse.value) : AppColors.cardBorder, width: task.claimable ? 2 : 1),
          boxShadow: [
            if (task.claimable) BoxShadow(color: m.colors.last.withValues(alpha: 0.18 + 0.2 * pulse.value), blurRadius: 14) else ...AppShapes.cardShadow,
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: m.colors),
              ),
              child: Icon(m.icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_taskText(task), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
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
                              gradient: LinearGradient(colors: task.claimed ? const [Color(0xFF34D17F), Color(0xFF14A85C)] : m.colors),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${task.progress} / ${task.target}', style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (task.claimed)
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 30)
            else if (task.claimable)
              FilledButton(
                onPressed: busy ? null : onClaim,
                style: FilledButton.styleFrom(backgroundColor: m.colors.last, padding: const EdgeInsets.symmetric(horizontal: 12)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Забрать'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                    Text('+${task.xp} XP', style: const TextStyle(fontSize: 11)),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(12)),
                child: Text('+${task.xp} XP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
              ),
          ],
        ),
      ),
    );
  }
}
