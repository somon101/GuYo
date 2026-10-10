import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../models/exercise.dart';
import '../../services/answer_sound.dart';
import '../../theme/app_colors.dart';
import '../audio_button.dart';
import '../ios_ui.dart';
import 'exercise_timer.dart';
import '../../services/answer_signals.dart';

/// One letter button/slot's contents, with a unique instance id so two
/// identical letters (e.g. HELLO's two L's) are always distinguishable and
/// independently tappable -- never matched or removed by letter text alone.
class _Tile {
  final String id;
  final String letter;
  const _Tile(this.id, this.letter);
}

/// "Собери слово", as ONE self-contained widget: the translation prompt,
/// the letter slots, the pool, the "Проверить" button, and its timer
/// (ExerciseTimeLimits.buildWordSeconds) -- all in one place, so a Lesson
/// host and a Quest host render the exact same thing and neither has to
/// reimplement the countdown.
///
/// [item] is treated as fixed for this widget's whole lifetime -- a host
/// placing this in a multi-item sequence must give it a fresh `key`
/// (e.g. ValueKey(item.wordId)) per item, so Flutter creates a new instance
/// -- and with it a freshly-started timer -- rather than trying to swap the
/// letters of a running one. [onAnswer] fires exactly once, either from
/// "Проверить" or from the timer reaching 0 (which always counts as
/// incorrect, the same way running out of time does anywhere else in the
/// app that has real stakes).
class BuildWordExercise extends StatefulWidget {
  final BuildWordItem item;
  final bool caseSensitive;
  final ValueChanged<bool> onAnswer;

  const BuildWordExercise({super.key, required this.item, required this.caseSensitive, required this.onAnswer});

  @override
  State<BuildWordExercise> createState() => _BuildWordExerciseState();
}

class _BuildWordExerciseState extends State<BuildWordExercise> {
  // Every letter keeps its own place in the pool: a used one leaves an
  // empty key behind instead of the row closing up, so the next letter
  // never slides away from under the finger.
  List<_Tile> _tiles = [];
  Set<String> _available = {};
  List<_Tile?> _slots = [];
  List<Color?> _slotColors = [];
  bool _isLocked = false;

  late final AnswerCountdown _countdown = AnswerCountdown(
    seconds: ExerciseTimeLimits.buildWordSeconds,
    onTick: (_) {
      if (mounted) setState(() {});
    },
    onExpired: () {
      if (mounted) {
        AnswerSignals.timedOut();
        _resolve(timedOut: true);
      }
    },
  );

  @override
  void initState() {
    super.initState();
    AnswerSignals.itemShown();
    _tiles = [for (var i = 0; i < widget.item.letters.length; i++) _Tile('$i-${widget.item.letters[i]}', widget.item.letters[i])];
    _available = {for (final t in _tiles) t.id};
    _slots = List<_Tile?>.filled(widget.item.correctWord.length, null);
    _slotColors = List<Color?>.filled(widget.item.correctWord.length, null);
    _countdown.start();
  }

  @override
  void dispose() {
    _countdown.cancel();
    super.dispose();
  }

  void _tapPool(_Tile tile) {
    if (_isLocked) return;
    final emptyIndex = _slots.indexWhere((s) => s == null);
    if (emptyIndex == -1) return;
    setState(() {
      _slots[emptyIndex] = tile;
      _available.remove(tile.id);
      _slotColors = List<Color?>.filled(_slots.length, null);
    });
  }

  void _tapSlot(int index) {
    if (_isLocked) return;
    final tile = _slots[index];
    if (tile == null) return;
    setState(() {
      _slots[index] = null;
      _available.add(tile.id);
      _slotColors = List<Color?>.filled(_slots.length, null);
    });
  }

