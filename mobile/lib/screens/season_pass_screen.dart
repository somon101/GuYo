import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../services/streak_state.dart';
import '../models/season_pass.dart';
import '../theme/app_colors.dart';
import '../widgets/game_icons.dart';
import '../widgets/season_pass_ui.dart';
import '../models/team.dart';
import 'cosmetics_screen.dart';
import 'season_summary_screen.dart';
import 'team_screen.dart';

String passSeasonName(SeasonPass pass) {
  final lang = appLanguage.value;
  if (lang == 'tg' && (pass.seasonNameTg ?? '').isNotEmpty)
    return pass.seasonNameTg!;
  if (lang == 'uz' && (pass.seasonNameUz ?? '').isNotEmpty)
    return pass.seasonNameUz!;
  return pass.seasonName;
}

/// "Фраза" for a reward: "Очки рейтинга +20", "Дни Premium +3".
String rewardSentence(PassReward r) {
  final style = rewardStyle(r);
  final amount = rewardAmountText(r);
  return amount.isEmpty ? style.label : '${style.label} $amount';
}

/// «Пропуск сезона»: XP earned by studying fills a ladder of levels, each with
/// a free reward and a Premium one. Everything
/// is decided on the server; this screen only shows it and sends the claims.
class SeasonPassScreen extends StatefulWidget {
  /// Shown at once with no request (used by tests and previews).
  final SeasonPass? initialPass;

  const SeasonPassScreen({super.key, this.initialPass});

  @override
  State<SeasonPassScreen> createState() => _SeasonPassScreenState();
}

