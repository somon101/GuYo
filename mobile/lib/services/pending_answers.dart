import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lesson answers the phone has already judged but the server has not accepted
/// yet.
///
/// Each one is written to the device BEFORE its request goes out, and removed
/// only once the server has taken it. So a killed app, a dead network or a
/// phone switched off mid-lesson can never lose a pass's progress: whatever is
/// still here is resent -- see ApiClient.flushPendingAnswers, called after
/// login and whenever the app comes back to the front.
///
/// The pass itself lives on the server (`Lesson.pass_pending_scores`), so a
/// late answer still lands in the same pass: it is counted exactly as if it had
/// arrived on time.
class PendingAnswers {
  PendingAnswers._();

  static const String _key = 'guyo_pending_answers_v1';
  static const _storage = FlutterSecureStorage();

  static List<Map<String, dynamic>> _items = [];
  static bool _loaded = false;
  static int _nextId = 1;

  /// Reads what a previous run left behind. Called once at startup.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _items = [for (final entry in list) Map<String, dynamic>.from(entry as Map)];
      for (final entry in _items) {
        final id = entry['id'];
        if (id is int && id >= _nextId) _nextId = id + 1;
      }
    } catch (_) {
      // An unreadable list is simply an empty one: the answers it held are
      // gone either way, and refusing to start would be worse.
      _items = [];
    }
  }

  static List<Map<String, dynamic>> get all => List.unmodifiable(_items);

  static bool get isEmpty => _items.isEmpty;

  static Future<int> add(Map<String, dynamic> answer) async {
    await load();
    final id = _nextId++;
    _items.add({'id': id, ...answer});
    await _save();
    return id;
  }

  static Future<void> remove(int id) async {
    await load();
    final before = _items.length;
    _items.removeWhere((entry) => entry['id'] == id);
    if (_items.length != before) await _save();
  }

  /// Forgets everything -- used on logout, where the answers belong to the
  /// account that just left.
  static Future<void> clear() async {
    _items = [];
    _loaded = true;
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }

  static Future<void> _save() async {
    try {
      await _storage.write(key: _key, value: jsonEncode(_items));
    } catch (_) {
      // Best effort: the in-memory queue still flushes in this run.
    }
  }
}
