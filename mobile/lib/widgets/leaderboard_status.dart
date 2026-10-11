import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'remote_image.dart';

/// A leaderboard status emoji: GuYo's own picture (the same on every
/// phone, unlike a system emoji), on a small white disc so it reads on
/// any avatar.
class StatusEmojiBadge extends StatelessWidget {
  final String url;
  final double size;

  const StatusEmojiBadge({super.key, required this.url, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      // Keyed by the picture, so a rebuilt list can never show one
      // person's emoji on another's avatar.
      child: RemoteImage(key: ValueKey(url), url: url, width: size, height: size, fallbackBuilder: () => const SizedBox.shrink()),
    );
  }
}

/// [child] (an avatar) with the status emoji pinned to its bottom-right
/// corner -- the whole status, kept to the size of the avatar itself.
class AvatarWithStatus extends StatelessWidget {
  final Widget child;
  final String? emojiUrl;
  final double badgeSize;

  const AvatarWithStatus({super.key, required this.child, required this.emojiUrl, this.badgeSize = 20});

  @override
  Widget build(BuildContext context) {
    final url = emojiUrl;
    if (url == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(right: -badgeSize * 0.3, bottom: -badgeSize * 0.25, child: StatusEmojiBadge(url: url, size: badgeSize)),
      ],
    );
  }
}


/// A status phrase shown the way Instagram shows notes: a small rounded
/// bubble that is simply always there above the avatar -- nothing to tap.
/// Two little dots under it point at the avatar. Compact: small type, at
/// most two lines, a fixed maximum width.
class StatusNote extends StatelessWidget {
  final String text;
  final double maxWidth;
  final String? emojiUrl;
  final VoidCallback? onTap;

  const StatusNote({super.key, required this.text, this.maxWidth = 120, this.emojiUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Light theme: a white note lifted by a soft shadow. Dark theme: no
    // shadow (it reads as a glow there) -- the note is a step lighter than
    // the cards instead, so it still stands out cleanly.
    final dark = AppColors.dark;
    final bubbleColor = dark ? AppColors.violetSurface : AppColors.surface;
    final shadow = dark
        ? const <BoxShadow>[]
        : [BoxShadow(color: AppColors.primaryDark.withValues(alpha: 0.10), blurRadius: 10, offset: const Offset(0, 3))];
    Widget dot(double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bubbleColor, shape: BoxShape.circle, boxShadow: shadow),
        );
    final note = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
            border: dark ? null : Border.all(color: AppColors.cardBorder),
            boxShadow: shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emojiUrl != null) ...[
                RemoteImage(key: ValueKey(emojiUrl), url: emojiUrl!, width: 16, height: 16, fallbackBuilder: () => const SizedBox.shrink()),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.25, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                ),
              ),
            ],
          ),
        ),
        // The thought-bubble tail: two shrinking dots toward the avatar.
        Transform.translate(
          offset: const Offset(-8, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot(8),
              const SizedBox(height: 2),
              Padding(padding: const EdgeInsets.only(right: 8), child: dot(5)),
            ],
          ),
        ),
      ],
    );
    if (onTap == null) return note;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: note);
  }
}

