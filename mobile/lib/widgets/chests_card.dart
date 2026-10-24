import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../screens/chest_open_screen.dart';
import '../services/streak_state.dart';
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

  @override
  void initState() {
    super.initState();
    dailyGoalTick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dailyGoalTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final bank = await ApiClient.instance.fetchChests();
    if (mounted && bank != null) setState(() => _bank = bank);
  }

  Future<void> _openAll(ChestBank bank) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChestOpenScreen(bank: bank)));
    if (mounted) _load();
  }

  Future<void> _claim() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bank = await ApiClient.instance.claimDailyChest();
      if (!mounted) return;
      setState(() => _bank = bank);
      await _openAll(bank);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Не удалось. Проверьте интернет.'))));
      }
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
        onOpen: bank.chests.isEmpty ? null : () => _openAll(bank),
      ),
    );
  }
}

class ChestsCardView extends StatelessWidget {
  final ChestBank bank;
  final VoidCallback? onClaim;
  final VoidCallback? onOpen;
  const ChestsCardView({super.key, required this.bank, this.onClaim, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final daily = bank.daily;
    final showDaily = daily.enabled && !daily.claimed;
    return Container(
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
            onTap: onClaim,
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
        if (showDaily && bank.chests.isNotEmpty) const Divider(color: Colors.white24, height: 22),
        if (bank.chests.isNotEmpty)
          InkWell(
            key: const ValueKey('my-chests'),
            borderRadius: BorderRadius.circular(16),
            onTap: onOpen,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${tr('Мои сундуки')} · ${bank.chests.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: Row(children: [
                      for (final c in bank.chests.take(5)) Padding(padding: const EdgeInsets.only(right: 6), child: ChestImage(c.chestKey, size: 46)),
                      if (bank.chests.length > 5)
                        Text('+${bank.chests.length - 5}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFFFC53D), borderRadius: BorderRadius.circular(14)),
                child: Text(tr('Открыть'), style: const TextStyle(color: Color(0xFF3B2600), fontWeight: FontWeight.w900)),
              ),
            ]),
          ),
        if (bank.doubleRewards)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('✨ ${tr('Двойные награды из сундуков!')}', style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w700, fontSize: 13)),
          ),
      ]),
    );
  }
}
