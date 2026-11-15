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
        for (final lang in availableUiLanguages)
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

/// The interface language as a small chip for a screen's corner: the language's code in a tinted
/// badge and a chevron; a tap opens the list of languages. [onSelected] gets the picked code.
class LanguageChip extends StatelessWidget {
  const LanguageChip({super.key, required this.selected, required this.onSelected, this.enabled = true});

  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  Widget _badge(String code, {bool on = true}) => Container(
        width: 26,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: on ? AppColors.primary : AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
        child: Text(code.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: on ? Colors.white : AppColors.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final languages = availableUiLanguages;
    return PopupMenuButton<String>(
      key: const ValueKey('ui-language-chip'),
      tooltip: tr('Выбрать язык'),
      enabled: enabled,
      onSelected: onSelected,
      offset: const Offset(0, 40),
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (_) => [
        for (final l in languages)
          PopupMenuItem<String>(
            value: l.code,
            height: 46,
            child: Row(children: [
              _badge(l.code, on: l.code == selected),
              const SizedBox(width: 12),
              Text(l.label, style: TextStyle(fontSize: 15, fontWeight: l.code == selected ? FontWeight.w700 : FontWeight.w500, color: AppColors.primaryDark)),
            ]),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.separator)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _badge(selected),
          const SizedBox(width: 2),
          Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.secondaryText),
        ]),
      ),
    );
  }
}
