import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'guyo_ui.dart';
import 'remote_image.dart';

// The shared vocabulary comes along with this file, so a screen that needs
// both the season pieces and the plain cards imports one thing.
export 'guyo_ui.dart';

/// The season-specific pieces of the «Квесты сезона» design, built on top
/// of GuYo's shared UI vocabulary (widgets/guyo_ui.dart): the season's own
/// artwork, its plate, and the panel showing its stretch of time.

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
