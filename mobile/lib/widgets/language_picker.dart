import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';

/// The three interface languages as a row of chips. [onSelected] gets the
/// picked code; the caller applies it (the app root then rebuilds).
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.selected, required this.onSelected, this.enabled = true});

  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        for (final lang in uiLanguages)
          ChoiceChip(
            label: Text(lang.label),
            selected: lang.code == selected,
            onSelected: !enabled || lang.code == selected ? null : (_) => onSelected(lang.code),
            selectedColor: AppColors.violetSurface,
            labelStyle: TextStyle(
              fontWeight: lang.code == selected ? FontWeight.w700 : FontWeight.w500,
              color: lang.code == selected ? AppColors.primary : AppColors.secondaryText,
            ),
          ),
      ],
    );
  }
}
