import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../api/api_client.dart';

/// Downloads images and audio ahead of time into the same on-disk cache
/// CachedNetworkImage already reads from (DefaultCacheManager), so a
/// prepared lesson shows its pictures and plays its sounds without waiting
/// on the network. Audio downloaded here plays from the local file; any
/// other URL still streams as before.
class MediaCache {
  MediaCache._();
  static final MediaCache instance = MediaCache._();

  final Map<String, String> _localFiles = {};

  /// Accepts the backend's relative media paths or full URLs.
  static String fullUrl(String url) => url.startsWith('http') ? url : ApiClient.instance.mediaUrl(url);

  /// Fetches everything in parallel. Never throws and never waits longer
  /// than [timeout]: media that isn't ready by then simply loads the old
  /// way when it is shown -- a slow file must never hold up a lesson.
  Future<void> prefetch(Iterable<String> urls, {Duration timeout = const Duration(seconds: 12)}) async {
    final unique = {for (final url in urls) if (url.isNotEmpty) fullUrl(url)};
    final pending = [
      for (final url in unique)
        if (!_localFiles.containsKey(url)) _download(url),
    ];
    if (pending.isEmpty) return;
    try {
      await Future.wait(pending).timeout(timeout);
    } on TimeoutException {
      // Whatever finished is cached; the rest loads on demand.
    }
  }

  /// Fills the map from the ON-DISK cache without touching the network.
  ///
  /// The files are still there after the app is closed, but [_localFiles]
  /// starts empty on every launch -- without this, a recording already on the
  /// phone would be downloaded again.
  Future<void> warm(Iterable<String> urls) async {
    final manager = DefaultCacheManager();
    for (final url in {for (final u in urls) if (u.isNotEmpty) fullUrl(u)}) {
      if (_localFiles.containsKey(url)) continue;
      try {
        final info = await manager.getFileFromCache(url);
        if (info != null) _localFiles[url] = info.file.path;
      } catch (e) {
        debugPrint('Warm failed for $url: $e');
      }
    }
  }

  Future<void> _download(String url) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      _localFiles[url] = file.path;
    } catch (e) {
      debugPrint('Prefetch failed for $url: $e');
    }
  }

  /// What an AudioPlayer should play for [url], always a file on the phone:
  /// one not cached yet is downloaded first (by Dart, off the main thread).
  /// Null when it can't be had -- then there is simply no sound.
  ///
  /// Never a UrlSource: Android's MediaPlayer opens a network URL on the
  /// platform main thread, and on a slow connection that froze the whole
  /// app ("Application Not Responding") seconds into an online lesson,
  /// while the same lesson offline played its cached files fine.
  Future<Source?> playableSource(String url, {Duration timeout = const Duration(seconds: 10)}) async {
    final full = fullUrl(url);
    if (!_localFiles.containsKey(full)) {
      await warm([full]);
    }
    if (!_localFiles.containsKey(full)) {
      try {
        await _download(full).timeout(timeout);
      } on TimeoutException {
        return null;
      }
    }
    final local = _localFiles[full];
    return local != null ? DeviceFileSource(local) : null;
  }

  /// What an AudioPlayer should play for [url]: the downloaded file when
  /// there is one, the network otherwise. Prefer [playableSource].
  Source audioSource(String url) {
    final full = fullUrl(url);
    final local = _localFiles[full];
    return local != null ? DeviceFileSource(local) : UrlSource(full);
  }
}
