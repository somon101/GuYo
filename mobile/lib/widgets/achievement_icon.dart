import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import 'rank_icon.dart';
import 'remote_image.dart';

/// One achievement's own uploaded icon -- never a substitute/generic image
/// -- shown at full brightness once earned, dimmed while locked/unearned
/// (including the hidden "mystery" state, which still uses the admin's
/// real icon, just darkened, per spec). Falls back to a generic badge only
/// when no icon was ever uploaded (or it fails to load), tinted by the
/// achievement's own color.
///
/// Shared by the Profile screen's compact achievement row, the full
/// "Достижения" screen, and the unlock celebration dialog, so all three
/// render an achievement identically. Cached to disk (same treatment as
/// avatars/rank icons) so a row of them never re-downloads on every view.
class AchievementIcon extends StatelessWidget {
  final UserAchievement achievement;
  final bool dimmed;
  final double size;
  const AchievementIcon({super.key, required this.achievement, required this.dimmed, required this.size});

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(achievement.color);
    final url = achievement.iconUrl;
    Widget child;
    if (url != null && url.isNotEmpty) {
      // contain, and deliberately NOT clipped to a circle -- see RankIcon's
      // own note: these badges have their own shape and transparent
      // background, and a circular crop cut their edges off. RemoteImage
      // is what keeps a non-square badge from being squeezed into the
      // square box on top of that.
      child = RemoteImage(
        url: url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        fallbackBuilder: () => _fallbackIcon(color),
      );
    } else {
      child = _fallbackIcon(color);
    }
    return Opacity(opacity: dimmed ? 0.35 : 1, child: child);
  }

  Widget _fallbackIcon(Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
      child: Icon(Icons.emoji_events_rounded, color: color, size: size * 0.55),
    );
  }
}
