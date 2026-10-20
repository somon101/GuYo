// The team model: parsing the server's answer and counting what waits to be claimed.

import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/team.dart';

Map<String, dynamic> goal(String id, {bool claimable = false, bool claimed = false, Map<String, dynamic>? reward}) => {
      'id': id,
      'scope': 'week',
      'metric': 'word',
      'target': 10,
      'progress': 10,
      'xp': 60,
      'reward': reward,
      'claimed': claimed,
      'claimable': claimable,
    };

void main() {
  test('a person with no team still sees their invitations', () {
    final s = TeamState.fromJson({
      'team': null,
      'capacity': 5,
      'invites': [
        {'team_id': 3, 'team_name': 'Орлы', 'from_login': 'Aziz'},
      ],
    });
    expect(s.team, isNull);
    expect(s.invites.single.teamName, 'Орлы');
    expect(s.capacity, 5);
  });

  test('counts the goals waiting to be claimed, week and season together', () {
    final s = TeamState.fromJson({
      'capacity': 5,
      'invites': [],
      'team': {
        'id': 1,
        'name': 'Звёзды',
        'is_open': true,
        'is_owner': true,
        'members': [
          {'user_id': 1, 'login': 'A', 'avatar_url': null, 'is_owner': true, 'week_xp': 10, 'badge': null},
        ],
        'week': {
          'starts_on': '2026-10-19',
          'ends_at': '2026-10-25T19:00:00Z',
          'goals': [goal('a', claimable: true), goal('b'), goal('c', claimed: true)],
        },
        'season_goal': goal('s', claimable: true, reward: {'type': 'badge', 'amount': 1, 'key': 'shield', 'text': 'Чемпион'}),
      },
    });
    expect(s.team!.claimableCount, 2);
    expect(s.team!.seasonGoal!.reward!.key, 'shield');
    expect(s.team!.members.single.isOwner, isTrue);
  });
}
