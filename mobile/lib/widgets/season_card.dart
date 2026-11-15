import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/quest.dart';
import '../theme/app_colors.dart';
import 'quest_ui.dart';

/// The season in ONE light card: the season's shield and name and the days left. The numbers of
/// the day are SeasonFigures under it («Квесты» screen); on Главная the two weekly tasks stand under it.
class SeasonCard extends StatelessWidget {
  final SeasonQuestOverview overview;

  /// The big header of the «Квесты» screen (bigger shield, a line about what the quests are for).
  final bool large;

  /// Header tap (on Главная it opens the quests); null when the card is already the quests screen.
  final VoidCallback? onOpenHeader;

  const SeasonCard({
    super.key,
    required this.overview,
    this.large = false,
    this.onOpenHeader,
  });

  @override
  Widget build(BuildContext context) {
    final season = overview.season;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(26)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          key: const ValueKey('season-header'),
          borderRadius: BorderRadius.circular(16),
          onTap: onOpenHeader,
          child: Row(children: [
            SeasonIconPlate(iconUrl: season?.iconUrl, iconSize: large ? 56 : 46, padding: EdgeInsets.all(large ? 9 : 7)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(tr('Квесты сезона'), style: TextStyle(fontSize: large ? 20 : 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.primaryDark)),
                const SizedBox(height: 2),
                Text(
                  large && season != null ? tr('Выполняй задания, получай очки и повышай свой ранг.') : seasonLine(overview),
                  style: TextStyle(fontSize: 12.5, height: 1.3, color: AppColors.secondaryText),
                  maxLines: large ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            if (onOpenHeader != null) Icon(Icons.chevron_right, color: AppColors.primary),
          ]),
        ),
        const SizedBox(height: 12),
        if (season != null)
          SeasonTimeline(startsAt: season.startsAt, endsAt: season.endsAt, daysLeft: overview.daysLeft, daysTotal: overview.daysTotal, compact: true, plain: true),
      ]),
    );
  }
}

/// The season's own name, or an honest note when none is running.
String seasonLine(SeasonQuestOverview overview) {
  final season = overview.season;
  if (season == null) return tr('Сейчас нет активного сезона');
  return season.name;
}

/// The day's figures on the «Квесты» screen: the points of today as the one big number, the place
/// in the rating and the tasks done beside it, small and quiet.
class SeasonFigures extends StatelessWidget {
  final SeasonQuestOverview overview;
  final VoidCallback? onOpenPoints;
  const SeasonFigures({super.key, required this.overview, this.onOpenPoints});

  Widget _small(String key, String label, String value) => Expanded(
        child: Container(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: AppColors.secondaryText), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Row(children: [
        Expanded(
          flex: 13,
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              key: const ValueKey('stat-points-today'),
              borderRadius: BorderRadius.circular(20),
              onTap: onOpenPoints,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(tr('очков сегодня'), style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                  const SizedBox(height: 2),
                  Text('+${overview.pointsToday}', style: TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.primary)),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 10,
          child: Column(children: [
            _small('stat-rank', tr('место'), overview.rankPosition == null ? '—' : '#${overview.rankPosition}'),
            const SizedBox(height: 8),
            _small('stat-quests', tr('заданий'), '${overview.questsDoneToday}/${overview.questsTotal}'),
          ]),
        ),
      ]),
    );
  }
}
