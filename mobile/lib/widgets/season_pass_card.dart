import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/season_pass.dart';
import '../screens/season_pass_screen.dart';
import '../theme/app_colors.dart';
import 'season_pass_ui.dart';

/// The way into «Пропуск сезона» from Главная: the level ring, how close the
/// next level is and how many rewards wait. Hides itself while no season is
/// live or the pass can't load, so it never gets in the way of the screen.
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
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SeasonPassScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pass = _pass;
    if (pass == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SeasonPassCardView(pass: pass, onTap: _open),
    );
  }
}

/// The card itself, drawn from a loaded pass (also used by previews and tests).
class SeasonPassCardView extends StatelessWidget {
  final SeasonPass pass;
  final VoidCallback onTap;
  const SeasonPassCardView({
    super.key,
    required this.pass,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final next = pass.xpForNext;
    final value = next == null || next == 0
        ? 1.0
        : (pass.xpIntoLevel / next).clamp(0.0, 1.0);
    final waiting = pass.claimableCount;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: passHeroGradient(AppColors.dark),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5862DD).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              LevelRing(
                size: 64,
                progress: value,
                level: pass.level,
                stroke: 7,
                compact: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Пропуск сезона'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${passSeasonName(pass)} · ⚡ ${pass.xp}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 7,
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        color: const Color(0xFFFFD54F),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (waiting > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFE066), Color(0xFFFFA000)],
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        size: 16,
                        color: Color(0xFF5A3B00),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$waiting',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF5A3B00),
                        ),
                      ),
                    ],
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
