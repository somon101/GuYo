import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../models/duel.dart';
import '../models/season_pass.dart';
import '../screens/chest_list_screen.dart';
import '../screens/season_pass_screen.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import 'duel_card.dart';
import 'game_icons.dart';
import 'gift_badge.dart';

/// «Мои награды» on Главная: a row of small tiles that scrolls sideways (the next one peeks out):
/// chests, the weekly duel, the season pass and the doublers. Each opens its own screen; the
/// duel opens its full card in a sheet, so nothing of its flow is lost.
class HomeTilesRow extends StatefulWidget {
  const HomeTilesRow({super.key});

  @override
  State<HomeTilesRow> createState() => _HomeTilesRowState();
}

class _HomeTilesRowState extends State<HomeTilesRow> {
  ChestBank? _bank = ApiClient.instance.cachedChests();
  DuelState? _duels = ApiClient.instance.cachedDuels();
  SeasonPass? _pass = ApiClient.instance.cachedSeasonPass();
  BoosterState? _boosters = ApiClient.instance.cachedBoosters();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    dailyGoalTick.addListener(_load);
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _anyRunning) setState(() {});
    });
  }

  @override
  void dispose() {
    dailyGoalTick.removeListener(_load);
    _tick?.cancel();
    super.dispose();
  }

  bool get _anyRunning => ['chest', 'rating', 'xp'].any((k) => _boosters?.of(k).running ?? false);

  Future<void> _load() async {
    final bank = ApiClient.instance.fetchChests();
    final duels = ApiClient.instance.fetchDuels();
    final pass = ApiClient.instance.fetchSeasonPass();
    final boosters = ApiClient.instance.fetchBoosters();
    final b = await bank;
    if (mounted && b != null) setState(() => _bank = b);
    final d = await duels;
    if (mounted && d != null) setState(() => _duels = d);
    final p = await pass;
    if (mounted && p != null) setState(() => _pass = p);
    final bo = await boosters;
    if (mounted && bo != null) setState(() => _boosters = bo);
  }

  Future<void> _openChests() async {
    final bank = _bank;
    if (bank == null) return;
    final result = await Navigator.of(context).push<ChestBank>(MaterialPageRoute(builder: (_) => ChestListScreen(bank: bank)));
    if (result != null && mounted) setState(() => _bank = result);
    if (mounted) _load();
  }

  Future<void> _openPass() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeasonPassScreen()));
    final fresh = ApiClient.instance.cachedSeasonPass();
    if (mounted && fresh != null) setState(() => _pass = fresh);
    if (mounted) _load();
  }

  Future<void> _openDuel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 24), child: SingleChildScrollView(child: DuelCard()))),
    );
    if (mounted) _load();
  }

  String _left(DateTime until) {
    final s = until.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    final bank = _bank;
    if (bank != null) {
      final owned = bank.chests.length;
      final dailyWaiting = bank.daily.enabled && !bank.daily.claimed && bank.daily.available;
      final best = bank.chests.isEmpty ? 'wood' : bank.chests.last.chestKey;
      tiles.add(HomeTile(
        key: const ValueKey('tile-chests'),
        icon: ChestImage(best, size: 34),
        title: tr('Сундуки'),
        big: '$owned',
        sub: dailyWaiting ? tr('Сундук дня ждёт') : bank.doubleRewards ? tr('Есть двойные награды') : tr('Мои сундуки'),
        onTap: _openChests,
        badge: dailyWaiting ? const GiftBadge(size: 22) : null,
      ));
    }
    final duels = _duels;
    if (duels != null && duels.enabled) {
      final d = duels.current;
      final days = d == null ? 0 : (d.endsAt.difference(DateTime.now()).inDays + 1).clamp(0, 99);
      final total = d == null ? 0 : d.myXp + d.theirXp;
      tiles.add(HomeTile(
        key: const ValueKey('tile-duel'),
        icon: Icon(Icons.sports_mma_rounded, size: 20, color: AppColors.primary),
        title: tr('Дуэль недели'),
        big: d == null ? tr('Вызов') : '${d.myXp}',
        sub: d == null ? tr('Вызвать друга') : d.isPending ? tr('Ждём ответ') : tr('Осталось дней: {0}', [days]),
        progress: d != null && d.isActive && total > 0 ? d.myXp / total : null,
        progressColor: AppColors.warning,
        onTap: _openDuel,
      ));
    }
    final pass = _pass;
    if (pass != null) {
      final next = pass.xpForNext;
      final waiting = pass.claimableCount;
      tiles.add(HomeTile(
        key: const ValueKey('tile-pass'),
        icon: const EnergyIcon(size: 28),
        title: tr('Пропуск'),
        big: tr('{0} ур.', [pass.level]),
        sub: tr('Энергии: {0}', [pass.xp]),
        progress: next == null || next == 0 ? 1.0 : (pass.xpIntoLevel / next).clamp(0.0, 1.0),
        progressColor: AppColors.primary,
        onTap: _openPass,
        badge: waiting > 0 ? GiftBadge(count: waiting, size: 22) : null,
      ));
    }
    final b = _boosters;
    if (b != null) {
      final kinds = [for (final k in const ['chest', 'rating', 'xp']) if (b.of(k).total > 0 || b.of(k).running) k];
      if (kinds.isNotEmpty) {
        final total = kinds.fold<int>(0, (n, k) => n + b.of(k).total);
        final running = [for (final k in kinds) if (b.of(k).running) k];
        tiles.add(HomeTile(
          key: const ValueKey('tile-boosters'),
          icon: BoosterIcon(size: 34, kind: running.isNotEmpty ? running.first : kinds.first),
          title: tr('Бонусы'),
          big: '$total',
          sub: running.isNotEmpty ? tr('Идёт {0}', [_left(b.of(running.first).activeUntil!)]) : tr('Удвоители'),
          onTap: _openChests,
        ));
      }
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth + 16; // the row runs to the screen edge, so the next tile peeks out
      return SizedBox(
        height: 134,
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: width,
          maxWidth: width,
          child: SizedBox(
            width: width,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 16),
              itemCount: tiles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => tiles[i],
            ),
          ),
        ),
      );
    });
  }
}

/// One tile of the row: a small icon on a soft chip, the title, a big figure and a short line.
class HomeTile extends StatelessWidget {
  final Widget icon;
  final String title;
  final String big;
  final String sub;
  final double? progress;
  final Color? progressColor;
  final VoidCallback onTap;
  final Widget? badge;
  const HomeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.big,
    required this.sub,
    required this.onTap,
    this.progress,
    this.progressColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 150,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(10)),
                child: icon,
              ),
              const SizedBox(width: 8),
              Expanded(child: Padding(padding: EdgeInsets.only(right: badge != null ? 26 : 0), child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, height: 1.15, fontWeight: FontWeight.w700, color: AppColors.primaryDark)))),
            ]),
            const Spacer(),
            Text(big, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.primaryDark)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 6,
                child: Stack(children: [
                  Positioned.fill(child: ColoredBox(color: AppColors.progressTrack)),
                  if (progress != null)
                    FractionallySizedBox(widthFactor: progress!.clamp(0.0, 1.0), child: ColoredBox(color: progressColor ?? AppColors.primary)),
                ]),
              ),
            ),
          ]),
        ),
        // Inside the tile's corner, so the row never clips it.
        if (badge != null) Positioned(top: 6, right: 6, child: IgnorePointer(child: badge!)),
      ]),
    );
  }
}
