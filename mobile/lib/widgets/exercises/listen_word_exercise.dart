import '../../l10n/l10n.dart';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../models/lesson.dart';
import '../../services/answer_sound.dart';
import '../../theme/app_colors.dart';
import 'choice_tile.dart';
import '../../services/media_cache.dart';
import '../../services/answer_signals.dart';

/// "Услышь слово", as ONE self-contained widget: plays [item]'s own
/// recording, offers its shuffled options as [ChoiceTile]s, and reports
/// exactly one answer. The SAME widget a Lesson host and a Quest host both
/// render for this exercise type.
class ListenWordExercise extends StatefulWidget {
  final ListenWordItem item;
  final ValueChanged<bool> onAnswer;

  const ListenWordExercise({super.key, required this.item, required this.onAnswer});

  @override
  State<ListenWordExercise> createState() => _ListenWordExerciseState();
}

class _ListenWordExerciseState extends State<ListenWordExercise> {
  final _player = AudioPlayer();
  bool _isPlayingAudio = false;
  ListenWordOption? _selected;
  bool _isLocked = false;

  // A subscription, not `.first`: see audio_button.dart's own note on why
  // `.first` throws if the player is disposed before completion ever
  // fires -- exactly what happens here once the lesson runner swaps this
  // item out for the next one.
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    AnswerSignals.itemShown();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _play({bool slow = false}) async {
    final url = widget.item.wordAudioUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _player.stop();
      if (!mounted) return;
      setState(() => _isPlayingAudio = true);
      await _completeSub?.cancel();
      _completeSub = _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlayingAudio = false);
      });
      await _player.setPlaybackRate(slow ? 0.6 : 1.0);
      final source = await MediaCache.instance.playableSource(url);
      if (source == null) {
        if (mounted) setState(() => _isPlayingAudio = false);
        return;
      }
      await _player.play(source);
    } catch (_) {
      if (mounted) setState(() => _isPlayingAudio = false);
    }
  }

  void _choose(ListenWordOption option) {
    if (_isLocked) return;
    final correct = option.wordId == widget.item.wordId;
    AnswerSignals.given(option.word);
    AnswerSignals.answer({'picked_word_id': option.wordId});
    setState(() {
      _selected = option;
      _isLocked = true;
    });
    AnswerSound.play(correct);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted) widget.onAnswer(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRevealed = _selected != null;
    final options = widget.item.options;
    Widget tile(ListenWordOption option) => ChoiceTile(
          key: ValueKey('listen-word-option-${option.wordId}'),
          label: option.word,
          isSelected: _selected == option,
          isRevealed: isRevealed,
          isCorrectOption: option.wordId == widget.item.wordId,
          onTap: isRevealed ? null : () => _choose(option),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      // Carries the current item's own (correct) word_id for integration
      // tests to read -- otherwise a test would have no way to know which
      // shuffled option is correct without a second, separate call.
      key: ValueKey('listen-word-active-${widget.item.wordId}'),
      children: [
        Text(
          tr('Что ты услышал?'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 22),
        _SpeakerHero(isPlaying: _isPlayingAudio, onPlay: () => _play(), onSlow: () => _play(slow: true)),
        const SizedBox(height: 28),
        // Options as a 2-column grid: shorter to scan than a long list.
        for (var i = 0; i < options.length; i += 2) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tile(options[i])),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < options.length ? tile(options[i + 1]) : const SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// The big round speaker in the middle, with soft rings pulsing out while
/// the word plays, and a small "slower" button beside it.
class _SpeakerHero extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onSlow;
  const _SpeakerHero({required this.isPlaying, required this.onPlay, required this.onSlow});

  @override
  State<_SpeakerHero> createState() => _SpeakerHeroState();
}

class _SpeakerHeroState extends State<_SpeakerHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _SpeakerHero old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.isPlaying && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 112.0;
    return SizedBox(
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                for (final offset in const [0.0, 0.5])
                  Builder(builder: (context) {
                    final t = (_pulse.value + offset) % 1.0;
                    return Opacity(
                      opacity: widget.isPlaying ? (1 - t) * 0.35 : 0,
                      child: Container(
                        width: size + 46 * t,
                        height: size + 46 * t,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                      ),
                    );
                  }),
              ],
            ),
          ),
          GestureDetector(
            key: const ValueKey('listen-word-play'),
            onTap: widget.onPlay,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary.withValues(alpha: 0.85), AppColors.primary],
                ),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8)),
                ],
              ),
              child: Icon(
                widget.isPlaying ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                color: Colors.white,
                size: 50,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 10,
            child: Material(
              color: AppColors.surface,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                key: const ValueKey('listen-word-slow'),
                customBorder: const CircleBorder(),
                onTap: widget.onSlow,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Text('🐢', style: const TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
