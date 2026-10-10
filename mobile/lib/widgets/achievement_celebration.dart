import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import 'achievement_icon.dart';
import 'rank_icon.dart';

bool _celebrating = false;

/// Shows the "achievement unlocked" celebration for everything this
/// account has earned but not yet been shown, then tells the server they
/// were shown. The server keeps that record, so each achievement is
/// celebrated exactly once per account -- logging out and in, or another
/// phone, never brings it back. Called when the app opens, at the end of
/// a lesson and in Профиль; quietly does nothing on any failure.
Future<void> celebrateNewAchievements(BuildContext context) async {
  if (_celebrating) return;
  _celebrating = true;
  try {
    final List<UserAchievement> fresh;
    try {
      fresh = await ApiClient.instance.fetchNewAchievements();
    } catch (_) {
      return;
    }
    if (fresh.isEmpty || !context.mounted) return;
    // Marked first: a celebration cut short (app closed) still counts as
    // shown, rather than popping up again and again.
    try {
      await ApiClient.instance.markAchievementsSeen([for (final a in fresh) a.id]);
    } catch (_) {
      return;
    }
    for (final achievement in fresh) {
      if (!context.mounted) return;
      await showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: tr('Достижение получено'),
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => _AchievementUnlockedDialog(achievement: achievement),
        transitionBuilder: (_, animation, _, child) => ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
          child: FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  } finally {
    _celebrating = false;
  }
}

class _AchievementUnlockedDialog extends StatelessWidget {
  final UserAchievement achievement;
  const _AchievementUnlockedDialog({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 32, offset: const Offset(0, 12))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: parseHexColor(achievement.color).withValues(alpha: 0.15),
                  boxShadow: [BoxShadow(color: parseHexColor(achievement.color).withValues(alpha: 0.5), blurRadius: 28, spreadRadius: 2)],
                ),
                child: AchievementIcon(achievement: achievement, dimmed: false, size: 88),
              ),
              const SizedBox(height: 18),
              Text(tr('Достижение получено!'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondaryText, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(achievement.title!, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(achievement.description!, style: TextStyle(fontSize: 14, color: AppColors.secondaryText), textAlign: TextAlign.center),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text(tr('Отлично!')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
