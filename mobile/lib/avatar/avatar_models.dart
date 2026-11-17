/// The avatar a person builds from parts, instead of uploading a photo.
///
/// Everything here comes from the server (GET /avatar/catalog): the parts the Avatar Studio made, each with
/// its own unique ID and its own saved place for each gender. The person places nothing by hand: a chosen
/// part is drawn exactly where the Studio put it.
library;

class AvatarPlace {
  final double x, y, w, r;

  /// Where `y` points on the part: its top, centre or bottom.
  final String pivot;
  const AvatarPlace({required this.x, required this.y, required this.w, this.r = 0, this.pivot = 'center'});

  factory AvatarPlace.fromJson(Map<String, dynamic> j) => AvatarPlace(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        r: (j['r'] as num?)?.toDouble() ?? 0,
        pivot: j['pivot'] as String? ?? 'center',
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'r': r, 'pivot': pivot};
}

class AvatarPart {
  final String id, slot, gender, setId, name, url;
  final int w, h, version;
  final Map<String, AvatarPlace> places;
  const AvatarPart({required this.id, required this.slot, required this.gender, required this.setId, required this.name, required this.url, required this.w, required this.h, required this.places, required this.version});

  factory AvatarPart.fromJson(Map<String, dynamic> j) => AvatarPart(
        id: j['id'] as String,
        slot: j['slot'] as String,
        gender: j['gender'] as String,
        setId: j['set_id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        url: j['url'] as String,
        w: (j['w'] as num?)?.toInt() ?? 0,
        h: (j['h'] as num?)?.toInt() ?? 0,
        version: (j['v'] as num?)?.toInt() ?? 1,
        places: {for (final e in (j['place'] as Map<String, dynamic>).entries) e.key: AvatarPlace.fromJson(e.value as Map<String, dynamic>)},
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'slot': slot, 'gender': gender, 'set_id': setId, 'name': name, 'url': url, 'w': w, 'h': h, 'v': version,
        'place': {for (final e in places.entries) e.key: e.value.toJson()},
      };

  bool fits(String gender) => places.containsKey(gender);
}

class AvatarBackground {
  final String id, name, kind;
  final String? c1, c2, url;
  final int w, h, version;
  final double offX, offY, zoom;
  const AvatarBackground({required this.id, required this.name, required this.kind, this.c1, this.c2, this.url, this.w = 0, this.h = 0, this.version = 1, this.offX = 0, this.offY = 0, this.zoom = 1});

  factory AvatarBackground.fromJson(Map<String, dynamic> j) {
    final p = j['place'] as Map<String, dynamic>?;
    return AvatarBackground(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      kind: j['kind'] as String,
      c1: j['c1'] as String?,
      c2: j['c2'] as String?,
      url: j['url'] as String?,
      w: (j['w'] as num?)?.toInt() ?? 0,
      h: (j['h'] as num?)?.toInt() ?? 0,
      version: (j['v'] as num?)?.toInt() ?? 1,
      offX: (p?['x'] as num?)?.toDouble() ?? 0,
      offY: (p?['y'] as num?)?.toDouble() ?? 0,
      zoom: (p?['s'] as num?)?.toDouble() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'kind': kind, 'c1': c1, 'c2': c2, 'url': url, 'w': w, 'h': h, 'v': version,
        if (kind == 'img') 'place': {'x': offX, 'y': offY, 's': zoom},
      };
}

class AvatarSlot {
  final String id, name;
  const AvatarSlot(this.id, this.name);
}

class AvatarCatalog {
  final int version;
  final double canvasW, canvasH;

  /// The square of the canvas that becomes the avatar picture (centre x, y and side), and its shape.
  final double frameX, frameY, frameSize;
  final String frameShape;
  final List<AvatarSlot> slots;
  final List<AvatarPart> parts;
  final List<AvatarBackground> backgrounds;
  const AvatarCatalog({required this.version, required this.canvasW, required this.canvasH, required this.frameX, required this.frameY, required this.frameSize, required this.frameShape, required this.slots, required this.parts, required this.backgrounds});

  factory AvatarCatalog.fromJson(Map<String, dynamic> j) {
    final canvas = j['canvas'] as Map<String, dynamic>? ?? const {};
    final frame = j['frame'] as Map<String, dynamic>? ?? const {};
    return AvatarCatalog(
      version: (j['version'] as num).toInt(),
      canvasW: (canvas['w'] as num?)?.toDouble() ?? 1200,
      canvasH: (canvas['h'] as num?)?.toDouble() ?? 1600,
      frameX: (frame['x'] as num?)?.toDouble() ?? 600,
      frameY: (frame['y'] as num?)?.toDouble() ?? 560,
      frameSize: (frame['size'] as num?)?.toDouble() ?? 760,
      frameShape: frame['shape'] as String? ?? 'circle',
      slots: [for (final s in (j['slots'] as List<dynamic>? ?? const [])) AvatarSlot((s as Map)['id'] as String, s['name'] as String? ?? s['id'] as String)],
      parts: [for (final p in (j['items'] as List<dynamic>? ?? const [])) AvatarPart.fromJson(p as Map<String, dynamic>)],
      backgrounds: [for (final b in (j['backgrounds'] as List<dynamic>? ?? const [])) AvatarBackground.fromJson(b as Map<String, dynamic>)],
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'canvas': {'w': canvasW, 'h': canvasH},
        'frame': {'x': frameX, 'y': frameY, 'size': frameSize, 'shape': frameShape},
        'slots': [for (final s in slots) {'id': s.id, 'name': s.name}],
        'items': [for (final p in parts) p.toJson()],
        'backgrounds': [for (final b in backgrounds) b.toJson()],
      };

  /// Slots that have at least one part for this gender, in drawing order.
  List<AvatarSlot> slotsFor(String gender) => [for (final s in slots) if (parts.any((p) => p.slot == s.id && p.fits(gender))) s];

  List<AvatarPart> partsFor(String slot, String gender) => [for (final p in parts) if (p.slot == slot && p.fits(gender)) p];

  AvatarPart? part(String? id) {
    for (final p in parts) {
      if (p.id == id) return p;
    }
    return null;
  }

  AvatarBackground? background(String? id) {
    for (final b in backgrounds) {
      if (b.id == id) return b;
    }
    return null;
  }

  bool get isEmpty => parts.isEmpty;
}

/// What the person picked: gender, one part per slot, a background.
class AvatarChoice {
  final String gender;
  final Map<String, String> slots;
  final String? bg;
  const AvatarChoice({required this.gender, required this.slots, this.bg});

  AvatarChoice withSlot(String slot, String id) => AvatarChoice(gender: gender, slots: {...slots, slot: id}, bg: bg);
  /// Takes the part of a slot off (glasses and other extras are optional).
  AvatarChoice withoutSlot(String slot) => AvatarChoice(gender: gender, slots: {for (final e in slots.entries) if (e.key != slot) e.key: e.value}, bg: bg);
  AvatarChoice withBg(String? id) => AvatarChoice(gender: gender, slots: slots, bg: id);

  Map<String, dynamic> toJson() => {'gender': gender, 'slots': slots, 'bg': bg};

  static AvatarChoice? fromLook(Map<String, dynamic>? look) {
    if (look == null) return null;
    final g = look['gender'] as String?;
    if (g != 'male' && g != 'female') return null;
    return AvatarChoice(
      gender: g!,
      slots: {for (final e in (look['slots'] as Map<String, dynamic>? ?? const {}).entries) e.key: e.value as String},
      bg: look['bg'] as String?,
    );
  }
}
