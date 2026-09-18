import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// Reusable play/stop button for one audio URL -- a Word's own pronunciation
/// or its translation's, wherever they're shown.
///
/// Every screen that displays a Word (or an exercise item built from one)
/// uses this instead of its own audio-playing widget: the URL always comes
/// from that Word's own data (`word_audio_url` / `translation_audio_url`,
/// ultimately `Word.word_audio_key` / `WordTranslation.audio_key` on the
/// backend), so a future screen only needs to pass the URL it already has --
/// never a new playback implementation.
class AudioButton extends StatefulWidget {
  final String url;
  final double size;
  const AudioButton({super.key, required this.url, this.size = 20});

  @override
  State<AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends State<AudioButton> {
  final _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    setState(() => _isPlaying = true);
    try {
      await _player.play(UrlSource(widget.url));
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(widget.size),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          _isPlaying ? Icons.stop_circle : Icons.volume_up,
          size: widget.size,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
