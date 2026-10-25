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

  static Set<int> get pending {
    final raw = DiskCache.get(_key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<int>().toSet();
    } catch (_) {
      return {};
    }
  }

  static void _store(Set<int> ids) {
    DiskCache.put(_key, jsonEncode(ids.toList()));
    // ignore: unawaited_futures
    DiskCache.saveNow();
  }

  /// Remembers these chests as opened, and tries to tell the server in the background.
  static void opened(List<int> ids) {
    _store({...pending, ...ids});
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
      final list = ids.toList();
      for (var i = 0; i < list.length; i += 10) {
        final part = list.sublist(i, i + 10 > list.length ? list.length : i + 10);
        await ApiClient.instance.sendOpenedChests(part);
        _store(pending..removeAll(part));
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
