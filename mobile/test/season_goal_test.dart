// «Цель сезона» on the team screen: a road to the reward with milestones, how far the team has come,
// how much is left, and the claim button only when there is something to claim.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/team.dart';
import 'package:guyo_app/screens/team_screen.dart';

Map<String, dynamic> season({int progress = 120, bool claimable = false, bool claimed = false}) => {
      'id': 's',
      'scope': 'season',
      'metric': 'streak',
      'target': 300,
      'progress': progress,
      'xp': 200,
      'reward': {'type': 'chest', 'amount': 1, 'key': 'gold', 'text': 'Сундук'},
      'claimed': claimed,
      'claimable': claimable,
    };

TeamState state(Map<String, dynamic> seasonGoal) => TeamState.fromJson({
      'capacity': 5,
      'invites': [],
      'team': {
        'id': 1,
        'name': 'Словарный взвод',
        'is_open': true,
        'is_owner': true,
        'members': [
          {'user_id': 1, 'login': 'Demo', 'avatar_url': null, 'is_owner': true, 'week_xp': 120, 'badge': null},
        ],
        'week': {'starts_on': '2026-10-19', 'ends_at': '2026-10-25T19:00:00Z', 'goals': []},
        'season_goal': seasonGoal,
      },
    });

Future<void> open(WidgetTester t, TeamState s) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: TeamScreen(key: UniqueKey(), initial: s)));
  await t.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);

  testWidgets('the road: the goal, milestones at a third and two thirds, progress and what is left', (t) async {
    await open(t, state(season()));
    expect(find.byKey(const ValueKey('season-goal')), findsOneWidget);
    expect(find.text('Цель сезона'), findsOneWidget);
    expect(find.text('Вместе набрать дней серии: 300'), findsOneWidget);
    expect(find.text('100'), findsOneWidget, reason: 'the first milestone');
    expect(find.text('200'), findsOneWidget, reason: 'the second milestone');
    expect(find.text('120 из 300'), findsOneWidget);
    expect(find.text('до награды: 180'), findsOneWidget);
    expect(find.byKey(const ValueKey('season-claim')), findsNothing, reason: 'nothing to claim yet');
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('a reached goal can be claimed; a claimed one says so and has no button', (t) async {
    await open(t, state(season(progress: 300, claimable: true)));
    expect(find.byKey(const ValueKey('season-claim')), findsOneWidget);
    expect(find.text('до награды: 0'), findsOneWidget);
    await open(t, state(season(progress: 300, claimed: true)));
    expect(find.byKey(const ValueKey('season-claim')), findsNothing);
    expect(find.text('Получено'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 2));
  });
}
