import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/achievement_icon.dart';
import '../widgets/rank_icon.dart';

/// Takes the achievements this account has earned but has never been shown,
/// and marks them shown.
///
/// The server keeps that record, so each achievement is celebrated exactly
/// once per account -- logging out and in, or another phone, never brings it
/// back. Marked BEFORE anything is displayed: a celebration cut short (the app
/// closed, a phone call) still counts as shown rather than popping up again and
/// again.
///
/// Separate from the showing itself ([AchievementCelebrationScreen]) because
/// the caller wants to fetch EARLY and show LATER: the results screen asks for
/// these the moment it opens, so tapping «Далее» can present them instantly
/// instead of waiting on the network.
Future<List<UserAchievement>> takeNewAchievements() async {
  final List<UserAchievement> fresh;
  try {
    fresh = await ApiClient.instance.fetchNewAchievements();
  } catch (_) {
    return const [];
  }
  if (fresh.isEmpty) return const [];
  try {
    await ApiClient.instance.markAchievementsSeen([for (final a in fresh) a.id]);
  } catch (_) {
    return const [];
  }
  return fresh;
}

/// The "achievement unlocked" celebration as a screen of its own, shown once
/// the lesson's results have been read -- never as a dialog on top of them.
///
/// Several achievements earned at once are shown one after another in the same
/// screen: the button becomes «Следующее» and the page only closes after the
/// last one, so nothing is skipped.
class AchievementCelebrationScreen extends StatefulWidget {
  final List<UserAchievement> achievements;

  const AchievementCelebrationScreen({super.key, required this.achievements});

  @override
  State<AchievementCelebrationScreen> createState() => _AchievementCelebrationScreenState();
}

class _AchievementCelebrationScreenState extends State<AchievementCelebrationScreen>
    with SingleTickerProviderStateMixin {
  /// The entrance: the ring around the icon, then the icon itself, then the
  /// text lines one by one. Everything is one controller, so a new achievement
  /// simply replays it.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  /// The soft glow behind the icon keeps breathing while the screen is open.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  int _index = 0;

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Animation<double> _at(double begin, double end) => CurvedAnimation(
        parent: _intro,
        curve: Interval(begin, end.clamp(0.0, 1.0), curve: Curves.easeOutCubic),
      );

  UserAchievement get _current => widget.achievements[_index];
  bool get _hasMore => _index < widget.achievements.length - 1;

  void _next() {
    if (!_hasMore) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
    _intro
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final achievement = _current;
    final color = parseHexColor(achievement.color);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The glow breathes, the icon springs in: the one moment
                      // in the app that is allowed to be loud.
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) => Container(
                          width: 190,
                          height: 190,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                color.withValues(alpha: 0.28 + 0.14 * _pulse.value),
                                color.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                          child: Center(child: child),
                        ),
                        child: ScaleTransition(
                          scale: CurvedAnimation(parent: _intro, curve: const Interval(0, 0.7, curve: Curves.elasticOut)),
                          child: FadeTransition(
                            opacity: _at(0, 0.4),
                            child: Container(
                              width: 132,
                              height: 132,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color.withValues(alpha: 0.14),
                                border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
                              ),
                              child: AchievementIcon(achievement: achievement, dimmed: false, size: 120),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      _Line(
                        animation: _at(0.35, 0.7),
                        child: Text(
                          tr('Достижение получено!'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _Line(
                        animation: _at(0.45, 0.8),
                        child: Text(
                          achievement.title ?? '',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      if ((achievement.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _Line(
                          animation: _at(0.55, 0.9),
                          child: Text(
                            achievement.description!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.secondaryText),
                          ),
                        ),
                      ],
                      if (widget.achievements.length > 1) ...[
                        const SizedBox(height: 18),
                        _Line(
                          animation: _at(0.6, 1.0),
                          child: Text(
                            tr('{0} из {1}', [_index + 1, widget.achievements.length]),
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.muted),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: FadeTransition(
                opacity: _at(0.6, 1.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    key: const ValueKey('achievement-celebration-next'),
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: Text(
                      _hasMore ? tr('Следующее') : tr('Отлично!'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the entrance: it rises a little and fades in.
class _Line extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _Line({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - animation.value)), child: child),
      ),
      child: child,
    );
  }
}
