import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The last answers of the main screens' requests, kept on the device
/// between launches -- so the app opens straight onto the previous data
/// and refreshes it quietly, instead of skeletons while the network
/// catches up. Read once at startup into memory; saved shortly after any
/// change. Cleared on logout: it is the account's own data.
class DiskCache {
  DiskCache._();

  static const _key = 'guyo_disk_cache_v1';
  static const _storage = FlutterSecureStorage();
  static Map<String, String> _bodies = {};
  static Timer? _saveTimer;

  /// Call once before the app starts.
  static Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null) _bodies = (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
    } catch (_) {
      _bodies = {};
    }
  }

  static String? get(String key) => _bodies[key];

  static void put(String key, String body) {
    if (_bodies[key] == body) return;
    _bodies[key] = body;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), _save);
  }

  static Future<void> _save() async {
    try {
      await _storage.write(key: _key, value: jsonEncode(_bodies));
    } catch (_) {
      // Best effort: the app works the same, it just opens slower next time.
    }
  }

  static Future<void> clear() async {
    _saveTimer?.cancel();
    _bodies = {};
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
