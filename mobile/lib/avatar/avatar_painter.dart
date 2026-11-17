import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'avatar_logic.dart';
import 'avatar_models.dart';

Color _hex(String? s, [Color fallback = const Color(0xFFCCCCCC)]) {
  if (s == null || !s.startsWith('#') || s.length < 7) return fallback;
  return Color(0xFF000000 | int.parse(s.substring(1, 7), radix: 16));
}

/// Draws the avatar into [size]: the background and the chosen parts in the catalog's slot order, each at its own
/// saved place. Shows the frame square of the canvas (what becomes the picture). Parts whose picture has not
/// arrived yet are simply skipped, so the avatar fills in as the pictures load.
void paintAvatar(Canvas canvas, Size size, AvatarCatalog c, AvatarChoice choice, Map<String, ui.Image> images) {
  final frame = avatarFrame(c);
  final k = size.width / frame.width;
  canvas.save();
  canvas.scale(k);
  canvas.translate(-frame.left, -frame.top);
  final bg = c.background(choice.bg);
  if (bg != null) {
    if (bg.kind == 'solid') {
      canvas.drawRect(frame, Paint()..color = _hex(bg.c1));
    } else if (bg.kind == 'grad') {
      canvas.drawRect(frame, Paint()..shader = ui.Gradient.linear(frame.topLeft, frame.bottomRight, [_hex(bg.c1), _hex(bg.c2)]));
    } else {
      final im = bg.url == null ? null : images[bg.url];
      if (im != null) {
        final kk = math.max(frame.width / im.width, frame.height / im.height) * bg.zoom;
        final w = im.width * kk, h = im.height * kk;
        final dst = Rect.fromLTWH(frame.left + (frame.width - w) / 2 + bg.offX / 100 * frame.width, frame.top + (frame.height - h) / 2 + bg.offY / 100 * frame.height, w, h);
        canvas.save();
        canvas.clipRect(frame);
        canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.high);
        canvas.restore();
      }
    }
  }
  final paint = Paint()..filterQuality = FilterQuality.high..isAntiAlias = true;
  for (final slot in c.slots) {
    final part = c.part(choice.slots[slot.id]);
    final place = part?.places[choice.gender];
    final im = part == null ? null : images[part.url];
    if (part == null || place == null || im == null) continue;
    final r = partRect(part, place);
    canvas.save();
    if (place.r != 0) {
      canvas.translate(place.x, place.y);
      canvas.rotate(place.r * math.pi / 180);
      canvas.translate(-place.x, -place.y);
    }
    canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), r, paint);
    canvas.restore();
  }
  canvas.restore();
}

class AvatarPainter extends CustomPainter {
  final AvatarCatalog catalog;
  final AvatarChoice choice;
  final Map<String, ui.Image> images;
  final int revision; // grows when another picture arrives, so the preview repaints
  AvatarPainter(this.catalog, this.choice, this.images, this.revision);

  @override
  void paint(Canvas canvas, Size size) => paintAvatar(canvas, size, catalog, choice, images);

  @override
  bool shouldRepaint(AvatarPainter old) => old.choice != choice || old.revision != revision || old.catalog != catalog;
}

/// The finished picture, a square PNG (the frame of the canvas), ready to send to the server.
Future<Uint8List> renderAvatarPng(AvatarCatalog c, AvatarChoice choice, Map<String, ui.Image> images, {int px = 512}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  paintAvatar(canvas, Size(px.toDouble(), px.toDouble()), c, choice, images);
  final im = await rec.endRecording().toImage(px, px);
  final data = await im.toByteData(format: ui.ImageByteFormat.png);
  im.dispose();
  return data!.buffer.asUint8List();
}
