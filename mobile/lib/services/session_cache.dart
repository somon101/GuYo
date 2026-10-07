/// The last data each screen showed, kept in memory for this session.
///
/// A screen opened again (a tab switched to, Квесты reopened, a reload
/// after returning from a lesson) paints these at once and refreshes
/// quietly in the background -- the skeleton is only for the very first
/// load, never a blank screen while a slow network catches up. Cleared on
/// logout so the next account never sees the previous one's data.
class SessionCache {
  SessionCache._();

  static final Map<String, Object> _values = {};

  static T? get<T>(String key) {
    final value = _values[key];
    return value is T ? value : null;
  }

  static void put(String key, Object value) => _values[key] = value;

  /// Returns and forgets [key] -- for data meant to be used once.
  static T? take<T>(String key) {
    final value = get<T>(key);
    _values.remove(key);
    return value;
  }

  static void clear() => _values.clear();
}
