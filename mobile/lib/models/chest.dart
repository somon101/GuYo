/// The chest of the day (GET /chest).
class ChestState {
  final bool enabled;
  final bool available;
  final String? kind; // xp | freeze (once opened)
  final int amount;

  const ChestState({required this.enabled, required this.available, this.kind, this.amount = 0});

  factory ChestState.fromJson(Map<String, dynamic> json) {
    final opened = json['opened'] as Map<String, dynamic>?;
    return ChestState(
      enabled: json['enabled'] as bool,
      available: json['available'] as bool,
      kind: opened?['kind'] as String?,
      amount: (opened?['amount'] as int?) ?? 0,
    );
  }

  bool get opened => kind != null;
}
