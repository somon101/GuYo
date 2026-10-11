import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// GuYo's shared UI vocabulary: the handful of shapes every redesigned
/// screen is assembled from.
///
/// Each piece the design repeats lives here exactly once -- the white
/// card, the round icon chip, the reward badge, the progress bar, the stat
/// column, the section header. Главная, «Квесты сезона», «Практика» and
/// anything added next build out of these rather than restyling from
/// scratch, which is what keeps the app visually consistent as it grows.
///
/// Colours, radii and the one shared shadow come from
/// theme/app_colors.dart -- these widgets add shape and arrangement, never
/// a second palette.

/// The standard white content card: rounded, hairline border, the one
/// shared shadow.
class GuyoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? _color;

  /// The card's fill; the theme's surface unless given.
  Color get color => _color ?? AppColors.surface;

  const GuyoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppShapes.cardRadius,
    this.onTap,
    Color? color,
  }) : _color = color;

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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.questRewardGradient,
        ),
        borderRadius: BorderRadius.circular(AppShapes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: AppColors.gold),
          const SizedBox(width: 3),
          Text(
            '+$points',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
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
  final Color? _color;
  final double height;

  /// The fill; the primary colour unless given.
  Color get color => _color ?? AppColors.primary;

  QuestProgressBar({
    super.key,
    required this.value,
    required this.target,
    this.label,
    Color? color,
    this.height = 8,
  }) : _color = color;

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
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondaryText),
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
  final Color? _iconColor;

  /// The icon's colour; the primary colour unless given.
  Color get iconColor => _iconColor ?? AppColors.primary;

  StatColumn({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    Color? iconColor,
  }) : _iconColor = iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoundIconChip(icon: icon, size: 40, iconColor: iconColor),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
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
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
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
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
      ],
    );
  }
}

/// The one "nothing here yet" view every screen uses: a soft glowing icon,
/// a short bold line, one calm sentence on what unlocks it, and -- when
/// there is something to do about it -- a single pill button. Fades and
/// rises in gently, readable on both themes. Never a bare icon and grey
/// text again.
class GuyoEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const GuyoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [primary.withValues(alpha: 0.20), primary.withValues(alpha: 0.0)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      border: Border.all(color: primary.withValues(alpha: 0.18)),
                      boxShadow: [
                        BoxShadow(color: primary.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Icon(icon, size: 28, color: primary),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryDark, height: 1.25),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.secondaryText, height: 1.4),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
