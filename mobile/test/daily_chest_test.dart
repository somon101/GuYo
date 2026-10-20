import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/chest.dart';
import 'package:guyo_app/widgets/daily_chest_card.dart';

void main() {
  test('parses an unopened and an opened chest', () {
    final a = ChestState.fromJson({'enabled': true, 'available': true, 'opened': null});
    expect(a.available, true);
    expect(a.opened, false);
    final b = ChestState.fromJson({'enabled': true, 'available': false, 'opened': {'kind': 'xp', 'amount': 25}});
    expect(b.opened, true);
    expect(b.amount, 25);
  });

  testWidgets('the chest card can be tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DailyChestCardView(onTap: () => taps++))));
    expect(find.text('Сундук дня'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-chest')));
    expect(taps, 1);
  });
}
