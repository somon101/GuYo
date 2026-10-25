/// One of the four chests (GET /chests → types).
class ChestType {
  final String key;
  final String name;
  final int color;

  const ChestType({required this.key, required this.name, required this.color});

  factory ChestType.fromJson(Map<String, dynamic> json) => ChestType(
    key: json['key'] as String,
    name: json['name'] as String,
    color: int.parse((json['color'] as String).substring(1), radix: 16) | 0xFF000000,
  );
}

/// An unopened chest in the person's bank.
class BankChest {
  final int id;
  final String chestKey;
  final String source;

  /// What is inside, decided by the server and sealed until the chest is opened.
  /// Known prizes let the app open the chest at once, with no network.
  final String? prizeKind;
  final int? prizeAmount;
  const BankChest({required this.id, required this.chestKey, required this.source, this.prizeKind, this.prizeAmount});

  bool get hasPrize => prizeKind != null && prizeAmount != null;
}

/// The chest of the day: which chest, why it is given, and whether it can be taken now.
class DailyChest {
  final bool enabled;
  final bool available;
  final bool claimed;
  final String chestKey;
  final String conditions;
  const DailyChest({
    required this.enabled,
    required this.available,
    required this.claimed,
    required this.chestKey,
    required this.conditions,
  });
}

/// What an opened chest gave.
class ChestPrize {
  final String chestKey;
  final String kind; // diamonds | freeze | merge | points | booster
  final int amount; // already doubled when [doubled]
  final bool doubled;
  const ChestPrize({required this.chestKey, required this.kind, required this.amount, this.doubled = false});

  /// What it would have been without the "x2" ticket.
  int get baseAmount => doubled ? amount ~/ 2 : amount;
}

/// The "x2" tickets a person holds and whether one is running now.
class BoosterState {
  final Map<int, int> items; // minutes -> how many
  final DateTime? activeUntil;
  const BoosterState({required this.items, this.activeUntil});

  factory BoosterState.fromJson(Map<String, dynamic> json) => BoosterState(
        items: {for (final i in json['items'] as List<dynamic>) i['minutes'] as int: i['qty'] as int},
        activeUntil: json['active_until'] == null ? null : DateTime.parse(json['active_until'] as String).toLocal(),
      );

  bool get running => activeUntil != null && activeUntil!.isAfter(DateTime.now());
  int get total => items.values.fold(0, (a, b) => a + b);
}

/// The bank and the chest of the day (GET /chests).
class ChestBank {
  final List<ChestType> types;
  final List<BankChest> chests;
  final DailyChest daily;
  final bool doubleRewards;
  final int inventoryMax;

  /// A running "x2" ticket ends here (doubles prizes of chests opened before it), and how many are held.
  final DateTime? boosterUntil;
  final int boosterQty;

  bool get boosterRunning => boosterUntil != null && boosterUntil!.isAfter(DateTime.now());

  const ChestBank({
    required this.types,
    required this.chests,
    required this.daily,
    this.doubleRewards = false,
    this.inventoryMax = 10,
    this.boosterUntil,
    this.boosterQty = 0,
  });

  factory ChestBank.fromJson(Map<String, dynamic> json) {
    final d = json['daily'] as Map<String, dynamic>;
    return ChestBank(
      types: [for (final t in json['types'] as List<dynamic>) ChestType.fromJson(t as Map<String, dynamic>)],
      chests: [
        for (final c in json['chests'] as List<dynamic>)
          BankChest(
            id: c['id'] as int,
            chestKey: c['chest_key'] as String,
            source: c['source'] as String,
            prizeKind: c['prize_kind'] as String?,
            prizeAmount: c['prize_amount'] as int?,
          ),
      ],
      daily: DailyChest(
        enabled: d['enabled'] as bool,
        available: d['available'] as bool,
        claimed: d['claimed'] as bool,
        chestKey: d['chest_key'] as String,
        conditions: (d['conditions'] as String?) ?? '',
      ),
      doubleRewards: (json['double'] as bool?) ?? false,
      inventoryMax: (json['inventory_max'] as int?) ?? 10,
      boosterUntil: json['booster_until'] == null ? null : DateTime.parse(json['booster_until'] as String).toLocal(),
      boosterQty: (json['booster_qty'] as int?) ?? 0,
    );
  }

  /// The same bank without the given chests (already opened on this phone).
  ChestBank without(Set<int> ids) => ChestBank(
        types: types,
        chests: [for (final c in chests) if (!ids.contains(c.id)) c],
        daily: daily,
        doubleRewards: doubleRewards,
        inventoryMax: inventoryMax,
        boosterUntil: boosterUntil,
        boosterQty: boosterQty,
      );

  ChestType? type(String key) {
    for (final t in types) {
      if (t.key == key) return t;
    }
    return null;
  }
}
