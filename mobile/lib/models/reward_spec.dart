/// One reward of an event (daily goal tier, duel result): xp | chest | diamonds | rating_points.
class RewardSpec {
  final String type;
  final int amount;
  final String? key;
  const RewardSpec({required this.type, required this.amount, this.key});

  factory RewardSpec.fromJson(Map<String, dynamic> json) =>
      RewardSpec(type: json['type'] as String, amount: (json['amount'] as int?) ?? 1, key: json['key'] as String?);

  static List<RewardSpec> list(dynamic raw) => [
    for (final r in (raw as List<dynamic>? ?? const [])) RewardSpec.fromJson(r as Map<String, dynamic>),
  ];
}
