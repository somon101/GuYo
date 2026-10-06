/// How an answer was given, beyond right/wrong: how long the item was on
/// screen, and whether the countdown ran out. Exercises mark the moment an
/// item appears and a timeout; whichever request submits the answer takes
/// both. Only one item is ever on screen at a time, so one slot is enough.
class AnswerSignals {
  AnswerSignals._();

  static DateTime? _shownAt;
  static bool _timedOut = false;

  static void itemShown() {
    _shownAt = DateTime.now();
    _timedOut = false;
  }

  static void timedOut() => _timedOut = true;

  /// The fields to add to an answer request; resets the slot.
  static Map<String, dynamic> take() {
    final shownAt = _shownAt;
    final fields = <String, dynamic>{
      if (shownAt != null) 'duration_ms': DateTime.now().difference(shownAt).inMilliseconds.clamp(0, 600000),
      'timed_out': _timedOut,
    };
    _shownAt = null;
    _timedOut = false;
    return fields;
  }
}
