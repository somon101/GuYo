import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/widgets/game_icons.dart';
import 'package:guyo_app/widgets/user_name.dart';

Future<void> _show(WidgetTester t, {required bool premium, String? badge}) => t.pumpWidget(
      MaterialApp(home: Center(child: UserNameText('somon', isPremium: premium, badge: badge, style: const TextStyle(fontSize: 16)))),
    );

void main() {
  testWidgets('a Premium name is a gradient and carries the Premium G when no badge is chosen', (t) async {
    await _show(t, premium: true);
    expect(find.byKey(const ValueKey('premium-name')), findsOneWidget);
    expect(find.byType(PremiumIcon), findsOneWidget);
  });

  testWidgets('a Premium person with a chosen badge shows only that badge', (t) async {
    await _show(t, premium: true, badge: 'crown');
    expect(find.byKey(const ValueKey('premium-name')), findsOneWidget);
    expect(find.byType(PremiumIcon), findsNothing);
  });

  testWidgets('without Premium: a plain name, a chosen badge still shows, no Premium G ever', (t) async {
    await _show(t, premium: false, badge: 'crown');
    expect(find.byKey(const ValueKey('premium-name')), findsNothing);
    expect(find.byType(PremiumIcon), findsNothing);
    await _show(t, premium: false);
    expect(find.byType(PremiumIcon), findsNothing);
  });
}
