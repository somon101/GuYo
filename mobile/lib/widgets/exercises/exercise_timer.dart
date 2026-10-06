import '../../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// How long each timed exercise gives for one answer. Running out counts
/// as a wrong answer, the same way everywhere.
class ExerciseTimeLimits {
  ExerciseTimeLimits._();

  static const int buildWordSeconds = 25;
  static const int trueOrFalseSeconds = 15;
}

/// A per-second countdown for one answer.
///
/// A plain [Timer], deliberately not an AnimationController: a running
/// controller keeps a frame permanently scheduled, which would make every
/// `tester.pumpAndSettle()` in the integration suite block for the whole
/// countdown while an exercise is on screen.
class AnswerCountdown {
  final int seconds;
  final ValueChanged<int> onTick;
  final VoidCallback onExpired;

  Timer? _ticker;
  late int secondsLeft = seconds;

  AnswerCountdown({required this.seconds, required this.onTick, required this.onExpired});

  /// Starts (or restarts) from the full [seconds].
  void start() {
    _ticker?.cancel();
    secondsLeft = seconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (secondsLeft <= 1) {
        cancel();
        secondsLeft = 0;
        onExpired();
        return;
      }
      secondsLeft--;
      onTick(secondsLeft);
    });
  }

  void cancel() => _ticker?.cancel();
}

/// The one timer badge in the app: a small ring with the seconds left,
/// turning red for the last 3.
class ExerciseTimerBadge extends StatelessWidget {
  final int secondsLeft;
  final int totalSeconds;
  final double size;

  const ExerciseTimerBadge({super.key, required this.secondsLeft, required this.totalSeconds, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final color = secondsLeft <= 3 ? AppColors.danger : AppColors.primary;
    return Semantics(
      label: tr('Осталось {0} сек', [secondsLeft]),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: totalSeconds == 0 ? 0 : (secondsLeft / totalSeconds).clamp(0.0, 1.0),
                strokeWidth: 3.5,
                strokeCap: StrokeCap.round,
                backgroundColor: AppColors.progressTrack,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            Text('$secondsLeft', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}
