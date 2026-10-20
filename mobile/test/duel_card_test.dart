import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/duel.dart';
import 'package:guyo_app/widgets/duel_card.dart';

Map<String, dynamic> _duel(String status, {bool mine = true, int my = 0, int their = 0}) => {
      'id': 1,
      'status': status,
      'week_start': '2026-10-19',
      'ends_at': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
      'i_challenged': mine,
      'opponent_id': 2,
      'opponent_login': 'Rustam',
      'my_xp': my,
      'their_xp': their,
      'won': null,
    };

Future<void> _show(WidgetTester tester, Map<String, dynamic> json, {List<String>? log}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DuelCardView(
        state: DuelState.fromJson({'enabled': true, 'current': json['id'] == null ? null : json, 'recent': []}),
        onChallenge: () => log?.add('challenge'),
        onAccept: (_) => log?.add('accept'),
        onDecline: (_) => log?.add('decline'),
      ),
    ),
  ));
}

void main() {
  testWidgets('no duel: offers to challenge a friend', (tester) async {
    final log = <String>[];
    await _show(tester, {'id': null}, log: log);
    await tester.tap(find.byKey(const ValueKey('duel-challenge')));
    expect(log, ['challenge']);
  });

  testWidgets('an incoming challenge can be accepted or declined', (tester) async {
    final log = <String>[];
    await _show(tester, _duel('pending', mine: false), log: log);
    expect(find.text('Rustam вызывает вас на дуэль'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duel-accept')));
    await tester.tap(find.byKey(const ValueKey('duel-decline')));
    expect(log, ['accept', 'decline']);
  });

  testWidgets('a running duel shows both scores', (tester) async {
    await _show(tester, _duel('active', my: 40, their: 25));
    expect(find.text('40'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('Rustam'), findsOneWidget);
  });
}
