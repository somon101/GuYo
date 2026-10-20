import 'season_pass.dart';

/// Teams -- mirrors the backend's MyTeamOut (GET /teams/me).
class TeamMember {
  final int userId;
  final String login;
  final String? avatarUrl;
  final bool isOwner;
  final int weekXp;
  final String? badge;

  const TeamMember({
    required this.userId,
    required this.login,
    this.avatarUrl,
    required this.isOwner,
    required this.weekXp,
    this.badge,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        userId: json['user_id'] as int,
        login: json['login'] as String,
        avatarUrl: json['avatar_url'] as String?,
        isOwner: json['is_owner'] as bool,
        weekXp: json['week_xp'] as int,
        badge: json['badge'] as String?,
      );
}

class TeamGoal {
  final String id;
  final String scope; // week | season
  final String metric;
  final int target;
  final int progress;
  final int xp;
  final PassReward? reward;
  final bool claimed;
  final bool claimable;

  const TeamGoal({
    required this.id,
    required this.scope,
    required this.metric,
    required this.target,
    required this.progress,
    required this.xp,
    this.reward,
    required this.claimed,
    required this.claimable,
  });

  factory TeamGoal.fromJson(Map<String, dynamic> json) {
    final r = json['reward'] as Map<String, dynamic>?;
    return TeamGoal(
      id: json['id'] as String,
      scope: json['scope'] as String,
      metric: json['metric'] as String,
      target: json['target'] as int,
      progress: json['progress'] as int,
      xp: json['xp'] as int,
      reward: r == null
          ? null
          : PassReward(
              type: r['type'] as String,
              amount: (r['amount'] as int?) ?? 1,
              key: r['key'] as String?,
              text: r['text'] as String?,
              claimed: false,
              claimable: false,
              lockedByPremium: false,
            ),
      claimed: json['claimed'] as bool,
      claimable: json['claimable'] as bool,
    );
  }
}

class Team {
  final int id;
  final String name;
  final bool isOpen;
  final bool isOwner;
  final List<TeamMember> members;
  final DateTime? weekEndsAt;
  final List<TeamGoal> weekGoals;
  final TeamGoal? seasonGoal;

  const Team({
    required this.id,
    required this.name,
    required this.isOpen,
    required this.isOwner,
    required this.members,
    this.weekEndsAt,
    required this.weekGoals,
    this.seasonGoal,
  });

  int get claimableCount => weekGoals.where((g) => g.claimable).length + ((seasonGoal?.claimable ?? false) ? 1 : 0);

  factory Team.fromJson(Map<String, dynamic> json) {
    final week = json['week'] as Map<String, dynamic>?;
    final sg = json['season_goal'] as Map<String, dynamic>?;
    return Team(
      id: json['id'] as int,
      name: json['name'] as String,
      isOpen: json['is_open'] as bool,
      isOwner: json['is_owner'] as bool,
      members: (json['members'] as List<dynamic>).map((e) => TeamMember.fromJson(e as Map<String, dynamic>)).toList(),
      weekEndsAt: week == null ? null : DateTime.parse(week['ends_at'] as String).toLocal(),
      weekGoals: week == null
          ? const []
          : (week['goals'] as List<dynamic>).map((e) => TeamGoal.fromJson(e as Map<String, dynamic>)).toList(),
      seasonGoal: sg == null ? null : TeamGoal.fromJson(sg),
    );
  }
}

class TeamInvite {
  final int teamId;
  final String teamName;
  final String fromLogin;
  const TeamInvite({required this.teamId, required this.teamName, required this.fromLogin});

  factory TeamInvite.fromJson(Map<String, dynamic> json) => TeamInvite(
        teamId: json['team_id'] as int,
        teamName: json['team_name'] as String,
        fromLogin: json['from_login'] as String,
      );
}

class TeamState {
  final Team? team;
  final List<TeamInvite> invites;
  final int capacity;
  const TeamState({this.team, this.invites = const [], this.capacity = 5});

  factory TeamState.fromJson(Map<String, dynamic> json) => TeamState(
        team: json['team'] == null ? null : Team.fromJson(json['team'] as Map<String, dynamic>),
        invites: (json['invites'] as List<dynamic>).map((e) => TeamInvite.fromJson(e as Map<String, dynamic>)).toList(),
        capacity: (json['capacity'] as int?) ?? 5,
      );
}

class OpenTeam {
  final int id;
  final String name;
  final int members;
  final int capacity;
  const OpenTeam({required this.id, required this.name, required this.members, required this.capacity});

  factory OpenTeam.fromJson(Map<String, dynamic> json) => OpenTeam(
        id: json['id'] as int,
        name: json['name'] as String,
        members: json['members'] as int,
        capacity: json['capacity'] as int,
      );
}
