import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../services/chest_queue.dart';
import '../screens/chest_list_screen.dart';
import '../services/streak_state.dart';
import 'counted_chest.dart';
import 'game_icons.dart';

/// The home card for chests: the chest of the day (take it once its condition
/// is met) and the bank of unopened chests.
class ChestsCard extends StatefulWidget {
  const ChestsCard({super.key});

  @override
  State<ChestsCard> createState() => _ChestsCardState();
}

class _ChestsCardState extends State<ChestsCard> {
  ChestBank? _bank = ApiClient.instance.cachedChests();
  bool _busy = false;
  String? _notice;
  Timer? _noticeTimer;

  void _say(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  @override
  void initState() {
    super.initState();
    dailyGoalTick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dailyGoalTick.removeListener(_load);
    _noticeTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await ChestQueue.flush();
    final bank = await ApiClient.instance.fetchChests();
    if (mounted && bank != null) setState(() => _bank = bank);
  }

  Future<void> _openList(ChestBank bank) async {
    final result = await Navigator.of(context).push<ChestBank>(MaterialPageRoute(builder: (_) => ChestListScreen(bank: bank)));
    if (result != null && mounted) setState(() => _bank = result);
    if (mounted) _load();
  }

  Future<void> _claim() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bank = await ApiClient.instance.claimDailyChest();
      if (!mounted) return;
      setState(() => _bank = bank);
    } on ApiException catch (e) {
      if (mounted) _say(e.message);
    } catch (_) {
      if (mounted) _say(tr('Не удалось. Проверьте интернет.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bank = _bank;
    if (bank == null) return const SizedBox.shrink();
    final daily = bank.daily;
    final showDaily = daily.enabled && !daily.claimed;
    if (!showDaily && bank.chests.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ChestsCardView(
        bank: bank,
        onClaim: _busy || !daily.available ? null : _claim,
        onOpen: () => _openList(bank),
        notice: _notice,
      ),
    );
  }
}

class ChestsCardView extends StatelessWidget {
  final ChestBank bank;
  final VoidCallback? onClaim;
  final VoidCallback? onOpen;
  final String? notice;
  const ChestsCardView({super.key, required this.bank, this.onClaim, this.onOpen, this.notice});

  @override
  Widget build(BuildContext context) {
    final daily = bank.daily;
    final showDaily = daily.enabled && !daily.claimed;
    final owned = [for (final tp in bank.types) if (bank.chests.any((c) => c.chestKey == tp.key)) tp];
    return GestureDetector(
      key: const ValueKey('chests-card'),
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFF3D2B8F), Color(0xFF1E1560)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (showDaily)
            InkWell(
              key: const ValueKey('daily-chest'),
              borderRadius: BorderRadius.circular(16),
              onTap: onClaim ?? onOpen,
              child: Row(children: [
                Opacity(opacity: daily.available ? 1 : 0.45, child: ChestImage(daily.chestKey, size: 64)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Сундук дня'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      daily.available ? tr('Нажмите, чтобы забрать') : daily.conditions,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ]),
                ),
                if (daily.available) const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ]),
            ),
          if (notice != null)
            Container(
              key: const ValueKey('chest-notice'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0x33FFB020), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x80FFB020))),
              child: Text(notice!, style: const TextStyle(color: Color(0xFFFFD27A), fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          if (showDaily && bank.chests.isNotEmpty) const Divider(color: Colors.white24, height: 22),
          if (bank.chests.isNotEmpty)
            Row(key: const ValueKey('my-chests'), children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tr('Мои сундуки')} · ${bank.chests.length}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 14, runSpacing: 8, children: [
                    for (final tp in owned)
                      CountedChest(chestKey: tp.key, color: Color(tp.color), count: bank.chests.where((c) => c.chestKey == tp.key).length, size: 42),
                  ]),
                ]),
              ),
              GreenButton(label: tr('Открыть'), onTap: onOpen),
            ]),
          if (bank.doubleRewards)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('✨ ${tr('Двойные награды из сундуков!')}', style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w700, fontSize: 13)),
            ),
        ]),
      ),
    );
  }
}
