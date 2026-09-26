// The Premium checkmark rides on UserNameText, the one widget every screen
// uses to show a name -- so pinning it here pins it everywhere.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/widgets/user_name.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SizedBox(width: 160, child: child)));

void main() {
  testWidgets('a Premium user gets the checkmark', (tester) async {
    await tester.pumpWidget(_host(const UserNameText('somon', isPremium: true, style: TextStyle(fontSize: 16))));
    expect(find.text('somon'), findsOneWidget);
    expect(find.byType(PremiumCheck), findsOneWidget);
    expect(find.bySemanticsLabel('GuYo Premium'), findsOneWidget);
  });

  testWidgets('everyone else does not', (tester) async {
    await tester.pumpWidget(_host(const UserNameText('somon', isPremium: false, style: TextStyle(fontSize: 16))));
    expect(find.text('somon'), findsOneWidget);
    expect(find.byType(PremiumCheck), findsNothing);
  });

  testWidgets('a long name is cut, the checkmark stays', (tester) async {
    await tester.pumpWidget(
      _host(const UserNameText('очень_длинный_логин_пользователя', isPremium: true, style: TextStyle(fontSize: 16))),
    );
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.byType(PremiumCheck), findsOneWidget);
  });
}
