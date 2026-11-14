import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/quest.dart';
import '../theme/app_colors.dart';
import 'game_icons.dart';
import 'quest_ui.dart';

/// The season in ONE light card (Главная and the «Квесты» screen): the season's shield and name,
/// the days left, the three numbers (points today, place, tasks done) and the quest of the day.
/// Nothing lies inside another card; the parts are separated by thin lines.
class SeasonCard extends StatelessWidget {
  final SeasonQuestOverview overview;

  /// The big header of the «Квесты» screen (bigger shield, a line about what the quests are for).
  final bool large;

  /// Header tap (on Главная it opens the quests); null when the card is already the quests screen.
  final VoidCallback? onOpenHeader;
  final VoidCallback? onOpenPoints;
  final VoidCallback? onOpenRating;
  final VoidCallback? onOpenQuests;
  final VoidCallback onQuestOfDay;

  const SeasonCard({
    super.key,
    required this.overview,
    required this.onQuestOfDay,
    this.large = false,
    this.onOpenHeader,
    this.onOpenPoints,
    this.onOpenRating,
    this.onOpenQuests,
  });

  Widget _stat(String key, VoidCallback? onTap, Widget child) => Expanded(
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child),
        ),
      );

  Widget get _line => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: AppColors.cardBorder));

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
        _line,
        IntrinsicHeight(
          child: Row(children: [
            _stat(
              'stat-points-today',
              onOpenPoints,
              StatColumn(icon: Icons.star_rounded, leading: const PointsIcon(size: 36), value: '+${overview.pointsToday}', label: tr('очков сегодня'), iconColor: AppColors.gold),
            ),
            _stat(
              'stat-rank',
              onOpenRating,
              StatColumn(icon: Icons.emoji_events_rounded, value: overview.rankPosition == null ? '—' : '#${overview.rankPosition}', label: tr('место в рейтинге')),
            ),
            _stat(
              'stat-quests',
              onOpenQuests,
              StatColumn(icon: Icons.check_box_rounded, value: '${overview.questsDoneToday}/${overview.questsTotal}', label: tr('заданий выполнено'), iconColor: AppColors.success),
            ),
          ]),
        ),
        _line,
        _QuestOfDayRow(pointsPerLearnedWord: overview.pointsPerLearnedWord, wordsLearnedToday: overview.wordsLearnedToday, onTap: onQuestOfDay),
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

/// «Квест дня» as a plain row inside the season card.
class _QuestOfDayRow extends StatelessWidget {
  final int pointsPerLearnedWord;
  final int wordsLearnedToday;
  final VoidCallback onTap;
  const _QuestOfDayRow({required this.pointsPerLearnedWord, required this.wordsLearnedToday, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('quest-of-day'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Row(children: [
        RoundIconChip(icon: Icons.local_fire_department_rounded, size: 44, gradient: AppColors.dailyQuestGradient),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Квест дня'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
            const SizedBox(height: 2),
            Text(tr('Изучай новые слова'), style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              wordsLearnedToday == 0 ? tr('Сегодня пока ни одного') : tr('Сегодня изучено: {0}', [wordsLearnedToday]),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        RewardBadge(points: pointsPerLearnedWord),
      ]),
    );
  }
}
