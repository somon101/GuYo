import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_colors.dart';

/// Every role has ONE colour, the same in every mini-phrase, so a learner
/// soon reads "violet = кто, orange = действие" at a glance. Both themes
/// have their own, equally readable value.
Color miniPhraseRoleColor(String? role) {
  final dark = AppColors.dark;
  switch (role) {
    case 'pronoun':
      return dark ? const Color(0xFFA996FF) : const Color(0xFF6B4EE6);
    case 'verb':
      return dark ? const Color(0xFFFFB35C) : const Color(0xFFD9730D);
    case 'noun':
      return dark ? const Color(0xFF4FD6C4) : const Color(0xFF0E9384);
    case 'adjective':
      return dark ? const Color(0xFFF48FC4) : const Color(0xFFC93B83);
    case 'adverb':
      return dark ? const Color(0xFF7FB0FF) : const Color(0xFF2F6FDB);
    default:
      return AppColors.secondaryText;
  }
}

/// The short question a role answers, shown under a part.
String? miniPhraseRoleLabel(String? role) {
  switch (role) {
    case 'pronoun':
      return tr('кто');
    case 'verb':
      return tr('действие');
    case 'noun':
      return tr('что');
    case 'adjective':
      return tr('какой');
    case 'adverb':
      return tr('как');
    default:
      return null;
  }
}

/// A part of a mini-phrase as a soft, role-coloured pill, with the word's
/// translation (and the role's question) underneath.
class MiniPhrasePartChip extends StatelessWidget {
  final String text;
  final String? role;
  final String? caption;
  final bool large;

  const MiniPhrasePartChip({super.key, required this.text, this.role, this.caption, this.large = false});

  @override
  Widget build(BuildContext context) {
    final color = miniPhraseRoleColor(role);
    final label = miniPhraseRoleLabel(role);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: large ? 16 : 12, vertical: large ? 10 : 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: AppColors.dark ? 0.20 : 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Text(
            text,
            style: TextStyle(fontSize: large ? 20 : 17, fontWeight: FontWeight.w800, color: color),
          ),
        ),
        if (caption != null || label != null) ...[
          const SizedBox(height: 4),
          Text(
            [if (caption != null && caption!.isNotEmpty) caption!, if (label != null) label].join(' · '),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
          ),
        ],
      ],
    );
  }
}

/// Fades and lifts its child in after [delay] -- the parts of a phrase
/// arrive one after another instead of all at once.
class MiniPhraseAppear extends StatelessWidget {
  final Duration delay;
  final Widget child;
  const MiniPhraseAppear({super.key, this.delay = Duration.zero, required this.child});

  @override
  Widget build(BuildContext context) {
    final total = delay + const Duration(milliseconds: 360);
    final start = total.inMilliseconds == 0 ? 0.0 : delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (context, t, child) {
        final v = Curves.easeOutCubic.transform(((t - start) / (1 - start)).clamp(0.0, 1.0));
        return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child));
      },
      child: child,
    );
  }
}
