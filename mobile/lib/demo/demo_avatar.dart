import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// The demo's avatar parts: the real parts from the Avatar Studio (a boys' set, file "Выгрузить для GuYo"),
/// kept as assets (assets/demo-avatar) and served by the demo's fake server under /media/demo-avatar/ID.png.
/// The catalog has the same shape as the real GET /avatar/catalog.

/// The catalog JSON the real server would send.
Future<String> demoAvatarCatalogJson() => rootBundle.loadString('assets/demo-avatar/catalog.json');

/// The picture of one demo part ("ID.png").
Future<Uint8List> demoPartPng(String file) async {
  final data = await rootBundle.load('assets/demo-avatar/${file.replaceAll('.png', '')}.png');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
