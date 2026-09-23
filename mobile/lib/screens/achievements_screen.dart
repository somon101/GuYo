import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/achievement_icon.dart';
import '../widgets/rank_icon.dart';

const List<String> _russianMonthsGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/// "Получено 21 сентября 2026" -- from `earnedAt`, which the backend always
/// sends as a server timestamp (see UserAchievement.earned_at), never the
/// phone's own clock.
String _formatEarnedDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_russianMonthsGenitive[local.month - 1]} ${local.year}';
}

/// The full "Достижения" list, opened from the Profile screen's compact
/// achievement row. Renders exactly what the backend already decided (see
/// GET /users/me/achievements): earned status, the withheld title/condition
/// of a still-hidden one, and current progress towards each unearned one --
/// this screen computes none of that itself, it's handed the same list the
/// Profile screen already loaded.
class AchievementsScreen extends StatelessWidget {
  final List<UserAchievement> achievements;
  const AchievementsScreen({super.key, required this.achievements});

  @override
  Widget build(BuildContext context) {
    final earnedCount = achievements.where((a) => a.earned).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Достижения')),
      body: SafeArea(
        child: achievements.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Пока нет доступных достижений', style: TextStyle(color: AppColors.secondaryText)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  Text(
                    'Получено $earnedCount из ${achievements.length}',
                    style: const TextStyle(fontSize: 14, color: AppColors.secondaryText, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  for (final achievement in achievements) _AchievementTile(achievement: achievement),
                ],
              ),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final UserAchievement achievement;
  const _AchievementTile({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final earned = achievement.earned;
    final locked = achievement.isLocked;
    final color = parseHexColor(achievement.color);
    final title = locked ? 'Скрытое достижение' : achievement.title!;
    final description = locked ? 'Условие неизвестно' : achievement.description!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: earned ? color.withValues(alpha: 0.07) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: earned ? color.withValues(alpha: 0.3) : const Color(0xFFEDEFF7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          AchievementIcon(achievement: achievement, dimmed: !earned, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: earned ? AppColors.primaryDark : AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(fontSize: 13, color: AppColors.secondaryText)),
                if (earned && achievement.earnedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Получено ${_formatEarnedDate(achievement.earnedAt!)}',
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
                  ),
                ],
                if (!earned && !locked) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: achievement.conditionValue == 0
                          ? 0
                          : (achievement.currentValue! / achievement.conditionValue!).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: const Color(0xFFEDEFF7),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${achievement.currentValue} / ${achievement.conditionValue}',
                    style: const TextStyle(fontSize: 11, color: AppColors.secondaryText, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          if (earned)
            Icon(Icons.check_circle, color: color, size: 22)
          else
            const Icon(Icons.lock_outline, color: Color(0xFFB9BEDA), size: 20),
        ],
      ),
    );
  }
}
