import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lesson work the phone has already done but the server has not accepted yet.
///
/// Three kinds of entry live here, in the order they happened: `start` (the
/// server freezes the pass's words), `answer` (this word, right or wrong) and
/// `finish` (the pass was played to the end, so its scores count). Each is
/// written to the device BEFORE its request goes out and removed only once the
/// server has taken it, so a killed app, a dead network or a phone switched off
/// mid-lesson can never lose a pass's progress: whatever is still here is
/// resent, in order -- see ApiClient.flushPendingAnswers.
///
/// The order matters: an answer must never reach the server before the pass it
/// belongs to was started, nor before the answer that came before it (the pass's
/// own counters depend on that), which is why a failed entry stops the flush
/// instead of being skipped.
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
    _items.add({'id': id, 'kind': 'answer', ...answer});
    await _save();
    return id;
  }

  /// The pass itself has to be started on the server before its answers mean
  /// anything; queued here when there was no network to start it with.
  ///
  /// At most one start per lesson: starting twice would make the server drop
  /// what the first pass held, so a second offline pass reuses the queued start
  /// that is already waiting.
  static Future<int> addStart(int lessonId) async {
    await load();
    for (final entry in _items) {
      if (entry['kind'] == 'start' && entry['lesson_id'] == lessonId && entry['id'] is int) {
        return entry['id'] as int;
      }
    }
    final id = _nextId++;
    _items.add({'id': id, 'kind': 'start', 'lesson_id': lessonId});
    await _save();
    return id;
  }

  /// The pass was played to the end: this is what makes its scores count.
  static Future<int> addFinish(int lessonId) async {
    await load();
    final id = _nextId++;
    _items.add({'id': id, 'kind': 'finish', 'lesson_id': lessonId});
    await _save();
    return id;
  }

  /// The answers of [lessonId] still waiting here, oldest first -- what the
  /// phone scores the pass with while the server has not seen them.
  static List<Map<String, dynamic>> answersFor(int lessonId) => [
        for (final entry in _items)
          if ((entry['kind'] ?? 'answer') == 'answer' && entry['lesson_id'] == lessonId) entry,
      ];

  /// Everything still waiting for [lessonId], whatever kind -- the pass is only
  /// counted once this is empty.
  static List<Map<String, dynamic>> forLesson(int lessonId) => [
        for (final entry in _items)
          if (entry['lesson_id'] == lessonId) entry,
      ];

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