class _SeasonPassScreenState extends State<SeasonPassScreen>
    with SingleTickerProviderStateMixin {
  SeasonPass? _pass;
  bool _loading = true;
  bool _busy = false;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);
  late final Animation<double> _pulse = CurvedAnimation(
    parent: _pulseController,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.initialPass != null) {
      _pass = widget.initialPass;
      _loading = false;
    } else {
      _pass = ApiClient.instance.cachedSeasonPass();
      _loading = _pass == null;
    }
    // Always ask for fresh numbers: the cached ones may be a lesson behind.
    _load();
    dailyGoalTick.addListener(_refreshQuietly);
  }

  void _refreshQuietly() async {
    final pass = await ApiClient.instance.fetchSeasonPass();
    if (mounted && pass != null) setState(() => _pass = pass);
  }

  @override
  void dispose() {
    dailyGoalTick.removeListener(_refreshQuietly);
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
    _showSummaryOnce();
  }

  /// The first time the pass is opened after a season ended: the recap.
  Future<void> _showSummaryOnce() async {
    const storage = FlutterSecureStorage();
    try {
      final summary = await ApiClient.instance.fetchSeasonSummary();
      if (summary == null || !mounted) return;
      if (await storage.read(key: 'guyo_summary_seen') == '${summary.seasonId}')
        return;
      await storage.write(
        key: 'guyo_summary_seen',
        value: '${summary.seasonId}',
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SeasonSummaryScreen(initial: summary),
        ),
      );
    } catch (_) {}
  }

  /// «Забрать всё»: everything waiting in one tap, one summary.
  Future<void> _claimAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final (pass, rewards, xp) = await ApiClient.instance.claimAllPass();
      if (!mounted) return;
      setState(() => _pass = pass);
      dailyGoalTick.value++;
      if (rewards.isNotEmpty || xp > 0) await showClaimAllSummary(context, rewards, xp);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(tr('Не удалось. Проверьте интернет.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim(
    Future<SeasonPass> Function() action, {
    required RewardStyle style,
    required String text,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pass = await action();
      if (!mounted) return;
      setState(() => _pass = pass);
      await showRewardDialog(
        context,
        style: style,
        title: tr('Награда получена!'),
        text: text,
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
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(tr('Пропуск сезона')),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pass == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr('Сейчас нет активного сезона'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(onRefresh: _load, child: _body(pass)),
    );
  }

  Widget _body(SeasonPass pass) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        _Hero(pass: pass, busy: _busy, onClaimAll: _claimAll),
        const SizedBox(height: 10),
        // The two ways out that used to be small icons in the top bar.
        Row(children: [
          Expanded(
            child: _LinkButton(
              key: const ValueKey('pass-summary'),
              icon: Icons.insights_rounded,
              label: tr('Итоги сезона'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeasonSummaryScreen())),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LinkButton(
              key: const ValueKey('pass-cosmetics'),
              icon: Icons.military_tech_rounded,
              label: tr('Мои награды'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CosmeticsScreen())),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        const TeamEntryCard(),
        if (pass.levels.isNotEmpty) _GrandPrize(pass: pass),
        if (pass.premiumEnabled && !pass.isPremium) const _PremiumBanner(),
        const SizedBox(height: 6),
        _SectionTitle(tr('Награды')),
        _RewardsStrip(
          pass: pass,
          pulse: _pulse,
          busy: _busy,
          onClaim: (level, track, reward) => _claim(
            () => ApiClient.instance.claimPassLevel(level, track),
            style: rewardStyle(reward),
            text: rewardSentence(reward),
          ),
        ),
      ],
    );
  }
}

/// A light pill button under the hero.
class _LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LinkButton({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(99)),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary))),
          ]),
        ),
      );
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
          child: Text(
            text,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryDark,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _Hero extends StatelessWidget {
  final SeasonPass pass;
  final bool busy;
  final VoidCallback? onClaimAll;
  const _Hero({required this.pass, this.busy = false, this.onClaimAll});

  @override
  Widget build(BuildContext context) {
    final next = pass.xpForNext;
    final value = next == null || next == 0 ? 1.0 : (pass.xpIntoLevel / next).clamp(0.0, 1.0);
    final left = pass.endsAt?.difference(DateTime.now()).inDays;
    final waiting = pass.claimableCount;
    final seasonLine = left != null && left >= 0 ? '${passSeasonName(pass)} · ${tr('До конца сезона дней: {0}', [left])}' : passSeasonName(pass);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.brandGradient)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(seasonLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85)))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
            child: Text(tr('Уровень {0}', [pass.level]), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const EnergyIcon(size: 28),
          const SizedBox(width: 8),
          Text('${pass.xp}', style: const TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1, color: Colors.white)),
          const SizedBox(width: 8),
          Text(tr('энергии'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85))),
        ]),
        const SizedBox(height: 12),
        _LevelBar(levels: pass.levels.length, level: pass.level, progress: value),
        const SizedBox(height: 6),
        Text(
          next == null ? tr('Все уровни пройдены') : tr('{0} из {1} энергии до следующего уровня', [pass.xpIntoLevel, next]),
          style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.85)),
        ),
        if (waiting > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: Colors.white.withValues(alpha: 0.16)),
            child: Row(children: [
              Expanded(child: Text(tr('Наград к получению: {0}', [waiting]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white))),
              if (waiting >= 2 && onClaimAll != null)
                GestureDetector(
                  key: const ValueKey('claim-all'),
                  onTap: busy ? null : onClaimAll,
                  child: Opacity(
                    opacity: busy ? 0.6 : 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                      child: Text(tr('Забрать всё'), style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// The levels as a row of divisions: passed ones filled, the next one filled as far as the energy
/// goes. With many levels it is one continuous bar.
class _LevelBar extends StatelessWidget {
  final int levels;
  final int level;
  final double progress;
  const _LevelBar({required this.levels, required this.level, required this.progress});

  @override
  Widget build(BuildContext context) {
    Widget seg(double fill) => Expanded(
          child: Container(
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(99)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fill.clamp(0.0, 1.0),
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99))),
            ),
          ),
        );
    if (levels > 0 && levels <= 12) {
      return Row(children: [
        for (var i = 0; i < levels; i++) seg(i < level ? 1 : (i == level ? progress : 0)),
      ]);
    }
    final total = levels <= 0 ? 1 : levels;
    return Row(children: [seg((level + progress) / total)]);
  }
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
    if (rewards.isEmpty) return const SizedBox.shrink();
    final dark = AppColors.dark;
    final bg = dark ? const Color(0xFF33290F) : const Color(0xFFFFF6E0);
    final ink = dark ? const Color(0xFFFFD98A) : const Color(0xFF7A5200);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: bg),
      child: Row(children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: const Color(0xFFF2B33D).withValues(alpha: 0.18)),
          child: RewardArt(reward: rewards.first, size: 60),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${tr('Главная награда сезона')} · ${tr('Уровень {0}', [last.level])}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final r in rewards)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.surface.withValues(alpha: dark ? 0.5 : 0.8), borderRadius: BorderRadius.circular(14)),
                  child: Text(rewardSentence(r), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                ),
            ]),
          ]),
        ),
      ]),
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
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3B0), Color(0xFFFFD54F)],
        ),
      ),
      child: Row(
        children: [
          const PremiumIcon(size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'С Premium откроются награды справа, в том числе за уже пройденные уровни.',
              ),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5A3B00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rewards as a strip that scrolls sideways: a column per level (the level number, the free
/// reward, the Premium one); the row names stay on the left. Opens at the level being worked on.
class _RewardsStrip extends StatefulWidget {
  final SeasonPass pass;
  final Animation<double> pulse;
  final bool busy;
  final void Function(int level, String track, PassReward reward) onClaim;
  const _RewardsStrip({required this.pass, required this.pulse, required this.busy, required this.onClaim});

  @override
  State<_RewardsStrip> createState() => _RewardsStripState();
}

class _RewardsStripState extends State<_RewardsStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Open near the level being worked on, the passed ones are to the left.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = ((widget.pass.level - 1) * 100.0).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.jumpTo(target);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _node(PassLevel l) {
    final reached = l.level <= widget.pass.level;
    final current = l.level == widget.pass.level + 1;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reached ? AppColors.primary : (current ? AppColors.surface : AppColors.violetSurface),
        border: current ? Border.all(color: AppColors.primary, width: 2) : null,
      ),
      child: Text('${l.level}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: reached ? Colors.white : (current ? AppColors.primary : AppColors.secondaryText))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pass = widget.pass;
    final premium = pass.premiumEnabled;
    Widget label(Widget child) => SizedBox(height: 104, child: Align(alignment: Alignment.centerLeft, child: child));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 64,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 38),
          label(Text(tr('Бесплатно'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.secondaryText))),
          if (premium) ...[
            const SizedBox(height: 8),
            label(Row(children: [
              const PremiumIcon(size: 16),
              const SizedBox(width: 3),
              Flexible(child: Text('Premium', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFFE09A12)))),
            ])),
          ],
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          key: const ValueKey('pass-strip'),
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final l in pass.levels)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(children: [
                  _node(l),
                  const SizedBox(height: 8),
                  if (l.free != null)
                    PassTile(reward: l.free!, reached: l.level <= pass.level, busy: widget.busy, onClaim: () => widget.onClaim(l.level, 'free', l.free!))
                  else
                    const SizedBox(width: 92, height: 104),
                  if (premium) ...[
                    const SizedBox(height: 8),
                    if (l.premium != null)
                      PassTile(reward: l.premium!, reached: l.level <= pass.level, busy: widget.busy, onClaim: () => widget.onClaim(l.level, 'premium', l.premium!))
                    else
                      const SizedBox(width: 92, height: 104),
                  ],
                ]),
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// The way into «Команда» from the pass: the team's name and goals waiting to be
/// claimed, or an invitation to make one. Hides itself if it can't load.
class TeamEntryCard extends StatefulWidget {
  const TeamEntryCard({super.key});

  @override
  State<TeamEntryCard> createState() => _TeamEntryCardState();
}

class _TeamEntryCardState extends State<TeamEntryCard> {
  TeamState? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ApiClient.instance.fetchMyTeam();
    if (mounted) setState(() => _state = s);
  }

  Future<void> _open() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TeamScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) return const SizedBox.shrink();
    final team = state.team;
    final waiting = team?.claimableCount ?? 0;
    final invites = state.invites.length;
    final String title = team?.name ?? tr('Командные цели');
    final String subtitle = team == null
        ? (invites > 0
              ? tr('Приглашений: {0}', [invites])
              : tr('Соберите команду из друзей'))
        : (waiting > 0
              ? tr('Наград к получению: {0}', [waiting])
              : tr('В команде: {0} из {1}', [
                  team.members.length,
                  state.capacity,
                ]));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _open,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF14B8A6), Color(0xFF2563EB)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.groups_rounded, size: 40, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              if (waiting > 0 || invites > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFE066), Color(0xFFFFA000)],
                    ),
                  ),
                  child: Text(
                    '${waiting + invites}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF5A3B00),
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
