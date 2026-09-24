import 'package:flutter/material.dart';
import '../models/user_rating.dart';
import 'remote_image.dart';

/// "#RRGGBB" -> Color -- the one place every rank/achievement color string
/// from the backend gets parsed, shared so it's never redefined per screen.
Color parseHexColor(String hex) {
  var value = hex.replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  return Color(int.parse(value, radix: 16));
}

/// One rank's own uploaded icon (never emoji/a system icon) -- falls back
/// to a generic badge, tinted by the rank's own color, when there's no
/// icon or it fails to load. Shared by the Profile screen's own "Рейтинг"
/// block and the dedicated "Рейтинг" tab's leaderboards, so both render a
/// rank identically.
class RankIcon extends StatelessWidget {
  final RankSummary? rank;
  final Color color;
  final double size;
  const RankIcon({super.key, required this.rank, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = rank?.iconUrl;
    if (url != null && url.isNotEmpty) {
      // Through RemoteImage, which disk-caches these (only 7 ranks exist,
      // reused across every leaderboard row and every screen) and decodes
      // them without deforming: rank artworks are wide shields, roughly
      // 1450x830, and forcing that into a square decode crushed them --
      // see RemoteImage's own note.
      //
      // contain, and deliberately NOT clipped to a circle: these badges
      // have their own transparent background and their own shape, and a
      // circular crop cut the crests, wings and laurels right off.
      return RemoteImage(
        url: url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        fallbackBuilder: _fallback,
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
      child: Icon(Icons.military_tech_rounded, color: color, size: size * 0.55),
    );
  }
}