  /// Runs from "Проверить" or from the timer hitting 0. [timedOut] forces
  /// the result to incorrect regardless of what is filled in (unfilled or
  /// not, running out counts the same way as a wrong tap anywhere else
  /// with a timer would).
  void _resolve({required bool timedOut}) {
    if (_isLocked) return;
    if (!timedOut && _slots.contains(null)) return;
    _countdown.cancel();

    var allCorrect = !timedOut;
    final colors = <Color?>[];
    for (var i = 0; i < _slots.length; i++) {
      final guess = _slots[i]?.letter;
      final correct = widget.item.correctWord[i];
      final matches = guess != null && (widget.caseSensitive ? guess == correct : guess.toLowerCase() == correct.toLowerCase());
      colors.add(matches ? AppColors.success : AppColors.danger);
      if (!matches) allCorrect = false;
    }
    if (!timedOut) {
      final built = _slots.map((s) => s?.letter ?? '_').join();
      AnswerSignals.given(built);
      AnswerSignals.answer({'text': built});
    }
    setState(() {
      _slotColors = colors;
      _isLocked = true;
    });
    AnswerSound.play(allCorrect);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted) widget.onAnswer(allCorrect);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasTranslationAudio = item.translationAudioUrl != null && item.translationAudioUrl!.isNotEmpty;
    final canCheck = !_slots.contains(null) && !_isLocked;

    return Column(
      mainAxisSize: MainAxisSize.min,
      key: ValueKey('build-word-active-${item.wordId}-${item.correctWord}'),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppShapes.cardRadius),
                  border: Border.all(color: AppColors.cardBorder),
                  boxShadow: AppShapes.cardShadow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        item.translation,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (hasTranslationAudio) ...[
                      const SizedBox(width: 8),
                      AudioButton(url: ApiClient.instance.mediaUrl(item.translationAudioUrl!)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            ExerciseTimerBadge(
              secondsLeft: _countdown.secondsLeft,
              totalSeconds: ExerciseTimeLimits.buildWordSeconds,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          key: const ValueKey('build-word-slots'),
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _slots.length; i++)
              _LetterSlot(letter: _slots[i]?.letter, color: _slotColors[i], onTap: () => _tapSlot(i)),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: IosPressable(
            key: const ValueKey('build-word-check-button'),
            onTap: canCheck ? () => _resolve(timedOut: false) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: canCheck ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                tr('Проверить'),
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          key: const ValueKey('build-word-pool'),
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tile in _tiles)
              if (_available.contains(tile.id))
                _LetterButton(key: ValueKey(tile.id), letter: tile.letter, onTap: () => _tapPool(tile))
              else
                const _UsedKey(),
          ],
        ),
      ],
    );
  }
}

/// One place in the word being built: a light empty box, the letter once
/// placed (tap it to send the letter back), green/red once checked.
class _LetterSlot extends StatelessWidget {
  final String? letter;
  final Color? color;
  final VoidCallback onTap;
  const _LetterSlot({required this.letter, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filled = letter != null;
    final Color background;
    final Color border;
    if (color != null) {
      background = color!.withValues(alpha: 0.12);
      border = color!;
    } else if (filled) {
      background = Colors.white;
      border = AppColors.primary.withValues(alpha: 0.35);
    } else {
      background = AppColors.violetSurface;
      border = Colors.transparent;
    }
    return IosPressable(
      onTap: filled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 42,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border, width: color != null ? 2 : 1.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          letter ?? '',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: color ?? AppColors.primaryDark),
        ),
      ),
    );
  }
}

/// The empty place a used letter leaves in the pool.
class _UsedKey extends StatelessWidget {
  const _UsedKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 52,
      decoration: BoxDecoration(color: AppColors.progressTrack.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
    );
  }
}

/// A letter in the pool, drawn like an iOS keyboard key: white, softly
/// rounded, with the thin shadow underneath that makes a key look raised.
class _LetterButton extends StatelessWidget {
  final String letter;
  final VoidCallback onTap;
  const _LetterButton({super.key, required this.letter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Color(0x33101B63), offset: Offset(0, 1.5), blurRadius: 0),
            BoxShadow(color: Color(0x14101B63), offset: Offset(0, 3), blurRadius: 8),
          ],
        ),
        child: Text(letter, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
      ),
    );
  }
}
