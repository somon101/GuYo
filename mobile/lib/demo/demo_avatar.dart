import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Made-up avatar parts for the demo build: drawn in code (no files), served by the demo's fake server under
/// /media/demo-avatar/ID.png, so the avatar editor can be tried with no real server and no Studio file.
/// Canvas 1200×1600; the face is centred at (600, 560); every part has its own saved place, like the real ones.

const _skins = [Color(0xFFF2C4A0), Color(0xFFE9B48C), Color(0xFFF6D0B4), Color(0xFFD9A07A)];
const _hairColors = [Color(0xFF8A4B2A), Color(0xFF3B2A20), Color(0xFFC98A4B), Color(0xFF2A2A2E), Color(0xFF6B4A2E), Color(0xFFB5502A), Color(0xFFE0B25A), Color(0xFF5A3420)];
const _clothColors = [Color(0xFF5B78E6), Color(0xFF222222), Color(0xFF4EA36D), Color(0xFFE8E8EF), Color(0xFFE45B6A), Color(0xFFF2B134), Color(0xFF8A5CD6), Color(0xFF3AA7C7)];
const _femaleHair = ['bun', 'long', 'bob', 'ponytail', 'curly', 'bun', 'long', 'bob'];
const _maleHair = ['short', 'quiff', 'curly', 'short', 'quiff', 'curly', 'short', 'quiff'];

/// The catalog JSON the real server would send (same shape as GET /avatar/catalog).
Map<String, dynamic> demoAvatarCatalog() {
  Map<String, dynamic> part(String id, String slot, String gender, String set, double x, double y, double w, int iw, int ih) => {
        'id': id, 'slot': slot, 'gender': gender, 'set_id': set, 'name': id, 'url': '/media/demo-avatar/$id.png', 'w': iw, 'h': ih, 'v': 1,
        'place': {
          if (gender != 'female') 'male': {'x': x, 'y': y, 'w': w, 'r': 0, 'pivot': 'center'},
          if (gender != 'male') 'female': {'x': x, 'y': y, 'w': w, 'r': 0, 'pivot': 'center'},
        },
      };
  final items = <Map<String, dynamic>>[];
  for (var i = 0; i < 8; i++) {
    for (final g in ['female', 'male']) {
      final set = '$g-set${i + 1}';
      items.add(part('$g-cloth-$i', 'cloth', g, set, 600, 1130, 1000, 1000, 700));
      items.add(part('$g-face-$i', 'face', g, set, 600, 560, 600, 600, 600));
      items.add(part('$g-hair-$i', 'hair', g, set, 600, 470, 800, 800, 700));
    }
  }
  final bg = <Map<String, dynamic>>[
    for (final c in ['#FFD0E2', '#CFF1DE', '#FFE6A6', '#D5E4FF', '#E6D9FF']) {'id': 'bg-$c', 'name': c, 'kind': 'solid', 'c1': c, 'v': 1},
    {'id': 'bg-g1', 'name': 'Закат', 'kind': 'grad', 'c1': '#FF9A6A', 'c2': '#FF5C8A', 'v': 1},
    {'id': 'bg-g2', 'name': 'Море', 'kind': 'grad', 'c1': '#8EE0FF', 'c2': '#5A6CF0', 'v': 1},
    {'id': 'bg-g3', 'name': 'Ночь', 'kind': 'grad', 'c1': '#1C2154', 'c2': '#0A0D2A', 'v': 1},
  ];
  return {
    'version': 1,
    'canvas': {'w': 1200, 'h': 1600},
    'frame': {'x': 600, 'y': 560, 'size': 760, 'shape': 'circle'},
    'slots': [
      {'id': 'cloth', 'name': 'Одежда'},
      {'id': 'face', 'name': 'Лицо'},
      {'id': 'hair', 'name': 'Волосы'},
    ],
    'sets': [for (final g in ['female', 'male']) for (var i = 0; i < 8; i++) {'id': '$g-set${i + 1}', 'name': 'Набор ${i + 1}'}],
    'items': items,
    'backgrounds': bg,
  };
}

