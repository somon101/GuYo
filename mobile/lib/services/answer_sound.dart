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

  /// Two things keep this safe, both learned the hard way (a real ANR on a
  /// phone: the app froze in Сопоставление after a couple of wrong pairs):
  ///
  /// 1. ONE chime at a time. Сопоставление and Собери слово fire a chime on
  ///    every attempt, and a wrong pair is followed by another attempt less
  ///    than a second later. Overlapping `play()` calls on the same player
  ///    queue up inside the native player and can leave it wedged.
  /// 2. A wedged player is thrown away, not reused. If `play()` does not
  ///    finish within [_timeout], that player instance is replaced, so a
  ///    single bad native state can never take every later answer with it.
  static const Duration _timeout = Duration(seconds: 2);

  static AudioPlayer _player = _newPlayer();
  static bool _busy = false;

  /// Сколько раз подряд звук не смог проиграться. На третьем провале звуки
  /// выключаются до перезапуска приложения: на устройстве, где нативный плеер
  /// сломан, каждый новый вызов -- это ещё один шанс подвесить урок, а польза
  /// от него нулевая.
  static int _failures = 0;
  static bool _disabled = false;

  static AudioPlayer _newPlayer() => AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  static Future<void> play(bool isCorrect) async {
    // A chime is decoration: losing one is invisible, hanging the exercise is
    // not. So a running chime simply wins and this call is dropped.
    if (_busy || _disabled) return;
    _busy = true;
    try {
      await _player
          .play(AssetSource(isCorrect ? 'sounds/correct-answer.mp3' : 'sounds/incorrect-answer.mp3'))
          .timeout(_timeout);
      _failures = 0;
    } catch (_) {
      // A missing/broken audio backend (e.g. a muted or misconfigured
      // device) must never block the exercise flow itself -- the visual
      // feedback already carries the result on its own.
      _failures++;
      if (_failures >= 3) _disabled = true;
      _discardPlayer();
    } finally {
      _busy = false;
    }
  }

  /// Throws the current player away and starts a fresh one. Disposing is not
  /// awaited: a hung player is exactly the thing that cannot be trusted to
  /// answer a dispose call, and nothing below depends on its reply.
  static void _discardPlayer() {
    final dead = _player;
    _player = _newPlayer();
    // ignore: unawaited_futures
    dead.dispose().timeout(const Duration(seconds: 1)).catchError((_) {});
  }
}
