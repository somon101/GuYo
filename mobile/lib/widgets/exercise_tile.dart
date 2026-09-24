import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'guyo_ui.dart';

/// One exercise as a compact, near-square tile, and the responsive grid
/// they sit in.
///
/// Part of GuYo's shared UI vocabulary (widgets/guyo_ui.dart), not a style
/// invented for one screen: the tile is a [GuyoCard] with a
/// [RoundIconChip], so it already matches Главная and «Квесты сезона», and
/// anywhere else that needs to offer a grid of things to launch should use
/// this rather than build its own.
///
/// Nothing here knows which exercises exist. A caller hands it whatever
/// list it has, so adding a new exercise type never touches this file or
/// the screen laying it out -- see exercises/practice_catalog.dart for how
/// «Практика» supplies its own.
class ExerciseTile extends StatelessWidget {
  final IconData icon;
  final String title;

  /// One line of context under the title, shown only if it fits. Optional
  /// on purpose: a tile stays readable with just an icon and a name.
  final String? description;

  final VoidCallback onTap;

  /// Tints the icon chip. Defaults to the shared violet used everywhere
  /// else; pass a colour only when a group of tiles needs telling apart.
  final Color? accentColor;

  const ExerciseTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.description,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.primary;
    return GuyoCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoundIconChip(
            icon: icon,
            size: 44,
            background: accent.withValues(alpha: 0.10),
            iconColor: accent,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            // Expanded, so whatever height is left after the icon and the
            // title is exactly what the description gets -- on a short
            // tile it simply clips instead of overflowing the card.
            Expanded(
              child: Text(
                description!,
                style: const TextStyle(fontSize: 11.5, color: AppColors.secondaryText, height: 1.3),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A grid of [ExerciseTile]s that decides its own column count from the
/// width it is given.
///
/// Sized by a maximum tile width rather than a fixed column count, so a
/// narrow phone gets two columns, a wide one or a tablet gets three or
/// more, and nothing has to be tuned per device. Non-scrolling by design:
/// it is meant to sit inside a screen's own list, next to whatever else
/// that screen shows.
class ExerciseGrid extends StatelessWidget {
  final List<Widget> tiles;

  /// The widest a single tile may get before another column is added.
  final double maxTileWidth;

  /// Height relative to width. Slightly taller than square so two lines of
  /// title still leave room for a line of description on small screens.
  final double aspectRatio;

  const ExerciseGrid({
    super.key,
    required this.tiles,
    this.maxTileWidth = 200,
    this.aspectRatio = 0.92,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: _columnsFor(MediaQuery.sizeOf(context).width),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: aspectRatio,
      children: tiles,
    );
  }

  /// Enough columns that no tile ends up wider than [maxTileWidth], and
  /// never fewer than two -- a tile that grows with the screen stops being
  /// compact, which is the whole point of the grid, and one column would
  /// just be the tall list this replaced.
  int _columnsFor(double screenWidth) {
    // The grid never gets the full screen -- its screen pads the sides --
    // so this only has to be close; rounding UP is what keeps a wide
    // screen from stretching three tiles instead of fitting four.
    final usable = screenWidth - 32;
    final columns = (usable / maxTileWidth).ceil();
    return columns.clamp(2, 4);
  }
}
