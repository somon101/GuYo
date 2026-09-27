// The ↑/↓ badge on the rating boards and the profile rank card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/theme/app_colors.dart';
import 'package:guyo_app/widgets/position_change.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('a climb is green with an up arrow', (tester) async {
    await tester.pumpWidget(_host(const PositionChangeBadge(change: 3)));
    expect(find.text('3'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.arrow_drop_up_rounded);
    expect(icon.color, AppColors.success);
  });

  testWidgets('a drop is red with a down arrow and no minus sign', (tester) async {
    await tester.pumpWidget(_host(const PositionChangeBadge(change: -2)));
    expect(find.text('2'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.arrow_drop_down_rounded);
    expect(icon.color, AppColors.danger);
  });

  testWidgets('no move draws nothing', (tester) async {
    await tester.pumpWidget(_host(const PositionChangeBadge(change: null)));
    expect(find.byType(Icon), findsNothing);
    await tester.pumpWidget(_host(const PositionChangeBadge(change: 0)));
    expect(find.byType(Icon), findsNothing);
  });
}
