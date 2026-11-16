// Контактный лист: все png папки на зелёном фоне, чтобы проверить вырезание глазами.
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> a) {
  final files = (Directory(a[0]).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.png')).toList()..sort((x, y) => x.path.compareTo(y.path)));
  const cell = 260, cols = 6;
  final rows = (files.length / cols).ceil();
  final sheet = img.Image(width: cols * cell, height: rows * cell, numChannels: 4);
  img.fill(sheet, color: img.ColorRgb8(40, 170, 110));
  for (var i = 0; i < files.length; i++) {
    final im = img.decodePng(files[i].readAsBytesSync())!;
    final s = (cell - 16) / (im.width > im.height ? im.width : im.height);
    final r = img.copyResize(im, width: (im.width * s).round(), height: (im.height * s).round(), interpolation: img.Interpolation.average);
    img.compositeImage(sheet, r, dstX: (i % cols) * cell + (cell - r.width) ~/ 2, dstY: (i ~/ cols) * cell + (cell - r.height) ~/ 2);
  }
  File(a[1]).writeAsBytesSync(img.encodePng(sheet));
  stdout.writeln('${files.length} файлов');
}
