import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../services/streak_state.dart';
import 'season_pass_ui.dart';

/// «Сундук дня»: appears after the day's first study; one tap opens it for a
/// small random bonus. Gone for the rest of the day once opened.
class DailyChestCard extends StatefulWidget {
  const DailyChestCard({super.key});

  @override
  State<DailyChestCard> createState() => _DailyChestCardState();
}

class _DailyChestCardState extends State<DailyChestCard> {
  ChestState? _state;
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
    final state = await ApiClient.instance.fetchChest();
    if (mounted && state != null) setState(() => _state = state);
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final state = await ApiClient.instance.openChest();
      ApiClient.instance.fetchEconomy();
      if (!mounted) return;
      setState(() => _state = state);
      final freeze = state.kind == 'freeze';
      final legacyXp = state.kind == 'xp';
      await showRewardDialog(
        context,
        style: freeze
            ? const RewardStyle(
                [Color(0xFF7FDBFF), Color(0xFF3A7BFF)],
                Icons.ac_unit_rounded,
                '',
              )
            : legacyXp
            ? const RewardStyle(
                [Color(0xFFFFD54F), Color(0xFFFF9800)],
                Icons.bolt_rounded,
                '',
              )
            : const RewardStyle(
                [Color(0xFF92F2FF), Color(0xFF6558FF)],
                Icons.diamond_rounded,
                '',
              ),
        title: tr('Сундук открыт!'),
        text: freeze
            ? tr('Заморозка серии +1')
            : legacyXp
            ? '+${state.amount} ⚡'
            : '+${state.amount} ${tr('бриллиантов')}',
      );
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Не удалось. Проверьте интернет.'))),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null || !state.available) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DailyChestCardView(onTap: _busy ? null : _open),
    );
  }
}

class DailyChestCardView extends StatelessWidget {
  final VoidCallback? onTap;
  const DailyChestCardView({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: const ValueKey('daily-chest'),
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFB74D), Color(0xFFFF7043)],
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.inventory_2_rounded,
              color: Colors.white,
              size: 38,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Сундук дня'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    tr('Нажмите, чтобы открыть'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}
