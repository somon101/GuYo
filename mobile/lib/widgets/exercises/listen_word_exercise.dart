import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../models/lesson.dart';
import '../../services/answer_sound.dart';
import '../../theme/app_colors.dart';
import 'choice_tile.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
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
      await _player.play(UrlSource(ApiClient.instance.mediaUrl(url)));
    } catch (_) {
      if (mounted) setState(() => _isPlayingAudio = false);
    }
  }

  void _choose(ListenWordOption option) {
    if (_isLocked) return;
    final correct = option.wordId == widget.item.wordId;
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      // Carries the current item's own (correct) word_id for integration
      // tests to read -- otherwise a test would have no way to know which
      // shuffled option is correct without a second, separate call.
      key: ValueKey('listen-word-active-${widget.item.wordId}'),
      children: [
        _ReplayPrompt(isPlaying: _isPlayingAudio, onReplay: _play),
        const SizedBox(height: 18),
        for (final option in widget.item.options) ...[
          ChoiceTile(
            key: ValueKey('listen-word-option-${option.wordId}'),
            label: option.word,
            isSelected: _selected == option,
            isRevealed: isRevealed,
            isCorrectOption: option.wordId == widget.item.wordId,
            onTap: isRevealed ? null : () => _choose(option),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// The compact "what to listen to" control: a round play button plus a
/// prompt, styled with the same shapes/colours as every other exercise
/// card in the app.
class _ReplayPrompt extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onReplay;
  const _ReplayPrompt({required this.isPlaying, required this.onReplay});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppShapes.cardRadius),
      child: InkWell(
        onTap: onReplay,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppShapes.cardRadius),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: AppShapes.cardShadow,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isPlaying
                        ? [AppColors.primary.withValues(alpha: 0.7), AppColors.primary]
                        : [AppColors.primary, AppColors.primaryDark],
                  ),
                ),
                child: Icon(isPlaying ? Icons.graphic_eq_rounded : Icons.volume_up_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Прослушать ещё раз',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
              ),
              const Icon(Icons.replay_rounded, color: AppColors.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
