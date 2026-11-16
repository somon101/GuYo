import 'dart:io';
import 'package:flutter/services.dart';

import 'package:avatar_studio/state/services.dart';
import 'package:avatar_studio/state/storage.dart';
import 'package:avatar_studio/state/studio.dart';
import 'package:image/image.dart' as img;

class FakeServices implements FileServices {
  List<PickedFile> next = [];
  PickedFile? project;
  final saved = <String, Uint8List>{};
  @override
  Future<List<PickedFile>> pickImages() async => next;
  @override
  Future<PickedFile?> pickProject() async => project;
  @override
  Future<bool> saveFile(String name, Uint8List bytes, String mime) async {
    saved[name] = bytes;
    return true;
  }
}

/// Картинка: цветной круг (с глазами) на чёрном фоне (JPEG) или на «шахматке» (PNG).
Uint8List faceOnBlack({int w = 240, int h = 200}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(0, 0, 0));
  img.fillCircle(im, x: w ~/ 2, y: h ~/ 2, radius: h ~/ 2 - 12, color: img.ColorRgb8(242, 188, 156));
  img.fillCircle(im, x: w ~/ 2 - 30, y: h ~/ 2 - 10, radius: 9, color: img.ColorRgb8(58, 36, 24));
  img.fillCircle(im, x: w ~/ 2 + 30, y: h ~/ 2 - 10, radius: 9, color: img.ColorRgb8(58, 36, 24));
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

Uint8List squareOnChecker({int w = 240, int h = 200}) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final light = (((x >> 3) + (y >> 3)) & 1) == 1;
      im.setPixelRgba(x, y, light ? 255 : 221, light ? 255 : 221, light ? 255 : 221, 255);
    }
  }
  img.fillRect(im, x1: 40, y1: 30, x2: w - 40, y2: h - 30, color: img.ColorRgb8(43, 58, 143));
  return Uint8List.fromList(img.encodePng(im));
}

Studio newStudio({MemoryStorage? storage, FakeServices? files}) => Studio(storage ?? MemoryStorage(), files ?? FakeServices(), useIsolate: false);

/// Реальный шрифт вместо тестового Ahem, чтобы тексты имели настоящую ширину (кириллица есть в Roboto из Flutter SDK).
Future<void> loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  var any = false;
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final file = File('$dir/$f');
    if (await file.exists()) {
      loader.addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
      any = true;
    }
  }
  if (any) await loader.load();
}
