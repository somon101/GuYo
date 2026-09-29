import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/widgets/in_app_banner.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(navigatorKey: appNavigatorKey, home: const Scaffold(body: Text('screen'))),
      );

  testWidgets('slides in with the message, then leaves by itself', (tester) async {
    await pumpApp(tester);
    InAppBanner.show(title: 'Серия дней', body: 'Зайди сегодня!');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Серия дней'), findsOneWidget);
    expect(find.text('Зайди сегодня!'), findsOneWidget);
    expect(find.text('screen'), findsOneWidget);

    await tester.pump(InAppBanner.visibleFor);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('in-app-banner')), findsNothing);
  });

  testWidgets('a swipe up dismisses it early', (tester) async {
    await pumpApp(tester);
    InAppBanner.show(body: 'Без заголовка');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.fling(find.byKey(const ValueKey('in-app-banner')), const Offset(0, -200), 1000);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Без заголовка'), findsNothing);
  });

  testWidgets('a second message replaces the first', (tester) async {
    await pumpApp(tester);
    InAppBanner.show(body: 'первое');
    await tester.pump(const Duration(milliseconds: 400));
    InAppBanner.show(body: 'второе');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('первое'), findsNothing);
    expect(find.text('второе'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
