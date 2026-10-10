import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../guyo_ui.dart';

/// The one "round over" card every Practice exercise ends on: a local
/// correct count -- Practice keeps no score of its own, so this is purely
/// feedback for the player, never sent anywhere -- plus "Играть ещё раз"
/// (a fresh random sample) and "Назад" (out to the Практика grid).
class PracticeRoundComplete extends StatelessWidget {
  final int correctCount;
  final int total;
  final VoidCallback onPlayAgain;
  final VoidCallback onBack;

  const PracticeRoundComplete({
    super.key,
    required this.correctCount,
    required this.total,
    required this.onPlayAgain,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GuyoCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RoundIconChip(
              icon: Icons.emoji_events_rounded,
              size: 56,
              background: AppColors.rewardBackground,
              iconColor: AppColors.rewardText,
            ),
            const SizedBox(height: 16),
            Text(
              tr('Практика завершена!'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 6),
            Text(tr('Правильно: {0} из {1}', [correctCount, total]), style: TextStyle(color: AppColors.secondaryText)),
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onBack, child: Text(tr('Назад'))),
                const SizedBox(width: 12),
                FilledButton.icon(onPressed: onPlayAgain, icon: const Icon(Icons.refresh_rounded), label: Text(tr('Играть ещё раз'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when there simply aren't enough learned words yet for this
/// exercise type -- not an error, a real and expected state for a new
/// account or a dictionary the user has barely started.
class PracticeEmptyState extends StatelessWidget {
  const PracticeEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return GuyoEmptyState(
      icon: Icons.auto_awesome_rounded,
      title: tr('Пока недостаточно слов для практики'),
      message: tr('Изучите больше слов в Уроках, чтобы открыть это упражнение здесь.'),
    );
  }
}
