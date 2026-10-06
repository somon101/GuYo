/// How an answer was given, beyond right/wrong: how long the item was on
/// screen, and whether the countdown ran out. Exercises mark the moment an
/// item appears and a timeout; whichever request submits the answer takes
/// both. Only one item is ever on screen at a time, so one slot is enough.
class AnswerSignals {
  AnswerSignals._();

  static DateTime? _shownAt;
  static bool _timedOut = false;
  static String? _given;

  static void itemShown() {
    _shownAt = DateTime.now();
    _timedOut = false;
    _given = null;
  }

  static void timedOut() => _timedOut = true;

  /// What the learner actually gave (picked option, built letters, heard
  /// speech) -- shown in Admin Web's per-user history.
  static void given(String? answer) => _given = answer;

  /// The fields to add to an answer request; resets the slot.
  static Map<String, dynamic> take() {
    final shownAt = _shownAt;
    final fields = <String, dynamic>{
      if (shownAt != null) 'duration_ms': DateTime.now().difference(shownAt).inMilliseconds.clamp(0, 600000),
      'timed_out': _timedOut,
      if (_given != null && _given!.isNotEmpty) 'given_answer': _given!.length > 255 ? _given!.substring(0, 255) : _given,
    };
    _shownAt = null;
    _timedOut = false;
    _given = null;
    return fields;
  }
}
