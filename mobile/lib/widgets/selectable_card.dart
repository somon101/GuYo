import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// One selectable card: a hairline border that turns into GuYo's primary
/// indigo, plus a filled check, when chosen.
class SelectableCard extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SelectableCard({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.violetSurface : Colors.white,
      borderRadius: BorderRadius.circular(AppShapes.rowRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.rowRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppShapes.rowRadius),
            border: Border.all(color: selected ? AppColors.primary : AppColors.cardBorder, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? AppColors.primary : AppColors.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
