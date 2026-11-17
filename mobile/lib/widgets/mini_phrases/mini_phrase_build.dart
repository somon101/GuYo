import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../l10n/l10n.dart';
import '../../models/mini_phrase.dart';
import '../../services/answer_sound.dart';
import '../../theme/app_colors.dart';

class _Tile {
  final int id;
  final String text;
  const _Tile(this.id, this.text);
}

/// "Собери фразу" for one mini-phrase: its parts plus a couple of extra
/// learned words, shuffled; the learner places them in order. Judged right
/// here against the stored answer (case and punctuation ignored) so
/// nothing waits on the network; the answer goes to the server in the
/// background, which re-checks it and grants the rating points.
class MiniPhraseBuildExercise extends StatefulWidget {
  final MiniPhrase phrase;
  final int? lessonId;

  /// Called once with the result, when the learner moves on.
  final ValueChanged<bool> onDone;

  const MiniPhraseBuildExercise({super.key, required this.phrase, this.lessonId, required this.onDone});

  @override
  State<MiniPhraseBuildExercise> createState() => _MiniPhraseBuildExerciseState();
}

class _MiniPhraseBuildExerciseState extends State<MiniPhraseBuildExercise> {
  late final List<_Tile> _tiles;
  late List<_Tile?> _slots;
  bool? _result;

  @override
  void initState() {
    super.initState();
    final words = [...widget.phrase.parts.map((p) => p.text), ...widget.phrase.distractors];
    _tiles = [for (var i = 0; i < words.length; i++) _Tile(i, words[i])];
    final random = Random();
    // Never hand the learner the answer already in order.
    for (var tries = 0; tries < 8; tries++) {
      _tiles.shuffle(random);
      if (_tiles.length < 2 || _tiles.take(widget.phrase.parts.length).map((t) => t.id).toList().toString() !=
          List.generate(widget.phrase.parts.length, (i) => i).toString()) {
        break;
      }
    }
    _slots = List<_Tile?>.filled(widget.phrase.parts.length, null);
  }

  bool get _locked => _result != null;
  bool _placed(_Tile t) => _slots.any((s) => s?.id == t.id);

  void _put(_Tile t) {
    if (_locked || _placed(t)) return;
    final i = _slots.indexWhere((s) => s == null);
    if (i == -1) return;
    HapticFeedback.selectionClick();
    setState(() => _slots[i] = t);
  }

  void _takeBack(int i) {
    if (_locked || _slots[i] == null) return;
    setState(() => _slots[i] = null);
  }

  void _check() {
    if (_locked || _slots.contains(null)) return;
    final answer = [for (final s in _slots) s!.text];
    final correct = widget.phrase.isCorrect(answer);
    AnswerSound.play(correct);
    ApiClient.instance.sendMiniPhraseAnswer(widget.phrase.id, answer, lessonId: widget.lessonId);
    setState(() => _result = correct);
    if (correct) {
      Future.delayed(const Duration(milliseconds: 950), () {
        if (mounted) widget.onDone(true);
      });
    }
  }

  Color? _slotColor(int i) {
    if (_result == null || _slots[i] == null) return null;
    final expected = widget.phrase.parts[i].text;
    return MiniPhrase.normalize(_slots[i]!.text) == MiniPhrase.normalize(expected) ? AppColors.success : AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final filled = !_slots.contains(null);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Соберите фразу'),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.phrase.translation ?? '',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 18),
                // The answer line.
                Container(
                  constraints: const BoxConstraints(minHeight: 76),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppShapes.cardRadius),
                    border: Border.all(color: AppColors.cardBorder),
                    boxShadow: AppShapes.cardShadow,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _slots.length; i++)
                        GestureDetector(
                          onTap: () => _takeBack(i),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, a) => ScaleTransition(
                              scale: Tween(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                              child: FadeTransition(opacity: a, child: child),
                            ),
                            child: _slots[i] == null
                                ? _EmptySlot(key: ValueKey('empty-$i'))
                                : _TileView(
                                    key: ValueKey('slot-$i-${_slots[i]!.id}'),
                                    text: _slots[i]!.text,
                                    accent: _slotColor(i),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_result == false) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(AppShapes.rowRadius),
                    ),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${tr('Правильно')}: '),
                        TextSpan(text: widget.phrase.text, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ]),
                      style: TextStyle(fontSize: 15.5, color: AppColors.success),
                    ),
                  ),
                ],
                if (_result == true) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text(
                        tr('Верно!'),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.success),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                // The tiles; a used one keeps its place as a faint outline.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final t in _tiles)
                      _placed(t)
                          ? _TileView(key: ValueKey('used-${t.id}'), text: t.text, used: true)
                          : GestureDetector(
                              key: ValueKey('tile-${t.id}'),
                              onTap: () => _put(t),
                              child: _TileView(text: t.text),
                            ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                key: const ValueKey('mini-phrase-check'),
                onPressed: _result == false
                    ? () => widget.onDone(false)
                    : (filled && !_locked ? _check : null),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _result == false ? tr('Дальше') : tr('Проверить'),
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.violetSurface,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

/// A word tile: a raised surface with GuYo's soft shadow; [accent] tints
/// it green/red after checking; [used] leaves just a faint outline.
class _TileView extends StatelessWidget {
  final String text;
  final Color? accent;
  final bool used;
  const _TileView({super.key, required this.text, this.accent, this.used = false});

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: accent ?? AppColors.primaryDark);
    if (used) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.muted.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Opacity(opacity: 0, child: Text(text, style: textStyle)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: accent != null ? accent!.withValues(alpha: AppColors.dark ? 0.20 : 0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent ?? AppColors.cardBorder, width: accent != null ? 1.6 : 1),
        boxShadow: accent != null
            ? null
            : [
                BoxShadow(color: AppColors.primary.withValues(alpha: 0.16), offset: const Offset(0, 2), blurRadius: 0),
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, 4), blurRadius: 10),
              ],
      ),
      child: Text(text, style: textStyle),
    );
  }
}
