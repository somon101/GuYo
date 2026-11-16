// Локальное хранилище: проект в JSON и картинки отдельными файлами в папке приложения. Без интернета.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

abstract class StudioStorage {
  Future<Map<String, dynamic>?> loadState();
  Future<void> saveState(Map<String, dynamic> json);
  Future<Uint8List?> readBlob(String id);
  Future<void> writeBlob(String id, Uint8List bytes);
  Future<void> deleteBlob(String id);
  Future<void> clearBlobs();
  Future<List<String>> blobIds();
}

class FileStorage implements StudioStorage {
  final Directory root;
  FileStorage(this.root);
  File get _state => File('${root.path}/project.json');
  Directory get _blobs => Directory('${root.path}/blobs');

  @override
  Future<Map<String, dynamic>?> loadState() async {
    try {
      if (!await _state.exists()) return null;
      return jsonDecode(await _state.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveState(Map<String, dynamic> json) async {
    await root.create(recursive: true);
    // пишем во временный файл и переименовываем, чтобы обрыв не испортил проект
    final tmp = File('${_state.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(_state.path);
  }

  @override
  Future<Uint8List?> readBlob(String id) async {
    final f = File('${_blobs.path}/$id');
    return await f.exists() ? await f.readAsBytes() : null;
  }

  @override
  Future<void> writeBlob(String id, Uint8List bytes) async {
    await _blobs.create(recursive: true);
    await File('${_blobs.path}/$id').writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> deleteBlob(String id) async {
    final f = File('${_blobs.path}/$id');
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> clearBlobs() async {
    if (await _blobs.exists()) await _blobs.delete(recursive: true);
  }

  @override
  Future<List<String>> blobIds() async {
    if (!await _blobs.exists()) return [];
    return [for (final f in _blobs.listSync()) if (f is File) f.uri.pathSegments.last];
  }
}

/// Для тестов: всё в памяти.
class MemoryStorage implements StudioStorage {
  Map<String, dynamic>? state;
  final Map<String, Uint8List> blobs = {};
  @override
  Future<Map<String, dynamic>?> loadState() async => state == null ? null : jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
  @override
  Future<void> saveState(Map<String, dynamic> json) async => state = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
  @override
  Future<Uint8List?> readBlob(String id) async => blobs[id];
  @override
  Future<void> writeBlob(String id, Uint8List bytes) async => blobs[id] = bytes;
  @override
  Future<void> deleteBlob(String id) async => blobs.remove(id);
  @override
  Future<void> clearBlobs() async => blobs.clear();
  @override
  Future<List<String>> blobIds() async => blobs.keys.toList();
}
