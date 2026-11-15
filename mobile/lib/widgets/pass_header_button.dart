import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/season_pass.dart';
import '../screens/season_pass_screen.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import 'game_icons.dart';

/// The season pass in the top bar of Главная, where the wordmark used to be: the energy, «Пропуск»,
/// the level and the energy so far, and a red number for the rewards waiting. Opens the pass.
/// Until a pass is known (no season, or not loaded yet) [fallback] stands in its place.
class PassHeaderButton extends StatefulWidget {
  final Widget fallback;

  /// The pass to start from (tests); otherwise the remembered one.
  final SeasonPass? initialPass;
  const PassHeaderButton({super.key, required this.fallback, this.initialPass});

  @override
  State<PassHeaderButton> createState() => _PassHeaderButtonState();
}

class _PassHeaderButtonState extends State<PassHeaderButton> {
  late SeasonPass? _pass = widget.initialPass ?? ApiClient.instance.cachedSeasonPass();

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
    final pass = await ApiClient.instance.fetchSeasonPass();
    if (mounted && pass != null) setState(() => _pass = pass);
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeasonPassScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pass = _pass;
    if (pass == null) return widget.fallback;
    final waiting = pass.claimableCount;
    return Semantics(
      button: true,
      label: tr('Пропуск'),
      child: GestureDetector(
        key: const ValueKey('pass-button'),
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            height: 44,
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const EnergyIcon(size: 26),
              const SizedBox(width: 8),
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Пропуск'), style: TextStyle(fontSize: 14, height: 1.15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                Text(
                  '${tr('{0} ур.', [pass.level])} · ${pass.xp}',
                  key: const ValueKey('pass-button-sub'),
                  style: TextStyle(fontSize: 11.5, height: 1.2, color: AppColors.secondaryText),
                ),
              ]),
            ]),
          ),
          if (waiting > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                key: const ValueKey('pass-button-badge'),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.canvas, width: 2)),
                child: Text('$waiting', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
        ]),
      ),
    );
  }
}
