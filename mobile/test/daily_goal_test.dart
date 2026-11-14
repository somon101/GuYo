// The daily-goal card: progress text, the done state and the model.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/daily_goal.dart';
import 'package:guyo_app/widgets/daily_goal_card.dart';

void main() {
  readyTest();
  test('parses the goal', () {
    final g = DailyGoal.fromJson({'goal': 10, 'done': 4, 'completed': false, 'just_completed': false, 'xp': 0, 'options': [5, 10, 20]});
    expect(g.done, 4);
    expect(g.options, [5, 10, 20]);
  });

  testWidgets('shows progress, then the done state', (tester) async {
    Future<void> show(DailyGoal g) => tester.pumpWidget(MaterialApp(home: Scaffold(body: DailyGoalCardView(goal: g, onTap: () {}))));
    await show(const DailyGoal(goal: 10, done: 4, completed: false));
    expect(find.text('4 из 10 слов'), findsOneWidget);
    await show(const DailyGoal(goal: 10, done: 12, completed: true));
    expect(find.text('Награда получена'), findsOneWidget);
    expect(find.text('Новая цель появится завтра'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}

void readyTest() {
  testWidgets('the card stays while the reward waits and leaves once it is taken', (tester) async {
    Future<void> show(DailyGoal g) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DailyGoalCard(key: UniqueKey(), initialGoal: g)))));
      await tester.pump(const Duration(milliseconds: 400));
    }

    // In progress: the card is there.
    await show(const DailyGoal(goal: 10, done: 4, completed: false));
    expect(find.byKey(const ValueKey('goal-card')), findsOneWidget);
    // Finished, reward waiting: still there, with «Получить».
    await show(DailyGoal.fromJson({'goal': 10, 'done': 10, 'completed': true, 'locked': true, 'reward_ready': true, 'claim_id': 5, 'options': [5, 10], 'tiers': <Object>[]}));
    expect(find.byKey(const ValueKey('goal-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-claim')), findsOneWidget);
    // Finished and taken: nothing is drawn.
    await show(const DailyGoal(goal: 10, done: 12, completed: true));
    expect(find.byKey(const ValueKey('goal-card')), findsNothing);
    expect(find.text('Награда получена'), findsNothing);
  });

  testWidgets('the goal sheet: pick a row, then «Выбрать цель» returns it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200); // a phone: the whole sheet fits
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    int? chosen;
    final goal = DailyGoal.fromJson({'goal': 10, 'done': 3, 'completed': false, 'options': [5, 10, 20]});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => chosen = await showModalBottomSheet<int>(context: context, isScrollControlled: true, builder: (_) => DailyGoalSheet(goal: goal)),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daily-goal-20')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('daily-goal-choose')));
    await tester.pumpAndSettle();
    expect(chosen, 20);
  });

  testWidgets('a filled goal shows the gift mark and «Получить»; nothing is paid by itself', (tester) async {
    var claims = 0;
    final goal = DailyGoal.fromJson({
      'goal': 10, 'done': 10, 'completed': true, 'locked': true, 'reward_ready': true, 'claim_id': 5,
      'options': [5, 10],
      'tiers': [
        {'words': 10, 'rewards': [{'type': 'xp', 'amount': 15}, {'type': 'chest', 'key': 'wood', 'amount': 1}], 'claimed': false},
      ],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: DailyGoalCardView(goal: goal, onTap: null, onClaim: () => claims++)))));
    expect(find.text('Выполнена! Заберите награду'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-claim')));
    expect(claims, 1);
  });
}
