import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// One selectable option in a "pick the right one" exercise -- Услышь
/// слово's word choices, and Quest's own single-target Сопоставление (see
/// that screen for why quest matching cannot share Lesson matching's
/// pair-board -- the backend hands it a different round shape entirely).
///
/// Turns green/red the moment a choice is locked in, exactly like every
/// other exercise's own reveal state, so "you picked X, X was right/wrong"
/// reads the same way everywhere it happens in the app.
class ChoiceTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isRevealed;
  final bool isCorrectOption;
  final VoidCallback? onTap;

  const ChoiceTile({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isRevealed,
    required this.isCorrectOption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color background = Colors.white;
    Color border = AppColors.cardBorder;
    Color textColor = AppColors.primaryDark;
    Widget? trailing;

    if (isRevealed) {
      if (isCorrectOption) {
        background = AppColors.successLight;
        border = AppColors.success;
        textColor = AppColors.success;
        trailing = const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20);
      } else if (isSelected) {
        background = AppColors.dangerLight;
        border = AppColors.danger;
        textColor = AppColors.danger;
        trailing = const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20);
      } else {
        textColor = AppColors.muted;
      }
    } else if (isSelected) {
      background = AppColors.violetSurface;
      border = AppColors.primary;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 1.4)),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor))),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
