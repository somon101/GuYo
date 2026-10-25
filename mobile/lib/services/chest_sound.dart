import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// The click and the buzz of a chest being tapped. One dedicated player: every tap cuts the
/// previous click and starts a new one (never two at once), and [stop] silences
/// it the moment the chest screen closes.
class ChestSound {
  ChestSound._();

  static AudioPlayer? _player;
  static AudioPlayer? _openPlayer;

  /// Bumped by every tap and by [stop]: a click still being prepared when a newer
  /// tap (or the close) comes in sees it is stale and never starts.
  static int _seq = 0;

  static bool? _canVibrate;
  static bool _tapReady = false;
  static bool _openReady = false;

  static AudioPlayer _get() =>
      _player ??= AudioPlayer()
        ..setReleaseMode(ReleaseMode.stop)
        ..setPlayerMode(PlayerMode.lowLatency);

  /// Loads both sounds ahead of the first tap, so nothing waits on a file read
  /// when the chest is pressed. Safe to call again; never throws.
  static Future<void> warmUp() async {
    try {
      _canVibrate ??= await Vibration.hasVibrator();
    } catch (_) {}
    try {
      if (!_tapReady) {
        await _get().setSource(AssetSource('sounds/chest-tap.mp3'));
        _tapReady = true;
      }
      if (!_openReady) {
        final p = _openPlayer ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource('sounds/chest-open.mp3'));
        _openReady = true;
      }
    } catch (_) {}
  }

  /// A real vibration of [duration] ms (or a pattern); falls back to the
  /// system haptic tick where the motor cannot be driven directly. Never throws.
  static Future<void> _vibrate({int duration = 30, List<int>? pattern, int amplitude = 200}) async {
    try {
      _canVibrate ??= await Vibration.hasVibrator();
      if (_canVibrate != true) {
        await HapticFeedback.mediumImpact();
        return;
      }
      if (pattern != null) {
        await Vibration.vibrate(pattern: pattern, intensities: [for (var i = 0; i < pattern.length; i++) i.isOdd ? amplitude : 0]);
      } else {
        await Vibration.vibrate(duration: duration, amplitude: amplitude);
      }
    } catch (_) {
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {}
    }
  }

  /// A short buzz for one tap.
  static void buzzTap() {
    // ignore: unawaited_futures
    _vibrate(duration: 35, amplitude: 180);
  }

  /// A longer rumble for the moment the chest bursts open.
  static void buzzOpen() {
    // ignore: unawaited_futures
    _vibrate(pattern: const [0, 90, 50, 90, 50, 200], amplitude: 255);
  }

  /// Plays the click from the start, cutting any click still sounding.
  static Future<void> tap() async {
    final mine = ++_seq;
    try {
      // ignore: unawaited_futures
      _openPlayer?.stop().catchError((_) {});
      final p = _get();
      await p.stop();
      if (mine != _seq) return;
      if (_tapReady) {
        await p.resume().timeout(const Duration(seconds: 2));
      } else {
        await p.play(AssetSource('sounds/chest-tap.mp3')).timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      // A sound is decoration: a broken audio backend must never block opening.
      _discard();
    }
  }

  /// The magic reveal when the chest bursts open. Cuts the tap click and any
  /// reveal still sounding, and never starts once [stop] has been called.
  static Future<void> open() async {
    final mine = ++_seq;
    try {
      // ignore: unawaited_futures
      _player?.stop().catchError((_) {});
      final p = _openPlayer ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await p.stop();
      if (mine != _seq) return;
      if (_openReady) {
        await p.resume().timeout(const Duration(seconds: 2));
      } else {
        await p.play(AssetSource('sounds/chest-open.mp3')).timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      final dead = _openPlayer;
      _openPlayer = null;
      _openReady = false;
      // ignore: unawaited_futures
      dead?.dispose().timeout(const Duration(seconds: 1)).catchError((_) {});
    }
  }

  /// Stops the click right now (the screen is closing).
  static void stop() {
    _seq++;
    try {
      // ignore: unawaited_futures
      Vibration.cancel().catchError((_) {});
    } catch (_) {}
    // ignore: unawaited_futures
    _player?.stop().catchError((_) {});
    // ignore: unawaited_futures
    _openPlayer?.stop().catchError((_) {});
  }

  static void _discard() {
    final dead = _player;
    _player = null;
    _tapReady = false;
    // ignore: unawaited_futures
    dead?.dispose().timeout(const Duration(seconds: 1)).catchError((_) {});
  }
}
