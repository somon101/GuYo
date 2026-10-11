import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../guyo_ui.dart';

/// The one "round over" screen every Practice exercise ends on, in the
/// style of the lesson results but simpler: one ring that fills up to the
/// share of right answers, a one-word verdict, "N из M правильно", and the
/// two ways on -- another round, or back. Practice keeps no score of its
/// own, so this is purely feedback for the player, never sent anywhere.
class PracticeRoundComplete extends StatelessWidget {
  final int correctCount;
  final int total;
  final VoidCallback onPlayAgain;
  final VoidCallback onBack;

  const PracticeRoundComplete({
    super.key,
    required this.correctCount,
    required this.total,
    required this.onPlayAgain,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : correctCount / total;
    final (String verdict, Color tone) = switch (share) {
      >= 1.0 => (tr('Идеально!'), AppColors.success),
      >= 0.8 => (tr('Отлично!'), AppColors.success),
      >= 0.5 => (tr('Хорошо!'), AppColors.primary),
      _ => (tr('Можно лучше'), AppColors.danger),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              final fade = Curves.easeOut.transform(((t - 0.35) / 0.65).clamp(0.0, 1.0));
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 156,
                    height: 156,
                    child: CustomPaint(
                      painter: _ResultRingPainter(progress: share * t, color: tone),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(share * t * 100).round()}%',
                              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                            ),
                            Text(tr('правильно'), style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: fade,
                    child: Column(
                      children: [
                        Text(
                          verdict,
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr('{0} из {1} правильно', [correctCount, total]),
                          style: TextStyle(fontSize: 15, color: AppColors.secondaryText),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: onPlayAgain,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(tr('Ещё раунд')),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: onBack,
                          style: TextButton.styleFrom(foregroundColor: AppColors.secondaryText),
                          child: Text(tr('Назад'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The result ring: a soft track and a round-capped arc that brightens
/// along its sweep -- the same drawing as the lesson results' rings.
class _ResultRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  static const double _stroke = 14;
  _ResultRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final arcRect = (Offset.zero & size).deflate(_stroke / 2);
    canvas.drawCircle(arcRect.center, arcRect.width / 2, Paint()..color = AppColors.surface);
    canvas.drawArc(
      arcRect,
      0,
      6.2832,
      false,
      Paint()
        ..color = AppColors.progressTrack
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
    if (progress > 0) {
      canvas.drawArc(
        arcRect,
        -1.5708,
        6.2832 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..shader = SweepGradient(
            startAngle: -1.5708,
            endAngle: 4.7124,
            colors: [color.withValues(alpha: 0.55), color],
          ).createShader(arcRect)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_ResultRingPainter old) => old.progress != progress || old.color != color;
}

/// Shown when there simply aren't enough learned words yet for this
/// exercise type -- not an error, a real and expected state for a new
/// account or a dictionary the user has barely started.
class PracticeEmptyState extends StatelessWidget {
  const PracticeEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return GuyoEmptyState(
      icon: Icons.auto_awesome_rounded,
      title: tr('Пока недостаточно слов для практики'),
      message: tr('Изучите больше слов в Уроках, чтобы открыть это упражнение здесь.'),
    );
  }
}
