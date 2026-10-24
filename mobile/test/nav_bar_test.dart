import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/screens/home_screen.dart';

void main() {
  testWidgets('the bar is compact, icon-only and reports taps', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: FloatingNavBar(
          selectedIndex: 0,
          onSelected: (i) => tapped = i,
          items: const [
            NavItemData(Icons.grid_view_rounded, 'Главная'),
            NavItemData(Icons.menu_book_rounded, 'Уроки'),
            NavItemData(Icons.bolt_rounded, 'Практика'),
            NavItemData(Icons.bar_chart_rounded, 'Рейтинг'),
            NavItemData(Icons.person_rounded, 'Профиль'),
          ],
        ),
      ),
    ));
    expect(find.text('Главная'), findsNothing, reason: 'no captions on the bar');
    expect(tester.getSize(find.byType(FloatingNavBar)).height, lessThan(90));
    await tester.tap(find.byIcon(Icons.bolt_rounded));
    expect(tapped, 2);
  });
}
