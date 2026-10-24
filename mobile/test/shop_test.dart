import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/season_pass.dart';
import 'package:guyo_app/screens/economy_screens.dart';
import 'package:guyo_app/widgets/gift_art.dart';
import 'package:guyo_app/widgets/season_pass_ui.dart';

Map<String, dynamic> _shop({int diamonds = 120}) => {
      'diamonds': diamonds,
      'streak_freezes': 2,
      'streak_merge_items': 0,
      'products': [
        {'id': 1, 'name': '1 заморозка серии', 'description': 'Защитит серию', 'item_type': 'streak_freeze', 'quantity': 1, 'price_diamonds': 50},
        {'id': 2, 'name': '10 заморозок серии', 'description': 'Запас', 'item_type': 'streak_freeze', 'quantity': 10, 'price_diamonds': 300},
        {'id': 3, 'name': 'Объединитель серии', 'description': 'Склеит дни', 'item_type': 'streak_merge', 'quantity': 1, 'price_diamonds': 500},
      ],
    };

void main() {
  testWidgets('the shop shows the balance, every product and where diamonds come from', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: EconomyScreen(initial: _shop())));
    await tester.pump();
    expect(find.text('120'), findsOneWidget);
    for (final id in [1, 2, 3]) {
      expect(find.byKey(ValueKey('shop-product-$id')), findsOneWidget);
    }
    expect(find.text('Выгодно'), findsOneWidget);
    expect(find.text('Нужно больше?'), findsOneWidget);
    expect(find.text('Подарки'), findsNothing, reason: 'no gifts tab any more');
  });

  testWidgets('the gift keeps its size', (tester) async {
    await tester.pumpWidget(const Center(child: GiftArt(size: 80)));
    expect(tester.getSize(find.byType(GiftArt)), const Size(80, 92));
  });

  test('a diamonds reward is drawn as the gift', () {
    const diamonds = PassReward(type: 'diamonds', amount: 10, claimed: false, claimable: true, lockedByPremium: false);
    const points = PassReward(type: 'rating_points', amount: 20, claimed: false, claimable: true, lockedByPremium: false);
    expect(rewardStyle(diamonds).gift, true);
    expect(rewardStyle(points).gift, false);
  });
}
