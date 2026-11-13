// The light claim screen: title, the rewards, sparkles, and the «Забрать» button that closes it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/reward_spec.dart';
import 'package:guyo_app/widgets/reward_claim_effect.dart';

void main() {
  testWidgets('shows the title and rewards, and «Забрать» closes it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showRewardClaimEffect(context, title: 'Цель дня выполнена!', rewards: const [RewardSpec(type: 'xp', amount: 5), RewardSpec(type: 'chest', key: 'wood', amount: 1)]),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2600));
    expect(find.text('Цель дня выполнена!'), findsOneWidget);
    expect(find.text('Вы получили'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('claim-done')));
    await tester.pumpAndSettle();
    expect(find.text('Цель дня выполнена!'), findsNothing);
  });
}
