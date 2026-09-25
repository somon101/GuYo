import 'dart:async';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/exercise.dart';
import '../theme/app_colors.dart';
import '../widgets/audio_button.dart';
import '../widgets/guyo_ui.dart';
import '../widgets/remote_image.dart';
import 'lesson_exercise_flow.dart';

/// "Правда или ложь", as one of a Lesson's exercises: the backend hands back
/// a round built from THIS lesson's fixed word set (wrong-answer candidates
/// come from the user's previously-learned pool, never from other words in
/// this same lesson) -- this screen only renders one card at a time and
/// compares the tapped button to `item.isCorrect`.
///
/// Each card carries its own [_answerSeconds]-second countdown: running out
/// counts as a real wrong answer, reported to the backend exactly like a
/// tapped "Ложь" would be -- there is only one path a card is ever
/// resolved through, see [_settle].
///
/// After every answer, this screen reports {word_id, is_correct} to the
/// backend via submitLessonAnswer, which is the ONLY place a word's score
/// (and any rating points it earns crossing the learned threshold) actually
/// changes -- this screen never computes either itself, it just sums up
/// `pointsAwarded` from what the backend already decided on each answer.
class TrueOrFalseScreen extends StatefulWidget {
  final int lessonId;
  final int lessonNumber;
  const TrueOrFalseScreen({super.key, required this.lessonId, required this.lessonNumber});

  @override
  State<TrueOrFalseScreen> createState() => _TrueOrFalseScreenState();
}

class _TrueOrFalseScreenState extends State<TrueOrFalseScreen> with LessonExerciseFlow {
  bool _isLoading = true;
  String? _errorMessage;
  List<TrueOrFalseItem> _items = [];
  int _index = 0;
  int _pointsEarned = 0;
  bool _isAnswering = false;

  static const int _answerSeconds = 10;

  // A plain Timer, deliberately NOT an AnimationController: a running
  // controller keeps a frame permanently scheduled, and integration tests
  // call tester.pumpAndSettle() right after this screen appears --
  // pumpAndSettle waits for scheduled frames, so a ticking controller would
  // make every one of those calls block for the full countdown. A bare
  // Timer sits outside Flutter's frame scheduler and has no such effect;
  // it is still always cancelled below, in dispose and at the start of
  // every _settle, so none is ever left running.
  Timer? _ticker;
  int _secondsLeft = _answerSeconds;

  // Briefly colours the card green/red right after an answer, before the
  // next card (or the lesson runner) takes over. Null while unanswered.
  bool? _lastAnswerCorrect;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final round = await ApiClient.instance.fetchLessonTrueOrFalseRound(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _items = round.items;
        _index = 0;
        _pointsEarned = 0;
        _isLoading = false;
      });
      // Nothing left for this exercise to test -- skip it instead of
      // stalling the lesson on a dead end.
      if (round.items.isEmpty) {
        finishExercise();
      } else {
        _startTimer();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось загрузить упражнение';
      });
    }
  }

  void _startTimer() {
    _ticker?.cancel();
    setState(() => _secondsLeft = _answerSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _ticker?.cancel();
        _settle(isCorrect: false);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  /// The one rule of the whole exercise, kept as a plain function separate
  /// from any button/layout: independent of how many buttons there are or
  /// where they sit on screen, "Правда" is correct exactly when the shown
  /// translation is the real one.
  bool _isAnswerCorrect(TrueOrFalseItem item, bool userSaidTrue) => userSaidTrue == item.isCorrect;

  void _answer(bool userSaidTrue) {
    if (_isAnswering || _index >= _items.length) return;
    _settle(isCorrect: _isAnswerCorrect(_items[_index], userSaidTrue));
  }

  /// The one place a card is actually resolved, whether by a tap or by
  /// running out of time -- both paths report the exact same
  /// {word_id, is_correct} shape to the backend, and neither can fire
  /// twice for the same card.
  Future<void> _settle({required bool isCorrect}) async {
    if (_isAnswering || _index >= _items.length) return;
    _ticker?.cancel();
    final item = _items[_index];
    setState(() {
      _isAnswering = true;
      _lastAnswerCorrect = isCorrect;
    });

    // The result itself is no longer read here for lesson-completion
    // purposes: whether the lesson is complete is decided once, at the
    // end, by the lesson's own results screen from fresh backend state.
    // pointsAwarded IS read -- it is exactly what the backend just granted
    // for this answer (almost always 0), summed into the running total.
    final submit = ApiClient.instance
        .submitLessonAnswer(widget.lessonId, 'true_or_false', wordId: item.wordId, isCorrect: isCorrect)
        .then<int>((result) => result.pointsAwarded)
        .catchError((_) {
      // A failed score update must never interrupt the flow card by card.
      return 0;
    });
    final results = await Future.wait([submit, Future.delayed(const Duration(milliseconds: 650))]);

    if (!mounted) return;
    setState(() {
      _pointsEarned += results[0] as int;
      _index++;
      _isAnswering = false;
      _lastAnswerCorrect = null;
    });
    // Last card answered -- the lesson runner takes over straight away.
    if (_index >= _items.length) {
      finishExercise();
    } else {
      _startTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Для этого упражнения пока нет слов', textAlign: TextAlign.center),
        ),
      );
    }

    final isRoundComplete = _index >= _items.length;

    return Container(
      color: AppColors.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            _ProgressHeader(points: _pointsEarned, position: _index + 1, total: _items.length),
            const SizedBox(height: 20),
            Expanded(
              child: isRoundComplete
                  ? const LessonExerciseHandoff()
                  : Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CountdownRing(secondsLeft: _secondsLeft, total: _answerSeconds),
                            const SizedBox(height: 22),
                            _TrueOrFalseCard(item: _items[_index], reveal: _lastAnswerCorrect),
                          ],
                        ),
                      ),
                    ),
            ),
            if (!isRoundComplete) ...[
              const SizedBox(height: 16),
              _AnswerButtons(isLocked: _isAnswering, onAnswer: _answer),
            ],
          ],
        ),
      ),
    );
  }
}

