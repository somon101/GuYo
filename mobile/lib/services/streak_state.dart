import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_fire.dart';
import '../widgets/in_app_banner.dart' show appNavigatorKey;

/// Whether today's streak day is already earned (a lesson, Практика round
/// or quest finished today) and the streak length -- one source every 🔥
/// in the app listens to. Null until the profile has loaded once.
final ValueNotifier<bool?> streakLitToday = ValueNotifier(null);
final ValueNotifier<int?> streakDays = ValueNotifier(null);

/// From the profile (GET /users/me/profile).
void setStreakState({required bool litToday, required int days}) {
  streakLitToday.value = litToday;
  streakDays.value = days;
}

/// From a finish response: `streak_lit_now` is true only for the call that
/// lit today's day -- that moment plays the flame lighting up.
void reportStreakResult(Map<String, dynamic> json) {
  final litNow = json['streak_lit_now'] as bool? ?? false;
  final days = json['streak_days'] as int?;
  if (days != null) streakDays.value = days;
  if (json.containsKey('streak_lit_now')) {
    if (litNow) {
      streakLitToday.value = true;
      _showIgnition(days ?? 1);
    } else if (streakLitToday.value != true && days != null && days > 0) {
      streakLitToday.value = true;
    }
  }
}

void _showIgnition(int days) {
  // A moment later, so it lands on the screen the finish leads to.
  Future.delayed(const Duration(milliseconds: 600), () {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('Серия'),
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) => _IgnitionDialog(days: days),
    );
  });
}

class _IgnitionDialog extends StatefulWidget {
  final int days;
  const _IgnitionDialog({required this.days});

  @override
  State<_IgnitionDialog> createState() => _IgnitionDialogState();
}

class _IgnitionDialogState extends State<_IgnitionDialog> {
  bool _lit = false;

  @override
  void initState() {
    super.initState();
    // Shown grey first, then it catches fire.
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _lit = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(28)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedFire(size: 130, lit: _lit),
                const SizedBox(height: 10),
                AnimatedOpacity(
                  opacity: _lit ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Column(
                    children: [
                      Text(
                        tr('Серия: {0}', [widget.days]),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFFFF7A29)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('Сегодня засчитано! Возвращайтесь завтра'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14.5, color: AppColors.secondaryText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF7A29)),
                    child: Text(tr('Отлично!')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
