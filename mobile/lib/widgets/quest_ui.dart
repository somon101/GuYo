import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../theme/app_colors.dart';

/// The building blocks of the Главная / «Квесты сезона» visual language.
///
/// Every piece the reference design repeats lives here exactly once -- the
/// white card, the progress bar, the reward badge, the round icon chip,
/// the stat column, the section header. A new screen or card in this part
/// of the app is assembled from these rather than restyled from scratch,
/// which is what keeps the section visually consistent as it grows.

/// The standard white content card: rounded, hairline border, the one
/// shared shadow.
class GuyoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color color;

  const GuyoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppShapes.cardRadius,
    this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: AppShapes.cardShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A soft violet rounded square holding one icon -- the shape in front of
/// every quest row and every stat in this section.
class RoundIconChip extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? background;
  final Color? iconColor;
  final List<Color>? gradient;

  const RoundIconChip({
    super.key,
    required this.icon,
    this.size = 44,
    this.background,
    this.iconColor,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradient;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors == null ? (background ?? AppColors.violetSurface) : null,
        gradient: colors == null ? null : LinearGradient(colors: colors),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: size * 0.46,
        color: colors == null ? (iconColor ?? AppColors.primary) : Colors.white,
      ),
    );
  }
}

/// "⭐ +20" -- a quest's rating reward.
class RewardBadge extends StatelessWidget {
  final int points;
  const RewardBadge({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.rewardBackground,
        borderRadius: BorderRadius.circular(AppShapes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: AppColors.rewardText),
          const SizedBox(width: 3),
          Text(
            '+$points',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.rewardText),
          ),
        ],
      ),
    );
  }
}

/// The one progress bar shape in this section: a rounded track with an
/// optional trailing label ("7 / 10", "60%").
class QuestProgressBar extends StatelessWidget {
  final int value;
  final int target;
  final String? label;
  final Color color;
  final double height;

  const QuestProgressBar({
    super.key,
    required this.value,
    required this.target,
    this.label,
    this.color = AppColors.primary,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    // A target of 0 would be a divide-by-zero AND a meaningless bar, so it
    // renders empty rather than full.
    final fraction = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: height,
              backgroundColor: AppColors.progressTrack,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 10),
          Text(
            label!,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondaryText),
          ),
        ],
      ],
    );
  }
}

/// One column of the three-up stats row: icon chip, a big value, a small
/// caption under it.
class StatColumn extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;

  const StatColumn({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoundIconChip(icon: icon, size: 40, iconColor: iconColor),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.secondaryText),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// The thin divider between two [StatColumn]s.
class StatDivider extends StatelessWidget {
  const StatDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 44, color: AppColors.cardBorder);
  }
}

/// "Ежедневные квесты        2 / 4" -- a section title with its own
/// counter pill on the right.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
        ),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.violetSurface,
              borderRadius: BorderRadius.circular(AppShapes.pillRadius),
            ),
            child: Text(
              trailing!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
      ],
    );
  }
}

/// The season's own picture, uploaded by an admin in the season settings.
/// Falls back to a generic shield when a season has no icon set -- never a
/// second, screen-owned image.
class SeasonIcon extends StatelessWidget {
  final String? iconUrl;
  final double size;

  const SeasonIcon({super.key, required this.iconUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = iconUrl;
    if (url == null || url.isEmpty) return _fallback();
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return CachedNetworkImage(
      imageUrl: ApiClient.instance.mediaUrl(url),
      width: size,
      height: size,
      // Contain, never cover: a badge artwork must not be cropped to a
      // square -- the same fix rank and achievement icons already carry.
      fit: BoxFit.contain,
      memCacheWidth: cacheSize,
      memCacheHeight: cacheSize,
      fadeInDuration: Duration.zero,
      placeholder: (_, _) => _fallback(),
      errorWidget: (_, _, _) => _fallback(),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C85F0), Color(0xFF4B54C9)],
        ),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(Icons.shield_rounded, size: size * 0.55, color: Colors.white.withValues(alpha: 0.92)),
    );
  }
}
