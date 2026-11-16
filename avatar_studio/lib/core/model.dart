// Модель проекта и его JSON (формат avatar-studio/1).
import 'dart:math';
import 'geometry.dart';

final _rnd = Random();
String uid() => List.generate(8, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rnd.nextInt(36)]).join();

/// Деталь слота: картинка (kind 'img') или цвет/градиент фона (kind 'solid' / 'grad').
class Part {
  String id, name, kind;
  double w, h;
  String? blobId, origId;
  double? origW, origH;
  String? c1, c2;
  Part({required this.id, required this.name, this.kind = 'img', this.w = 0, this.h = 0, this.blobId, this.origId, this.origW, this.origH, this.c1, this.c2});
  bool get isImage => kind == 'img';
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'kind': kind, 'w': w, 'h': h,
        if (blobId != null) 'blobId': blobId,
        if (origId != null) 'origId': origId,
        if (origW != null) 'origW': origW,
        if (origH != null) 'origH': origH,
        if (c1 != null) 'c1': c1,
        if (c2 != null) 'c2': c2,
      };
  factory Part.fromJson(Map j) => Part(
        id: j['id'] as String? ?? uid(),
        name: j['name'] as String? ?? 'Деталь',
        kind: j['kind'] as String? ?? 'img',
        w: (j['w'] as num?)?.toDouble() ?? 0,
        h: (j['h'] as num?)?.toDouble() ?? 0,
        blobId: j['blobId'] as String?,
        origId: j['origId'] as String?,
        origW: (j['origW'] as num?)?.toDouble(),
        origH: (j['origH'] as num?)?.toDouble(),
        c1: j['c1'] as String?,
        c2: j['c2'] as String?,
      );
}

class SlotDef {
  String id, name;
  bool custom;
  SlotDef(this.id, this.name, {this.custom = false});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'custom': custom};
}

class FrameState {
  String mode, shape; // mode: head, bust, full, custom; shape: circle, round
  double x, y, size;
  FrameState({this.mode = 'head', this.x = 600, this.y = 560, this.size = 760, this.shape = 'circle'});
  FrameState copy() => FrameState(mode: mode, x: x, y: y, size: size, shape: shape);
  Map<String, dynamic> toJson() => {'mode': mode, 'x': x, 'y': y, 'size': size, 'shape': shape};
  factory FrameState.fromJson(Map j) => FrameState(
        mode: j['mode'] as String? ?? 'head',
        x: (j['x'] as num?)?.toDouble() ?? 600,
        y: (j['y'] as num?)?.toDouble() ?? 560,
        size: (j['size'] as num?)?.toDouble() ?? 760,
        shape: j['shape'] as String? ?? 'circle',
      );
}

