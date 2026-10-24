import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/chest.dart';
import 'package:guyo_app/screens/chest_open_screen.dart';
import 'package:guyo_app/widgets/chests_card.dart';

Map<String, dynamic> _json({List<Map<String, dynamic>> chests = const [], bool available = true, bool claimed = false}) => {
  'types': [
    for (final k in ['wood', 'silver', 'purple', 'gold'])
      {'key': k, 'name': 'Сундук $k', 'color': '#a0693b', 'max_diamonds': 10, 'max_freezes': 1, 'max_merges': 1, 'max_points': 20},
  ],
  'chests': chests,
  'daily': {'enabled': true, 'chest_key': 'purple', 'claimed': claimed, 'available': available, 'conditions': 'Позанимайтесь'},
  'double': false,
  'inventory_max': 10,
};

void main() {
  test('the bank parses chests, types and the chest of the day', () {
    final bank = ChestBank.fromJson(_json(chests: [
      {'id': 1, 'chest_key': 'gold', 'source': 'pass'},
    ]));
    expect(bank.chests.single.chestKey, 'gold');
    expect(bank.type('silver')!.name, 'Сундук silver');
    expect(bank.daily.chestKey, 'purple');
  });

  testWidgets('the card claims the daily chest and opens the bank', (tester) async {
    var claims = 0, opens = 0;
    final bank = ChestBank.fromJson(_json(chests: [
      {'id': 1, 'chest_key': 'gold', 'source': 'pass'},
    ]));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ChestsCardView(bank: bank, onClaim: () => claims++, onOpen: () => opens++)),
    ));
    expect(find.text('Сундук дня'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-chest')));
    await tester.tap(find.byKey(const ValueKey('my-chests')));
    expect((claims, opens), (1, 1));
  });

  testWidgets('three taps open the chest and the prize shows in the middle', (tester) async {
    final bank = ChestBank.fromJson(_json(chests: [
      {'id': 7, 'chest_key': 'gold', 'source': 'admin'},
    ]));
    final after = ChestBank.fromJson(_json());
    await tester.pumpWidget(MaterialApp(
      home: ChestOpenScreen(
        bank: bank,
        opener: (id) async => (ChestPrize(chestKey: 'gold', kind: 'diamonds', amount: 12345), after),
      ),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('chest-tap')));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.text('+12к'), findsOneWidget);
    expect(find.byKey(const ValueKey('chest-collect')), findsOneWidget);
  });
}
