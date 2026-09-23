import 'package:cached_network_image/cached_network_image.dart';
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
      // CachedNetworkImage persists the decoded file to disk the first time
      // it loads, so the SAME rank icon (only 7 ranks exist, reused across
      // every leaderboard row and every screen) renders instantly on every
      // later view -- a cold app restart included -- instead of every row
      // in a long leaderboard list re-fetching it over the network and
      // showing a brief empty circle first, same fix already applied to
      // UserAvatar.
      final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: ApiClient.instance.mediaUrl(url),
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          fadeInDuration: Duration.zero,
          placeholder: (_, _) => _fallback(),
          errorWidget: (_, _, _) => _fallback(),
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
