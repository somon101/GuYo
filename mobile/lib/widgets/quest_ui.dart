import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'remote_image.dart';

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

/// "24 дня осталось" with the right Russian plural for the number.
String daysLeftLabel(int days) {
  if (days <= 0) return 'Завершается';
  final mod100 = days % 100;
  final String word;
  if (mod100 >= 11 && mod100 <= 14) {
    word = 'дней';
  } else {
    switch (days % 10) {
      case 1:
        word = 'день';
      case 2:
      case 3:
      case 4:
        word = 'дня';
      default:
        word = 'дней';
    }
  }
  return '$days $word осталось';
}

/// "18 сент." -- short enough to sit at either end of the season range
/// without wrapping. Written out rather than pulled in through a
/// localization package: this is the only place the app formats a date,
/// and the app is Russian-only.
String shortDate(DateTime date) {
  const months = [
    'янв.', 'февр.', 'марта', 'апр.', 'мая', 'июня',
    'июля', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

/// The season's own stretch of time: when it started, when it ends, and
/// how much of it is gone.
///
/// Deliberately its OWN panel on a plain surface rather than a bar drawn
/// straight onto the banner's gradient -- the banner is atmosphere, this
/// is data, and the two were reading as one blurred thing. It is also
/// deliberately not the same bar as quest progress: days elapsed and
/// quests completed are different measures and must never be mistaken for
/// each other.
///
/// Shows nothing at all for a season with no scheduled end: there is no
/// range to draw, and inventing one would be a lie.
class SeasonTimeline extends StatelessWidget {
  final DateTime startsAt;
  final DateTime? endsAt;

  /// Both already rounded by the backend -- see SeasonQuestOverview.
  final int? daysLeft;
  final int? daysTotal;

  /// The tighter variant used inside the season block on Главная.
  final bool compact;

  const SeasonTimeline({
    super.key,
    required this.startsAt,
    required this.endsAt,
    required this.daysLeft,
    required this.daysTotal,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final left = daysLeft;
    final total = daysTotal;
    final end = endsAt;
    if (left == null || total == null || end == null) {
      return _OpenEndedNote(compact: compact);
    }
    final elapsed = (total - left).clamp(0, total);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14, vertical: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.rowRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  daysLeftLabel(left),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          QuestProgressBar(value: elapsed, target: total, height: 6),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(shortDate(startsAt), style: _rangeStyle),
              Text(shortDate(end), style: _rangeStyle),
            ],
          ),
        ],
      ),
    );
  }

  static const TextStyle _rangeStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.secondaryText,
  );
}

class _OpenEndedNote extends StatelessWidget {
  final bool compact;
  const _OpenEndedNote({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14, vertical: compact ? 9 : 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.rowRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 15, color: AppColors.secondaryText),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Без срока окончания',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The season artwork on its own clean plate.
///
/// The artworks are busy, full-colour badges and the banner behind them is
/// a soft violet wash; sitting one directly on the other made both harder
/// to read. A plain white rounded plate gives the picture a defined edge
/// and its own quiet ground, which is what separates the layers.
class SeasonIconPlate extends StatelessWidget {
  final String? iconUrl;
  final double iconSize;
  final EdgeInsets padding;

  const SeasonIconPlate({
    super.key,
    required this.iconUrl,
    required this.iconSize,
    this.padding = const EdgeInsets.all(10),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: SeasonIcon(iconUrl: iconUrl, size: iconSize),
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
    return RemoteImage(
      url: url,
      width: size,
      height: size,
      // Contain, never cover: a season artwork must not be cropped to a
      // square -- and RemoteImage is what stops it being squeezed into one
      // during the decode, the same fix rank and achievement icons carry.
      fit: BoxFit.contain,
      fallbackBuilder: _fallback,
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
