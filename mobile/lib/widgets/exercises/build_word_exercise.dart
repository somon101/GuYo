import 'dart:async';

import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../models/exercise.dart';
import '../../services/answer_sound.dart';
import '../../theme/app_colors.dart';
import '../audio_button.dart';

/// One letter button/slot's contents, with a unique instance id so two
/// identical letters (e.g. HELLO's two L's) are always distinguishable and
/// independently tappable -- never matched or removed by letter text alone.
class _Tile {
  final String id;
  final String letter;
  const _Tile(this.id, this.letter);
}

/// "Собери слово", as ONE self-contained widget: the translation prompt,
/// the letter slots, the pool, the "Проверить" button, and the ONLY timer
/// any exercise carries (15 seconds, per spec) -- all in one place, so a
/// Lesson host and a Quest host render the exact same thing and neither
/// has to reimplement the countdown.
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
  static const int _answerSeconds = 15;

  List<_Tile> _pool = [];
  List<_Tile?> _slots = [];
  List<Color?> _slotColors = [];
  bool _isLocked = false;

  // A plain Timer, not an AnimationController -- see true_or_false_exercise
  // .dart's own note (removed from there, still true here): a running
  // controller keeps a frame permanently scheduled, which would make every
  // tester.pumpAndSettle() in the integration suite block for the full 15
  // seconds while this widget is on screen.
  Timer? _ticker;
  int _secondsLeft = _answerSeconds;

  @override
  void initState() {
    super.initState();
    _pool = [for (var i = 0; i < widget.item.letters.length; i++) _Tile('$i-${widget.item.letters[i]}', widget.item.letters[i])];
    _slots = List<_Tile?>.filled(widget.item.correctWord.length, null);
    _slotColors = List<Color?>.filled(widget.item.correctWord.length, null);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _ticker?.cancel();
        _resolve(timedOut: true);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tapPool(_Tile tile) {
    if (_isLocked) return;
    final emptyIndex = _slots.indexWhere((s) => s == null);
    if (emptyIndex == -1) return;
    setState(() {
      _slots[emptyIndex] = tile;
      _pool = _pool.where((t) => t.id != tile.id).toList();
      _slotColors = List<Color?>.filled(_slots.length, null);
    });
  }

  void _tapSlot(int index) {
    if (_isLocked) return;
    final tile = _slots[index];
    if (tile == null) return;
    setState(() {
      _slots[index] = null;
      _pool = [..._pool, tile];
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
    _ticker?.cancel();

    var allCorrect = !timedOut;
    final colors = <Color?>[];
    for (var i = 0; i < _slots.length; i++) {
      final guess = _slots[i]?.letter;
      final correct = widget.item.correctWord[i];
      final matches = guess != null && (widget.caseSensitive ? guess == correct : guess.toLowerCase() == correct.toLowerCase());
      colors.add(matches ? AppColors.success : AppColors.danger);
      if (!matches) allCorrect = false;
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
    final isUrgent = _secondsLeft <= 3;

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
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
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
            _TimerBadge(secondsLeft: _secondsLeft, urgent: isUrgent),
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
          child: Material(
            color: canCheck ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppShapes.pillRadius),
            child: InkWell(
              key: const ValueKey('build-word-check-button'),
              borderRadius: BorderRadius.circular(AppShapes.pillRadius),
              onTap: canCheck ? () => _resolve(timedOut: false) : null,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Center(
                  child: Text('Проверить', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
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
            for (final tile in _pool) _LetterButton(key: ValueKey(tile.id), letter: tile.letter, onTap: () => _tapPool(tile)),
          ],
        ),
      ],
    );
  }
}

/// The one timer badge in the app: a small ring + seconds, next to the
/// prompt rather than dominating it -- «Собери слово» already has a lot on
/// screen (prompt, slots, pool), so the countdown stays compact.
class _TimerBadge extends StatelessWidget {
  final int secondsLeft;
  final bool urgent;
  const _TimerBadge({required this.secondsLeft, required this.urgent});

  @override
  Widget build(BuildContext context) {
    final color = urgent ? AppColors.danger : AppColors.primary;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: (secondsLeft / _BuildWordExerciseState._answerSeconds).clamp(0.0, 1.0),
              strokeWidth: 3.5,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.progressTrack,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text('$secondsLeft', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _LetterSlot extends StatelessWidget {
  final String? letter;
  final Color? color;
  final VoidCallback onTap;
  const _LetterSlot({required this.letter, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filled = letter != null;
    return InkWell(
      onTap: filled ? onTap : null,
      borderRadius: BorderRadius.circular(AppShapes.rowRadius),
      child: Container(
        width: 42,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color != null ? color!.withValues(alpha: 0.10) : AppColors.violetSurface,
          border: Border.all(color: color ?? AppColors.cardBorder, width: color != null ? 2 : 1),
          borderRadius: BorderRadius.circular(AppShapes.rowRadius),
        ),
        child: Text(
          letter ?? '',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? AppColors.primaryDark),
        ),
      ),
    );
  }
}

class _LetterButton extends StatelessWidget {
  final String letter;
  final VoidCallback onTap;
  const _LetterButton({super.key, required this.letter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppShapes.rowRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShapes.rowRadius),
        child: Container(
          width: 46,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(AppShapes.rowRadius),
            boxShadow: AppShapes.cardShadow,
          ),
          child: Text(letter, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
        ),
      ),
    );
  }
}
