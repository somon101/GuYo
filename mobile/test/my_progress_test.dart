import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/my_progress.dart';
import 'package:guyo_app/screens/my_progress_screen.dart';

MyProgress _data() => MyProgress.fromJson({
      'total_words': 120,
      'total_active_days': 41,
      'weeks': [
        for (var i = 0; i < 12; i++)
          {
            'week_start': DateTime(2026, 8, 3).add(Duration(days: 7 * i)).toIso8601String().substring(0, 10),
            'words': i == 11 ? 14 : i,
            'active_days': 3,
          },
      ],
    });

void main() {
  test('this week and last week', () {
    final p = _data();
    expect(p.thisWeek, 14);
    expect(p.lastWeek, 10);
  });

  testWidgets('shows totals, the comparison and the chart', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MyProgressScreen(initial: _data())));
    await tester.pump();
    expect(find.text('120'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('слов на этой неделе, на 4 больше прошлой'), findsOneWidget);
    expect(find.byKey(const ValueKey('progress-chart')), findsOneWidget);
  });
}
