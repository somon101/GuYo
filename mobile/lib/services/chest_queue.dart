import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
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

  /// Said once when the server paid a different amount than the phone showed (for example a wrong
  /// clock on the phone). Screens that show chests listen and write it as a note.
  static final ValueNotifier<String?> correction = ValueNotifier<String?>(null);

  /// id -> {at: the moment it was opened on this phone (the server judges a doubled prize by it),
  /// kind, amount: what the phone showed}.
  static Map<int, Map<String, dynamic>> get _map {
    final raw = DiskCache.get(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      final now = DateTime.now().toUtc().toIso8601String();
      if (decoded is List) return {for (final i in decoded.cast<int>()) i: {'at': now}};
      return (decoded as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v is String ? {'at': v} : (v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  static Set<int> get pending => _map.keys.toSet();

  static void _store(Map<int, Map<String, dynamic>> map) {
    DiskCache.put(_key, jsonEncode(map.map((k, v) => MapEntry('$k', v))));
    // ignore: unawaited_futures
    DiskCache.saveNow();
  }

  /// Remembers these chests as opened (now) with the prize the phone showed, and tries to tell the
  /// server in the background.
  static void opened(List<(int id, String kind, int amount)> shown) {
    final now = DateTime.now().toUtc().toIso8601String();
    _store({..._map, for (final s in shown) s.$1: {'at': now, 'kind': s.$2, 'amount': s.$3}});
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
      final entries = _map;
      final list = ids.toList();
      for (var i = 0; i < list.length; i += 10) {
        final part = list.sublist(i, i + 10 > list.length ? list.length : i + 10);
        final paid = await ApiClient.instance.sendOpenedChests([for (final id in part) (id, entries[id]?['at'] as String?)]);
        _store(_map..removeWhere((k, _) => part.contains(k)));
        _compare(part, entries, paid);
      }
      // ignore: unawaited_futures
      ApiClient.instance.fetchEconomy();
    } catch (_) {
      // Offline or the server is busy: try again at the next chance.
    } finally {
      _flushing = false;
    }
  }

  @visibleForTesting
  static void compareForTest(List<int> ids, Map<int, Map<String, dynamic>> shown, Map<int, (String, int)> paid) => _compare(ids, shown, paid);

  /// What the server paid against what the phone showed: told to the person if they differ.
  static void _compare(List<int> ids, Map<int, Map<String, dynamic>> shown, Map<int, (String kind, int amount)> paid) {
    for (final id in ids) {
      final s = shown[id];
      final p = paid[id];
      if (s == null || p == null || s['amount'] == null) continue;
      if (p.$2 != s['amount'] && p.$1 != 'booster') {
        correction.value = tr('Приз скорректирован: начислено +{0} вместо +{1}', [p.$2, s['amount']]);
        return;
      }
    }
  }
}
