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
  const BankChest({required this.id, required this.chestKey, required this.source});
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
  final String kind; // diamonds | freeze | merge | points
  final int amount;
  const ChestPrize({required this.chestKey, required this.kind, required this.amount});
}

/// The bank and the chest of the day (GET /chests).
class ChestBank {
  final List<ChestType> types;
  final List<BankChest> chests;
  final DailyChest daily;
  final bool doubleRewards;
  final int inventoryMax;

  const ChestBank({
    required this.types,
    required this.chests,
    required this.daily,
    this.doubleRewards = false,
    this.inventoryMax = 10,
  });

  factory ChestBank.fromJson(Map<String, dynamic> json) {
    final d = json['daily'] as Map<String, dynamic>;
    return ChestBank(
      types: [for (final t in json['types'] as List<dynamic>) ChestType.fromJson(t as Map<String, dynamic>)],
      chests: [
        for (final c in json['chests'] as List<dynamic>)
          BankChest(id: c['id'] as int, chestKey: c['chest_key'] as String, source: c['source'] as String),
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
    );
  }

  ChestType? type(String key) {
    for (final t in types) {
      if (t.key == key) return t;
    }
    return null;
  }
}
