// Системные окна: выбор и сохранение файлов. Вынесено, чтобы подменять в тестах.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedFile {
  final String name;
  final Uint8List bytes;
  PickedFile(this.name, this.bytes);
}

abstract class FileServices {
  Future<List<PickedFile>> pickImages();
  Future<PickedFile?> pickProject();

  /// Сохраняет файл: на компьютере системное окно «Сохранить как», на Android выбор места в «Файлах».
  Future<bool> saveFile(String name, Uint8List bytes, String mime);
}

class SystemFileServices implements FileServices {
  @override
  Future<List<PickedFile>> pickImages() async {
    final r = await FilePicker.pickFiles(type: FileType.image, dialogTitle: 'Выберите картинки');
    final out = <PickedFile>[];
    for (final f in r) {
      out.add(PickedFile(f.name, await f.readAsBytes()));
    }
    return out;
  }

  @override
  Future<PickedFile?> pickProject() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['json'], dialogTitle: 'Открыть проект');
    if (f == null) return null;
    return PickedFile(f.name, await f.readAsBytes());
  }

  @override
  Future<bool> saveFile(String name, Uint8List bytes, String mime) async {
    final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime, dialogTitle: 'Сохранить');
    return uri != null;
  }
}
