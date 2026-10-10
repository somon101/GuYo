import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/achievement_icon.dart';
import '../widgets/rank_icon.dart';

List<String> get _russianMonthsGenitive => [
  tr('января'), tr('февраля'), tr('марта'), tr('апреля'), tr('мая'), tr('июня'),
  tr('июля'), tr('августа'), tr('сентября'), tr('октября'), tr('ноября'), tr('декабря'),
];

/// "21 сентября 2026" -- from `earnedAt`, which the backend always sends as
/// a server timestamp (see UserAchievement.earned_at), never the phone's
/// own clock.
String _formatEarnedDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_russianMonthsGenitive[local.month - 1]} ${local.year}';
}

/// The full "Достижения" list, opened from the Profile screen's compact
/// achievement row: a badge wall, three per row, each badge with its goal
/// in a small coin on its lower edge. Tapping one opens its details (the
/// date it was earned, or progress towards it). Renders exactly what the
/// backend already decided (GET /users/me/achievements) -- it is handed the
/// same list the Profile screen already loaded and computes nothing itself.
/// Same order as Admin Web's groups (backend CONDITION_TYPES).
const List<String> _typeOrder = ['phrases_opened', 'words_learned', 'lessons_completed', 'streak_days'];

/// Earned first, then not yet earned, hidden last; within each, grouped by
/// type and then climbing by goal, so a chain reads like steps.
List<UserAchievement> sortAchievements(List<UserAchievement> list) {
  int typeRank(UserAchievement a) {
    final i = _typeOrder.indexOf(a.conditionType ?? '');
    return i == -1 ? _typeOrder.length : i;
  }

  int group(UserAchievement a) => a.earned ? 0 : (a.isLocked ? 2 : 1);

  return [...list]..sort((a, b) {
      final byGroup = group(a).compareTo(group(b));
      if (byGroup != 0) return byGroup;
      final byType = typeRank(a).compareTo(typeRank(b));
      if (byType != 0) return byType;
      final byGoal = (a.conditionValue ?? 0).compareTo(b.conditionValue ?? 0);
      return byGoal != 0 ? byGoal : a.id.compareTo(b.id);
    });
}

class AchievementsScreen extends StatelessWidget {
  final List<UserAchievement> achievements;
  AchievementsScreen({super.key, required List<UserAchievement> achievements})
      : achievements = sortAchievements(achievements);

  @override
  Widget build(BuildContext context) {
    final earnedCount = achievements.where((a) => a.earned).length;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          tr('Достижения'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: IconThemeData(color: AppColors.primaryDark),
      ),
      body: SafeArea(
        child: achievements.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(tr('Пока нет доступных достижений'), style: TextStyle(color: AppColors.secondaryText)),
                ),
              )
            : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    sliver: SliverToBoxAdapter(child: _Summary(earned: earnedCount, total: achievements.length)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 8,
                        mainAxisExtent: 196,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _Badge(achievement: achievements[i]),
                        childCount: achievements.length,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final int earned;
  final int total;
  const _Summary({required this.earned, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Получено {0} из {1}', [earned, total]),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : earned / total,
              minHeight: 8,
              backgroundColor: AppColors.progressTrack,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// One badge in the wall: the icon with its goal coin, then the title and
/// the condition, centered.
class _Badge extends StatelessWidget {
  final UserAchievement achievement;
  const _Badge({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final earned = achievement.earned;
    final locked = achievement.isLocked;
    final title = locked ? tr('Скрытое') : achievement.title!;
    final description = locked ? tr('Условие откроется позже') : achievement.description!;

    return InkWell(
      key: ValueKey('achievement-${achievement.id}'),
      borderRadius: BorderRadius.circular(AppShapes.rowRadius),
      onTap: () => _showDetails(context, achievement),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          children: [
            _BadgeArt(achievement: achievement, size: 84),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: earned ? AppColors.primaryDark : AppColors.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, height: 1.25, color: AppColors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

/// The icon on a soft circle, with the goal coin overlapping its lower
/// edge: gold once earned, grey before.
class _BadgeArt extends StatelessWidget {
  final UserAchievement achievement;
  final double size;
  const _BadgeArt({required this.achievement, required this.size});

  @override
  Widget build(BuildContext context) {
    final earned = achievement.earned;
    final color = parseHexColor(achievement.color);
    final goal = achievement.isLocked ? '?' : '${achievement.conditionValue ?? ''}';
    final coin = size * 0.3;

    return SizedBox(
      width: size,
      height: size + coin * 0.35,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: earned
                  ? RadialGradient(colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.06)])
                  : null,
              color: earned ? null : AppColors.progressTrack.withValues(alpha: 0.6),
            ),
            alignment: Alignment.center,
            child: AchievementIcon(achievement: achievement, dimmed: !earned, size: size * 0.78),
          ),
          if (goal.isNotEmpty)
            Positioned(
              top: size - coin * 0.65,
              child: Container(
                constraints: BoxConstraints(minWidth: coin, minHeight: coin),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: earned ? AppColors.gold : const Color(0xFFE4E7F0),
                  borderRadius: BorderRadius.circular(coin),
                  border: Border.all(color: AppColors.surface, width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1)),
                  ],
                ),
                child: Text(
                  goal,
                  style: TextStyle(
                    fontSize: coin * 0.45,
                    fontWeight: FontWeight.w800,
                    color: earned ? AppColors.pointsOnSurface : AppColors.secondaryText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _showDetails(BuildContext context, UserAchievement achievement) {
  final earned = achievement.earned;
  final locked = achievement.isLocked;
  final color = parseHexColor(achievement.color);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppShapes.bannerRadius))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BadgeArt(achievement: achievement, size: 120),
            const SizedBox(height: 16),
            Text(
              locked ? tr('Скрытое достижение') : achievement.title!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 6),
            Text(
              locked ? tr('Условие откроется, когда вы получите это достижение') : achievement.description!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 18),
            if (earned && achievement.earnedAt != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppShapes.pillRadius),
                ),
                child: Text(
                  tr('Получено {0}', [_formatEarnedDate(achievement.earnedAt!)]),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
              )
            else if (!earned && !locked) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (achievement.conditionValue ?? 0) == 0
                      ? 0
                      : ((achievement.currentValue ?? 0) / achievement.conditionValue!).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.progressTrack,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('{0} из {1}', [achievement.currentValue ?? 0, achievement.conditionValue]),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondaryText),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
