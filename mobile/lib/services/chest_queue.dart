import 'dart:async';
import 'dart:convert';

import '../api/api_client.dart';
import 'disk_cache.dart';

/// Chests opened on this phone that the server has not been told about yet.
///
/// The prize of every chest is decided by the server and sent down ahead of time, so the
/// opening is shown at once, even with no internet. The server is told afterwards; if that
/// fails, the ids wait here (kept on the device) and are sent on the next occasion. Telling
/// the server twice is harmless, it pays only once.
class ChestQueue {
  ChestQueue._();

  static const _key = 'chest-pending';
  static bool _flushing = false;

  /// id -> the moment it was opened on this phone (the server judges a doubled prize by it).
  static Map<int, String> get _map {
    final raw = DiskCache.get(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return {for (final i in decoded.cast<int>()) i: DateTime.now().toUtc().toIso8601String()};
      return (decoded as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v as String));
    } catch (_) {
      return {};
    }
  }

  static Set<int> get pending => _map.keys.toSet();

  static void _store(Map<int, String> map) {
    DiskCache.put(_key, jsonEncode(map.map((k, v) => MapEntry('$k', v))));
    // ignore: unawaited_futures
    DiskCache.saveNow();
  }

  /// Remembers these chests as opened (now), and tries to tell the server in the background.
  static void opened(List<int> ids) {
    final now = DateTime.now().toUtc().toIso8601String();
    _store({..._map, for (final i in ids) i: now});
    // ignore: unawaited_futures
    flush();
  }

  /// Sends everything waiting. Never throws; a failure just leaves the ids for later.
  static Future<void> flush() async {
    if (_flushing) return;
    final ids = pending;
    if (ids.isEmpty) return;
    _flushing = true;
    try {
      final times = _map;
      final list = ids.toList();
      for (var i = 0; i < list.length; i += 10) {
        final part = list.sublist(i, i + 10 > list.length ? list.length : i + 10);
        await ApiClient.instance.sendOpenedChests([for (final i in part) (i, times[i])]);
        _store(_map..removeWhere((k, _) => part.contains(k)));
      }
      // ignore: unawaited_futures
      ApiClient.instance.fetchEconomy();
    } catch (_) {
      // Offline or the server is busy: try again at the next chance.
    } finally {
      _flushing = false;
    }
  }
}