class StudioSet {
  String id, name;
  Map<String, List<Part>> parts;
  Map<String, String> pick;
  Map<String, Geo> geo;
  StudioSet({required this.id, required this.name, Map<String, List<Part>>? parts, Map<String, String>? pick, Map<String, Geo>? geo})
      : parts = parts ?? {}, pick = pick ?? {}, geo = geo ?? {};
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name,
        'parts': parts.map((k, v) => MapEntry(k, v.map((p) => p.toJson()).toList())),
        'pick': pick,
        'geo': geo.map((k, v) => MapEntry(k, v.toJson())),
      };
  factory StudioSet.fromJson(Map j) => StudioSet(
        id: j['id'] as String? ?? uid(),
        name: j['name'] as String? ?? 'Набор',
        parts: ((j['parts'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, (v as List).map((p) => Part.fromJson(p as Map)).toList())),
        pick: ((j['pick'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, v as String)),
        geo: ((j['geo'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, Geo.fromJson(v as Map))),
      );
}

/// Сохранённая аватарка: набор, выбранные детали, скрытые слоты и кадр.
class Look {
  String id, name, set;
  Map<String, String> pick;
  List<String> hide;
  FrameState frame;
  Look({required this.id, required this.name, required this.set, required this.pick, required this.hide, required this.frame});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'set': set, 'pick': pick, 'hide': hide, 'frame': frame.toJson()};
  factory Look.fromJson(Map j) => Look(
        id: j['id'] as String? ?? uid(),
        name: j['name'] as String? ?? 'Аватарка',
        set: j['set'] as String? ?? '',
        pick: ((j['pick'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, v as String)),
        hide: ((j['hide'] as List?) ?? []).map((e) => e as String).toList(),
        frame: FrameState.fromJson((j['frame'] as Map?) ?? {}),
      );
}

class Settings {
  String removeMode; // ask, cut, keep: что делать с фоном при загрузке
  String theme; // system, light, dark
  int tol;
  Settings({this.removeMode = 'ask', this.theme = 'system', this.tol = 16});
  Map<String, dynamic> toJson() => {'removeMode': removeMode, 'theme': theme, 'tol': tol};
  factory Settings.fromJson(Map j) => Settings(removeMode: j['removeMode'] as String? ?? 'ask', theme: j['theme'] as String? ?? 'system', tol: (j['tol'] as num?)?.toInt() ?? 16);
}

class ProjectState {
  List<SlotDef> slots;
  List<String> order;
  Map<String, Geo> geo;
  List<StudioSet> sets;
  String cur, sel;
  FrameState frame;
  List<Look> looks;
  Settings settings;
  ProjectState({required this.slots, required this.order, required this.geo, required this.sets, required this.cur, required this.sel, required this.frame, required this.looks, required this.settings});

  factory ProjectState.fresh() => ProjectState(
        slots: [for (final b in baseSlots) SlotDef(b.id, b.name)],
        order: [for (final b in baseSlots) b.id],
        geo: {for (final b in baseSlots) b.id: Geo.fromBase(b)},
        sets: [StudioSet(id: 's1', name: 'Набор 1')],
        cur: 's1',
        sel: 'face',
        frame: FrameState(),
        looks: [],
        settings: Settings(),
      );

  Map<String, dynamic> toJson() => {
        'format': projectFormat,
        'slots': slots.map((s) => s.toJson()).toList(),
        'order': order,
        'geo': geo.map((k, v) => MapEntry(k, v.toJson())),
        'sets': sets.map((s) => s.toJson()).toList(),
        'cur': cur,
        'sel': sel,
        'frame': frame.toJson(),
        'looks': looks.map((l) => l.toJson()).toList(),
        'settings': settings.toJson(),
      };

  /// Разбор проекта из JSON с починкой порядка слотов и ссылок. Бросает FormatException на чужом файле.
  factory ProjectState.migrate(dynamic raw) {
    if (raw is! Map) throw const FormatException('Это не проект студии аватаров');
    if (raw['format'] != projectFormat) throw const FormatException('Неизвестный формат файла');
    final base = ProjectState.fresh();
    final slots = ((raw['slots'] as List?) ?? []).map((s) => SlotDef((s as Map)['id'] as String, s['name'] as String? ?? 'Слот', custom: s['custom'] == true)).toList();
    final st = ProjectState(
      slots: slots.isEmpty ? base.slots : slots,
      order: ((raw['order'] as List?) ?? []).map((e) => e as String).toList(),
      geo: ((raw['geo'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, Geo.fromJson(v as Map))),
      sets: ((raw['sets'] as List?) ?? []).map((s) => StudioSet.fromJson(s as Map)).toList(),
      cur: raw['cur'] as String? ?? '',
      sel: raw['sel'] as String? ?? '',
      frame: FrameState.fromJson((raw['frame'] as Map?) ?? {}),
      looks: ((raw['looks'] as List?) ?? []).map((l) => Look.fromJson(l as Map)).toList(),
      settings: Settings.fromJson((raw['settings'] as Map?) ?? {}),
    );
    final ids = st.slots.map((s) => s.id).toSet();
    st.order = st.order.where(ids.contains).toList();
    for (final s in st.slots) {
      if (!st.order.contains(s.id)) st.order.add(s.id);
      st.geo.putIfAbsent(s.id, () => baseSlot(s.id) != null ? Geo.fromBase(baseSlot(s.id)!) : Geo(x: 600, y: 700));
    }
    if (st.sets.isEmpty) st.sets = base.sets;
    if (!st.sets.any((s) => s.id == st.cur)) st.cur = st.sets.first.id;
    if (!ids.contains(st.sel)) st.sel = st.slots.first.id;
    return st;
  }
}
