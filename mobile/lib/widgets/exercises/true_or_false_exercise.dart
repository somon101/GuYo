import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../models/exercise.dart';
import '../../services/answer_sound.dart';
import '../../theme/app_colors.dart';
import '../audio_button.dart';
import '../ios_ui.dart';
import '../remote_image.dart';
import 'exercise_timer.dart';
import '../../services/answer_signals.dart';

/// "Правда или ложь", as ONE self-contained widget: the card plus its two
/// answer buttons, and everything that happens between a tap and the
/// round moving on. This is the single implementation every place that
/// offers "Правда или ложь" renders -- a Lesson host feeds it one item at
/// a time from a multi-item round, a Quest host feeds it the round's one
/// and only item -- so a design change here is a design change
/// everywhere at once, and neither host has to re-implement the reveal
/// flash, the lock-while-answered state, or the tap logic itself.
///
/// Each card has ExerciseTimeLimits.trueOrFalseSeconds to answer. Running
/// out counts as a wrong answer and goes through the exact same reveal
/// and [onAnswer] path as a wrong tap. The countdown restarts for every
/// new item.
///
/// [onAnswer] fires exactly once per item, AFTER the brief reveal flash
/// finishes -- a host never needs its own "wait, then report" delay; it
/// only needs to swap in the next item (or move on) once this fires.
class TrueOrFalseExercise extends StatefulWidget {
  final TrueOrFalseItem item;
  final ValueChanged<bool> onAnswer;

  const TrueOrFalseExercise({super.key, required this.item, required this.onAnswer});

  @override
  State<TrueOrFalseExercise> createState() => _TrueOrFalseExerciseState();
}

class _TrueOrFalseExerciseState extends State<TrueOrFalseExercise> {
  bool _isLocked = false;
  bool? _reveal;

  late final AnswerCountdown _countdown = AnswerCountdown(
    seconds: ExerciseTimeLimits.trueOrFalseSeconds,
    onTick: (_) {
      if (mounted) setState(() {});
    },
    onExpired: () {
      if (mounted) {
        AnswerSignals.timedOut();
        _resolve(false);
      }
    },
  );

  @override
  void initState() {
    super.initState();
    AnswerSignals.itemShown();
    _countdown.start();
  }

  @override
  void dispose() {
    _countdown.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrueOrFalseExercise oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new item means the host moved the round on -- start this card
    // fresh rather than carrying over the previous one's lock/flash or
    // what was left of its time.
    if (oldWidget.item.wordId != widget.item.wordId) {
      _isLocked = false;
      _reveal = null;
      _countdown.start();
    }
  }

  void _answer(bool userSaidTrue) {
    AnswerSignals.given(userSaidTrue ? 'Правда' : 'Ложь');
    AnswerSignals.answer({'shown': widget.item.shownTranslation, 'choice': userSaidTrue});
    _resolve(userSaidTrue == widget.item.isCorrect);
  }

  void _resolve(bool correct) {
    if (_isLocked) return;
    _countdown.cancel();
    setState(() {
      _isLocked = true;
      _reveal = correct;
    });
    AnswerSound.play(correct);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted) widget.onAnswer(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The card and its buttons travel together as one compact block --
    // never a card floating alone with the buttons pinned to the very
    // bottom of the screen, which is what made them hard to reach.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExerciseTimerBadge(
          secondsLeft: _countdown.secondsLeft,
          totalSeconds: ExerciseTimeLimits.trueOrFalseSeconds,
          size: 40,
        ),
        const SizedBox(height: 12),
        _TrueOrFalseCard(item: widget.item, reveal: _reveal),
        const SizedBox(height: 18),
        _AnswerButtons(isLocked: _isLocked, onAnswer: _answer),
      ],
    );
  }
}

class _TrueOrFalseCard extends StatelessWidget {
  final TrueOrFalseItem item;

  /// Null while the card is still waiting for an answer; true/false for a
  /// brief moment right after, to flash the border green or red.
  final bool? reveal;

  const _TrueOrFalseCard({required this.item, this.reveal});

  @override
  Widget build(BuildContext context) {
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final hasTranscription = item.transcription != null && item.transcription!.isNotEmpty;
    final hasWordAudio = item.wordAudioUrl != null && item.wordAudioUrl!.isNotEmpty;
    final hasTranslationAudio = item.shownTranslationAudioUrl != null && item.shownTranslationAudioUrl!.isNotEmpty;

    final borderColor = switch (reveal) {
      true => AppColors.success,
      false => AppColors.danger,
      null => AppColors.cardBorder,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      key: ValueKey('true-or-false-card-${item.wordId}'),
      constraints: const BoxConstraints(maxWidth: 360),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: borderColor, width: reveal == null ? 1 : 2),
        boxShadow: AppShapes.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppShapes.rowRadius),
              child: RemoteImage(
                url: item.imageUrl!,
                width: 320,
                height: 140,
                fit: BoxFit.cover,
                fallbackBuilder: () => const SizedBox(height: 0),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  item.original,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  textAlign: TextAlign.center,
                ),
              ),
              if (hasWordAudio) ...[
                const SizedBox(width: 8),
                AudioButton(url: ApiClient.instance.mediaUrl(item.wordAudioUrl!), size: 22),
              ],
            ],
          ),
          if (hasTranscription)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(item.transcription!, style: const TextStyle(fontSize: 15, color: AppColors.secondaryText)),
            ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(AppShapes.pillRadius)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    item.shownTranslation,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (hasTranslationAudio) ...[
                  const SizedBox(width: 8),
                  AudioButton(url: ApiClient.instance.mediaUrl(item.shownTranslationAudioUrl!), size: 20),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Правда" / "Ложь" as two full-width pill buttons, green and red so the
/// choice reads at a glance without reading the label. "Правда" leads on
/// the left.
class _AnswerButtons extends StatelessWidget {
  final bool isLocked;
  final ValueChanged<bool> onAnswer;

  const _AnswerButtons({required this.isLocked, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AnswerButton(
            key: const ValueKey('true-or-false-answer-true'),
            label: tr('Правда'),
            icon: Icons.check_rounded,
            color: AppColors.success,
            onTap: isLocked ? null : () => onAnswer(true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _AnswerButton(
            key: const ValueKey('true-or-false-answer-false'),
            label: tr('Ложь'),
            icon: Icons.close_rounded,
            color: AppColors.danger,
            onTap: isLocked ? null : () => onAnswer(false),
          ),
        ),
      ],
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _AnswerButton({super.key, required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return IosPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 54,
        decoration: BoxDecoration(
          color: isEnabled ? color : color.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isEnabled
              ? [BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
