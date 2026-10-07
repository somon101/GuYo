import 'package:flutter/widgets.dart';

/// The per-question stopwatch and answer details sent with every answer
/// (duration_ms, timed_out, given_answer).
///
/// The stopwatch runs only while the app is in front: minimising it (or
/// the screen turning off) pauses it, coming back resumes it, so time
/// away from the app is never counted as study time.
class AnswerSignals {
  AnswerSignals._();

  static bool _shown = false;
  static int _accumulatedMs = 0;
  static DateTime? _runningSince;
  static bool _foreground = true;
  static bool _timedOut = false;
  static String? _given;
  static AppLifecycleListener? _listener;

  /// Starts following the app going to the background and back.
  static void init() {
    _listener ??= AppLifecycleListener(onStateChange: (state) {
      final foreground = state == AppLifecycleState.resumed;
      if (foreground == _foreground) return;
      _foreground = foreground;
      if (!_shown) return;
      if (foreground) {
        _runningSince = DateTime.now();
      } else {
        _pause();
      }
    });
  }

  static void _pause() {
    final since = _runningSince;
    if (since != null) _accumulatedMs += DateTime.now().difference(since).inMilliseconds;
    _runningSince = null;
  }

  static void itemShown() {
    _shown = true;
    _accumulatedMs = 0;
    _runningSince = _foreground ? DateTime.now() : null;
    _timedOut = false;
    _given = null;
  }

  static void timedOut() => _timedOut = true;

  /// What the learner actually gave (picked option, built letters, heard
  /// speech) -- shown in Admin Web's per-user history.
  static void given(String? answer) => _given = answer;

  /// The fields to add to an answer request; resets the slot. Call it
  /// before any await, so the next question's stopwatch can't start first.
  static Map<String, dynamic> take() {
    _pause();
    final fields = <String, dynamic>{
      if (_shown) 'duration_ms': _accumulatedMs.clamp(0, 600000),
      'timed_out': _timedOut,
      if (_given != null && _given!.isNotEmpty) 'given_answer': _given!.length > 255 ? _given!.substring(0, 255) : _given,
    };
    _shown = false;
    _accumulatedMs = 0;
    _timedOut = false;
    _given = null;
    return fields;
  }
}
