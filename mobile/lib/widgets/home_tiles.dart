import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../screens/chest_list_screen.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import 'game_icons.dart';
import 'gift_badge.dart';

/// «Мои награды» on Главная: one card «Подарки» (the chests and, inside them, the doublers). A
/// waiting chest of the day is taken right from the card's button; otherwise the card just opens
/// the chests. The pass is in the top bar and the duel is in «Уроки», so neither is here.
class HomeTilesRow extends StatefulWidget {
  const HomeTilesRow({super.key});

  @override
  State<HomeTilesRow> createState() => _HomeTilesRowState();
}

class _HomeTilesRowState extends State<HomeTilesRow> {
  ChestBank? _bank = ApiClient.instance.cachedChests();
  int _gain = 0; // chests that just arrived (shown as «+N» for a few seconds)
  Timer? _gainTimer;

  @override
  void initState() {
    super.initState();
    dailyGoalTick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dailyGoalTick.removeListener(_load);
    _gainTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final b = await ApiClient.instance.fetchChests();
    if (mounted && b != null) {
      final before = _bank?.chests.length;
      setState(() {
        _bank = b;
        if (before != null && b.chests.length > before) _gain = b.chests.length - before;
      });
      if (_gain > 0) {
        _gainTimer?.cancel();
        _gainTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _gain = 0);
        });
      }
    }
  }

  Future<void> _openChests() async {
    final bank = _bank;
    if (bank == null) return;
    final result = await Navigator.of(context).push<ChestBank>(MaterialPageRoute(builder: (_) => ChestListScreen(bank: bank)));
    if (result != null && mounted) setState(() => _bank = result);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final bank = _bank;
    if (bank == null) return const SizedBox.shrink();
    final dailyWaiting = bank.daily.enabled && !bank.daily.claimed && bank.daily.available;
    return HomeGiftsCard(
      key: const ValueKey('tile-chests'),
      sub: dailyWaiting ? tr('Сундук дня ждёт') : bank.doubleRewards ? tr('Есть двойные награды') : tr('Мои сундуки'),
      count: bank.chests.length,
      plus: _gain > 0 ? '+$_gain' : null,
      ready: dailyWaiting,
      onTap: _openChests,
    );
  }
}

/// The «Подарки» card: the gift, the name, one short line and either «Забрать» (the chest of the
/// day is waiting) or an arrow. A flat surface, no colour plate.
class HomeGiftsCard extends StatelessWidget {
  final String sub;
  final int count;
  final String? plus;
  final bool ready;
  final VoidCallback onTap;
  const HomeGiftsCard({super.key, required this.sub, required this.count, this.plus, required this.ready, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.cardBorder)),
          child: Row(children: [
            ready ? const GiftBadge(size: 44) : const GiftIcon(size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Flexible(child: Text(tr('Подарки'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark))),
                  if (plus != null) ...[
                    const SizedBox(width: 6),
                    Text(plus!, key: const ValueKey('tile-plus'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.success)),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
              ]),
            ),
            const SizedBox(width: 8),
            if (ready)
              Container(
                key: const ValueKey('tile-claim'),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                child: Text(tr('Забрать'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
              )
            else
              Icon(Icons.chevron_right_rounded, color: AppColors.secondaryText),
          ]),
        ),
      ),
    );
  }
}