/// "⭐ 12" and "Слова 3 из 10" in one pill -- real rating points earned so
/// far this round, and where the round is. Points are almost always 0
/// (they only move the moment a card pushes some word over the learned
/// threshold), which matches this round's own starting card too.
class _ProgressHeader extends StatelessWidget {
  final int points;
  final int position;
  final int total;

  const _ProgressHeader({required this.points, required this.position, required this.total});

  @override
  Widget build(BuildContext context) {
    return GuyoCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, size: 18, color: AppColors.rewardText),
          const SizedBox(width: 6),
          Text('$points', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          const SizedBox(width: 14),
          Container(width: 1, height: 20, color: AppColors.cardBorder),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(AppShapes.pillRadius)),
            // One plain Text (not Text.rich) so a test can find the whole
            // phrase with a single textContaining match, same convention
            // as every other progress label in this app.
            child: Text(
              'Слова $position из $total',
              style: const TextStyle(fontSize: 13, color: AppColors.primaryDark, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// The per-card countdown: a ring that empties over [_answerSeconds] with
/// the remaining whole second in the middle. Turns [AppColors.danger] in
/// the last 3 seconds, so running out is never a surprise.
class _CountdownRing extends StatelessWidget {
  final int secondsLeft;
  final int total;

  const _CountdownRing({required this.secondsLeft, required this.total});

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (secondsLeft / total).clamp(0.0, 1.0);
    final isUrgent = secondsLeft <= 3;
    final color = isUrgent ? AppColors.danger : AppColors.primary;
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            // A determinate indicator (a non-null value) never animates on
            // its own -- it only redraws when `value` changes, exactly on
            // this Timer's own once-a-second setState. See the Timer note
            // on _TrueOrFalseScreenState._ticker for why that matters.
            child: CircularProgressIndicator(
              value: fraction,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.progressTrack,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            '$secondsLeft',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: isUrgent ? AppColors.danger : AppColors.primaryDark),
          ),
        ],
      ),
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
/// the left, matching the visual reference this screen was redesigned to.
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
            label: 'Правда',
            icon: Icons.check_rounded,
            color: AppColors.success,
            onTap: isLocked ? null : () => onAnswer(true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _AnswerButton(
            key: const ValueKey('true-or-false-answer-false'),
            label: 'Ложь',
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
    return Material(
      color: isEnabled ? color : color.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(AppShapes.pillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.pillRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
