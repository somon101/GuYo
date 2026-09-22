import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user_rating.dart';

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
      return ClipOval(
        child: Image.network(
          ApiClient.instance.mediaUrl(url),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(),
        ),
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
