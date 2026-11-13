// The light claim screen: title, the rewards, sparkles, and the «Забрать» button that closes it.
// Checked on several phone sizes: nothing overlaps and the block sits in the middle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/reward_spec.dart';
import 'package:guyo_app/widgets/reward_chips.dart';
import 'package:guyo_app/widgets/reward_claim_effect.dart';

Future<void> _open(WidgetTester tester, Size logical, {List<RewardSpec>? rewards}) async {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => showRewardClaimEffect(context,
            title: 'Цель дня выполнена!', rewards: rewards ?? const [RewardSpec(type: 'xp', amount: 5), RewardSpec(type: 'chest', key: 'wood', amount: 1)]),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 1500));
}

void main() {
  testWidgets('shows the title and rewards, and «Забрать» closes it', (tester) async {
    await _open(tester, const Size(360, 800));
    expect(find.text('Цель дня выполнена!'), findsOneWidget);
    expect(find.text('Вы получили'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('claim-done')));
    await tester.pumpAndSettle();
    expect(find.text('Цель дня выполнена!'), findsNothing);
  });

  for (final size in const [Size(320, 568), Size(360, 800), Size(411, 890), Size(600, 1000)]) {
    testWidgets('on ${size.width.toInt()}x${size.height.toInt()}: no overlap, content in the middle', (tester) async {
      await _open(tester, size);
      final title = tester.getRect(find.text('Цель дня выполнена!'));
      final slots = tester.getRect(find.byType(Wrap));
      final button = tester.getRect(find.byKey(const ValueKey('claim-done')));
      expect(title.bottom, lessThan(slots.top), reason: 'the title is above the rewards');
      expect(slots.bottom, lessThan(button.top), reason: 'the button is below the rewards');
      expect((slots.center.dx - size.width / 2).abs(), lessThan(2), reason: 'rewards are centred sideways');
      expect(button.bottom, lessThanOrEqualTo(size.height));
      // The block (title + rewards) sits around the middle of the free area above the button.
      final blockMid = (title.top + slots.bottom) / 2;
      final freeMid = button.top / 2;
      expect((blockMid - freeMid).abs(), lessThan(size.height * 0.08));
    });
  }

  testWidgets('many rewards wrap to a second row without overflow', (tester) async {
    await _open(tester, const Size(320, 568), rewards: [for (var i = 0; i < 6; i++) RewardSpec(type: 'xp', amount: i + 1)]);
    expect(find.byType(RewardSlot), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the whole show takes about a second and a half: the button is shown and works by then', (tester) async {
    await _open(tester, const Size(360, 800));
    final fade = tester.widget<FadeTransition>(find.ancestor(of: find.byKey(const ValueKey('claim-done')), matching: find.byType(FadeTransition)).first);
    expect(fade.opacity.value, 1.0);
  });
}
