import 'package:flutter/material.dart';

/// The blue "verified" checkmark a GuYo Premium user carries next to their
/// name, Instagram-style.
class PremiumCheck extends StatelessWidget {
  final double size;
  const PremiumCheck({super.key, this.size = 16});

  static const Color color = Color(0xFF1D9BF0);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'GuYo Premium',
      child: Icon(Icons.verified_rounded, size: size, color: color),
    );
  }
}

/// A user's name, followed by [PremiumCheck] when they have Premium.
///
/// The ONE way a name is shown anywhere in the app -- greeting, profile,
/// rating, and every future place -- so the checkmark can never be
/// forgotten on a new screen. Wherever a name comes from the backend, the
/// same payload carries whether that person is Premium (`is_premium` on
/// leaderboard rows, `premium_until` on the profile).
///
/// The name shrinks with an ellipsis; the checkmark always stays visible.
class UserNameText extends StatelessWidget {
  final String name;
  final bool isPremium;
  final TextStyle style;
  final TextAlign textAlign;

  const UserNameText(
    this.name, {
    super.key,
    required this.isPremium,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      style: style,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!isPremium) return text;
    final fontSize = style.fontSize ?? 14;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: textAlign == TextAlign.center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Flexible(child: text),
        SizedBox(width: fontSize * 0.25),
        PremiumCheck(size: fontSize * 1.05),
      ],
    );
  }
}
