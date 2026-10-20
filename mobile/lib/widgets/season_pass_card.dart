import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/season_pass.dart';
import '../screens/season_pass_screen.dart';
import '../theme/app_colors.dart';
import 'guyo_ui.dart';

/// The way into «Пропуск сезона» from Главная: the level and how close the
/// next one is. Hides itself while no season is live or the pass can't load,
/// so it never gets in the way of the rest of the screen.
class SeasonPassCard extends StatefulWidget {
  const SeasonPassCard({super.key});

  @override
  State<SeasonPassCard> createState() => _SeasonPassCardState();
}

class _SeasonPassCardState extends State<SeasonPassCard> {
  SeasonPass? _pass;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pass = await ApiClient.instance.fetchSeasonPass();
    if (mounted) setState(() => _pass = pass);
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeasonPassScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pass = _pass;
    if (pass == null) return const SizedBox.shrink();
    final next = pass.xpForNext;
    final value = next == null || next == 0 ? 1.0 : (pass.xpIntoLevel / next).clamp(0.0, 1.0);
    final waiting = pass.claimableCount;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GuyoCard(
        onTap: _open,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.violetSurface),
              child: Text(
                '${pass.level}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Пропуск сезона'),
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 7,
                      backgroundColor: AppColors.progressTrack,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    waiting > 0 ? tr('Наград к получению: {0}', [waiting]) : '${pass.xp} XP',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: waiting > 0 ? FontWeight.w700 : FontWeight.w400,
                      color: waiting > 0 ? AppColors.success : AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
