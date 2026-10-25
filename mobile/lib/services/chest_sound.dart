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

  static String _tapAsset = 'sounds/chest-tap.mp3';
  static bool _tapReady = false;
  static bool _openReady = false;

  static AudioPlayer _get() =>
      _player ??= AudioPlayer()
        ..setReleaseMode(ReleaseMode.stop)
        ..setPlayerMode(PlayerMode.lowLatency);

  /// Loads both sounds ahead of the first tap, so nothing waits on a file read
  /// when the chest is pressed. Safe to call again; never throws.
  static Future<void> warmUp({String tapAsset = 'sounds/chest-tap.mp3'}) async {
    if (tapAsset != _tapAsset) {
      _tapAsset = tapAsset;
      _tapReady = false;
    }
    try {
      if (!_tapReady) {
        await _get().setSource(AssetSource(_tapAsset));
        _tapReady = true;
      }
      if (!_openReady) {
        final p = _openPlayer ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource('sounds/chest-open.mp3'));
        _openReady = true;
      }
    } catch (_) {}
  }

  /// A real vibration of the motor for [duration] ms at full strength. One plain call, as a plain
  /// call is what every phone obeys; if it fails the system haptic tick is used. Never throws.
  static Future<void> _vibrate(int duration) async {
    try {
      await Vibration.vibrate(duration: duration, amplitude: 255);
    } catch (_) {
      try {
        await HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }

  /// A short buzz for one tap.
  static void buzzTap() {
    // ignore: unawaited_futures
    _vibrate(90);
  }

  /// A long, strong rumble for the moment the chest bursts open (it replaces the tap's buzz).
  static void buzzOpen() {
    // ignore: unawaited_futures
    _vibrate(1000);
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
        await p.play(AssetSource(_tapAsset)).timeout(const Duration(seconds: 2));
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

  /// Back to the chest click for the next screen that uses it.
  static void resetTapSound() {
    _tapAsset = 'sounds/chest-tap.mp3';
    _tapReady = false;
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
