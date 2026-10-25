import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// The click and the buzz of a chest being tapped. One dedicated player: every tap cuts the
/// previous click and starts a new one (never two at once), and [stop] silences
/// it the moment the chest screen closes.
class ChestSound {
  ChestSound._();

  static AudioPlayer? _player;

  /// Bumped by every tap and by [stop]: a click still being prepared when a newer
  /// tap (or the close) comes in sees it is stale and never starts.
  static int _seq = 0;

  /// Pending pulses of the opening rumble; [stop] cancels them so nothing
  /// keeps buzzing after the screen is gone.
  static final List<Timer> _pulses = [];

  /// A short buzz for one tap.
  static void buzzTap() {
    _cancelPulses();
    HapticFeedback.mediumImpact();
  }

  /// A longer rumble for the moment the chest bursts open: a few heavy pulses.
  static void buzzOpen() {
    _cancelPulses();
    HapticFeedback.heavyImpact();
    for (final ms in const [110, 220, 330]) {
      _pulses.add(Timer(Duration(milliseconds: ms), HapticFeedback.heavyImpact));
    }
  }

  static void _cancelPulses() {
    for (final t in _pulses) {
      t.cancel();
    }
    _pulses.clear();
  }

  static AudioPlayer _get() =>
      _player ??= AudioPlayer()
        ..setReleaseMode(ReleaseMode.stop)
        ..setPlayerMode(PlayerMode.lowLatency);

  /// Plays the click from the start, cutting any click still sounding.
  static Future<void> tap() async {
    final mine = ++_seq;
    try {
      final p = _get();
      await p.stop();
      if (mine != _seq) return;
      await p.play(AssetSource('sounds/chest-tap.mp3')).timeout(const Duration(seconds: 2));
    } catch (_) {
      // A sound is decoration: a broken audio backend must never block opening.
      _discard();
    }
  }

  /// Stops the click right now (the screen is closing).
  static void stop() {
    _seq++;
    _cancelPulses();
    final p = _player;
    if (p == null) return;
    // ignore: unawaited_futures
    p.stop().catchError((_) {});
  }

  static void _discard() {
    final dead = _player;
    _player = null;
    // ignore: unawaited_futures
    dead?.dispose().timeout(const Duration(seconds: 1)).catchError((_) {});
  }
}
