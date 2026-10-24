import 'reward_spec.dart';

/// A weekly friend duel (GET /duels).
class Duel {
  final int id;
  final String status; // pending | active | finished
  final DateTime endsAt;
  final bool iChallenged;
  final int opponentId;
  final String opponentLogin;
  final String? opponentAvatarUrl;
  final int myXp;
  final int theirXp;
  final bool? won;

  const Duel({
    required this.id,
    required this.status,
    required this.endsAt,
    required this.iChallenged,
    required this.opponentId,
    required this.opponentLogin,
    this.opponentAvatarUrl,
    required this.myXp,
    required this.theirXp,
    this.won,
  });

  factory Duel.fromJson(Map<String, dynamic> json) => Duel(
    id: json['id'] as int,
    status: json['status'] as String,
    endsAt: DateTime.parse(json['ends_at'] as String),
    iChallenged: json['i_challenged'] as bool,
    opponentId: json['opponent_id'] as int,
    opponentLogin: json['opponent_login'] as String,
    opponentAvatarUrl: json['opponent_avatar_url'] as String?,
    myXp: json['my_xp'] as int,
    theirXp: json['their_xp'] as int,
    won: json['won'] as bool?,
  );

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get incoming => isPending && !iChallenged;
}

class DuelState {
  final bool enabled;
  final Map<String, List<RewardSpec>> rewards; // win | draw | lose
  final Duel? current;
  final List<Duel> recent;
  const DuelState({
    required this.enabled,
    this.rewards = const {},
    this.current,
    this.recent = const [],
  });

  factory DuelState.fromJson(Map<String, dynamic> json) => DuelState(
    enabled: json['enabled'] as bool,
    rewards: {
      for (final e in ((json['rewards'] as Map<String, dynamic>?) ?? const {}).entries) e.key: RewardSpec.list(e.value),
    },
    current: json['current'] == null
        ? null
        : Duel.fromJson(json['current'] as Map<String, dynamic>),
    recent: (json['recent'] as List<dynamic>)
        .map((e) => Duel.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
