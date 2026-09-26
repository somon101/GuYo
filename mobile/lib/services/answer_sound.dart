import 'package:audioplayers/audioplayers.dart';

/// The one place that plays the short correct/incorrect feedback chime --
/// every exercise widget (Правда или ложь, Собери слово, Сопоставление,
/// Услышь слово, Произнеси слово, Собери фразу, Собери фразу на слух) calls
/// [AnswerSound.play] at the exact moment IT locally learns whether the
/// user's answer was right, right alongside its own visual reveal (green/red
/// flash, checkmark, etc). A future exercise type follows the same rule:
/// call this from wherever that widget first knows `isCorrect`, never invent
/// a second sound-playing path.
///
/// A dedicated `AudioPlayer` instance, separate from the one word-
/// pronunciation playback uses (`AudioButton`), so a feedback chime can
/// never fight over playback state with a word's audio the user tapped.
class AnswerSound {
  AnswerSound._();

  static final AudioPlayer _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  static Future<void> play(bool isCorrect) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(isCorrect ? 'sounds/correct-answer.mp3' : 'sounds/incorrect-answer.mp3'));
    } catch (_) {
      // A missing/broken audio backend (e.g. a muted or misconfigured
      // device) must never block the exercise flow itself -- the visual
      // feedback already carries the result on its own.
    }
  }
}
