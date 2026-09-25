import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../guyo_ui.dart';

/// The one progress readout every Lesson exercise round shows at the top:
/// real rating points earned so far this round (almost always 0 -- see
/// SubmitAnswerResult.pointsAwarded, only ever positive the moment some
/// word crosses the learned threshold), and where the round is.
///
/// Exists once here so every exercise type's Lesson host renders the
/// identical strip instead of five near-copies of the same row -- part of
/// bringing every exercise to one shared design language, not just
/// «Правда или ложь». A Quest host never uses this: a quest is always
/// exactly one item, so "N из M" would always read "1 из 1".
class ExerciseProgressHeader extends StatelessWidget {
  final int points;
  final int position;
  final int total;

  const ExerciseProgressHeader({super.key, required this.points, required this.position, required this.total});

  @override
  Widget build(BuildContext context) {
    return GuyoCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, size: 18, color: AppColors.rewardText),
          const SizedBox(width: 6),
          Text('$points', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          const SizedBox(width: 14),
          Container(width: 1, height: 20, color: AppColors.cardBorder),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(AppShapes.pillRadius)),
            // One plain Text, not Text.rich, so a test can find the whole
            // phrase with a single textContaining match.
            child: Text(
              'Слова $position из $total',
              style: const TextStyle(fontSize: 13, color: AppColors.primaryDark, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
