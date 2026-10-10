import '../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// "↑3" in green or "↓2" in red: how many places someone moved within
/// their rank in their latest move. The backend decides the number and
/// how long it stays visible (app/rating/movement.py); a null or zero
/// change draws nothing.
class PositionChangeBadge extends StatelessWidget {
  final int? change;

  /// Size of the number; the arrow scales with it.
  final double fontSize;

  /// Adds a white ring, for sitting on top of an avatar.
  final bool outlined;

  const PositionChangeBadge({super.key, required this.change, this.fontSize = 11, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final value = change;
    if (value == null || value == 0) return const SizedBox.shrink();
    final up = value > 0;
    final color = up ? AppColors.success : AppColors.danger;
    return Semantics(
      label: up ? tr('Поднялся на {0}', [value]) : tr('Опустился на {0}', [-value]),
      child: Container(
        padding: EdgeInsets.fromLTRB(fontSize * 0.25, fontSize * 0.1, fontSize * 0.55, fontSize * 0.1),
        decoration: BoxDecoration(
          color: outlined ? color : (up ? AppColors.successLight : AppColors.dangerLight),
          borderRadius: BorderRadius.circular(AppShapes.pillRadius),
          border: outlined ? Border.all(color: AppColors.surface, width: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
              size: fontSize * 1.7,
              color: outlined ? Colors.white : color,
            ),
            Text(
              '${value.abs()}',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: outlined ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
