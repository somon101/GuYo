import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../api/api_client.dart';
import 'avatar_models.dart';

/// Keeps the avatar catalog and its pictures on the phone, so the editor opens at once and the person's own
/// avatar shows even without internet. The server's catalog `version` decides whether anything is downloaded again;
/// when a part changed or was removed, its old picture file is deleted from the phone.
class AvatarStore {
  AvatarStore._();
  static final AvatarStore instance = AvatarStore._();

  static const _catalogKey = 'avatar-catalog-json';
  late final CacheManager _cache = DefaultCacheManager(); // lazy: tests never touch the phone's files
  final Map<String, ui.Image> images = {};
  final Map<String, Future<ui.Image?>> _loading = {};
  AvatarCatalog? catalog;

  /// Tests stand in for the server and the phone's files.
  @visibleForTesting
  Future<AvatarCatalog?> Function()? debugCatalog;
  @visibleForTesting
  Future<ui.Image?> Function(String url)? debugImage;

  /// The copy saved on the phone (null the very first time).
  Future<AvatarCatalog?> cached() async {
    if (debugCatalog != null) return null;
    try {
      final info = await _cache.getFileFromCache(_catalogKey);
      if (info == null) return catalog;
      final c = AvatarCatalog.fromJson(jsonDecode(utf8.decode(await info.file.readAsBytes())) as Map<String, dynamic>);
      return catalog = c;
    } catch (_) {
      return catalog;
    }
  }

  /// Asks the server whether the catalog changed; downloads it only if so. Old pictures of changed or removed parts go.
  Future<AvatarCatalog?> refresh() async {
    if (debugCatalog != null) return catalog = await debugCatalog!();
    final have = catalog ?? await cached();
    final json = await ApiClient.instance.fetchAvatarCatalog(since: have?.version);
    if (json['unchanged'] == true && have != null) return have;
    final fresh = AvatarCatalog.fromJson(json);
    final keep = <String, int>{for (final p in fresh.parts) p.url: p.version, for (final b in fresh.backgrounds) if (b.url != null) b.url!: b.version};
    if (have != null) {
      final before = <String, int>{for (final p in have.parts) p.url: p.version, for (final b in have.backgrounds) if (b.url != null) b.url!: b.version};
      for (final e in before.entries) {
        if (keep[e.key] != e.value) {
          images.remove(e.key)?.dispose();
          _loading.remove(e.key);
          try {
            await _cache.removeFile(ApiClient.instance.mediaUrl(e.key));
          } catch (_) {}
        }
      }
    }
    try {
      await _cache.putFile(_catalogKey, Uint8List.fromList(utf8.encode(jsonEncode(fresh.toJson()))), key: _catalogKey, fileExtension: 'json', maxAge: const Duration(days: 3650));
    } catch (_) {}
    return catalog = fresh;
  }

  /// One picture of a part or background: from the phone if it is already there, otherwise downloaded and kept.
  Future<ui.Image?> image(String url) {
    final done = images[url];
    if (done != null) return Future.value(done);
    return _loading[url] ??= _load(url);
  }

  Future<ui.Image?> _load(String url) async {
    if (debugImage != null) {
      final im = await debugImage!(url);
      if (im != null) images[url] = im;
      return im;
    }
    try {
      final file = await _cache.getSingleFile(ApiClient.instance.mediaUrl(url));
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      codec.dispose();
      return images[url] = frame.image;
    } catch (_) {
      _loading.remove(url);
      return null;
    }
  }

  /// The avatar was reset: its picture file leaves the phone.
  Future<void> forgetAvatar(String? url) async {
    if (url == null) return;
    try {
      await _cache.removeFile(ApiClient.instance.mediaUrl(url));
    } catch (_) {}
  }

  /// After saving: the new avatar picture goes onto the phone at once (shown even offline) and the old one is deleted.
  Future<void> replaceMyAvatar({required String? oldUrl, required String newUrl, required Uint8List png}) async {
    final api = ApiClient.instance;
    try {
      await _cache.putFile(api.mediaUrl(newUrl), png, key: api.mediaUrl(newUrl), fileExtension: 'png', maxAge: const Duration(days: 3650));
      if (oldUrl != null && oldUrl != newUrl) await _cache.removeFile(api.mediaUrl(oldUrl));
    } catch (_) {}
  }
}
