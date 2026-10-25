import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/chest.dart';
import 'package:guyo_app/screens/chest_list_screen.dart';
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

  ChestBank bankOf(Map<String, int> counts) => ChestBank.fromJson(_json(chests: [
        for (final e in counts.entries)
          for (var i = 0; i < e.value; i++) {'id': e.key.hashCode % 1000 * 100 + i, 'chest_key': e.key, 'source': 'pass'},
      ]));

  testWidgets('tapping the card always opens the list', (tester) async {
    var opens = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ChestsCardView(bank: bankOf({'gold': 2}), onClaim: null, onOpen: () => opens++)),
    ));
    await tester.tap(find.byKey(const ValueKey('chests-card')));
    expect(opens, 1);
    expect(find.byKey(const ValueKey('count-gold')), findsOneWidget);
  });

  testWidgets('×5 appears from 5 chests and ×10 from 10; fewer open one by one', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChestListScreen(bank: bankOf({'wood': 7, 'silver': 3, 'gold': 12}))));
    expect(find.byKey(const ValueKey('mode-wood-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-wood-10')), findsNothing);
    expect(find.byKey(const ValueKey('mode-silver-5')), findsNothing);
    expect(find.byKey(const ValueKey('mode-gold-10')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('mode-wood-5')));
    await tester.tap(find.byKey(const ValueKey('mode-wood-5')));
    await tester.pump();
    expect(find.text('ОТКРЫТЬ ×5'), findsOneWidget);
  });

  testWidgets('three taps open a batch and every prize flies out', (tester) async {
    final after = bankOf({});
    await tester.pumpWidget(MaterialApp(
      home: ChestOpenScreen(
        bank: bankOf({'gold': 5}),
        chestKey: 'gold',
        count: 5,
        opener: (key, n) async => ([
              for (var i = 0; i < n; i++) ChestPrize(chestKey: key, kind: 'diamonds', amount: 10 + i),
            ], after),
      ),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('chest-tap')));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 4000));
    expect(find.text('+10'), findsOneWidget);
    expect(find.text('+14'), findsOneWidget);
    expect(find.byKey(const ValueKey('chest-collect')), findsOneWidget);
  });

  testWidgets('three taps open a single chest and the prize shows in the middle', (tester) async {
    final after = bankOf({});
    await tester.pumpWidget(MaterialApp(
      home: ChestOpenScreen(
        bank: bankOf({'gold': 1}),
        chestKey: 'gold',
        opener: (key, n) async => ([const ChestPrize(chestKey: 'gold', kind: 'diamonds', amount: 12345)], after),
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
