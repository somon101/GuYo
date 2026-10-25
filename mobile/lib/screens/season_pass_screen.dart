import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../services/streak_state.dart';
import '../models/season_pass.dart';
import '../theme/app_colors.dart';
import '../widgets/counted_chest.dart' show GreenButton;
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
        actions: [
          IconButton(
            tooltip: tr('Итоги сезона'),
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SeasonSummaryScreen()),
            ),
          ),
          IconButton(
            tooltip: tr('Мои награды'),
            icon: const Icon(Icons.military_tech_rounded),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CosmeticsScreen())),
          ),
        ],
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
        const SizedBox(height: 14),
        const TeamEntryCard(),
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
              () => ApiClient.instance.claimPassLevel(
                pass.levels[i].level,
                track,
              ),
              style: rewardStyle(reward),
              text: rewardSentence(reward),
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
    final value = next == null || next == 0 ? 1.0 : pass.xpIntoLevel / next;
    final left = pass.endsAt?.difference(DateTime.now()).inDays;
    final waiting = pass.claimableCount;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: passHeroGradient(AppColors.dark),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5862DD).withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
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
                    Text(
                      passSeasonName(pass),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 2),
                    IconText(
                      '⚡ ${pass.xp} ${tr('энергии')}',
                      style: const TextStyle(
                        fontSize: 30,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      next == null
                          ? tr('Все уровни пройдены')
                          : tr('{0} из {1} энергии до следующего уровня', [
                              pass.xpIntoLevel,
                              next,
                            ]),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    if (left != null && left >= 0) ...[
                      const SizedBox(height: 8),
                      _Pill(
                        icon: Icons.timer_outlined,
                        text: tr('До конца сезона дней: {0}', [left]),
                      ),
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
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withValues(alpha: 0.16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GiftIcon(size: 28),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      tr('Наград к получению: {0}', [waiting]),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                  if (waiting >= 2 && onClaimAll != null) ...[
                    const SizedBox(width: 10),
                    GreenButton(key: const ValueKey('claim-all'), label: tr('Забрать всё'), onTap: busy ? null : onClaimAll, compact: true),
                  ],
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
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF3A2A00), Color(0xFF6B4B00)],
        ),
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withValues(alpha: 0.28),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFFE066), Color(0xFFFF9800)],
              ),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFF5A3B00),
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Главная награда сезона'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFFE066),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr('Уровень {0}', [last.level]),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final r in rewards)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              rewardStyle(r).icon,
                              size: 14,
                              color: const Color(0xFFFFE066),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rewardSentence(r),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
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

class _LaneHeader extends StatelessWidget {
  final bool showPremium;
  const _LaneHeader({required this.showPremium});

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, IconData icon, List<Color> colors, {Widget? leading}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: colors),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ?? Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
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
              child: chip(tr('Бесплатно'), Icons.card_giftcard_rounded, const [
                Color(0xFF7C84F0),
                Color(0xFF5862DD),
              ]),
            ),
          ),
          const SizedBox(width: 52),
          if (showPremium)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: chip('Premium', Icons.workspace_premium_rounded, const [
                  Color(0xFFFFB300),
                  Color(0xFFFF7A00),
                ], leading: const PremiumIcon(size: 18)),
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
          child: RewardCard(
            reward: reward,
            reached: reached,
            pulse: pulse,
            busy: busy,
            onClaim: () => onClaim(track, reward),
          ),
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
            child: _Node(
              level: level.level,
              reached: reached,
              current: current,
              first: first,
              last: last,
              pulse: pulse,
            ),
          ),
          Expanded(
            child: showPremium
                ? _slot(level.premium, 'premium')
                : const SizedBox.shrink(),
          ),
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
          child: Container(
            width: 5,
            decoration: BoxDecoration(
              color: lit,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: pulse,
          builder: (_, __) => Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: reached
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF9B8CFF), Color(0xFF5862DD)],
                    )
                  : null,
              color: reached ? null : AppColors.surface,
              border: Border.all(
                color: current
                    ? const Color(0xFFFFB300)
                    : (reached ? Colors.white : AppColors.progressTrack),
                width: current ? 3 : 2,
              ),
              boxShadow: [
                if (reached)
                  BoxShadow(
                    color: const Color(0xFF7C6BFF).withValues(alpha: 0.45),
                    blurRadius: 10,
                  ),
                if (current)
                  BoxShadow(
                    color: const Color(0xFFFFB300)
                        .withValues(alpha: 0.25 + 0.4 * pulse.value),
                    blurRadius: 8 + 8 * pulse.value,
                  ),
              ],
            ),
            child: Text(
              '$level',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: reached ? Colors.white : AppColors.secondaryText,
              ),
            ),
          ),
        ),
      ],
    );
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
