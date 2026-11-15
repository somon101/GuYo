import '../l10n/l10n.dart';
import '../widgets/guyo_ui.dart';
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

/// The full "Достижения" screen, opened from the Profile screen's compact
/// achievement row: one chain of steps per kind (10 → 100 → 300 ...), a line filling up to what has
/// been reached. Tapping a step opens its details (the date it was earned, or progress towards it). Renders exactly what the
/// backend already decided (GET /users/me/achievements) -- it is handed the
/// same list the Profile screen already loaded and computes nothing itself.
/// Same order as Admin Web's groups (backend CONDITION_TYPES).
const List<String> _typeOrder = ['phrases_opened', 'words_learned', 'mini_phrases_done', 'lessons_completed', 'streak_days'];

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
    final groups = groupAchievements(achievements);
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
            ? GuyoEmptyState(
                icon: Icons.emoji_events_outlined,
                title: tr('Пока нет доступных достижений'),
                message: tr('Скоро здесь появятся награды за ваши успехи.'),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _Summary(earned: earnedCount, total: achievements.length),
                  for (final g in groups) ...[
                    const SizedBox(height: 18),
                    _GroupHeader(group: g),
                    const SizedBox(height: 8),
                    _Chain(group: g),
                  ],
                ],
              ),
      ),
    );
  }
}

/// The achievements of one kind (words, lessons, streak ...), climbing by goal. Hidden ones, whose
/// kind is not shown yet, make the last group.
class AchievementGroup {
  final String? type;
  final List<UserAchievement> items;
  const AchievementGroup(this.type, this.items);

  /// What the player has reached in this kind: the furthest goal got, or the current value.
  int get reached {
    var best = 0;
    for (final a in items) {
      final v = a.earned ? (a.conditionValue ?? 0) : (a.currentValue ?? 0);
      if (v > best) best = v;
    }
    return best;
  }

  int get target => items.fold<int>(0, (m, a) => (a.conditionValue ?? 0) > m ? (a.conditionValue ?? 0) : m);
}

List<AchievementGroup> groupAchievements(List<UserAchievement> list) {
  final byType = <String?, List<UserAchievement>>{};
  for (final a in list) {
    byType.putIfAbsent(a.isLocked ? null : a.conditionType, () => []).add(a);
  }
  int rank(String? t) {
    if (t == null) return _typeOrder.length + 1;
    final i = _typeOrder.indexOf(t);
    return i == -1 ? _typeOrder.length : i;
  }

  final types = byType.keys.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  return [
    for (final t in types)
      AchievementGroup(t, [...byType[t]!]..sort((a, b) => (a.conditionValue ?? 0).compareTo(b.conditionValue ?? 0))),
  ];
}

String _groupTitle(String? type) => switch (type) {
      'words_learned' => tr('Слова'),
      'phrases_opened' => tr('Фразы'),
      'mini_phrases_done' => tr('Мини-фразы'),
      'lessons_completed' => tr('Уроки'),
      'streak_days' => tr('Серия'),
      null => tr('Скрытые'),
      _ => tr('Другое'),
    };

String _unit(String? type) => switch (type) {
      'words_learned' => tr('слов'),
      'phrases_opened' => tr('фраз'),
      'mini_phrases_done' => tr('мини-фраз'),
      'lessons_completed' => tr('уроков'),
      'streak_days' => tr('дней'),
      _ => '',
    };

class _Summary extends StatelessWidget {
  final int earned;
  final int total;
  const _Summary({required this.earned, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
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
              minHeight: 6,
              backgroundColor: AppColors.progressTrack,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final AchievementGroup group;
  const _GroupHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(_groupTitle(group.type), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        ),
        if (group.type != null && group.target > 0)
          Text(
            tr('{0} из {1}', [group.reached, group.target]),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
          ),
      ],
    );
  }
}

/// One kind as a chain of steps: the icons on a line that fills up to what has been reached.
class _Chain extends StatelessWidget {
  static const double _step = 76;
  final AchievementGroup group;
  const _Chain({required this.group});

  /// 0..1 along the line: through the got steps and part of the way to the next one.
  double get _fill {
    final items = group.items;
    final got = items.where((a) => a.earned).length;
    if (got == 0 || items.length < 2) return 0;
    if (got >= items.length) return 1;
    final prev = items[got - 1].conditionValue ?? 0;
    final next = items[got].conditionValue ?? 0;
    final part = next > prev ? ((group.reached - prev) / (next - prev)).clamp(0.0, 1.0) : 0.0;
    return ((got - 1) + part) / (items.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final items = group.items;
    final width = items.length * _step;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: width,
          child: Stack(children: [
            Positioned(
              left: _step / 2,
              right: _step / 2,
              top: 21,
              child: Stack(children: [
                Container(height: 3, decoration: BoxDecoration(color: AppColors.progressTrack, borderRadius: BorderRadius.circular(3))),
                FractionallySizedBox(
                  widthFactor: _fill,
                  child: Container(height: 3, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(3))),
                ),
              ]),
            ),
            Row(children: [for (final a in items) SizedBox(width: _step, child: _Step(achievement: a, type: group.type))]),
          ]),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final UserAchievement achievement;
  final String? type;
  const _Step({required this.achievement, required this.type});

  @override
  Widget build(BuildContext context) {
    final earned = achievement.earned;
    final locked = achievement.isLocked;
    final color = parseHexColor(achievement.color);
    final goal = locked ? '?' : '${achievement.conditionValue ?? ''}';
    return InkWell(
      key: ValueKey('achievement-${achievement.id}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showDetails(context, achievement),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _StepIcon(achievement: achievement, size: 44, color: color, earned: earned),
          const SizedBox(height: 6),
          Text(
            goal,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: earned ? AppColors.primaryDark : AppColors.secondaryText),
          ),
          if (!locked && _unit(type).isNotEmpty)
            Text(_unit(type), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText)),
        ]),
      ),
    );
  }
}

/// The step's icon on a round tint; a small tick marks a got one. The tint ring in the card's own
/// colour keeps the line from showing through.
class _StepIcon extends StatelessWidget {
  final UserAchievement achievement;
  final double size;
  final Color color;
  final bool earned;
  const _StepIcon({required this.achievement, required this.size, required this.color, required this.earned});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: earned ? Color.alphaBlend(color.withValues(alpha: 0.18), AppColors.surface) : Color.alphaBlend(AppColors.progressTrack, AppColors.surface),
            border: Border.all(color: AppColors.surface, width: 4),
          ),
          alignment: Alignment.center,
          child: AchievementIcon(achievement: achievement, dimmed: !earned, size: size * 0.72),
        ),
        if (earned)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 2)),
              child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
            ),
          ),
      ]),
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
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepIcon(achievement: achievement, size: 76, color: color, earned: earned),
            const SizedBox(height: 14),
            Text(
              locked ? tr('Скрытое достижение') : achievement.title!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 4),
            Text(
              locked ? tr('Условие откроется, когда вы получите это достижение') : achievement.description!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 14),
            if (earned && achievement.earnedAt != null)
              Text(
                tr('Получено {0}', [_formatEarnedDate(achievement.earnedAt!)]),
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.success),
              )
            else if (!earned && !locked) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (achievement.conditionValue ?? 0) == 0
                      ? 0
                      : ((achievement.currentValue ?? 0) / achievement.conditionValue!).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: AppColors.progressTrack,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('{0} из {1}', [achievement.currentValue ?? 0, achievement.conditionValue]),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondaryText),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.violetSurface,
                  foregroundColor: AppColors.primaryDark,
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr('Закрыть'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