/// The PNG of one demo part, drawn in code. `id` looks like "female-hair-3".
Future<Uint8List> demoPartPng(String id) async {
  final bits = id.replaceAll('.png', '').split('-');
  final gender = bits[0], slot = bits[1], n = int.tryParse(bits[2]) ?? 0;
  final (w, h) = slot == 'cloth' ? (1000, 700) : (slot == 'face' ? (600, 600) : (800, 700));
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  switch (slot) {
    case 'cloth':
      final col = _clothColors[n % _clothColors.length];
      c.drawPath(Path()..moveTo(60, 700)..lineTo(110, 270)..quadraticBezierTo(130, 60, 330, 30)..lineTo(670, 30)..quadraticBezierTo(870, 60, 890, 270)..lineTo(940, 700)..close(), Paint()..color = col);
      c.drawPath(Path()..moveTo(400, 30)..lineTo(500, 180)..lineTo(600, 30)..close(), Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .85));
    case 'face':
      final skin = _skins[n % _skins.length];
      c.drawCircle(const Offset(300, 300), 290, Paint()..color = skin);
      final eye = Paint()..color = const Color(0xFF2B1D16);
      final wow = n % 3 == 2;
      c.drawOval(Rect.fromCenter(center: const Offset(205, 280), width: 52, height: wow ? 76 : 64), eye);
      c.drawOval(Rect.fromCenter(center: const Offset(395, 280), width: 52, height: wow ? 76 : 64), eye);
      final blush = Paint()..color = const Color(0x99F4A09A);
      c.drawCircle(const Offset(150, 380), 36, blush);
      c.drawCircle(const Offset(450, 380), 36, blush);
      final mouth = Paint()..color = const Color(0xFFB2504A)..style = PaintingStyle.stroke..strokeWidth = 16..strokeCap = StrokeCap.round;
      if (wow) {
        c.drawOval(Rect.fromCenter(center: const Offset(300, 440), width: 60, height: 76), Paint()..color = const Color(0xFFB2504A));
      } else {
        c.drawPath(Path()..moveTo(220, 425)..quadraticBezierTo(300, 510, 380, 425), mouth);
      }
    default:
      final kind = (gender == 'female' ? _femaleHair : _maleHair)[n % 8];
      final col = _hairColors[(n + (gender == 'female' ? 0 : 3)) % _hairColors.length];
      final p = Paint()..color = col;
      // the face circle sits at (400, 440) here, radius 290: hair covers its top, never the eyes
      final cap = Path()
        ..moveTo(70, 470)
        ..arcToPoint(const Offset(730, 470), radius: const Radius.circular(330), clockwise: true)
        ..quadraticBezierTo(660, 300, 400, 290)
        ..quadraticBezierTo(140, 300, 70, 470)
        ..close();
      switch (kind) {
        case 'bun':
          c.drawCircle(const Offset(400, 120), 100, p);
        case 'long':
          c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(40, 420, 130, 280), const Radius.circular(50)), p);
          c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(630, 420, 130, 280), const Radius.circular(50)), p);
        case 'bob':
          c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(40, 420, 120, 190), const Radius.circular(50)), p);
          c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(640, 420, 120, 190), const Radius.circular(50)), p);
        case 'ponytail':
          c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(590, 200, 150, 430), const Radius.circular(70)), p);
        case 'curly':
          for (var i = 0; i < 8; i++) {
            final a = math.pi + i * math.pi / 7;
            c.drawCircle(Offset(400 + 330 * math.cos(a), 440 + 330 * math.sin(a)), 80, p);
          }
        case 'quiff':
          c.drawOval(const Rect.fromLTWH(250, 60, 380, 200), p);
      }
      c.drawPath(cap, p);
  }
  final im = await rec.endRecording().toImage(w, h);
  final data = await im.toByteData(format: ui.ImageByteFormat.png);
  im.dispose();
  return data!.buffer.asUint8List();
}
