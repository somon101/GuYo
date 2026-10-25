// The daily-goal card: progress text, the done state and the model.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/daily_goal.dart';
import 'package:guyo_app/widgets/daily_goal_card.dart';

void main() {
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
    expect(find.text('Выполнена! Новую цель выберете завтра'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
