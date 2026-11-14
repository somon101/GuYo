// The season pass model: what is waiting to be claimed, parsed from the
// server's JSON.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/widgets/gift_badge.dart';
import 'package:guyo_app/widgets/season_pass_ui.dart';
import 'package:guyo_app/widgets/season_pass_card.dart';
import 'package:guyo_app/models/season_pass.dart';
import 'package:guyo_app/screens/season_pass_screen.dart';

Map<String, dynamic> _json() => {
      'season_id': 1,
      'season_name': 'Октябрь 2026',
      'season_name_tg': 'Октябр 2026',
      'season_name_uz': null,
      'starts_at': '2026-09-30T19:00:00Z',
      'ends_at': '2026-10-31T19:00:00Z',
      'xp': 90,
      'level': 1,
      'xp_into_level': 10,
      'xp_for_next': 80,
      'is_premium': false,
      'premium_enabled': true,
      'levels': [
        {
          'level': 1,
          'xp': 80,
          'free': {'type': 'rating_points', 'amount': 20, 'claimed': false, 'claimable': true, 'locked_by_premium': false},
          'premium': {'type': 'rating_points', 'amount': 50, 'claimed': false, 'claimable': false, 'locked_by_premium': true},
        },
        {'level': 2, 'xp': 80, 'free': null, 'premium': null},
      ],
      'week': {
        'starts_on': '2026-10-19',
        'ends_at': '2026-10-25T19:00:00Z',
        'tasks': [
          {'id': 'words', 'metric': 'word', 'target': 5, 'xp': 50, 'progress': 5, 'claimed': false, 'claimable': true},
          {'id': 'quests', 'metric': 'quest', 'target': 3, 'xp': 40, 'progress': 1, 'claimed': false, 'claimable': false},
        ],
      },
    };

void main() {
  passScreenTests();
  test('parses the pass and counts what is waiting to be claimed', () {
    final pass = SeasonPass.fromJson(_json());
    expect(pass.level, 1);
    expect(pass.levels.length, 2);
    expect(pass.levels[0].premium!.lockedByPremium, isTrue);
    expect(pass.levels[1].free, isNull);
    // One level reward and one finished weekly task.
    expect(pass.claimableCount, 2);
  });

  test('the top of the ladder has no next level', () {
    final json = _json()..['xp_for_next'] = null;
    expect(SeasonPass.fromJson(json).xpForNext, isNull);
  });

  testWidgets('a waiting reward is shown by the small gift, not a yellow pill', (tester) async {
    final pass = SeasonPass.fromJson(_json());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: SeasonPassCardView(pass: pass, onTap: () {})))));
    await tester.pump();
    expect(find.byType(GiftBadge), findsOneWidget);
    expect(find.byIcon(Icons.card_giftcard_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('«Забрать всё»: the summary adds the same kind up, one tile each', (tester) async {
    PassReward diamonds(int n) => PassReward(type: 'diamonds', amount: n, claimed: true, claimable: false, lockedByPremium: false);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => showClaimAllSummary(context, [diamonds(10), diamonds(10), diamonds(25)], 40), child: const Text('go'))))),
    ));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('claim-all-tile')), findsNWidgets(2)); // diamonds (all added up) and energy
    expect(find.text('+45'), findsOneWidget);
    expect(find.text('+40'), findsOneWidget);
  });
}

void passScreenTests() {
  testWidgets('the pass screen (variant B): hero, two link buttons, the main prize and a strip of rewards', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final json = _json()
      ..['level'] = 1
      ..['levels'] = [
        {
          'level': 1,
          'xp': 80,
          'free': {'type': 'rating_points', 'amount': 20, 'claimed': false, 'claimable': true, 'locked_by_premium': false},
          'premium': {'type': 'chest', 'amount': 1, 'key': 'silver', 'claimed': false, 'claimable': true, 'locked_by_premium': false},
        },
        {
          'level': 2,
          'xp': 160,
          'free': {'type': 'chest', 'amount': 1, 'key': 'gold', 'claimed': false, 'claimable': false, 'locked_by_premium': false},
          'premium': {'type': 'diamonds', 'amount': 5, 'claimed': false, 'claimable': false, 'locked_by_premium': true},
        },
      ];
    await tester.pumpWidget(MaterialApp(home: SeasonPassScreen(initialPass: SeasonPass.fromJson(json))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Уровень 1'), findsWidgets);
    expect(find.byKey(const ValueKey('pass-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('pass-cosmetics')), findsOneWidget);
    expect(find.text('Главная награда сезона · Уровень 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('pass-strip')), findsOneWidget);
    expect(find.byType(PassTile), findsNWidgets(4));
    // Two level rewards and one finished weekly task wait: «Забрать всё» is offered.
    expect(find.byKey(const ValueKey('claim-all')), findsOneWidget);
    expect(find.byIcon(Icons.insights_rounded), findsOneWidget); // the link button, no longer in the top bar
    expect(tester.takeException(), isNull);
  });
}
